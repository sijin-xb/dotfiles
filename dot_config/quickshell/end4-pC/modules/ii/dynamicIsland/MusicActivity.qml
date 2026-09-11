import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Item {
    id: root

    property bool expanded: false
    property var payload: ({})
    property var visualizerPoints: []
    property var lyricsProvider: null
    property int page: 0
    readonly property int pageCount: 2

    // 从桌面歌词数据源取当前行附近 5 行
    readonly property var lyricLines: lyricsProvider ? (lyricsProvider.lyricLines ?? []) : []
    readonly property int curIdx: lyricsProvider ? (lyricsProvider.currentLineIndex ?? -1) : -1
    readonly property real lyricTime: lyricsProvider ? (lyricsProvider.adjustedTime ?? 0) : 0

    function escapeHtml(s) {
        return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    readonly property var lyricWindow: {
        const lines = []
        if (!lyricLines || lyricLines.length === 0) return lines
        const start = Math.max(0, curIdx - 2)
        const end = Math.min(lyricLines.length, start + 5)
        for (let i = start; i < end; i++) {
            lines.push({
                text: lyricLines[i].text ?? "",
                trans: lyricLines[i].trans ?? "",
                words: lyricLines[i].words ?? null,
                active: i === curIdx
            })
        }
        return lines
    }

    signal prevRequested()
    signal playPauseRequested()
    signal nextRequested()

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
        anchors.margins: 16
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
                visible: root.lyricWindow.length === 0
                text: "暂无歌词"
                color: IslandTheme.textTertiary
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 2
                visible: root.lyricWindow.length > 0

                Repeater {
                    model: root.lyricWindow
                    delegate: Column {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // 当前行：逐字高亮（分字渲染，避免 RichText 每帧重解析导致的卡顿）
                        Item {
                            // delegate 根是普通 Column，Layout.* 不会生效；必须显式给宽高。
                            // 旧版只写了 Layout.fillWidth/fillHeight，Item 实际宽高都是 0，
                            // 而子项用 anchors.centerIn + clip:true，于是当前行主文本被整条裁掉，
                            // 只剩下面的翻译行可见。
                            width: parent.width
                            height: !modelData.active ? 0 : ((modelData.words && modelData.words.length > 0)
                                ? wordsRow.implicitHeight
                                : plainText.implicitHeight)
                            visible: modelData.active
                            clip: true

                            // 无逐字数据时，整行普通渲染
                            Text {
                                id: plainText
                                anchors.centerIn: parent
                                visible: !(modelData.words && modelData.words.length > 0)
                                text: modelData.text
                                color: IslandTheme.text
                                font.family: IslandTheme.fontFamily
                                font.pixelSize: IslandTheme.fontBody + 1
                                font.weight: Font.Bold
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            // 逐字渲染：每个字一个 Text，仅颜色变化，引擎无需重解析
                            Row {
                                id: wordsRow
                                anchors.centerIn: parent
                                visible: modelData.words && modelData.words.length > 0
                                Repeater {
                                    model: modelData.words ?? []
                                    delegate: Text {
                                        required property var modelData
                                        readonly property bool lit: root.lyricTime >= modelData.start
                                        text: modelData.text
                                        // 已唱：纯白高亮；未唱：更暗（0.22），拉开对比
                                        color: lit ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.22)
                                        font.family: IslandTheme.fontFamily
                                        font.pixelSize: IslandTheme.fontBody + 1
                                        font.weight: Font.Bold
                                        Behavior on color { ColorAnimation { duration: 90 } }
                                    }
                                }
                            }
                        }

                        // 非当前行：暗淡、字号略小
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            visible: !modelData.active
                            text: modelData.text
                            color: IslandTheme.textTertiary
                            font.family: IslandTheme.fontFamily
                            font.pixelSize: IslandTheme.fontSmall
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            opacity: {
                                const d = Math.abs(root.lyricWindow.indexOf(modelData) - 2)
                                return Math.max(0.2, 0.6 - d * 0.15)
                            }
                        }

                        // 翻译/英文行：随当前行一同高亮（原来恒暗，导致“英文不高亮”）
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            visible: modelData.active && modelData.trans.length > 0
                            text: modelData.trans
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
