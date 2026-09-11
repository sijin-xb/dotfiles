pragma Singleton
import QtQuick
import Quickshell

// 活动管理器：数据源通过 set/clear 注册活动，UI 订阅 currentType/currentPayload。
// 同一时刻只显示优先级最高的活动，无活动时 hasActivity 为 false（UI 隐藏）。
Singleton {
    id: root

    // type -> { payload, priority }
    property var entries: ({})
    property int revision: 0

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

    function set(type, payload, priority) {
        const next = Object.assign({}, entries)
        next[type] = { payload: payload, priority: priority }
        entries = next
        revision++
    }

    function clear(type) {
        if (!entries[type]) return
        const next = Object.assign({}, entries)
        delete next[type]
        entries = next
        revision++
    }

    function debugList() {
        return Object.keys(entries).map(t => `${t}(${entries[t].priority})`).join(", ") || "无活动"
    }
}
