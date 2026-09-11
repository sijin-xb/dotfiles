import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock

/**
 * Serpantinum 风格锁屏视图（结构移植，非 1:1 复刻）。
 *
 * 大时钟居中 → 点击 / 按键展开三栏面板 → Esc 收起。
 * 配色、圆角、字体、动画曲线全部取自 Appearance；
 * 认证 / 指纹 / keyring / 电源动作复用 LockContext。
 */
MouseArea {
    id: root
    required property LockContext context
    property bool active: false

    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool mediaActive: player !== null
        && player.trackTitle !== ""
        && player.playbackState !== MprisPlaybackState.Stopped

    // ── 字体 ────────────────────────────────────────────────
    // Config 里配的 "Google Sans Flex" 系统不存在，会回退到 Noto Sans CJK。
    // 锁屏单独用 SF Pro Display（系统有完整 18 字重）。
    readonly property string lockFont: "SF Pro Display"

    // ── 卡片尺寸 / 圆角 ──────────────────────────────────────
    readonly property int cardWidth: 400
    readonly property int cardHeight: 500
    readonly property int wingWidth: 312
    readonly property int cardSpacing: 14
    readonly property int cardRadius: Appearance.rounding.verylarge
    readonly property int tileRadius: Appearance.rounding.large

    // ── 不透明卡片色 ────────────────────────────────────────
    // colLayer* 由 contentTransparency 算出 alpha（当前 0.43），叠在模糊壁纸上发灰。
    // 锁屏改用 m3 原始色，完全不透明。
    readonly property color cardColor: Appearance.m3colors.m3surfaceContainerLow
    readonly property color tileColor: Appearance.m3colors.m3surfaceContainerHigh
    readonly property color mediaColor: Appearance.m3colors.m3surfaceContainerHighest

    // ── 圆形图标按钮 ────────────────────────────────────────
    // Qt6 的 Button.contentItem 是 FINAL，无法覆盖，因此自绘。
    component CircleIconButton: Item {
        id: iconBtn
        required property string glyph
        property color tint: Appearance.colors.colOnLayer2
        property real iconSize: 22
        property color bgColor: root.tileColor
        property color bgHoverColor: ColorUtils.mix(root.tileColor, Appearance.colors.colOnLayer2, 0.90)
        property color bgPressColor: ColorUtils.mix(root.tileColor, Appearance.colors.colOnLayer2, 0.82)
        property color toggledBgColor: Appearance.colors.colPrimaryContainer
        property bool interactive: true
        property bool toggled: false
        signal clicked()

        implicitWidth: 44
        implicitHeight: 44
        opacity: interactive ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: {
                if (iconBtn.toggled) return iconBtn.toggledBgColor
                if (iconMa.pressed) return iconBtn.bgPressColor
                if (iconMa.containsMouse) return iconBtn.bgHoverColor
                return iconBtn.bgColor
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: iconBtn.glyph
                iconSize: iconBtn.iconSize
                fill: 1
                color: iconBtn.tint
            }
        }

        MouseArea {
            id: iconMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: iconBtn.interactive
            cursorShape: iconBtn.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: iconBtn.clicked()
        }
    }

    // ── 展开状态 ────────────────────────────────────────────
    property bool expanded: false
    onExpandedChanged: Qt.callLater(root.focusInput)

    property real wingReveal: expanded ? 1 : 0
    Behavior on wingReveal {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    // ── 入场 ────────────────────────────────────────────────
    property real introReveal: 0
    Component.onCompleted: {
        introAnimation.start()
        root.forceActiveFocus()
    }
    NumberAnimation {
        id: introAnimation
        target: root
        property: "introReveal"
        from: 0
        to: 1
        duration: 700
        easing.type: Easing.OutCubic
    }

    // ── 时间 ────────────────────────────────────────────────
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    function greetingFor(h) {
        if (h < 6) return Translation.tr("夜深了，注意休息")
        if (h < 9) return Translation.tr("早上好")
        if (h < 12) return Translation.tr("上午好")
        if (h < 14) return Translation.tr("中午好")
        if (h < 18) return Translation.tr("下午好")
        return Translation.tr("晚上好")
    }

    function relativeTime(t) {
        const s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return Translation.tr("刚刚")
        if (s < 3600) return Math.floor(s / 60) + Translation.tr(" 分钟前")
        if (s < 86400) return Math.floor(s / 3600) + Translation.tr(" 小时前")
        return Math.floor(s / 86400) + Translation.tr(" 天前")
    }

    function fmtSeconds(sec) {
        sec = Math.max(0, Math.floor(sec || 0))
        return Math.floor(sec / 60) + ":" + (sec % 60).toString().padStart(2, "0")
    }

    // ── 密码同步 ────────────────────────────────────────────
    Connections {
        target: root.context
        function onCurrentTextChanged() {
            if (passwordInput.text !== root.context.currentText)
                passwordInput.text = root.context.currentText
        }
        function onShouldReFocus() {
            passwordInput.forceActiveFocus()
        }
    }

    // ── 焦点 / 键鼠 ─────────────────────────────────────────
    focus: true
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    function focusInput() {
        if (root.expanded) passwordInput.forceActiveFocus()
        else root.forceActiveFocus()
    }

    onPressed: {
        root.context.resetClearTimer()
        if (!root.expanded) root.expanded = true
        Qt.callLater(root.focusInput)
    }

    Keys.onPressed: event => {
        if (!root.expanded) {
            root.expanded = true
            Qt.callLater(root.focusInput)
            event.accepted = true
            return
        }
        root.context.resetClearTimer()
        if (event.key === Qt.Key_Escape) {
            root.context.currentText = ""
            passwordInput.text = ""
            root.expanded = false
            root.forceActiveFocus()
            event.accepted = true
        }
    }

    // ── 背景壁纸 ────────────────────────────────────────────
    Item {
        anchors.fill: parent
        z: -3

        readonly property string effectivePath: {
            if (Config.options.background.lockWall !== "")
                return Config.options.background.lockWall
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath
        }
        readonly property bool isVideo: effectivePath.endsWith(".mp4") || effectivePath.endsWith(".webm")
            || effectivePath.endsWith(".mkv") || effectivePath.endsWith(".avi") || effectivePath.endsWith(".mov")
        readonly property string sourcePath: isVideo ? Config.options.background.thumbnailPath : effectivePath

        Image {
            id: wallpaperImg
            anchors.fill: parent
            source: parent.sourcePath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }
        FastBlur {
            anchors.fill: parent
            source: wallpaperImg
            radius: Config.options.lock.blur.enable ? Config.options.lock.blur.radius : 0
            scale: Config.options.lock.blur.extraZoom
        }
    }

    // 纯黑遮罩，不用 colScrim（它自带透明度，叠加会发灰）
    Rectangle {
        anchors.fill: parent
        z: -2
        color: "black"
        opacity: root.expanded ? 0.55 : 0.22
        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
    }

    // ── 大时钟 ──────────────────────────────────────────────
    Column {
        id: clockSection
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.expanded ? -root.height * 0.30 : -root.height * 0.01
        spacing: 8
        opacity: root.introReveal * (root.expanded ? 0.85 : 1.0)
        scale: root.expanded ? 0.40 : 1.0
        transformOrigin: Item.Center

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 440; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 440; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            StyledText {
                font.family: root.lockFont
                text: Qt.formatDateTime(root.now, "HH")
                font.pixelSize: Math.round(Appearance.font.pixelSize.hugeass * 5.2)
                font.weight: Font.Light
                color: "#ffffff"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.3)
            }
            StyledText {
                font.family: root.lockFont
                text: ":"
                font.pixelSize: Math.round(Appearance.font.pixelSize.hugeass * 5.2)
                font.weight: Font.Thin
                color: "#ffffff"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.3)
                opacity: 0.4
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.introReveal > 0.9
                    NumberAnimation { to: 0.9; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                }
            }
            StyledText {
                font.family: root.lockFont
                text: Qt.formatDateTime(root.now, "mm")
                font.pixelSize: Math.round(Appearance.font.pixelSize.hugeass * 5.2)
                font.weight: Font.Light
                color: "#ffffff"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.3)
            }
        }

        StyledText {
            font.family: root.lockFont
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 2
            text: Qt.formatDateTime(root.now, "dddd, d MMMM").toUpperCase()
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            font.letterSpacing: 3.5
            color: Qt.rgba(1, 1, 1, 0.88)
        }

        StyledText {
            font.family: root.lockFont
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 4
            text: root.greetingFor(root.now.getHours())
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // ── 三栏面板 ────────────────────────────────────────────
    Item {
        id: dashboard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.expanded ? root.height * 0.13 : root.height * 0.70
        // 显式尺寸：不可引用 dashboardRow.width，否则与 anchors.centerIn 形成循环绑定
        width: root.cardWidth + 2 * (root.wingWidth * root.wingReveal + root.cardSpacing)
        height: root.cardHeight
        opacity: root.expanded && root.introReveal > 0.5 ? 1 : 0
        visible: opacity > 0.01

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        Row {
            id: dashboardRow
            anchors.centerIn: parent
            spacing: 14

            // ── 左翼：系统监控 ────────────────────────────
            Item {
                id: leftWing
                width: root.wingWidth * root.wingReveal
                height: root.cardHeight
                clip: true
                opacity: root.wingReveal

                Rectangle {
                    id: leftCardBg
                    width: root.wingWidth
                    height: parent.height
                    radius: root.cardRadius
                    color: root.cardColor
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowBlur: 0.7
                        shadowColor: Appearance.colors.colShadow
                        shadowVerticalOffset: 4
                    }
                }

                ColumnLayout {
                    anchors.fill: leftCardBg
                    anchors.margins: 18
                    spacing: 12

                    StyledText {
                        font.family: root.lockFont
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: Translation.tr("系统")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.6
                        color: Appearance.colors.colOnLayer1Inactive
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 10

                        component MetricTile: Rectangle {
                            id: tile
                            required property string glyph
                            required property string label
                            required property string value
                            required property real ratio
                            required property color tint

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: root.tileRadius
                            color: root.tileColor

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5
                                    MaterialSymbol {
                                        text: tile.glyph
                                        iconSize: Appearance.font.pixelSize.small
                                        color: tile.tint
                                        fill: 1
                                    }
                                    StyledText {
                                        font.family: root.lockFont
                                        Layout.fillWidth: true
                                        text: tile.label
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1Inactive
                                        elide: Text.ElideRight
                                    }
                                }

                                Item { Layout.fillHeight: true }

                                // 环形进度 + 居中数值
                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 66
                                    Layout.preferredHeight: 66

                                    CircularProgress {
                                        anchors.fill: parent
                                        implicitSize: 66
                                        lineWidth: 5
                                        value: Math.max(0, Math.min(1, tile.ratio))
                                        colPrimary: tile.tint
                                        colSecondary: ColorUtils.transparentize(tile.tint, 0.85)
                                        gapAngle: 0
                                    }

                                    StyledText {
                                        font.family: root.lockFont
                                        anchors.centerIn: parent
                                        text: tile.value
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        MetricTile {
                            glyph: "memory"
                            label: Translation.tr("处理器")
                            value: Math.round((ResourceUsage.cpuUsage || 0) * 100) + "%"
                            ratio: ResourceUsage.cpuUsage || 0
                            tint: Appearance.colors.colPrimary
                        }
                        MetricTile {
                            glyph: "developer_board"
                            label: Translation.tr("内存")
                            value: Math.round((ResourceUsage.memoryUsedPercentage || 0) * 100) + "%"
                            ratio: ResourceUsage.memoryUsedPercentage || 0
                            tint: Appearance.colors.colSecondary
                        }
                        MetricTile {
                            glyph: "device_thermostat"
                            label: Translation.tr("温度")
                            value: Math.round(ResourceUsage.cpuTemp || 0) + "°"
                            ratio: (ResourceUsage.cpuTemp || 0) / 100
                            tint: Appearance.colors.colTertiary
                        }
                        MetricTile {
                            glyph: "hard_drive"
                            label: Translation.tr("磁盘")
                            value: Math.round((ResourceUsage.diskUsedPercentage || 0) * 100) + "%"
                            ratio: ResourceUsage.diskUsedPercentage || 0
                            tint: Appearance.colors.colError
                        }
                    }
                }
            }

            // ── 中央：认证卡片 ────────────────────────────
            Item {
                id: centerWing
                width: root.cardWidth
                height: root.cardHeight

                Rectangle {
                    id: centerCard
                    anchors.fill: parent
                    radius: root.cardRadius
                    color: root.cardColor
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowBlur: 0.7
                        shadowColor: Appearance.colors.colShadow
                        shadowVerticalOffset: 4
                    }
                }

                ColumnLayout {
                    anchors.fill: centerCard
                    anchors.margins: 26
                    spacing: 0

                Item { Layout.fillHeight: true; Layout.preferredHeight: 10 }

                // 头像：与桌面 UserCardWidget 同源的加载逻辑
                // clip: true 只裁矩形，圆形必须用 OpacityMask
                Item {
                    id: avatarWrap
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 128
                    Layout.preferredHeight: 128
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: avatarWrap.width
                            height: avatarWrap.height
                            radius: width / 2
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colPrimaryContainer
                    }

                    Image {
                        id: lockAvatar
                        anchors.fill: parent
                        source: Config.options.profile.avatarPath !== ""
                            ? "file://" + Config.options.profile.avatarPicture
                            : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status !== Image.Error
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"
                        iconSize: 68
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                        visible: lockAvatar.status === Image.Error
                    }
                }

                Item { Layout.preferredHeight: 18 }

                // 用户名 + 状态
                StyledText {
                    font.family: root.lockFont
                    Layout.alignment: Qt.AlignHCenter
                    text: SystemInfo.username + "  ·  " + (root.context.showFailure
                        ? Translation.tr("密码错误")
                        : root.context.unlockInProgress
                            ? Translation.tr("验证中…")
                            : Translation.tr("已锁定"))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.context.showFailure
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnLayer1
                }

                Item { Layout.preferredHeight: 18 }

                // 密码框：胶囊 + 明确背景层次 + 可见密码点
                Rectangle {
                    id: passwordShell
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: height / 2
                    color: root.tileColor
                    border.width: 2
                    border.color: root.context.showFailure
                        ? Appearance.colors.colError
                        : passwordInput.activeFocus
                            ? Appearance.colors.colPrimary
                            : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)

                    Behavior on border.color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter

                        enabled: !root.context.unlockInProgress
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        passwordMaskDelay: 0
                        inputMethodHints: Qt.ImhSensitiveData
                        selectByMouse: false
                        clip: true
                        // 空输入时隐藏光标，否则会盖在 placeholder 上
                        cursorVisible: text.length > 0 && activeFocus

                        color: Appearance.colors.colOnLayer2
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer

                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.small
                            variableAxes: Appearance.font.variableAxes.main
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: passwordInput.text.length === 0
                            text: root.context.showFailure
                                ? Translation.tr("密码错误")
                                : Translation.tr("输入密码")
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1Inactive
                        }

                        onTextChanged: {
                            if (root.context.currentText !== text)
                                root.context.currentText = text
                        }
                        onAccepted: root.context.tryUnlock()

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.context.currentText = ""
                                passwordInput.text = ""
                                root.expanded = false
                                root.forceActiveFocus()
                                event.accepted = true
                                return
                            }
                            root.context.resetClearTimer()
                        }

                        ErrorShakeAnimation {
                            id: shakeAnim
                            target: passwordShell
                        }
                        Connections {
                            target: root.context
                            function onFailed() { shakeAnim.restart() }
                            function onShowFailureChanged() {
                                if (root.context.showFailure) shakeAnim.restart()
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                // 键盘布局 + 电池
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    component Pill: Rectangle {
                        id: pill
                        required property string glyph
                        required property string label
                        required property color tint
                        implicitWidth: pillRow.implicitWidth + 24
                        implicitHeight: 32
                        radius: height / 2
                        color: root.tileColor

                        RowLayout {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: pill.glyph
                                iconSize: Appearance.font.pixelSize.small
                                color: pill.tint
                                fill: 1
                            }
                            StyledText {
                                font.family: root.lockFont
                                text: pill.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: pill.tint
                            }
                        }
                    }

                    Pill {
                        visible: WM.compositor === "hyprland"
                        glyph: "keyboard"
                        label: HyprlandXkb.currentLayoutCode || "--"
                        tint: Appearance.colors.colOnLayer2
                    }
                    Pill {
                        visible: Battery.available
                        glyph: Battery.isCharging ? "bolt" : "battery_full"
                        label: Math.round(Battery.percentage * 100) + "%"
                        tint: Battery.isLow && !Battery.isCharging
                            ? Appearance.colors.colError
                            : Appearance.colors.colOnLayer2
                    }
                }

                Item { Layout.fillHeight: true }

                // 电源动作
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    CircleIconButton {
                        glyph: "bedtime"
                        bgColor: root.tileColor
                        onClicked: Session.suspend()
                    }
                    CircleIconButton {
                        glyph: "restart_alt"
                        bgColor: root.tileColor
                        toggled: root.context.targetAction === LockContext.ActionEnum.Reboot
                        toggledBgColor: ColorUtils.transparentize(Appearance.colors.colSecondary, 0.35)
                        tint: toggled ? Appearance.colors.colSecondary : Appearance.colors.colOnLayer2
                        onClicked: {
                            if (!root.requirePasswordToPower) {
                                root.context.unlocked(LockContext.ActionEnum.Reboot)
                                return
                            }
                            if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                                root.context.resetTargetAction()
                            } else {
                                root.context.targetAction = LockContext.ActionEnum.Reboot
                                root.context.shouldReFocus()
                            }
                        }
                    }
                    CircleIconButton {
                        glyph: "power_settings_new"
                        bgColor: root.tileColor
                        toggled: root.context.targetAction === LockContext.ActionEnum.Poweroff
                        toggledBgColor: ColorUtils.transparentize(Appearance.colors.colError, 0.35)
                        tint: toggled ? Appearance.colors.colError : Appearance.colors.colOnLayer2
                        onClicked: {
                            if (!root.requirePasswordToPower) {
                                root.context.unlocked(LockContext.ActionEnum.Poweroff)
                                return
                            }
                            if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                                root.context.resetTargetAction()
                            } else {
                                root.context.targetAction = LockContext.ActionEnum.Poweroff
                                root.context.shouldReFocus()
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.preferredHeight: 10 }
                }
            }

            // ── 右翼：通知 + 媒体 ─────────────────────────
            Item {
                id: rightWing
                width: root.wingWidth * root.wingReveal
                height: root.cardHeight
                clip: true
                opacity: root.wingReveal

                Rectangle {
                    id: rightCardBg
                    width: root.wingWidth
                    height: parent.height
                    radius: root.cardRadius
                    color: root.cardColor
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowBlur: 0.7
                        shadowColor: Appearance.colors.colShadow
                        shadowVerticalOffset: 4
                    }
                }

                ColumnLayout {
                    anchors.fill: rightCardBg
                    anchors.margins: 18
                    spacing: 12

                    // 通知
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            StyledText {
                                font.family: root.lockFont
                                Layout.fillWidth: true
                                text: Translation.tr("通知")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.6
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                font.family: root.lockFont
                                visible: Notifications.list.length > 0
                                text: Notifications.list.length
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                            }
                        }

                        // 空态
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: Notifications.list.length === 0
                            spacing: 8
                            Item { Layout.fillHeight: true }
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "notifications_off"
                                iconSize: 40
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1Inactive, 0.45)
                            }
                            StyledText {
                                font.family: root.lockFont
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("暂无通知")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1Inactive, 0.2)
                            }
                            Item { Layout.fillHeight: true }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: Notifications.list.length > 0
                            clip: true
                            spacing: 8
                            model: Notifications.list
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: notifCard
                                required property var modelData
                                width: ListView.view.width
                                implicitHeight: notifCol.implicitHeight + 20
                                radius: root.tileRadius
                                color: root.tileColor

                                ColumnLayout {
                                    id: notifCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: 11
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        StyledText {
                                            font.family: root.lockFont
                                            Layout.fillWidth: true
                                            text: notifCard.modelData.appName || ""
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colPrimary
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            font.family: root.lockFont
                                            text: root.relativeTime(notifCard.modelData.time)
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                    }
                                    StyledText {
                                        font.family: root.lockFont
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: notifCard.modelData.summary || ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                    StyledText {
                                        font.family: root.lockFont
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: notifCard.modelData.body || ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1Inactive
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // 歌词：复用 LyricsService（全局单例，shell.qml 启动时已拉起）
                    Rectangle {
                        id: lyricsCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: LyricsService.status === "ok" ? 176 : 0
                        visible: Layout.preferredHeight > 0
                        radius: root.tileRadius
                        color: root.tileColor
                        clip: true

                        Lyrics {
                            anchors.fill: parent
                            anchors.margins: 10
                            textColor: Qt.rgba(1, 1, 1, 0.55)
                            activeColor: Appearance.colors.colPrimary
                            dimColor: Qt.rgba(1, 1, 1, 0.22)
                            indicatorColor: root.tileColor
                            indicatorShapeColor: Appearance.colors.colOnLayer2
                            textAlignment: Text.AlignHCenter
                        }
                    }

                    // 媒体卡片
                    Rectangle {
                        id: mediaCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.mediaActive ? 116 : 0
                        visible: root.mediaActive
                        radius: root.tileRadius
                        color: root.tileColor
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 60
                                Layout.preferredHeight: 60
                                Layout.alignment: Qt.AlignVCenter
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colPrimaryContainer
                                clip: true

                                Image {
                                    id: artImage
                                    anchors.fill: parent
                                    source: root.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false
                                    asynchronous: true
                                }
                                Rectangle {
                                    id: artMask
                                    anchors.fill: parent
                                    radius: parent.radius
                                    visible: false
                                    layer.enabled: true
                                }
                                OpacityMask {
                                    anchors.fill: parent
                                    source: artImage
                                    maskSource: artMask
                                    visible: (root.player?.trackArtUrl ?? "") !== ""
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: (root.player?.trackArtUrl ?? "") === ""
                                    text: "music_note"
                                    iconSize: 26
                                    fill: 1
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                StyledText {
                                    font.family: root.lockFont
                                    Layout.fillWidth: true
                                    text: root.player?.trackTitle ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                StyledText {
                                    font.family: root.lockFont
                                    Layout.fillWidth: true
                                    text: root.player?.trackArtist ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1Inactive
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                StyledText {
                                    font.family: root.lockFont
                                    text: root.fmtSeconds(root.player?.position ?? 0)
                                        + " / " + root.fmtSeconds(root.player?.length ?? 0)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1Inactive
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                CircleIconButton {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    glyph: "skip_previous"
                                    iconSize: 20
                                    interactive: root.player?.canGoPrevious ?? false
                                    onClicked: MprisController.previous()
                                }
                                CircleIconButton {
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    glyph: root.player?.isPlaying ? "pause" : "play_arrow"
                                    iconSize: 20
                                    bgColor: Appearance.colors.colPrimary
                                    bgHoverColor: Appearance.colors.colPrimaryHover
                                    bgPressColor: Appearance.colors.colPrimaryActive
                                    tint: Appearance.colors.colOnPrimary
                                    interactive: root.player?.canTogglePlaying ?? false
                                    onClicked: MprisController.togglePlaying()
                                }
                                CircleIconButton {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    glyph: "skip_next"
                                    iconSize: 20
                                    interactive: root.player?.canGoNext ?? false
                                    onClicked: MprisController.next()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
