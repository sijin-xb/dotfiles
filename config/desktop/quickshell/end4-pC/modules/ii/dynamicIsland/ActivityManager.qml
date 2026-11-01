pragma Singleton
import QtQuick
import Quickshell

// 活动注册表：数据源通过 set / pulse / clear 注册活动，UI 订阅 currentType / currentPayload。
//
// 相比早期的扁平 map，这里补上了「联动性」需要的三件事：
//   - group      同组活动可合并渲染（多个任务 → 一个胶囊）
//   - transient  标记瞬态活动（音量 / 通知），可被 IslandContext 按场景抑制
//   - pulse      统一的暂态生命周期，数据源不再各自持有 Timer
Singleton {
    id: root

    // type -> { payload, priority, group, transient, since }
    property var entries: ({})
    property int revision: 0

    // type -> 过期时间（ms epoch）；到点后自动清除
    property var _expiries: ({})

    readonly property string currentType: {
        revision
        let bestType = "idle"
        let bestPriority = -1
        for (const t in entries) {
            const e = entries[t]
            if (e && e.priority > bestPriority) {
                bestPriority = e.priority
                bestType = t
            }
        }
        return bestType
    }

    readonly property var currentPayload: {
        revision
        const t = currentType
        return (entries[t] && entries[t].payload) ? entries[t].payload : ({})
    }

    readonly property bool hasActivity: currentType !== "idle"

    // 场景由活动组合推导，供 IslandContext 做门控。
    // 顺序即优先级：录屏 > 媒体 > 任务 > 空闲。
    readonly property string scene: {
        revision
        if (entries["recording"])
            return "recording"
        if (entries["music"])
            return "media"
        if (entries["package"] || entries["download"])
            return "task"
        return "idle"
    }

    // 同组活动：group -> [type]，供副岛合并渲染。
    readonly property var groups: {
        revision
        const out = {}
        for (const t in entries) {
            const g = entries[t].group
            if (!g)
                continue
            if (!out[g])
                out[g] = []
            out[g].push(t)
        }
        return out
    }

    function set(type, payload, priority, options) {
        const opts = options ?? {}
        const next = Object.assign({}, entries)
        next[type] = {
            payload: payload,
            priority: priority,
            group: opts.group ?? "",
            transient: opts.transient ?? false,
            since: Date.now()
        }
        entries = next
        revision++
    }

    function clear(type) {
        if (!entries[type])
            return
        const next = Object.assign({}, entries)
        delete next[type]
        entries = next
        revision++
        dropExpiry(type)
    }

    // 统一暂态：显示 duration ms 后自动清除。
    // 重复调用顺延过期时间，即「最小展示时长」语义。
    function pulse(type, payload, priority, duration, options) {
        set(type, payload, priority, options)
        scheduleExpiry(type, duration)
    }

    // 暂停过期：展开态要看内容时用，变为常驻直到 clear。
    function hold(type) {
        dropExpiry(type)
    }

    // 恢复过期倒计时：收起时用。
    function release(type, duration) {
        if (!entries[type])
            return
        scheduleExpiry(type, duration)
    }

    function debugList() {
        return Object.keys(entries).map(t => `${t}(${entries[t].priority})`).join(", ") || "无活动"
    }

    // ---- 过期管理 ----
    // 仅在存在待过期项时运行计时器，避免常驻轮询。
    function scheduleExpiry(type, duration) {
        const next = Object.assign({}, _expiries)
        next[type] = Date.now() + Math.max(0, duration)
        _expiries = next
        if (!expiryTimer.running)
            expiryTimer.start()
    }

    function dropExpiry(type) {
        if (_expiries[type] === undefined)
            return
        const next = Object.assign({}, _expiries)
        delete next[type]
        _expiries = next
        // 没有待过期项就别继续空转
        if (Object.keys(next).length === 0)
            expiryTimer.stop()
    }

    function expireDue() {
        const now = Date.now()
        const due = []
        for (const t in _expiries) {
            if (_expiries[t] <= now)
                due.push(t)
        }
        for (const t of due) {
            dropExpiry(t)
            clear(t)
        }
        if (Object.keys(_expiries).length === 0)
            expiryTimer.stop()
    }

    Timer {
        id: expiryTimer
        interval: 100
        repeat: true
        onTriggered: root.expireDue()
    }
}
