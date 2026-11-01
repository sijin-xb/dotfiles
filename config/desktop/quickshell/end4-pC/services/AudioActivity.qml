pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * 「现在有没有音频在放」—— 事件驱动，覆盖所有音源。
 *
 * 歌词要通杀，就不能只认支持 MPRIS 的播放器（浏览器、游戏、视频播放器大多不支持），
 * 所以改成问系统音频：PipeWire/PulseAudio 里只要有没被挂起（uncorked）的播放流，
 * 就认为在放声音。这对「谁在放」是完全中立的。
 *
 * 实现上刻意不用轮询：
 *   pactl subscribe        常驻，只在音频对象变化时吐一行
 *   pactl -f json list ... 只在收到事件后查一次（250ms 去抖合并连发事件）
 * 空闲时没有任何定时器和子进程，开销可以忽略。
 *
 * 注意 PipeWire 的坑：`pactl -f json list sink-inputs` 在 PipeWire 后端下
 * **没有 state 字段**（那是原生 PulseAudio 才有的），只有一个 corked 布尔。
 * 所以判断「在播」要优先看 corked，state 只作为非 PipeWire 环境的兜底。
 */
Singleton {
    id: root

    /** pactl 是否可用；不可用时 playing 恒为 false，调用方自然会退回 MPRIS 路径 */
    property bool available: false
    /** 是否有音频在播放 */
    property bool playing: false
    /** 正在播放的应用名（application.name），仅用于展示与调试 */
    property var activeApps: []

    function refresh() {
        if (!root.available)
            return
        listProc.running = false
        listProc.running = true
    }

    Process {
        id: whichProc
        running: true
        command: ["which", "pactl"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0)
            if (root.available)
                root.refresh() // subscribe 只报「变化」，初始状态得自己查一次
        }
    }

    Process {
        id: subscribeProc
        running: root.available
        command: ["pactl", "subscribe"]

        stdout: SplitParser {
            // subscribe 会对 sink / source / client 的所有变化都吐行（音量调节也会），
            // 所以统一去抖后再查一次，避免短时间内起一堆 pactl 进程。
            onRead: (line) => eventDebounce.restart()
        }

        onRunningChanged: {
            // pactl 挂掉（音频服务重启等）：不要留着过期的 playing 状态
            if (!running)
                root.playing = false
        }
    }

    Timer {
        id: eventDebounce
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["pactl", "-f", "json", "list", "sink-inputs"]

        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
    }

    function apply(raw) {
        let streams
        try {
            streams = JSON.parse(raw)
        } catch (e) {
            return // 输出被截断或格式变了，保留上一次的状态
        }
        if (!Array.isArray(streams))
            return

        const apps = []
        let anyPlaying = false
        for (const stream of streams) {
            if (!root.isRunning(stream))
                continue
            anyPlaying = true
            const props = stream.properties ? stream.properties : {}
            const app = props["application.name"]
            if (app)
                apps.push(String(app))
        }

        root.playing = anyPlaying
        root.activeApps = apps
    }

    /** 单个播放流是否处于「正在出声」的状态 */
    function isRunning(stream) {
        const state = stream.state ? String(stream.state) : ""
        if (state !== "")
            return state === "RUNNING" // 原生 PulseAudio
        // PipeWire：没有 state，用 corked 判断（挂起 = 暂停/空闲）
        return stream.corked !== true
    }
}
