pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * 用音频指纹自动认出「现在放的是什么歌」，给歌词通杀兜底。
 *
 * 为什么要指纹：MPRIS 只能覆盖愿意实现它的播放器（Spotify、mpv、部分 Electron 客户端），
 * 浏览器里的网页播放器、游戏、视频播放器基本都没有。逐个软件做适配是不可能维护的，
 * 所以改成直接听系统音频 —— recognize-music.sh 抓的是默认输出设备的 monitor 源，
 * 不管声音是哪个进程发的都能录到，再交给 songrec（Shazam）认歌。
 *
 * 触发由 AudioActivity 的播放状态驱动，不用轮询：
 *   有音频在放 且 还没有可信身份  → 识别一次
 *   音频停了（静默超过 10 秒）    → 忘掉身份，下次重新认
 * 识别结果有 15 分钟有效期，两次识别之间有 60 秒冷却（Shazam 会限流）。
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.desktopLyricsFingerprintEnable
    readonly property string scriptPath: `${Directories.scriptPath}/musicRecognition/recognize-music.sh`

    property string title: ""
    property string artist: ""
    /** 正在识别中 */
    property bool identifying: false
    /** 最近一次识别成功的时刻 */
    property double identifiedAt: 0
    property double lastAttemptAt: 0

    /** 身份有效期：超过就认为过期，需要重新识别 */
    readonly property int identityTtlMs: 15 * 60 * 1000
    /** 两次识别之间的最小间隔，避免 Shazam 限流 */
    readonly property int attemptCooldownMs: 60 * 1000
    /** 识别失败后隔多久再试（比成功后的冷却短，因为可能只是这一小段没匹配上） */
    readonly property int retryDelayMs: 20 * 1000

    readonly property bool hasIdentity: root.title !== ""
        && (Date.now() - root.identifiedAt) < root.identityTtlMs

    /** 请求识别。可重复调用：正在识别 / 冷却期内 / 没在放音频都会直接返回。 */
    function requestIdentify() {
        if (!root.enabled || root.identifying)
            return
        if (!AudioActivity.playing)
            return
        if (root.hasIdentity)
            return
        const cooldown = root.lastAttemptAt > 0 ? root.attemptCooldownMs : 0
        if (Date.now() - root.lastAttemptAt < cooldown)
            return

        root.lastAttemptAt = Date.now()
        root.identifying = true
        recognizeProc.running = false
        recognizeProc.running = true
    }

    function clear() {
        root.title = ""
        root.artist = ""
        root.identifiedAt = 0
    }

    function handleOutput(raw) {
        const text = String(raw).trim()
        if (text === "")
            return // 没匹配上，保留上一次的身份（可能仍然有效）
        let payload
        try {
            payload = JSON.parse(text)
        } catch (e) {
            return
        }
        const track = payload ? payload.track : null
        if (!track)
            return
        const title = String(track.title ? track.title : "").trim()
        if (title === "")
            return

        // Shazam 把「艺人」放在 subtitle 里
        const artist = String(track.subtitle ? track.subtitle : "").trim()
        const changed = (title !== root.title) || (artist !== root.artist)
        root.title = title
        root.artist = artist
        root.identifiedAt = Date.now()
        if (changed)
            root.identified.emit()
    }

    signal identified()

    Process {
        id: recognizeProc
        running: false
        // -i 2：每 2 秒向 Shazam 请求一次；-t 20：最多听 20 秒（通常 2~6 秒就出结果，
        // 脚本一匹配上就退出）；-s monitor：抓系统输出而不是麦克风
        command: [root.scriptPath, "-i", "2", "-t", "20", "-s", "monitor"]

        stdout: StdioCollector {
            onStreamFinished: root.handleOutput(this.text)
        }

        onExited: (exitCode, exitStatus) => {
            root.identifying = false
            if (!root.hasIdentity) {
                // 没认出来：把冷却压短，过一会儿再试
                root.lastAttemptAt = Date.now() - root.attemptCooldownMs + root.retryDelayMs
            }
        }
    }

    // 音频停了就忘掉身份。用去抖是因为切歌、缓冲、短暂静音都会让 playing 抖一下，
    // 立刻清掉会导致每次短暂停顿都重新识别一遍。
    Connections {
        target: AudioActivity
        function onPlayingChanged() {
            if (AudioActivity.playing)
                silenceTimer.stop()
            else
                silenceTimer.restart()
        }
    }

    Timer {
        id: silenceTimer
        interval: 10000
        repeat: false
        onTriggered: root.clear()
    }
}
