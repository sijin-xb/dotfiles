import QtQuick
import qs.services

// 灵动岛主容器。
// 窗口尺寸恒定，动画只发生在内部 pill 上；无活动时 pill 收缩到 0。
Item {
    id: root

    property string activityType: "idle"
    property bool expanded: false
    property var payload: ({})

    // 聚焦的活动：点副岛胶囊时设置，主岛临时改为显示它并展开。
    // 收起时清空，回到正常的「优先级最高的活动」。
    property string focusType: ""
    readonly property string renderType: focusType.length > 0 ? focusType : activityType
    readonly property var renderPayload: focusType.length > 0
        ? (((ActivityManager.entries ?? {})[focusType] ?? {}).payload ?? {})
        : payload
    property var visualizerPoints: []
    property var lyricsProvider: null
    // 封面主色：注入到活动组件，用于频谱/歌词高亮着色
    property color accentColor: "transparent"

    // 位置偏移：由 Host 设置并持久化（Persistent.states.island），右键拖动改变。
    property real offsetX: 0
    property real offsetY: 0
    // 无偏移时岛距屏幕顶部的距离。
    property real baseTop: 62

    // 展开态的页面（多页活动用，如音乐的控制页/歌词页）
    property int page: 0
    readonly property int pageCount: activityLoader.item ? (activityLoader.item.pageCount ?? 1) : 1

    property real dragShift: 0

    signal activated()
    signal dismissRequested()
    signal musicPrev()
    signal musicPlayPause()
    signal musicNext()
    // 点击左侧录屏伴随指示器：请求停止录屏。
    // 录屏与音乐并存时主岛归音乐，停止录屏只能从这里触发。
    signal recordingStopRequested()
    // 点击歌词页某一行：请求跳转到该行时间点
    signal seekRequested(real seconds)
    // 点副岛胶囊：请求展开主岛（Host 负责把 expanded 置 true）
    signal expandRequested()
    // 右键拖动灵动岛：增量位移（root 坐标系）交给 Host 累加应用
    signal dragMoveRequested(real dx, real dy)

    property alias pillItem: pill
    property alias contentMaskItem: contentRow
    property alias companionItem: companion

    // 左侧伴随指示器：录屏与其它活动并存时贴在主岛左侧（便于演示/录屏）；
    // 主岛本身显示录屏、或岛已展开时不再重复显示。
    readonly property bool recordingActive: ActivityManager.entries !== undefined
        && ActivityManager.entries["recording"] !== undefined
    readonly property bool showCompanion: recordingActive
        && activityType !== "recording" && !expanded
    readonly property var recordingPayload: recordingActive
        ? ActivityManager.entries["recording"].payload : ({})

    // 右侧伴随指示器：包管理（下载 / AUR 构建）进度，与左侧录屏副岛对称。
    readonly property bool packageActive: ActivityManager.entries !== undefined
        && ActivityManager.entries["package"] !== undefined
    readonly property bool showPackageCompanion: packageActive
        && activityType !== "package" && !expanded
    readonly property var packagePayload: packageActive
        ? ActivityManager.entries["package"].payload : ({})

    // 右侧伴随指示器：通知（来消息时轻轻顶一下，几秒后自动消失）。
    readonly property bool notificationActive: ActivityManager.entries !== undefined
        && ActivityManager.entries["notification"] !== undefined
    readonly property bool showNotifCompanion: notificationActive
        && activityType !== "notification" && !expanded
    readonly property var notificationPayload: notificationActive
        ? ActivityManager.entries["notification"].payload : ({})

    // 任务类副岛：凡是在 ActivityManager 里声明了 group 的活动，
    // 只要没占着主岛就挂到右侧。新增任务类型只需声明 group，无需改这里。
    readonly property var companionOrder: ["package", "download"]
    readonly property var taskCompanionTypes: {
        const out = []
        const e = ActivityManager.entries
        if (!e) return out
        for (const t in e) {
            if (e[t].group && activityType !== t && !expanded)
                out.push(t)
        }
        // 稳定展示顺序：已知类型按 companionOrder，未知类型排后面
        out.sort((a, b) => {
            const ia = companionOrder.indexOf(a)
            const ib = companionOrder.indexOf(b)
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
        })
        return out
    }
    readonly property bool hasAnyTaskCompanion: taskCompanionTypes.length > 0

    function companionPayload(type) {
        const e = ActivityManager.entries
        return (e && e[type] && e[type].payload) ? e[type].payload : ({})
    }

    // 点副岛胶囊：把主岛切到该活动并展开
    function focusOn(type) {
        if (!ActivityManager.entries || !ActivityManager.entries[type])
            return
        focusType = type
        expandRequested()
    }

    // 聚焦的活动消失了就取消聚焦，避免主岛卡在空内容
    Connections {
        target: ActivityManager
        function onRevisionChanged() {
            if (root.focusType.length > 0 && !ActivityManager.entries[root.focusType])
                root.focusType = ""
        }
    }

    function fmtCompanion(sec) {
        const m = Math.floor(sec / 60)
        const s = sec % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    readonly property bool hasContent: renderType !== "idle"
    readonly property var targetSize: IslandTheme.sizeFor(renderType, expanded)

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

    // 展开时驱动内容进场。收起不做淡出：
    // compact 内容是收起态的常态显示，把它一起透明化会让岛变成黑色空条。
    // 收缩过程中超出 pill 的部分由 clip 裁掉，不需要额外的退场动画。
    onExpandedChanged: {
        if (expanded) {
            activityLoader.playEnter()
        } else {
            page = 0
            focusType = ""   // 收起后回到正常的主岛归属
            // 收起后把透明度复位，保证 compact 内容可见
            activityLoader.playEnter()
        }
    }
    onActivityTypeChanged: page = 0

    Component.onCompleted: syncSize()

    // 果冻感：弹簧动画带轻微回弹，比 OutQuint 更"活"。
    // damping 越低回弹越明显；0.45 是"看得出弹性但不晃"的平衡点。
    Behavior on animatedWidth {
        SpringAnimation { spring: 3.2; damping: 0.45; epsilon: 0.5 }
    }
    Behavior on animatedHeight {
        SpringAnimation { spring: 3.2; damping: 0.45; epsilon: 0.5 }
    }
    Behavior on animatedRadius {
        SpringAnimation { spring: 3.2; damping: 0.45; epsilon: 0.5 }
    }

    // 整体（伴随指示器 + 主岛）水平居中；无伴随指示器时与原来等价。
    // 偏移通过 anchor offset 应用：窗口全屏固定，动的只有岛本身。
    Item {
        id: contentRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.offsetX
        anchors.top: parent.top
        anchors.topMargin: root.baseTop + root.offsetY
        width: (companion.visible ? companion.width + 8 : 0)
             + pill.width
             + ((rightCompanions.visible && rightCompanions.width > 0) ? 8 + rightCompanions.width : 0)
        height: Math.max(companion.height, Math.max(pill.height, rightCompanions.height))

        // 左：录屏伴随指示器（脉冲红点 + 计时 + 点击停止）
        // 尺寸与主岛 compact 对齐：同高 37、同圆角 19、同字号 fontBody。
        Rectangle {
            id: companion
            // 显隐跟随宽度：宽度收到 0 才真正隐藏，让退场动画可见。
            // 若直接用 showCompanion 控制 visible，退场会瞬间消失、看不到过渡。
            property real animatedCompanionWidth: root.showCompanion ? (compRow.implicitWidth + 26) : 0
            visible: animatedCompanionWidth > 0.5
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: animatedCompanionWidth
            height: IslandTheme.compactSizes.idle.h
            radius: IslandTheme.compactSizes.idle.r
            color: IslandTheme.surface
            clip: true

            Behavior on animatedCompanionWidth {
                SpringAnimation { spring: 3.2; damping: 0.45; epsilon: 0.5 }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.recordingStopRequested()
            }

            Row {
                id: compRow
                anchors.centerIn: parent
                spacing: 7

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: IslandTheme.danger
                        opacity: 0.0
                        SequentialAnimation on scale {
                            running: companion.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 2.2; duration: 1100; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 1.0; duration: 0 }
                        }
                        SequentialAnimation on opacity {
                            running: companion.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.4; to: 0.0; duration: 1100; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 0.4; duration: 0 }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: IslandTheme.danger
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fmtCompanion(root.recordingPayload.elapsed ?? 0)
                    color: IslandTheme.text
                    font.family: IslandTheme.fontFamily
                    font.pixelSize: IslandTheme.fontBody
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }
        }

        Rectangle {
            id: pill
            // 锚点恒定指向副岛右缘：副岛宽度收到 0 时它自然贴回 parent.left。
            // 若用 visible 切换锚点，会在退场动画中途跳变；
            // margin 同样按副岛宽度比例收缩，而不是在阈值处硬切。
            anchors.left: companion.right
            anchors.leftMargin: Math.min(8, companion.animatedCompanionWidth)
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
            // 默认只接受左键，必须显式加右键，否则右键拖动收不到事件
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: rightDragging ? Qt.SizeAllCursor : Qt.PointingHandCursor

            property real pressX: 0
            property bool swiped: false

            // 右键拖动：窗口固定不动、只移动窗口内的岛，事件坐标始终在稳定
            // 坐标系里。「本次 - 上次」即纯鼠标位移，交给 Host 累加即可。
            property bool rightDragging: false
            property real lastRightX: 0
            property real lastRightY: 0

            onPressed: (e) => {
                if (e.button === Qt.RightButton) {
                    rightDragging = true
                    const rp = pillMouse.mapToItem(root, e.x, e.y)
                    lastRightX = rp.x
                    lastRightY = rp.y
                    return
                }
                // 映射到 root 而非直接用 e.x/e.y（相对 MouseArea）：展开态切页
                // 会让灵动岛宽度变化，MouseArea 原点也会平移，用局部坐标会把
                // 「布局变化」误算成「手指移动」。root 锚在窗口中心，尺寸固定，
                // 映射后坐标稳定。
                const p0 = pillMouse.mapToItem(root, e.x, e.y)
                pressX = p0.x
                swiped = false
                root.dragShift = 0
            }

            onPositionChanged: (e) => {
                if (rightDragging) {
                    // 右键已松开（事件可能先于 released 到达）就结束拖动
                    if (!(e.buttons & Qt.RightButton)) {
                        rightDragging = false
                        return
                    }
                    const rp = pillMouse.mapToItem(root, e.x, e.y)
                    const rdx = rp.x - lastRightX
                    const rdy = rp.y - lastRightY
                    lastRightX = rp.x
                    lastRightY = rp.y
                    if (rdx !== 0 || rdy !== 0)
                        root.dragMoveRequested(rdx, rdy)
                    return
                }

                // 收起态没有拖动手势（音量改由滚轮调节），直接忽略
                if (!root.expanded)
                    return

                const p = pillMouse.mapToItem(root, e.x, e.y)
                const dx = p.x - pressX

                // 展开态：水平滑动切页
                if (root.pageCount > 1 && Math.abs(dx) > 8) {
                    swiped = true
                    if (swiped)
                        root.dragShift = Math.max(-root.animatedWidth, Math.min(root.animatedWidth, dx * 0.5))
                }
            }

            onReleased: (e) => {
                if (rightDragging) {
                    rightDragging = false
                    return
                }
                if (swiped) {
                    const pRel = pillMouse.mapToItem(root, e.x, e.y)
                    const dx = pRel.x - pressX
                    if (dx < -40 && root.page < root.pageCount - 1) root.page += 1
                    else if (dx > 40 && root.page > 0) root.page -= 1
                } else {
                    // 歌词页：先尝试把点击命中到某一行并 seek；
                    // 命中则不再触发展开/收起。
                    if (root.expanded && root.page === 1 && activityLoader.item
                            && typeof activityLoader.item.seekAtY === "function") {
                        const p = pillMouse.mapToItem(activityLoader.item, e.x, e.y)
                        if (activityLoader.item.seekAtY(p.y)) {
                            root.dragShift = 0
                            return
                        }
                    }
                    root.activated()
                }
                root.dragShift = 0
            }

            // 滚轮调音量：向上滚增大、向下滚减小。
            // 鼠标一格 angleDelta.y 为 ±120；触控板是连续小值，同样按比例缩放。
            onWheel: (e) => {
                if (!Audio.sink?.audio)
                    return
                const step = e.angleDelta.y / 120.0 * 0.05
                if (step === 0)
                    return
                Audio.sink.audio.volume = Math.max(0, Math.min(1, Audio.sink.audio.volume + step))
            }
        }

        Loader {
            id: activityLoader
            anchors.fill: parent
            sourceComponent: root.componentFor(root.renderType)
            opacity: 0
            // 切换内容时轻微缩放：单靠淡入会显得"平"，
            // 0.96 → 1 的形变让新内容像是从岛里长出来。
            scale: 0.96
            transformOrigin: Item.Center

            // 进场：淡入 + 轻微放大。唯一的 opacity 驱动者，
            // 避免多个动画抢同一属性导致透明度卡死。
            ParallelAnimation {
                id: contentIn
                NumberAnimation {
                    target: activityLoader
                    property: "opacity"
                    to: 1
                    duration: IslandTheme.durationContentFade
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: activityLoader
                    property: "scale"
                    to: 1
                    duration: IslandTheme.durationExpand
                    easing.type: Easing.OutCubic
                }
            }

            // 统一的进场入口：先复位再播，重复调用安全。
            function playEnter() {
                contentIn.stop()
                opacity = 0
                scale = 0.96
                contentIn.restart()
            }

            onSourceComponentChanged: activityLoader.playEnter()
            onItemChanged: {
                if (item) {
                    item.expanded = Qt.binding(function() { return root.expanded })
                    item.payload = Qt.binding(function() { return root.renderPayload })
                    if (item.visualizerPoints !== undefined)
                        item.visualizerPoints = Qt.binding(function() { return root.visualizerPoints })
                    if (item.page !== undefined)
                        item.page = Qt.binding(function() { return root.page })
                    if (item.lyricsProvider !== undefined)
                        item.lyricsProvider = Qt.binding(function() { return root.lyricsProvider })
                    if (item.accentColor !== undefined)
                        item.accentColor = Qt.binding(function() { return root.accentColor })
                    // 转发音乐控制信号（仅 MusicActivity 有这些信号）
                    if (item.prevRequested !== undefined) {
                        item.prevRequested.connect(root.musicPrev)
                        item.playPauseRequested.connect(root.musicPlayPause)
                        item.nextRequested.connect(root.musicNext)
                    }
                    // 歌词行点击跳转
                    if (item.seekRequested !== undefined)
                        item.seekRequested.connect(root.seekRequested)
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
                    readonly property bool current: index === root.page
                    // 当前点拉长成胶囊，比单纯换色更容易一眼看出在哪页
                    width: current ? 14 : 5
                    height: 5
                    radius: 2.5
                    color: current ? IslandTheme.text : IslandTheme.trackStrong
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on width {
                        NumberAnimation { duration: IslandTheme.durationQuick; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
        }

        // 右：伴随指示器组（任务 + 通知）
        // 与左侧录屏副岛对称：同高 37、同圆角 19、同字号 fontBody。
        Row {
            id: rightCompanions
            anchors.left: pill.right
            // 与左侧副岛对称：显隐时 margin 做弹簧过渡，避免硬切
            property real animatedMargin: visible ? 8 : 0
            anchors.leftMargin: animatedMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: root.hasAnyTaskCompanion || root.showNotifCompanion
            Behavior on animatedMargin {
                SpringAnimation { spring: 3.2; damping: 0.45; epsilon: 0.5 }
            }
            // Row 的 width/height 默认是 0（不是 implicit 值），用 childrenRect 取实际内容宽。
            width: childrenRect.width
            height: IslandTheme.compactSizes.idle.h

        // 任务类副岛：图标 + 迷你进度条 + 百分比
        // 由 taskCompanionTypes 驱动，新增任务类型无需改布局。
        Repeater {
            id: taskCompanions
            model: root.taskCompanionTypes

            delegate: Rectangle {
                id: taskPill
                required property string modelData
                readonly property var payload: root.companionPayload(modelData)
                readonly property bool indet: payload.indeterminate ?? true
                // 暴露给子项：Repeater delegate 里的 parent.parent 链在
                // 组件边界处不可靠，用显式 id 引用。
                readonly property string iconName: payload.icon ?? "download"

                width: taskRow.implicitWidth + 26
                height: IslandTheme.compactSizes.idle.h
                radius: IslandTheme.compactSizes.idle.r
                color: IslandTheme.surface
                clip: true

                Row {
                    id: taskRow
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: taskPill.iconName
                        font.family: IslandTheme.iconFontFamily
                        font.pixelSize: 16
                        color: IslandTheme.text
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 4
                        radius: 2
                        color: IslandTheme.track
                        clip: true

                        // 已知进度：按百分比填充
                        Rectangle {
                            visible: !taskPill.indet
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * Math.max(0, Math.min(100, taskPill.payload.percent ?? 0)) / 100
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: IslandPalette.progressStart }
                                GradientStop { position: 1.0; color: IslandPalette.progressEnd }
                            }
                            Behavior on width {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }

                        // 进度未知：一小块来回滑动，明确表示“正在跑”
                        Rectangle {
                            id: taskIndetBlock
                            visible: taskPill.indet
                            width: 16
                            height: parent.height
                            radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: IslandPalette.progressStart }
                                GradientStop { position: 1.0; color: IslandPalette.progressEnd }
                            }
                            SequentialAnimation on x {
                                running: taskIndetBlock.visible
                                loops: Animation.Infinite
                                NumberAnimation { from: -16; to: 40; duration: 850; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 40; to: -16; duration: 850; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    // 进度未知时用旋转图标代替省略号
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: taskPill.indet
                        text: "progress_activity"
                        font.family: IslandTheme.iconFontFamily
                        font.pixelSize: 14
                        color: IslandTheme.text
                        transformOrigin: Item.Center
                        RotationAnimation on rotation {
                            running: parent.visible
                            from: 0; to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !taskPill.indet
                        text: (taskPill.payload.percent ?? 0) + "%"
                        color: IslandTheme.text
                        font.family: IslandTheme.fontFamily
                        font.pixelSize: IslandTheme.fontBody
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }

                // 点胶囊：主岛切到该任务并展开看细节
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.focusOn(taskPill.modelData)
                }
            }
        }

        // 通知：铃铛 + 摘要（超长省略），几秒后自动消失
        Rectangle {
            id: notifCompanion
            visible: root.showNotifCompanion
            width: notifRow.implicitWidth + 26
            height: IslandTheme.compactSizes.idle.h
            radius: IslandTheme.compactSizes.idle.r
            color: IslandTheme.surface
            clip: true

            Row {
                id: notifRow
                anchors.centerIn: parent
                spacing: 7

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "notifications"
                    font.family: IslandTheme.iconFontFamily
                    font.pixelSize: 16
                    color: IslandTheme.text
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 130)
                    text: (root.notificationPayload.summary ?? "").length > 0
                        ? root.notificationPayload.summary
                        : ((root.notificationPayload.appName ?? "").length > 0
                            ? root.notificationPayload.appName : "新通知")
                    color: IslandTheme.text
                    font.family: IslandTheme.fontFamily
                    font.pixelSize: IslandTheme.fontBody
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            // 点胶囊：展开看通知全文
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusOn("notification")
            }
        }
        }
    }

    function componentFor(type) {
        switch (type) {
        case "music":      return musicComp
        case "volume":     return volumeComp
        case "brightness": return brightnessComp
        case "privacy":    return privacyComp
        case "connectivity": return connectivityComp
        case "battery":    return batteryComp
        case "recording":  return recordingComp
        case "package":    return packageComp
        case "download":   return packageComp
        case "notification": return notificationComp
        default:           return idleComp
        }
    }

    Component { id: musicComp;     MusicActivity {} }
    Component { id: volumeComp;    VolumeActivity {} }
    Component { id: brightnessComp; BrightnessActivity {} }
    Component { id: privacyComp;   PrivacyActivity {} }
    Component { id: connectivityComp; ConnectivityActivity {} }
    Component { id: batteryComp;   BatteryActivity {} }
    Component { id: recordingComp; RecordingActivity {} }
    Component { id: packageComp;   PackageActivity {} }
    Component { id: notificationComp; NotificationActivity {} }
    Component { id: idleComp;      IdleActivity {} }
}
