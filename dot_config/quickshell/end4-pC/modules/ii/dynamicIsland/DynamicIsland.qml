import QtQuick

// 灵动岛主容器。
// 窗口尺寸恒定，动画只发生在内部 pill 上；无活动时 pill 收缩到 0。
Item {
    id: root

    property string activityType: "idle"
    property bool expanded: false
    property var payload: ({})
    property var visualizerPoints: []
    property var lyricsProvider: null

    // 展开态的页面（多页活动用，如音乐的控制页/歌词页）
    property int page: 0
    readonly property int pageCount: activityLoader.item ? (activityLoader.item.pageCount ?? 1) : 1

    property real dragShift: 0

    signal activated()
    signal dismissRequested()
    signal musicPrev()
    signal musicPlayPause()
    signal musicNext()

    property alias pillItem: pill

    readonly property bool hasContent: activityType !== "idle"
    readonly property var targetSize: IslandTheme.sizeFor(activityType, expanded)

    property real animatedWidth: 0
    property real animatedHeight: 0
    property real animatedRadius: 19

    // 活动组件报告的“内容自然宽度”（compact 态自适应用）
    readonly property real itemPreferredWidth: activityLoader.item
        ? (activityLoader.item.preferredCompactWidth ?? 0) : 0

    function syncSize() {
        if (!hasContent) {
            animatedWidth = 0
            animatedHeight = 0
            animatedRadius = 19
            return
        }
        animatedHeight = targetSize.h
        animatedRadius = targetSize.r
        if (expanded) {
            animatedWidth = targetSize.w
        } else {
            // compact：宽度跟随内容，限制在 [w, maxW]
            const minW = targetSize.w
            const maxW = (targetSize.maxW !== undefined) ? targetSize.maxW : minW
            const pref = itemPreferredWidth > 0 ? itemPreferredWidth : minW
            animatedWidth = Math.max(minW, Math.min(maxW, pref))
        }
    }
    onTargetSizeChanged: syncSize()
    onHasContentChanged: syncSize()
    onItemPreferredWidthChanged: syncSize()

    // 收起时回到第一页；切换活动时也重置
    onExpandedChanged: { if (!expanded) page = 0 }
    onActivityTypeChanged: page = 0

    Component.onCompleted: syncSize()

    Behavior on animatedWidth {
        NumberAnimation { duration: IslandTheme.durationExpand; easing.type: Easing.OutQuint }
    }
    Behavior on animatedHeight {
        NumberAnimation { duration: IslandTheme.durationExpand; easing.type: Easing.OutQuint }
    }
    Behavior on animatedRadius {
        NumberAnimation { duration: IslandTheme.durationExpand; easing.type: Easing.OutQuint }
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.animatedWidth
        height: root.animatedHeight
        radius: root.animatedRadius
        color: IslandTheme.surface
        clip: true
        antialiasing: true

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            property real pressX: 0
            property bool swiped: false

            onPressed: (e) => { pressX = e.x; swiped = false; root.dragShift = 0 }
            onPositionChanged: (e) => {
                if (root.expanded && root.pageCount > 1) {
                    const dx = e.x - pressX
                    if (Math.abs(dx) > 8) swiped = true
                    // 跟手位移（限制在相邻页范围内）
                    if (swiped)
                        root.dragShift = Math.max(-root.animatedWidth, Math.min(root.animatedWidth, dx * 0.5))
                }
            }
            onReleased: (e) => {
                if (swiped) {
                    const dx = e.x - pressX
                    if (dx < -40 && root.page < root.pageCount - 1) root.page += 1
                    else if (dx > 40 && root.page > 0) root.page -= 1
                } else {
                    root.activated()
                }
                root.dragShift = 0
            }
        }

        Loader {
            id: activityLoader
            anchors.fill: parent
            sourceComponent: root.componentFor(root.activityType)
            opacity: 0

            NumberAnimation {
                id: fadeIn
                target: activityLoader
                property: "opacity"
                to: 1
                duration: IslandTheme.durationContentFade
                easing.type: Easing.OutCubic
            }
            onSourceComponentChanged: {
                opacity = 0
                fadeIn.restart()
            }
            onItemChanged: {
                if (item) {
                    item.expanded = Qt.binding(function() { return root.expanded })
                    item.payload = Qt.binding(function() { return root.payload })
                    if (item.visualizerPoints !== undefined)
                        item.visualizerPoints = Qt.binding(function() { return root.visualizerPoints })
                    if (item.page !== undefined)
                        item.page = Qt.binding(function() { return root.page })
                    if (item.lyricsProvider !== undefined)
                        item.lyricsProvider = Qt.binding(function() { return root.lyricsProvider })
                    // 转发音乐控制信号（仅 MusicActivity 有这些信号）
                    if (item.prevRequested !== undefined) {
                        item.prevRequested.connect(root.musicPrev)
                        item.playPauseRequested.connect(root.musicPlayPause)
                        item.nextRequested.connect(root.musicNext)
                    }
                }
            }
        }

        // 页面指示点（仅展开且多页时显示）
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 5
            visible: root.expanded && root.pageCount > 1

            Repeater {
                model: root.pageCount
                Rectangle {
                    required property int index
                    width: 5
                    height: 5
                    radius: 2.5
                    color: index === root.page ? IslandTheme.text : IslandTheme.trackStrong
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }

    function componentFor(type) {
        switch (type) {
        case "music":     return musicComp
        case "volume":    return volumeComp
        case "recording": return recordingComp
        default:          return idleComp
        }
    }

    Component { id: musicComp;     MusicActivity {} }
    Component { id: volumeComp;    VolumeActivity {} }
    Component { id: recordingComp; RecordingActivity {} }
    Component { id: idleComp;      IdleActivity {} }
}
