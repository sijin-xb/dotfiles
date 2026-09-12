pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// 共享进程探测器。
//
// 早期每个 TaskSource 各自跑 `ps | grep`，N 个任务类型就是 N 份轮询，
// 频率都是 2 秒一次。这里合并成单次 `ps -eo comm=`，各 TaskSource 读同一份快照，
// 进程数从 N 降到 1。
//
// 只在有订阅者时才运行：无人订阅则停表，空转没有意义。
Singleton {
    id: root

    // 当前存活的进程名集合。首个订阅者到达后开始填充。
    property var runningCommands: ({})
    property bool ready: false

    // 订阅者数量：0 时停表
    property int subscriberCount: 0

    readonly property int pollInterval: 2000

    function subscribe() {
        subscriberCount += 1
    }

    function unsubscribe() {
        subscriberCount = Math.max(0, subscriberCount - 1)
    }

    // 查询某进程是否在跑。未就绪时返回 false，避免首次误报。
    function isRunning(name) {
        return runningCommands[name] === true
    }

    Process {
        id: probe
        // -eo comm= 只输出命令名，无表头，解析成本最低
        command: ["ps", "-eo", "comm="]
        running: root.subscriberCount > 0

        stdout: StdioCollector {
            onStreamFinished: {
                const next = {}
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const name = lines[i].trim()
                    if (name.length > 0)
                        next[name] = true
                }
                // 正常系统永远有进程在跑；解析出 0 个说明 ps 本身出问题了，
                // 此时保留上次快照，避免所有任务活动瞬间消失又闪回。
                if (Object.keys(next).length === 0)
                    return
                root.runningCommands = next
                root.ready = true
            }
        }
    }

    Timer {
        interval: root.pollInterval
        repeat: true
        running: root.subscriberCount > 0
        triggeredOnStart: true
        onTriggered: {
            if (!probe.running)
                probe.running = true
        }
    }
}
