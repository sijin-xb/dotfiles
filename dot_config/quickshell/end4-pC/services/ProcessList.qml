pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * 进程快照服务。
 *
 * 用一次 `ps -eo pid,user,comm,pcpu,pmem,rss,args --sort=-pcpu` 拿全量进程，
 * 比 N 次 grep 便宜得多。上层需要时通过 `requestRefresh()` 主动拉取，
 * 或者由 `autoRefresh` 控制是否随计时器持续刷新。
 *
 * 数据布局与 caelestia / 系统监视器的常见进程视图对齐，
 * 只保留展示层要用的字段，避免把 ps 全部列都往 QML 里灌。
 */
Singleton {
    id: root

    // 排序键："cpu" | "mem" | "name"
    property string sortKey: "cpu"
    // ps 侧拉取行数。全系统通常 300~500 个进程，
    // 拉 200 行成本与 100 行几乎相同（实测 ~15ms），
    // 过滤掉内核线程后仍能覆盖用户关心的全部进程。
    property int displayLimit: 200

    // 隐藏内核线程：args 形如 `[kworker/0:1]` 的条目。
    // 这些进程对桌面用户毫无意义，只会把列表塞满、拉大 delegate 池；
    // 过滤后列表更短更干净，视觉和滚动都更快。
    property bool hideKernelThreads: true
    // 是否自动轮询
    property bool autoRefresh: false
    // 刷新间隔（毫秒）。ps + 解析实测 ~15ms，间隔不宜太短，
    // 否则每次 ListView 的 model 都会变、触发重新绑定。
    readonly property int refreshInterval: 3000

    // 每条：{ pid, user, name, args, cpu, mem, rss }
    property var list: []
    property bool loading: false
    property string lastError: ""
    property bool ready: false

    function requestRefresh() {
        if (psProc.running)
            return
        psProc.running = true
    }

    function setSortKey(key) {
        if (key !== "cpu" && key !== "mem" && key !== "name")
            return
        root.sortKey = key
        root.requestRefresh()
    }

    // 大小写不敏感的子串匹配：pid / 用户名 / 命令名 / 完整命令行
    function matches(proc, query) {
        if (!query || query.length === 0)
            return true
        const q = query.toLowerCase()
        if (proc.name && proc.name.toLowerCase().indexOf(q) !== -1) return true
        if (proc.args && proc.args.toLowerCase().indexOf(q) !== -1) return true
        if (proc.user && proc.user.toLowerCase().indexOf(q) !== -1) return true
        if (String(proc.pid).indexOf(q) !== -1) return true
        return false
    }

    // 内核线程的 args 是 ps 主动包了方括号的命令名，形如 `[kworker/u16:0]`；
    // 用户态进程 args 是真实命令行，不会整段被方括号包裹。
    function isKernelThread(proc) {
        const a = proc?.args
        if (!a || a.length < 2)
            return false
        return a.charAt(0) === "[" && a.charAt(a.length - 1) === "]"
    }

    function filtered(query) {
        const out = []
        const hasQuery = query && query.length > 0
        for (let i = 0; i < root.list.length; i++) {
            const p = root.list[i]
            if (root.hideKernelThreads && root.isKernelThread(p))
                continue
            if (!hasQuery || root.matches(p, query))
                out.push(p)
        }
        return out
    }

    function killProcess(pid, signal) {
        if (!pid || pid <= 1)
            return
        const sig = signal || "TERM"
        Quickshell.execDetached(["kill", `-${sig}`, String(pid)])
        killRefreshTimer.restart()
    }

    Timer {
        id: killRefreshTimer
        interval: 300
        onTriggered: root.requestRefresh()
    }

    Timer {
        interval: root.refreshInterval
        repeat: true
        running: root.autoRefresh
        onTriggered: root.requestRefresh()
    }

    Process {
        id: psProc
        // 排序交给 ps，QML 侧只做过滤/展示。
        // ps 的 `-` 前缀是降序：CPU/内存要降序（大的在前），
        // 名称要升序（A→Z），之前统一加 `-` 导致按名称反而是 Z→A。
        readonly property string _sortFlag: {
            if (root.sortKey === "mem")
                return "-pmem"
            if (root.sortKey === "name")
                return "comm"
            return "-pcpu"
        }
        command: ["bash", "-c",
            `ps -eo pid,user,comm,pcpu,pmem,rss,args --sort=${psProc._sortFlag} | head -n ${root.displayLimit + 1}`]
        stdout: StdioCollector {
            id: stdoutCollector
            onStreamFinished: {
                const text = stdoutCollector.text
                const lines = text.split("\n")
                console.log("[ProcessList] ps finished, raw bytes:", text.length, "lines:", lines.length)
                const out = []
                // 跳过表头（第一行）；ps 的列名以 PID 开头
                for (let i = 1; i < lines.length; i++) {
                    const line = lines[i]
                    if (line.trim().length === 0)
                        continue
                    // 拆分：PID USER COMM %CPU %MEM RSS ARGS
                    // ARGS 里可能有空格，用 
                    // 前 6 列拆分，剩下的都当 ARGS
                    const m = line.match(/^\s*(\d+)\s+(\S+)\s+(\S+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(.*)$/)
                    if (!m)
                        continue
                    out.push({
                        pid: Number(m[1]),
                        user: m[2],
                        name: m[3],
                        cpu: Number(m[4]) || 0,
                        mem: Number(m[5]) || 0,
                        rss: Number(m[6]) || 0,
                        args: m[7]
                    })
                }
                root.list = out
                root.ready = true
                root.lastError = ""
                console.log("[ProcessList] parsed", out.length, "processes")
            }
        }
        onRunningChanged: root.loading = running
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.lastError = `ps exited with ${exitCode}`
        }
    }

    Component.onCompleted: root.requestRefresh()
}
