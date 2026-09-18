// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/services/CavaService.qml
//
// 改动：
//   1. 删除相对 import（原文件 `import "../"`）。
//   2. 根类型 QtObject → Singleton（对齐本目录单例写法）。
//   3. 正文逐字保留，包括它自己起 cava 进程、写 /tmp/brain_shell/cava_shared.ini
//      的那段（cava 二进制本机存在，配置写法与上游一致）。
//   4. 频谱来源改为优先走 Caelestia 的 C++ cava 插件（见下方说明）。原来那段
//      起 cava 子进程的代码原样保留，作为插件不可用时的兜底。
//
// 为什么不用 end4-pC 的 CavaSource 包一层：modules/ii/dynamicIsland/CavaSource.qml
// 不是单例（是 Item），而且它的 API 是 points: list<real>（复用
// GlobalStates.visualizerPoints），没有 barCount / bars / isPlaying 这套形状，
// 与上层 PlayerCard / CenterContent 的用法对不上，所以按用户给的规则退回照搬。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Single cava process shared by CenterContent and PlayerCard.
// 32 bars at 30fps. isPlaying mirrors the active MPRIS player state.

Singleton {
    id: root

    readonly property int barCount: 32

    property var bars: (function() {
        var a = []; for (var i = 0; i < 32; i++) a.push(0); return a
    })()

    // isPlaying is true if ANY MPRIS player is currently playing.
    // This ensures bars flow regardless of which player index is active in PlayerCard.
    readonly property bool isPlaying: {
        var vals = Mpris.players.values
        for (var i = 0; i < vals.length; i++) {
            if (vals[i].playbackState === MprisPlaybackState.Playing) return true
        }
        return false
    }

    // ── 频谱来源：Caelestia 的 C++ cava 插件 ─────────────────────────────────
    // 上游这里是 `running: true` 的常驻 cava 子进程 —— 不管有没有播放器都在跑，
    // 而且每帧的 ascii 输出还要在主线程上 split + parseInt。
    //
    // 现在优先用 C++ 插件（它内部直接从 PipeWire 抓音频、在独立线程里算 FFT），
    // 并且跟着 isPlaying 启停。插件不可用（没编译 / QML2_IMPORT_PATH 没指对）时
    // 才退回原来的子进程。
    //
    // 本文件是 Singleton，没法用 Loader 兜住 import 失败（Loader 是 Item，塞不进
    // QtObject 派生类型），所以用 Qt.createComponent 手动加载：status 不是 Ready
    // 就说明插件不可用，此时把 _bridgeFailed 置位，让下面的 Process 接手。
    property var _bridge: null
    property bool _bridgeFailed: false

    Component.onCompleted: {
        var c = Qt.createComponent(Qt.resolvedUrl("../services/CaelestiaCava.qml"))
        if (c.status !== Component.Ready) {
            root._bridgeFailed = true
            console.warn("Caelestia cava 插件不可用，岛屿频谱回退到 cava 子进程：" + c.errorString())
            return
        }
        root._bridge = c.createObject(root, {
            bars: root.barCount,
            // 上游那份配置写的是 ascii_max_range = 100，所以这里缩放到 0~100
            valueScale: 100,
            active: root.isPlaying
        })
    }

    onIsPlayingChanged: {
        if (root._bridge)
            root._bridge.active = root.isPlaying
    }

    Connections {
        target: root._bridge

        function onPointsChanged(): void {
            const p = root._bridge.points
            var a = []
            for (var i = 0; i < root.barCount; i++)
                a.push(p[i] ?? 0)
            root.bars = a
        }
    }

    // 兜底：插件不可用时的原实现（保持它原来的 running: true 常开行为）
    property var _proc: Process {
        command: [
            "bash", "-c",
            "mkdir -p /tmp/brain_shell && " +
            "printf '[general]\\nbars = 32\\nframerate = 30\\nnoise_reduction = 77\\n\\n" +
            "[output]\\nmethod = raw\\nraw_target = /dev/stdout\\n" +
            "data_format = ascii\\nascii_max_range = 100\\n" +
            "bar_delimiter = 59\\nframe_delimiter = 10\\n' " +
            "> /tmp/brain_shell/cava_shared.ini && " +
            "exec cava -p /tmp/brain_shell/cava_shared.ini 2>/dev/null"
        ]
        running: root._bridgeFailed
        stdout: SplitParser {
            onRead: function(line) {
                var t = line.trim()
                if (t === "") return
                if (t.endsWith(";")) t = t.slice(0, -1)
                var parts = t.split(";")
                if (parts.length !== root.barCount) return
                var arr = []
                for (var i = 0; i < parts.length; i++)
                    arr.push(parseInt(parts[i]) || 0)
                root.bars = arr
            }
        }
    }
}
