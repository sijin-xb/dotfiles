import QtQuick
import Quickshell
import Quickshell.Io

// 封面取色源：把当前歌曲封面量化成一个主色，供灵动岛着色。
//
// 时序：封面 URL 变化 → 下载到本地（带缓存）→ ColorQuantizer 异步量化 →
// 拿到主色后通过 Behavior 平滑过渡，避免切歌瞬间颜色跳变。
// 无封面或量化未完成时保持 fallbackColor。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // 由外部（Host）注入当前封面 URL
    property string artUrl: ""
    // 未就绪时的回退色（与 IslandPalette.progressEnd 默认值一致）
    property color fallbackColor: "#6366F1"

    readonly property string cacheDir: `${Quickshell.env("HOME")}/.cache/quickshell/media/coverart`
    readonly property string artFilePath: `${cacheDir}/${Qt.md5(root.artUrl)}`
    property bool downloaded: false

    // 量化出来的原始主色；空封面时为空
    property color rawColor: "transparent"

    // 对外输出：量化成功用主色，否则回退。
    // 加 Behavior 让切歌时颜色平滑过渡而不是瞬间跳变。
    property color dominantColor: (downloaded && rawColor.a > 0.01)
        ? rawColor : fallbackColor
    Behavior on dominantColor {
        ColorAnimation { duration: 600; easing.type: Easing.InOutQuad }
    }

    onArtUrlChanged: {
        if (!artUrl || artUrl.length === 0) {
            downloaded = false
            rawColor = "transparent"
            return
        }
        if (artUrl.startsWith("file://")) {
            // 本地文件直接量化，不需要下载
            downloaded = false
            rawColor = "transparent"
            localQuantTimer.restart()
            return
        }
        downloaded = false
        rawColor = "transparent"
        downloader.running = false
        downloader.running = true
    }

    // 本地封面：直接把 source 指过去
    Timer {
        id: localQuantTimer
        interval: 0
        onTriggered: {
            quantizer.source = root.artUrl
            root.downloaded = true
        }
    }

    Process {
        id: downloader
        // -f 已存在则不重复下载；-sSL 静默跟随重定向
        command: ["bash", "-c",
            `mkdir -p '${root.cacheDir}'; [ -f '${root.artFilePath}' ] || curl -4 -sSL '${root.artUrl}' -o '${root.artFilePath}'`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                quantizer.source = Qt.resolvedUrl(root.artFilePath)
                root.downloaded = true
            }
        }
    }

    ColorQuantizer {
        id: quantizer
        source: ""
        depth: 0          // 2^0 = 1 color，只要主色
        rescaleSize: 8    // 小图足够，量化更快
        onColorsChanged: {
            if (quantizer.colors.length > 0)
                root.rawColor = quantizer.colors[0]
        }
    }
}
