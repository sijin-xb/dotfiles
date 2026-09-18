import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services

// ─────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 的 src/services/home/PlayerCard.qml 移植。
//
// 改动：
//   1. 删除 import "../../" 与 import "../../components"（扁平化后同目录隐式导入）；
//   2. 播放器来源从裸 `Mpris.players.values`（自己维护一份 blocklist）改为
//      end4-pC 的 `MprisController`。原因：上游那份 blocklist 只挡了
//      kdeconnect / gsconnect / playerctld / plasma-browser-integration，
//      挡不住 Chrome 原生 MPRIS bus，结果一个开着 GitHub 页面的 Chrome
//      会被当成"正在播放"，卡片显示网页标题。MprisController 走
//      `Config.options.media.ignoreBrowserPlayers`（用户已开），
//      判定逻辑与 Bar / 侧栏的媒体组件完全一致；
//   3. 播放器下拉切换改为写 `MprisController.trackedPlayer`，
//      不再维护自己的 selectedPlayerIndex；
//   4. 新增「多行歌词窗」（当前行居中，上下各两行，只给当前行配翻译），
//      取自 ClockDashboard 的 lyricsColumn，改成岛屿的配色与字号；
//   5. 进度条从「点击跳转」升级为「可拖拽 seek」，取自 ClockDashboard：
//      preventStealing 防父级抢事件、拖动期间本地预览、松手后按相对偏移
//      seek(target - current)、400ms 后再放开预览以免 D-Bus position 未追上时回跳；
//   6. 整块内容改为 ColumnLayout 纵向排布（标题 / 艺术家 / 歌词 / 控制 / 进度），
//      让歌词窗吃掉剩余高度。原来的「标题贴顶 + 底部堆栈贴底」两段式布局
//      中间会留一大片空白；
//   7. Nerd Font 字形补 font.family（end4-pC 无应用级图标字体约定）。
//
// 依赖：
//   - MprisController / LyricsService：end4-pC 的服务单例（import qs.services）；
//   - CavaService：并行工作提供的同名 shim 单例（bars 属性），原样引用。
// ─────────────────────────────────────────────────────────────────────────

