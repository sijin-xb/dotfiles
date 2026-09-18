// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/services/CavaService.qml
//
// 改动：
//   1. 删除相对 import（原文件 `import "../"`）。
//   2. 根类型 QtObject → Singleton（对齐本目录单例写法）。
//   3. 正文逐字保留，包括它自己起 cava 进程、写 /tmp/brain_shell/cava_shared.ini
//      的那段（cava 二进制本机存在，配置写法与上游一致）。
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
        running: true
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
