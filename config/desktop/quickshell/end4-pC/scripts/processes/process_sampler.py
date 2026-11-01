#!/usr/bin/env python3
"""进程采样器 —— 供 Quickshell 的 ProcessList 服务消费。

为什么不用 `ps` 轮询：
  `ps` 每次都要 spawn 一个进程并重新解析全表（实测 ~15ms），而且拿不到
  per-process 的 GPU 占用。这里改成**单进程长驻**，直接读 /proc，
  每次采样只做增量差值，启动成本只付一次。

输出协议：每次采样往 stdout 打**一行 JSON**（NDJSON），形如
  {"t": <采样时刻秒>, "dt": <与上次采样的间隔秒>, "procs": [ ... ]}
每条进程：
  {"pid":int,"user":str,"name":str,"args":str,"cpu":float,"mem":float,
   "rss":int,"gpu":float}
  - cpu: 相对**单核**的百分比（与 top/htop 一致，可以 >100）
  - mem: 常驻内存占物理内存的百分比
  - rss: 常驻内存字节数
  - gpu: 该进程占用最高的那个 DRM 引擎的百分比；拿不到时为 null

跨平台：
  - Linux：/proc + fdinfo（fdinfo 里有 drm-engine-* 就能算 GPU）
  - 其它平台：GPU 一律为 null，进程表仍由 /proc 不可用时的降级路径给出
  目前非 Linux 平台只保证「不崩、字段齐全」，GPU 列显示为「—」。
"""

import argparse
import json
import os
import re
import sys
import time

CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1

# /proc/<pid>/fdinfo/<fd> 里的 DRM 引擎累计忙碌时间
DRM_RE = re.compile(rb"^drm-engine-([a-z0-9_]+):\s+(\d+)\s*ns", re.M)


def total_memory_bytes():
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) * 1024
    except OSError:
        pass
    return 0


def read_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            raw = f.read()
    except (OSError, PermissionError):
        return ""
    if not raw:
        return ""
    # cmdline 是 NUL 分隔的；末尾通常还有一个 NUL
    return raw.rstrip(b"\0").replace(b"\0", b" ").decode("utf-8", "replace").strip()


def read_uid(pid):
    """取进程的真实 uid。

    不去读 /proc/<pid>/status（那要 open+read 整个文件），而是直接 stat
    /proc/<pid> 目录 —— 它的属主就是进程的 real uid。600+ 个进程下
    这是省掉 600 次文件读的关键。
    """
    try:
        return os.stat(f"/proc/{pid}").st_uid
    except (OSError, PermissionError):
        return None


def sample_proc():
    """扫描 /proc，返回 {pid: {"utime","stime","rss","comm","args","uid"}}。"""
    out = {}
    for entry in os.scandir("/proc"):
        name = entry.name
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/stat", "rb") as f:
                stat = f.read()
        except (OSError, PermissionError):
            continue
        # comm 可能含空格和括号，必须从**最后一个** ')' 往前切
        rp = stat.rfind(b")")
        lp = stat.find(b"(")
        if rp < 0 or lp < 0 or rp < lp:
            continue
        comm = stat[lp + 1:rp].decode("utf-8", "replace")
        fields = stat[rp + 2:].split()
        # 字段 3 起（state）对应 fields[0]，所以 utime(14) → [11]、stime(15) → [12]、rss(24) → [21]
        if len(fields) < 22:
            continue
        try:
            utime = int(fields[11])
            stime = int(fields[12])
            rss = int(fields[21])
        except ValueError:
            continue
        args = read_cmdline(pid)
        # 内核线程的 cmdline 是空的（ps 会用 [comm] 显示）。
        # 僵尸进程 cmdline 也为空，但它 state == 'Z'，要区分开。
        state = fields[0].decode("ascii", "replace") if fields else "?"
        out[pid] = {
            "utime": utime,
            "stime": stime,
            "rss": rss * PAGE_SIZE,
            "comm": comm,
            "args": args,
            "uid": read_uid(pid),
            "kthread": (len(args) == 0 and state != "Z"),
        }
    return out