Item {
    id: root

    // ── MPRIS ─────────────────────────────────────────────────────────────────
    // MprisController.players 已经做过去重 + 浏览器过滤，
    // activePlayer 优先返回 trackedPlayer（用户在下拉里手选的），否则返回第一个。
    readonly property var filteredPlayers: MprisController.players
    readonly property var player:          MprisController.activePlayer

    readonly property int selectedPlayerIndex: {
        const i = root.filteredPlayers.indexOf(root.player)
        return i >= 0 ? i : 0
    }

    property bool _dropdownOpen: false

    onVisibleChanged: if (!visible) root._dropdownOpen = false

    readonly property bool   isPlaying: root.player?.playbackState === MprisPlaybackState.Playing ?? false
    readonly property string artUrl:    root.player?.trackArtUrl ?? ""

    readonly property string title: {
        var t = root.player?.trackTitle
        return (t && t !== "") ? t : "Nothing Playing"
    }
    readonly property string artist: {
        var a = root.player?.trackArtists
        if (!a) return ""
        if (typeof a === "string") return a
        if (typeof a.join === "function") return a.join(", ")
        return a.toString()
    }

    readonly property real length:   root.player?.length   ?? 0
    readonly property real position: root.player?.position ?? 0

    property real _pos: 0
    onPositionChanged: root._pos = position

    Timer {
        interval: 1000; running: root.isPlaying; repeat: true
        onTriggered: {
            if (root.length > 0)
                root._pos = Math.min(root._pos + 1, root.length)
        }
    }

    function _fmt(sec) {
        var s = Math.floor(sec)
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    // ── Shared cava bars (32 bars from CavaService) ───────────────────────────
    readonly property int _cavaBars: 32
    readonly property var _bars: CavaService.bars

    // ── Player icon helper ────────────────────────────────────────────────────
    function _playerIcon(player) {
        if (!player) return "♪"
        var id = (player.identity || "").toLowerCase()
        if (id.indexOf("spotify")  !== -1) return "󰓇"
        if (id.indexOf("firefox")  !== -1) return "󰈹"
        if (id.indexOf("chromium") !== -1) return "󰊯"
        if (id.indexOf("chrome")   !== -1) return "󰊯"
        if (id.indexOf("brave")    !== -1) return "󰊯"
        if (id.indexOf("youtube")  !== -1) return "󰗃"
        return "♪"
    }

    // ── Player label helper ───────────────────────────────────────────────────
    function _playerLabel(player) {
        if (!player) return "—"
        var id = (player.identity || "").toLowerCase()
        if (id.indexOf("spotify")  !== -1) return "Spotify"
        if (id.indexOf("firefox")  !== -1) return "Firefox"
        if (id.indexOf("chromium") !== -1) return "Chromium"
        if (id.indexOf("chrome")   !== -1) return "Chrome"
        if (id.indexOf("brave")    !== -1) return "Brave"
        if (id.indexOf("youtube")  !== -1) return "YouTube"
        if (id.indexOf("edge")     !== -1) return "Edge"
        if (id.indexOf("opera")    !== -1) return "Opera"
        if (id.indexOf("vivaldi")  !== -1) return "Vivaldi"
        return player.identity || "Player"
    }

    // ── Background visuals ────────────────────────────────────────────────────
    Item {
        id: bgSource
        anchors.fill:  parent
        opacity:       0
        layer.enabled: true

        Item {
            id: artSource
            anchors.fill:  parent
            layer.enabled: true
            Image {
                anchors.fill: parent
                source:   root.artUrl
                fillMode: Image.PreserveAspectCrop
                smooth:   true
            }
        }

        MultiEffect {
            source:       artSource
            anchors.fill: parent
            visible:      root.artUrl !== ""
            opacity:      root.artUrl !== "" ? 1 : 0
            blurEnabled:  true
            blur:         0.5
            blurMax:      32
            saturation:   0.2
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0,0,0,0.38) }
                GradientStop { position: 0.4; color: Qt.rgba(0,0,0,0.50) }
                GradientStop { position: 1.0; color: Qt.rgba(0,0,0,0.88) }
            }
        }
    }

    Rectangle {
        id: bgMask
        anchors.fill:  parent
        radius:        Theme.cornerRadius
        visible:       false
        layer.enabled: true
    }

    MultiEffect {
        source:           bgSource
        anchors.fill:     parent
        maskEnabled:      true
        maskSource:       bgMask
        maskThresholdMin: 0.5
        maskSpreadAtMin:  1.0
    }

    // ── Content: title / artist / lyrics / controls / progress ────────────────
    ColumnLayout {
        anchors {
            left:   parent.left;   leftMargin:   14
            right:  parent.right;  rightMargin:  14
            top:    parent.top;    topMargin:    12
            bottom: parent.bottom; bottomMargin: 42   // 让开底部 cava 频谱条
        }
        spacing: 0

        // ── Title with Marquee Scroll ──
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            clip: true
            TextMetrics {
                id: titleMetrics
                font: titleText.font
                text: root.title
            }
            Text {
                id: titleText
                text: root.title
                font.pixelSize: 18; font.weight: Font.Bold
                color: "#ffffff"
                anchors.horizontalCenter: titleMetrics.width <= parent.width ? parent.horizontalCenter : undefined
                NumberAnimation on x {
                    id: marqueeAnim
                    running: titleMetrics.width > titleText.parent.width && root.isPlaying
                    from: titleText.parent.width
                    to: -titleMetrics.width
                    duration: Math.max(0, (titleMetrics.width + titleText.parent.width) * 20)
                    loops: Animation.Infinite
                }
                onTextChanged: marqueeAnim.restart()
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            text:    root.artist
            visible: root.artist !== ""
            font.pixelSize: 13
            color: Qt.rgba(1,1,1,0.55)
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        // ── 多行歌词窗 ────────────────────────────────────────────────────────
        // 视觉层级：
        //   当前行：14px + Bold + active 色，最亮最重
        //   相邻行：11px + text 色，opacity 随距离线性衰减
        //   翻译行：只给当前行显示，subtext 色
        Item {
            id: lyricsWindow
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6
            clip: true

            readonly property int beforeLines: 2
            readonly property int afterLines:  2
            readonly property int windowSize:  beforeLines + 1 + afterLines
            readonly property int activeLine:  LyricsService.currentLineIndex
            readonly property var lineData:    LyricsService.lyricLines
            readonly property bool showing:    LyricsService.hasLyrics && activeLine >= 0

            function lineAt(i) {
                const idx = activeLine - beforeLines + i
                if (idx < 0 || idx >= lineData.length)
                    return null
                return lineData[idx]
            }

            // 没有歌词时的占位文案
            Text {
                anchors.centerIn: parent
                visible: !lyricsWindow.showing
                text: LyricsService.status === "loading"
                      ? Translation.tr("Searching lyrics…")
                      : Translation.tr("No lyrics")
                font.pixelSize: 11
                color: Qt.rgba(1,1,1,0.28)
            }

            Column {
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 3
                visible: lyricsWindow.showing

                Repeater {
                    model: lyricsWindow.windowSize

                    delegate: Column {
                        required property int index
                        readonly property var  line:     lyricsWindow.lineAt(index)
                        readonly property bool isActive: index === lyricsWindow.beforeLines
                        readonly property int  distance: Math.abs(index - lyricsWindow.beforeLines)

                        width:   parent.width
                        spacing: 1
                        visible: line !== null

                        Text {
                            width: parent.width
                            text:  line?.text ?? ""
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: isActive ? 2 : 1
                            elide: Text.ElideRight
                            color: isActive ? Theme.active : Theme.text
                            opacity: isActive ? 1.0 : Math.max(0.20, 0.60 - distance * 0.20)
                            font.pixelSize: isActive ? 14 : 11
                            font.weight: isActive ? Font.Bold : Font.Normal
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            width: parent.width
                            visible: isActive && (line?.trans ?? "").length > 0
                            text: line?.trans ?? ""
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            color: Theme.subtext
                            opacity: 0.9
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        // ── Controls ──────────────────────────────────────────────────────────
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            spacing: 28
            Repeater {
                model: [ { key: "prev" }, { key: "play" }, { key: "next" } ]
                delegate: Rectangle {
                    required property var  modelData
                    required property int  index
                    readonly property bool isPlay: modelData.key === "play"
                    readonly property string dispIcon: {
                        if (modelData.key === "prev") return "󰒫"
                        if (modelData.key === "next") return "󰒬"
                        return !root.isPlaying ? "󰐊" : "󰏤"
                    }
                    width: 36; height: 36
                    radius: height / 2
                    color: isPlay
                           ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.18)
                           : cH.hovered ? Qt.rgba(1,1,1,0.14) : Qt.rgba(1,1,1,0.06)
                    border.color: isPlay ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.3) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: parent.dispIcon
                        font.pixelSize: isPlay ? 18 : 14
                        // dispIcon 是 Nerd Font 字形，不指定字体族会渲染成豆腐块
                        font.family: Theme.nerdFontFamily
                        color: isPlay ? Theme.active : Qt.rgba(1,1,1,0.7)
                    }
                    HoverHandler { id: cH; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!root.player) return
                            switch (modelData.key) {
                                case "play":
                                    if (root.player.canTogglePlaying)
                                        root.player.isPlaying = !root.player.isPlaying
                                    break
                                case "prev":
                                    if (root.player.canGoPrevious) root.player.previous()
                                    break
                                case "next":
                                    if (root.player.canGoNext) root.player.next()
                                    break
                            }
                        }
                    }
                }
            }
        }

        // ── Progress bar (draggable seek) + timestamps ────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 3

            Item {
                id: progressTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 6

                readonly property real totalLength: Math.max(1, root.length)
                readonly property bool hasTrack:    root.length > 0
                // 拖动时的本地预览位置（秒）；-1 表示没有拖动
                property real dragPosition: -1
                readonly property real displayPosition: dragPosition >= 0 ? dragPosition : root._pos
                readonly property real progress: Math.max(0, Math.min(1, displayPosition / totalLength))

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1,1,1,0.2)

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width:  Math.max(0, parent.width * progressTrack.progress)
                        radius: parent.radius
                        color:  Theme.active
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }

                // 进度圆点
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: Theme.active
                    visible: progressTrack.hasTrack
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * progressTrack.progress - width / 2
                    scale: progressMouse.pressed ? 1.35 : (progressMouse.containsMouse ? 1.15 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }

                Timer {
                    id: seekClearTimer
                    interval: 400
                    onTriggered: progressTrack.dragPosition = -1
                }

                MouseArea {
                    id: progressMouse
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    width:  parent.width
                    height: 20
                    enabled: root.player !== null && progressTrack.hasTrack
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    // 阻止父级 Flickable 在按下时偷走事件，否则一拖就变成翻页
                    preventStealing: true

                    function posToSeconds(mx) {
                        const ratio = Math.max(0, Math.min(1, mx / width))
                        return ratio * progressTrack.totalLength
                    }

                    onPressed: (mouse) => {
                        seekClearTimer.stop()
                        progressTrack.dragPosition = posToSeconds(mouse.x)
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed)
                            progressTrack.dragPosition = posToSeconds(mouse.x)
                    }
                    onReleased: (mouse) => {
                        const target  = posToSeconds(mouse.x)
                        const current = root.player?.position ?? 0
                        if (root.player)
                            root.player.seek(target - current)
                        // 保住预览，等 D-Bus position 追上再放开，避免视觉回跳
                        progressTrack.dragPosition = target
                        seekClearTimer.restart()
                    }
                    onCanceled: progressTrack.dragPosition = -1
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 14

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: root._fmt(progressTrack.displayPosition)
                    font.pixelSize: 9; font.family: Theme.monoFontFamily
                    color: Qt.rgba(1,1,1,0.4)
                }

                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: root._fmt(root.length)
                    font.pixelSize: 9; font.family: Theme.monoFontFamily
                    color: Qt.rgba(1,1,1,0.4)
                }
            }
        }
    }

    // ── Source picker — dropdown from the top-right corner ────────────────────
    Item {
        id: sourcePicker
        anchors {
            top:          parent.top
            right:        parent.right
            topMargin:    12
            rightMargin:  12
        }
        visible: root.filteredPlayers.length > 1
        z:       30

        width:  pill.width
        height: pill.height

        Rectangle {
            id: pill
            anchors.top:   parent.top
            anchors.right: parent.right

            // Width tracks the active row + padding
            width: activeRow.implicitWidth + 24

            readonly property int _rowH: 26
            height: root._dropdownOpen
                    ? (_rowH * root.filteredPlayers.length)
                    : _rowH
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            radius:       _rowH / 2
            clip:         true
            color:        Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.15)
            border.color: root._dropdownOpen
                          ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.30)
                          : "transparent"
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 150 } }

            // Stacks downward from the top
            Column {
                anchors.top:   parent.top
                anchors.left:  parent.left
                anchors.right: parent.right
                spacing: 0

                // ── Active player row (Always at the top) ─────────────
                Item {
                    height: pill._rowH
                    width:  parent.width

                    Row {
                        id: activeRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text:           root.player ? root._playerIcon(root.player) : "♪"
                            font.pixelSize: 11
                            font.family:    Theme.nerdFontFamily
                            color:          Theme.active
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text:           root.player ? root._playerLabel(root.player) : "Player"
                            font.pixelSize: 11
                            font.weight:    Font.Medium
                            color:          Qt.rgba(1,1,1,0.92)
                            // Cap width so crazy browser identities don't stretch the pill
                            width:          Math.min(implicitWidth, 120)
                            elide:          Text.ElideRight
                        }
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked:    root._dropdownOpen = !root._dropdownOpen
                    }
                }

                // ── Other player rows (Drop down below active) ─────────
                Repeater {
                    model: root.filteredPlayers
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: index === root.selectedPlayerIndex

                        width:  parent.width
                        height: isCurrent ? 0 : (root._dropdownOpen ? pill._rowH : 0)
                        visible: !isCurrent
                        opacity: root._dropdownOpen ? 1 : 0

                        Behavior on height  { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 140 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text:           root._playerIcon(modelData)
                                font.pixelSize: 11
                                font.family:    Theme.nerdFontFamily
                                color:          rowH.hovered ? Qt.rgba(1,1,1,0.90) : Qt.rgba(1,1,1,0.55)
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text:           root._playerLabel(modelData)
                                font.pixelSize: 11
                                color:          rowH.hovered ? Qt.rgba(1,1,1,0.90) : Qt.rgba(1,1,1,0.55)
                                width:          Math.min(implicitWidth, 120)
                                elide:          Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                        }

                        HoverHandler { id: rowH; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                // 交给 MprisController 记住选择，activePlayer 会跟随
                                MprisController.trackedPlayer = modelData
                                root._dropdownOpen = false
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Cava bars — independent, always flush with the card bottom ────────────
    Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 7; rightMargin: 7; bottomMargin: 4 }
        height: 32
        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 2
            readonly property real barW: Math.max(1, (parent.width - spacing * (root._cavaBars - 1)) / root._cavaBars)
            Repeater {
                model: root._bars
                delegate: Item {
                    required property int modelData
                    required property int index
                    width: parent.barW; height: 32
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width:  parent.width
                        readonly property real _amp: root.isPlaying ? (modelData / 100) : 0
                        height: Math.max(2, _amp * 32)
                        radius: width / 2
                        color:  Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.25 + _amp * 0.65)
                        Behavior on height { NumberAnimation { duration: 50; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    // Border
    Rectangle {
        anchors.fill: parent
        radius:       Theme.cornerRadius
        color:        "transparent"
        border.color: Qt.rgba(1,1,1,0.08)
        border.width: 1
    }

    // Close dropdown on click outside
    TapHandler {
        enabled: root._dropdownOpen
        onTapped: root._dropdownOpen = false
    }
}
