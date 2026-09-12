import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Item {
    id: root

    property bool expanded: false
    property var payload: ({})
    property var visualizerPoints: []
    property var lyricsProvider: null
    // 封面主色走全局 IslandPalette，其他活动也能读到同一份颜色。
    // 保留 accentColor 属性仅供宿主兼容注入，实际渲染用 effectiveAccent。
    property color accentColor: "transparent"
    readonly property color effectiveAccent: IslandPalette.accentOr(IslandTheme.text)
    property int page: 0
    readonly property int pageCount: 2

    // 从桌面歌词数据源取当前行附近 5 行
    readonly property var lyricLines: lyricsProvider ? (lyricsProvider.lyricLines ?? []) : []
    readonly property int curIdx: lyricsProvider ? (lyricsProvider.currentLineIndex ?? -1) : -1
    readonly property real lyricTime: lyricsProvider ? (lyricsProvider.adjustedTime ?? 0) : 0

    // 歌词页点击命中：把相对 root 的 y 映射到某一行，命中即请求 seek。
    // 由 DynamicIsland 的 pillMouse 在「未滑动」的点击里调用，
    // 这样既不破坏滑动翻页手势，也不需要在 Column 里放锚点非法的 MouseArea。
    function seekAtY(y) {
        if (!lyricRepeater || lyricRepeater.count === 0)
            return false
        for (let i = 0; i < lyricRepeater.count; i++) {
            const it = lyricRepeater.itemAt(i)
            // 越界槽位高度为 0，跳过
            if (!it || !it.hasLine)
                continue
            const topLeft = it.mapToItem(root, 0, 0)
            if (y >= topLeft.y && y <= topLeft.y + it.height) {
                // 行时间是「歌词坐标系」的时间，而当前行判定用的是
                // currentTime + effectiveOffset。要让它跳过去之后正好成为当前行，
                // 得把这个偏移扣掉，否则手动调过歌词偏移时会差一截。
                const lineStart = it.line ? (it.line.start ?? 0) : 0
                const off = root.lyricsProvider
                    ? (root.lyricsProvider.effectiveOffset ?? 0) : 0
                root.seekRequested(Math.max(0, lineStart - off))
                return true
            }
        }
        return false
    }

    function escapeHtml(s) {
        return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // 歌词窗口用「固定槽位数 + 索引访问」而不是每次重建的数组。
    //
    // 旧写法每次 curIdx 变化都生成一个新数组，Repeater 会把 5 个 delegate
    // 连同内层逐字 Repeater 全部销毁重建；而窗口其实只滑动一行，
    // 多数行内容并未改变。改成整数 model 后 delegate 恒定复用，
    // 窗口滑动只更新属性，不动对象树。
    readonly property int lyricWindowSize: 5
    readonly property int lyricLineCount: lyricLines ? lyricLines.length : 0
    readonly property bool hasLyrics: lyricLineCount > 0

    // 尽量让当前行居中；靠近首尾时窗口贴边
    readonly property int lyricWindowStart: {
        if (lyricLineCount === 0)
            return 0
        return Math.max(0, Math.min(curIdx - 2, Math.max(0, lyricLineCount - lyricWindowSize)))
    }

    // 槽位 → 歌词数组下标；越界返回 -1，delegate 据此塌缩
    function lyricIndexAt(slot) {
        const i = lyricWindowStart + slot
        return (i >= 0 && i < lyricLineCount) ? i : -1
    }

    signal prevRequested()
    signal playPauseRequested()
    signal nextRequested()
    // 歌词行点击：请求跳转到该行起始时间。
    // 必须显式声明，否则 DynamicIsland 里的 `item.seekRequested !== undefined`
    // 恒为 false（连接不会建立），seekAtY 里调用它还会抛 TypeError。
    signal seekRequested(real seconds)

    readonly property real preferredCompactWidth: compactRow.implicitWidth + 10 + 14

    readonly property string title: payload.title !== undefined ? payload.title : "未知歌曲"
    readonly property string artist: payload.artist !== undefined ? payload.artist : "未知艺术家"
    readonly property string artUrl: payload.artUrl !== undefined ? payload.artUrl : ""
    readonly property bool playing: payload.isPlaying !== undefined ? payload.isPlaying : false
    readonly property real progressSec: payload.progress !== undefined ? payload.progress : 0
    readonly property real totalSec: payload.durationSec !== undefined ? payload.durationSec : 1

    function fmtTime(sec) {
        const m = Math.floor(sec / 60)
        const s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    // 圆形封面（带渐变兜底）
    component CircularCover: ClippingRectangle {
        id: cc
        property string artSource: ""
        property real coverSize: 26
        width: coverSize
        height: coverSize
        radius: coverSize / 2
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: cc.radius
            visible: coverImg.status !== Image.Ready
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#EC4899" }
                GradientStop { position: 0.5; color: "#EF4444" }
                GradientStop { position: 1.0; color: "#EAB308" }
            }
        }

        Image {
            id: coverImg
            anchors.fill: parent
            source: cc.artSource
            sourceSize.width: cc.coverSize * 2
            sourceSize.height: cc.coverSize * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }

        Text {
            anchors.centerIn: parent
            visible: coverImg.status !== Image.Ready
            text: "music_note"
            font.family: IslandTheme.iconFontFamily
            font.pixelSize: cc.coverSize * 0.55
            color: "#FFFFFF"
        }
    }

    // ===================== Compact =====================
    RowLayout {
        id: compactRow
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        visible: !root.expanded

        CircularCover {
            Layout.alignment: Qt.AlignVCenter
            coverSize: 26
            artSource: root.artUrl
        }

        IslandVisualizer {
            Layout.alignment: Qt.AlignVCenter
            active: root.playing
            points: root.visualizerPoints
            barCount: 6
            barWidth: 3
            barSpacing: 3
            maxBarHeight: 18
            minBarHeight: 3
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 220
            text: root.title
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }

    // ===================== Expanded =====================
    Item {
        anchors.fill: parent
        // 底部多留 10px：分页点贴在岛底 8px 处，若底部同为 16 会
        // 让按钮行和分页点几乎贴在一起，看起来像顶到了边缘。
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 16
        anchors.bottomMargin: 26
        visible: root.expanded

        // ---- 第 0 页：播放控制 ----
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            opacity: root.page === 0 ? 1 : 0
            transform: Translate {
                x: (0 - root.page) * root.width
                Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                CircularCover {
                    Layout.alignment: Qt.AlignVCenter
                    coverSize: 48
                    artSource: root.artUrl
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.title
                        color: IslandTheme.text
                        font.family: IslandTheme.fontFamily
                        font.pixelSize: IslandTheme.fontTitle
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.artist
                        color: IslandTheme.textSecondary
                        font.family: IslandTheme.fontFamily
                        font.pixelSize: IslandTheme.fontSmall
                        elide: Text.ElideRight
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: IslandTheme.track
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: IslandTheme.text
                        width: parent.width * Math.min(1, root.progressSec / Math.max(1, root.totalSec))
                        Behavior on width {
                            NumberAnimation { duration: IslandTheme.durationQuick; easing.type: Easing.Linear }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.fmtTime(root.progressSec)
                        color: IslandTheme.textTertiary
                        font.family: IslandTheme.fontFamily
                        font.pixelSize: IslandTheme.fontTiny
                        font.features: { "tnum": 1 }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.fmtTime(root.totalSec)
                        color: IslandTheme.textTertiary
                        font.family: IslandTheme.fontFamily
                        font.pixelSize: IslandTheme.fontTiny
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 24

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    Text {
                        anchors.centerIn: parent
                        text: "skip_previous"
                        font.family: IslandTheme.iconFontFamily
                        font.pixelSize: 24
                        color: prevArea.pressed ? IslandTheme.text : IslandTheme.textSecondary
                    }
                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.prevRequested()
                    }
                }

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                        color: IslandTheme.text
                        opacity: playArea.pressed ? 0.75 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                        Text {
                            anchors.centerIn: parent
                            text: root.playing ? "pause" : "play_arrow"
                            font.family: IslandTheme.iconFontFamily
                            font.pixelSize: 22
                            color: "#000000"
                        }
                    }
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.playPauseRequested()
                    }
                }

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    Text {
                        anchors.centerIn: parent
                        text: "skip_next"
                        font.family: IslandTheme.iconFontFamily
                        font.pixelSize: 24
                        color: nextArea.pressed ? IslandTheme.text : IslandTheme.textSecondary
                    }
                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextRequested()
                    }
                }
            }
        }

        // ---- 第 1 页：歌词 ----
        Item {
            anchors.fill: parent
            opacity: root.page === 1 ? 1 : 0
            transform: Translate {
                x: (1 - root.page) * root.width
                Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.hasLyrics
                text: "暂无歌词"
                color: IslandTheme.textTertiary
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 2
                visible: root.hasLyrics

                Repeater {
                    id: lyricRepeater
                    // 整数 model：delegate 数量恒定，窗口滑动不触发销毁重建
                    model: root.lyricWindowSize
                    delegate: Column {
                        id: lineDelegate
                        required property int index
                        // 本槽位对应的歌词下标；越界为 -1
                        readonly property int lineIndex: root.lyricIndexAt(index)
                        readonly property bool hasLine: lineIndex >= 0
                        readonly property var line: hasLine ? root.lyricLines[lineIndex] : null
                        readonly property bool active: hasLine && lineIndex === root.curIdx
                        readonly property var words: (line && line.words) ? line.words : null
                        // 离当前行的距离决定暗度，直接用槽位下标算，
                        // 不再对数组做 indexOf 扫描
                        readonly property real dimOpacity: Math.max(0.2, 0.6 - Math.abs(index - 2) * 0.15)

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // 越界槽位塌缩，让可见行保持原有分布
                        visible: hasLine

                        // 当前行：逐字高亮（分字渲染，避免 RichText 每帧重解析导致的卡顿）
                        Item {
                            id: activeHit
                            // delegate 根是普通 Column，Layout.* 不会生效；必须显式给宽高。
                            // 旧版只写了 Layout.fillWidth/fillHeight，Item 实际宽高都是 0，
                            // 而子项用 anchors.centerIn + clip:true，于是当前行主文本被整条裁掉，
                            // 只剩下面的翻译行可见。
                            width: parent.width
                            height: !lineDelegate.active ? 0 : ((lineDelegate.words && lineDelegate.words.length > 0)
                                ? wordsRow.implicitHeight
                                : plainText.implicitHeight)
                            visible: lineDelegate.active
                            clip: true

                            // 无逐字数据时，整行普通渲染
                            Text {
                                id: plainText
                                anchors.centerIn: parent
                                visible: !(lineDelegate.words && lineDelegate.words.length > 0)
                                text: lineDelegate.line ? (lineDelegate.line.text ?? "") : ""
                                color: IslandTheme.text
                                font.family: IslandTheme.fontFamily
                                font.pixelSize: IslandTheme.fontBody + 1
                                font.weight: Font.Bold
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            // 逐字渲染：每个字两层，暗色底 + 亮色层按字内进度裁剪，
                            // 形成卡拉OK式"从左往右抹过去"的填充，而不是整字硬切。
                            Row {
                                id: wordsRow
                                anchors.centerIn: parent
                                visible: lineDelegate.words && lineDelegate.words.length > 0
                                Repeater {
                                    model: lineDelegate.words ?? []
                                    delegate: Item {
                                        required property var modelData
                                        // 字内进度 0→1；dur 缺失时按整字已唱/未唱处理
                                        readonly property real fill: {
                                            const d = (modelData.dur ?? 0)
                                            if (d <= 0.001)
                                                return root.lyricTime >= modelData.start ? 1 : 0
                                            return Math.max(0, Math.min(1,
                                                (root.lyricTime - modelData.start) / d))
                                        }
                                        implicitWidth: Math.max(1, dimText.implicitWidth)
                                        implicitHeight: dimText.implicitHeight

                                        // 底层：未唱状态
                                        Text {
                                            id: dimText
                                            anchors.left: parent.left
                                            text: modelData.text
                                            color: Qt.rgba(1, 1, 1, 0.22)
                                            font.family: IslandTheme.fontFamily
                                            font.pixelSize: IslandTheme.fontBody + 1
                                            font.weight: Font.Bold
                                        }

                                        // 上层：按 fill 从左往右裁出的已唱部分
                                        Item {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            width: parent.width * parent.fill
                                            height: parent.height
                                            clip: true
                                            visible: parent.fill > 0

                                            Text {
                                                anchors.left: parent.left
                                                text: modelData.text
                                                // 有封面主色时用它，否则纯白
                                                color: root.effectiveAccent
                                                font.family: IslandTheme.fontFamily
                                                font.pixelSize: IslandTheme.fontBody + 1
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 非当前行：暗淡、字号略小
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            visible: !lineDelegate.active
                            text: lineDelegate.line ? (lineDelegate.line.text ?? "") : ""
                            color: IslandTheme.textTertiary
                            font.family: IslandTheme.fontFamily
                            font.pixelSize: IslandTheme.fontSmall
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            opacity: lineDelegate.dimOpacity
                        }

                        // 翻译/英文行：随当前行一同高亮（原来恒暗，导致“英文不高亮”）
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            readonly property string transText: lineDelegate.line ? (lineDelegate.line.trans ?? "") : ""
                            visible: lineDelegate.active && transText.length > 0
                            text: transText
                            color: IslandTheme.text
                            opacity: 0.85
                            font.family: IslandTheme.fontFamily
                            font.pixelSize: IslandTheme.fontTiny + 1
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