def sample_gpu(pids):
    """只对给定的 pid 扫 fdinfo，返回 {pid: {engine: total_ns}}。

    只扫候选 pid 是关键：全量扫 620 个进程的 9000+ 条 fdinfo 要 ~100ms，
    而真正持有 DRM 引擎计数的通常只有个位数。上限由调用方（top N）控制。
    """
    out = {}
    for pid in pids:
        fdinfo = f"/proc/{pid}/fdinfo"
        try:
            fds = os.listdir(fdinfo)
        except (OSError, PermissionError):
            continue
        engines = {}
        for fd in fds:
            try:
                with open(f"{fdinfo}/{fd}", "rb") as f:
                    data = f.read(2048)
            except (OSError, PermissionError):
                continue
            if b"drm-engine" not in data:
                continue
            for m in DRM_RE.finditer(data):
                key = m.group(1).decode()
                engines[key] = engines.get(key, 0) + int(m.group(2))
        if engines:
            out[pid] = engines
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", type=float, default=2.0, help="采样间隔（秒）")
    ap.add_argument("--gpu-top", type=int, default=40,
                    help="最多对多少个进程扫 fdinfo 算 GPU（按 CPU 降序取前 N）")
    ap.add_argument("--limit", type=int, default=200,
                    help="最多输出多少条进程（取 CPU 前 N ∪ 内存前 N/3）")
    ap.add_argument("--args-max", type=int, default=200,
                    help="命令行截断长度；完整命令行是载荷里最大的一块")
    args = ap.parse_args()

    # 用户名解析缓存：pwd.getpwuid 每次都要读 /etc/passwd，缓存掉
    uid_cache = {}
    try:
        import pwd
        getpwuid = pwd.getpwuid
    except ImportError:
        getpwuid = None

    def user_of(uid):
        if uid is None:
            return ""
        if uid in uid_cache:
            return uid_cache[uid]
        name = str(uid)
        if getpwuid is not None:
            try:
                name = getpwuid(uid).pw_name
            except (KeyError, OSError):
                pass
        uid_cache[uid] = name
        return name

    mem_total = total_memory_bytes()
    prev = {}
    prev_t = None
    prev_gpu = None
    tick = 0

    while True:
        t = time.monotonic()
        cur = sample_proc()

        # 第一轮没有上一份样本，差值算不出来，先出一份 cpu=0 的骨架
        dt = (t - prev_t) if prev_t is not None else 0.0

        rows = []
        for pid, p in cur.items():
            cpu = 0.0
            if dt > 0 and pid in prev:
                d_ticks = (p["utime"] - prev[pid]["utime"]) + (p["stime"] - prev[pid]["stime"])
                # 相对单核：一个核跑满 = 100%
                cpu = max(0.0, d_ticks / CLK_TCK / dt * 100.0)
            mem = (p["rss"] / mem_total * 100.0) if mem_total else 0.0
            rows.append({
                "pid": pid,
                "user": user_of(p["uid"]),
                "name": p["comm"],
                # 命令行截断：它是载荷里最大的一块，而 UI 只用于搜索和单行展示
                "args": (p["args"] or p["comm"])[:args.args_max],
                "cpu": round(cpu, 1),
                "mem": round(mem, 2),
                "rss": p["rss"],
                "gpu": None,
                "kthread": p["kthread"],
            })

        # 按 CPU 降序，后面 GPU 扫描和限流都依赖这个顺序
        rows.sort(key=lambda r: r["cpu"], reverse=True)

        # GPU：只对 CPU 最高的前 N 个进程扫 fdinfo。
        # 全量扫 620 个进程的 9000+ 条 fdinfo 要 ~100ms，而真正持有 DRM
        # 引擎计数的通常只有个位数，所以必须限定候选集。
        # 注意要在限流**之前**做，否则限流会把 GPU 大户裁掉（GPU 占用高
        # 的进程未必 CPU 也高，比如视频解码）。
        if prev_t is not None and args.gpu_top > 0:
            candidates = [r["pid"] for r in rows[:args.gpu_top]]
            gpu_now = sample_gpu(candidates)
            gpu_prev = prev_gpu
            if gpu_prev is not None:
                by_pid = {r["pid"]: r for r in rows}
                for pid, engines in gpu_now.items():
                    row = by_pid.get(pid)
                    if row is None:
                        continue
                    peak = 0.0
                    for eng, ns in engines.items():
                        before = gpu_prev.get(pid, {}).get(eng, ns)
                        delta = ns - before
                        if delta > 0:
                            peak = max(peak, delta / (dt * 1e7))
                    row["gpu"] = round(min(peak, 100.0), 1)
            prev_gpu = gpu_now

        # 限流：全量 620+ 条 JSON 约 93KB，每轮都要在 QML 主线程 parse 一次，
        # 没必要。保留「CPU 前 N」∪「内存前 N/3」∪「GPU 前 N/4」——
        # 三个排序维度下的头部进程都在榜上，用户切换排序时不会缺项。
        if args.limit > 0 and len(rows) > args.limit:
            keep = {r["pid"] for r in rows[:args.limit]}
            mem_n = max(args.limit // 3, 20)
            keep |= {r["pid"] for r in sorted(rows, key=lambda r: r["mem"], reverse=True)[:mem_n]}
            gpu_n = max(args.limit // 4, 10)
            with_gpu = [r for r in rows if r["gpu"]]
            keep |= {r["pid"] for r in sorted(with_gpu, key=lambda r: r["gpu"], reverse=True)[:gpu_n]}
            rows = [r for r in rows if r["pid"] in keep]

        prev = cur
        prev_t = t

        sys.stdout.write(json.dumps({"t": t, "dt": round(dt, 3), "procs": rows},
                                    ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        tick += 1

        # 统一用固定间隔。CPU / GPU 都是差值量，第一轮没有基线、第二轮才有数，
        # 这是差值法的固有代价。试过前两轮改用 0.5s 短间隔「预热」，但窗口太短
        # 会让首个 CPU 读数明显偏噪（实测 electron 飙到 148%），得不偿失。
        time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
