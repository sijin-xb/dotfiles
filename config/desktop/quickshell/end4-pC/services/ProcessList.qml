pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * 进程快照服务。
 *
 * 数据来自常驻脚本 `scripts/processes/process_sampler.py`（NDJSON，每轮一行）。
 * 它直接读 /proc 并做增量差值，比每轮 spawn 一次 `ps` 更省，而且能给出
 * **per-process 的 GPU 占用**（读 /proc/<pid>/fdinfo 里的 drm-engine-*）。
 *
 * 开销控制：
 *   - 脚本是**长驻单进程**，只在 `autoRefresh` 为真时运行 —— 没人在看进程页
 *     时开销为 0（调用方在页面显示时把 autoRefresh 打开即可）；
 *   - 脚本侧已做限流（CPU 前 N ∪ 内存前 N/3 ∪ GPU 前 N/4），单轮 JSON ~33KB；
 *   - 排序在 QML 侧做，切换排序键不需要重启脚本。
 *
 * 对外 API 与旧版（ps 实现）保持一致，`bar/ClockDashboard.qml` 无需改动：
 *   list / ready / loading / lastError / sortKey / setSortKey / filtered /
 *   matches / killProcess / autoRefresh / requestRefresh /
 *   hideKernelThreads / displayLimit
 * 新增：
 *   sortKey 支持 "gpu"；每条进程多一个 `gpu` 字段（百分比，拿不到时为 null）。
 */
Singleton {
    id: root

    // ── 排序 ────────────────────────────────────────────────────────────
    // "cpu" | "mem" | "gpu" | "name"
    property string sortKey: "cpu"

    // 展示上限。脚本侧已限流到 ~250 条，这里再兜一层。
    property int displayLimit: 200

    // 隐藏内核线程：对桌面用户无意义，只会把列表塞满、拉大 delegate 池。
    property bool hideKernelThreads: true

    // 是否轮询。同时是脚本进程的开关 —— 关掉即零开销。
    property bool autoRefresh: false

    // 采样间隔（秒）。传给脚本；改这个值会让 Process 重启脚本。
    property real refreshInterval: 2.0

    // ── 状态 ────────────────────────────────────────────────────────────
    // 脚本最近一轮的原始数据（未排序、未过滤）
    property var _raw: []
    // 已排序 + 已截断，供 UI 直接当 model 用
    property var list: []
    property bool loading: false
    property string lastError: ""
    property bool ready: false
    // 最近一次采样的时刻（脚本的 monotonic 秒），供 UI 判断数据新鲜度
    property real lastSampleTime: 0

    function requestRefresh() {
        // 脚本自己按 interval 推数据；这里只把「有人要数据」表达成打开开关。
        if (!root.autoRefresh)
            root.autoRefresh = true
    }

    function setSortKey(key) {
        if (key !== "cpu" && key !== "mem" && key !== "gpu" && key !== "name")
            return
        root.sortKey = key
    }

    // 排序 + 截断。250 条以内，每次采样做一次，成本可忽略。
    function _resort() {
        const arr = root._raw.slice()
        const key = root.sortKey
        if (key === "name")
            arr.sort((a, b) => (a.name || "").localeCompare(b.name || ""))
        else if (key === "mem")
            arr.sort((a, b) => b.mem - a.mem)
        else if (key === "gpu")
            // 没有 GPU 数值的排最后，而不是当成 0 混进前面
            arr.sort((a, b) => (b.gpu ?? -1) - (a.gpu ?? -1))
        else
            arr.sort((a, b) => b.cpu - a.cpu)
        root.list = arr.slice(0, root.displayLimit)
    }

    // 大小写不敏感的子串匹配：pid / 用户名 / 命令名 / 完整命令行
    function matches(proc, query) {
        if (!query || query.length === 0)
            return true
        const q = query.toLowerCase()
        if (proc.name && proc.name.toLowerCase().indexOf(q) !== -1)
            return true
        if (proc.args && proc.args.toLowerCase().indexOf(q) !== -1)
            return true
        if (proc.user && proc.user.toLowerCase().indexOf(q) !== -1)
            return true
        if (String(proc.pid).indexOf(q) !== -1)
            return true
        return false
    }

    // 内核线程由脚本判定（cmdline 为空且不是僵尸）；这里保留旧签名，
    // 老数据（只有方括号 args）仍能识别。
    function isKernelThread(proc) {
        if (!proc)
            return false
        if (proc.kthread !== undefined)
            return proc.kthread
        const a = proc.args
        return !!a && a.length >= 2 && a.charAt(0) === "[" && a.charAt(a.length - 1) === "]"
    }

    function filtered(query) {
        const out = []
        const hasQuery = query && query.length > 0
        const src = root.list
        for (let i = 0; i < src.length; i++) {
            const p = src[i]
            if (root.hideKernelThreads && root.isKernelThread(p))
                continue
            if (!hasQuery || root.matches(p, query))
                out.push(p)
        }
        return out
    }

    /**
     * 结束进程。
     * @param pid    进程号
     * @param signal "TERM"（默认，礼貌退出）或 "KILL"（强杀）
     * pid <= 1 直接拒绝：杀掉 init 会让整机挂掉。
     */
    function killProcess(pid, signal) {
        if (!pid || pid <= 1)
            return
        const sig = (signal === "KILL") ? "KILL" : "TERM"
        Quickshell.execDetached(["kill", `-${sig}`, String(pid)])
        // 给内核一点回收时间再刷新，否则列表里还是旧数据
        killRefreshTimer.interval = (sig === "KILL") ? 150 : 300
        killRefreshTimer.restart()
    }

    Timer {
        id: killRefreshTimer
        interval: 300
        onTriggered: root._resort()
    }

    // ── 采样脚本 ────────────────────────────────────────────────────────
    // running 直接绑 autoRefresh：没人看进程页时脚本不跑，开销为 0。
    Process {
        id: sampler
        running: root.autoRefresh
        command: ["python3", Quickshell.shellPath("scripts/processes/process_sampler.py"),
            "--interval", String(root.refreshInterval)]

        stdout: SplitParser {
            onRead: line => root._handleSample(line)
        }

        onExited: (exitCode, exitStatus) => {
            root.loading = false
            if (exitCode !== 0 && root.autoRefresh)
                root.lastError = `采样脚本退出，code=${exitCode}`
        }
    }

    onAutoRefreshChanged: {
        if (root.autoRefresh) {
            root.loading = true
            root.lastError = ""
        } else {
            root.loading = false
        }
    }

    function _handleSample(line) {
        if (!line || line.length === 0)
            return
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            root.lastError = "采样数据解析失败"
            return
        }
        if (!msg || !msg.procs)
            return
        root._raw = msg.procs
        root.lastSampleTime = msg.t ?? 0
        root.ready = true
        root.loading = false
        root.lastError = ""
        root._resort()
    }

    onSortKeyChanged: root._resort()
    onDisplayLimitChanged: root._resort()
}
