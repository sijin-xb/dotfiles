import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property MprisPlayer activePlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return MprisController.activePlayer
        const _ = MprisController.players.count
        for (const p of MprisController.players) {
            if ((p.identity ?? "").toLowerCase().includes(preferred) ||
                (p.desktopEntry ?? "").toLowerCase().includes(preferred))
                return p
        }
        return MprisController.activePlayer
    }

    property var    artUrl:      activePlayer?.trackArtUrl ?? ""

    // Force focus on entry
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        forceFieldFocus();
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Toolbar appearing animation
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        } 
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // RippleButton {
    //     anchors {
    //         top: parent.top
    //         left: parent.left
    //         leftMargin: 10
    //         topMargin: 10
    //     }
    //     implicitHeight: 40
    //     colBackground: Appearance.colors.colLayer2
    //     onClicked: {
    //         context.unlocked(LockContext.ActionEnum.Unlock);
    //         GlobalStates.screenLocked = false;
    //     }
    //     contentItem: StyledText {
    //         text: "[[ DEBUG BYPASS ]]"
    //     }
    // }

    // Ambient album art background: whenever a player has a current track
    // with artwork, the lock background fades to the cover blurred
    // full-screen (Android ambient style) with a light scrim so the
    // password box stays readable. Falls back to the wallpaper otherwise.
    Item {
        id: ambientArtBg
        anchors.fill: parent
        readonly property bool active: root.artUrl !== "" && root.activePlayer !== null
        visible: opacity > 0.001
        opacity: active ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 600
                easing.type: Easing.InOutQuad
            }
        }

        Image {
            id: ambientArtSource
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: false
        }
        FastBlur {
            anchors.fill: parent
            source: ambientArtSource
            radius: 48
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.25)
        }
    }

    // Refresh lyrics on every lock so the lock session always shows
    // up-to-date lines (fixes stale / never-fetched lyrics).
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) LyricsService.restartLyrics()
        }
    }

    // ── Desktop wallpaper backdrop (all compositors) ────────────
    // Bugfix: the old backdrop Loader was niri-only, so Hyprland locks
    // fell back to a blank/frozen frame. Mirror Background.qml's source
    // chain so the lock always shows the live desktop wallpaper.
    Item {
        id: wallpaperBg
        anchors.fill: parent
        z: -1

        Image {
            id: lockWallpaperImg
            anchors.fill: parent
            source: Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }
        FastBlur {
            anchors.fill: parent
            source: lockWallpaperImg
            radius: 28
        }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.18)
        }
    }


    // ── Dark scrim for text readability ─────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.30)
    }

    // ── Clock + Date + Greeting (centered upper zone) ──────────
    Column {
        id: clockSection
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: parent.height * 0.18
        }
        spacing: 2
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        property date now: new Date()
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clockSection.now = new Date()
        }

        // Large clock
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var h = clockSection.now.getHours().toString().padStart(2, "0")
                var m = clockSection.now.getMinutes().toString().padStart(2, "0")
                return h + ":" + m
            }
            font.pixelSize: 88
            font.weight: Font.Bold
            font.family: "Google Sans Flex Medium"
            color: "#ffffff"
            horizontalAlignment: Text.AlignHCenter
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.25)
        }

        // Date line
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var days = ["日","一","二","三","四","五","六"]
                var d = clockSection.now
                return (d.getMonth()+1) + "月" + d.getDate() + "日 · 星期" + days[d.getDay()]
            }
            font.pixelSize: Appearance.font.pixelSize.hugeass
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.80)
            horizontalAlignment: Text.AlignHCenter
        }

        // Greeting
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 8
            text: {
                var h = clockSection.now.getHours()
                if (h < 6) return "夜深了，注意休息"
                if (h < 9) return "早上好 ☀"
                if (h < 12) return "上午好"
                if (h < 14) return "中午好 🍱"
                if (h < 18) return "下午好"
                return "晚上好 🌙"
            }
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Qt.rgba(1, 1, 1, 0.55)
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Media card: glass panel, seekable progress, micro-interactions ──
    Item {
        id: mediaCard
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: clockSection.bottom
            topMargin: 44
        }
        width: 400
        height: mediaCol.implicitHeight + 40
        visible: root.activePlayer !== null && Config.options.lock.showMedia
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }

        readonly property MprisPlayer player: root.activePlayer
        readonly property real progress: player ? Math.min(1, player.position / Math.max(1, player.length)) : 0
        property real dragPos: 0
        readonly property real shownProgress: seekArea.dragging ? dragPos : progress

        function fmtTime(s) {
            s = Math.max(0, Math.floor(s || 0));
            return Math.floor(s / 60) + ":" + (s % 60).toString().padStart(2, "0");
        }

        // Mpris position updates lazily; ping it while the card is visible
        Timer {
            interval: 500
            running: mediaCard.visible && mediaCard.player !== null
            repeat: true
            onTriggered: mediaCard.player.positionChanged()
        }

        // Soft shadow under the card
        Rectangle {
            id: cardShadowSrc
            anchors.fill: parent
            radius: 24
            color: Appearance.colors.colLayer2
            visible: false
        }
        DropShadow {
            anchors.fill: cardShadowSrc
            source: cardShadowSrc
            radius: 28
            samples: 48
            color: Qt.rgba(0, 0, 0, 0.45)
            verticalOffset: 10
            transparentBorder: true
        }

        // Card surface (theme-aware)
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.92)
        }

        Column {
            id: mediaCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            // Row: album art card + track info
            Row {
                spacing: 14
                width: parent.width

                Rectangle {
                    id: artCard
                    width: 64; height: 64; radius: 16
                    color: Appearance.colors.colPrimaryContainer
                    clip: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle { width: artCard.width; height: artCard.height; radius: artCard.radius }
                    }
                    StyledImage {
                        anchors.fill: parent
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        visible: root.artUrl !== ""
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1; text: "music_note"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnPrimaryContainer
                        visible: root.artUrl === ""
                    }
                }
                DropShadow {
                    anchors.fill: artCard
                    source: artCard
                    radius: 10
                    samples: 24
                    color: Qt.rgba(0, 0, 0, 0.35)
                    verticalOffset: 4
                    transparentBorder: true
                }

                Column {
                    width: parent.width - 78
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        width: parent.width
                        text: mediaCard.player?.trackTitle || ""
                        font.pixelSize: 19
                        font.bold: true
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideMiddle
                        maximumLineCount: 1
                    }
                    StyledText {
                        width: parent.width
                        text: {
                            const artist = mediaCard.player?.trackArtist || ""
                            const pname = mediaCard.player?.identity || ""
                            return artist + (pname ? "  \u00b7  " + pname : "")
                        }
                        font.pixelSize: 13
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            // Seekable progress bar
            Item {
                width: parent.width
                height: 20

                StyledText {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: mediaCard.fmtTime(mediaCard.shownProgress * (mediaCard.player?.length ?? 0))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: mediaCard.fmtTime(mediaCard.player?.length ?? 0)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Rectangle {
                    id: trackBg
                    anchors { left: parent.left; right: parent.right; leftMargin: 40; rightMargin: 40; verticalCenter: parent.verticalCenter }
                    height: 4
                    radius: 2
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.85)

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * mediaCard.shownProgress
                        radius: 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Appearance.colors.colPrimary }
                            GradientStop { position: 1; color: Appearance.colors.colSecondary }
                        }
                    }

                    Rectangle {
                        id: thumb
                        x: parent.width * mediaCard.shownProgress - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: seekArea.containsMouse || seekArea.dragging ? 14 : 10
                        height: width
                        radius: width / 2
                        color: Appearance.colors.colPrimary
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                    DropShadow {
                        anchors.fill: thumb
                        source: thumb
                        radius: 8
                        samples: 16
                        color: Appearance.colors.colPrimary
                        transparentBorder: true
                        visible: seekArea.containsMouse || seekArea.dragging
                    }

                    MouseArea {
                        id: seekArea
                        anchors { fill: parent; topMargin: -8; bottomMargin: -8; leftMargin: -4; rightMargin: -4 }
                        hoverEnabled: true
                        enabled: mediaCard.player !== null && mediaCard.player.canSeek
                        property bool dragging: false
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                        function ratioAt(mx) {
                            const px = mapToItem(trackBg, mx, 0).x
                            return Math.max(0, Math.min(1, px / trackBg.width))
                        }
                        onPressed: mouse => {
                            dragging = true
                            mediaCard.dragPos = ratioAt(mouse.x)
                        }
                        onPositionChanged: mouse => {
                            if (dragging) mediaCard.dragPos = ratioAt(mouse.x)
                        }
                        onReleased: {
                            dragging = false
                            if (mediaCard.player)
                                mediaCard.player.position = mediaCard.dragPos * mediaCard.player.length
                        }
                    }
                }
            }

            // Transport controls with hover/press micro-interactions
            Row {
                spacing: 18
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    width: 42; height: 42; radius: 21
                    color: prevMa.pressed ? Appearance.colors.colLayer2Active
                         : prevMa.containsMouse ? Appearance.colors.colLayer2Hover
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: prevMa.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_previous"; fill: 1
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnLayer2
                    }
                    MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: mediaCard.player?.previous() }
                }

                Rectangle {
                    width: 52; height: 52; radius: 26
                    color: playMa.pressed ? Appearance.colors.colPrimaryActive
                         : playMa.containsMouse ? Appearance.colors.colPrimaryHover
                         : Appearance.colors.colPrimary
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: playMa.pressed ? 0.92 : playMa.containsMouse ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: mediaCard.player?.isPlaying ? "pause" : "play_arrow"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnPrimary
                    }
                    MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; onClicked: mediaCard.player?.togglePlaying() }
                }

                Rectangle {
                    width: 42; height: 42; radius: 21
                    color: nextMa.pressed ? Appearance.colors.colLayer2Active
                         : nextMa.containsMouse ? Appearance.colors.colLayer2Hover
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: nextMa.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_next"; fill: 1
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnLayer2
                    }
                    MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: mediaCard.player?.next() }
                }
            }
        }
    }

    // ── Live lyrics (auto-hidden when unavailable) ──────────────
    Column {
        id: lyricsBlock
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: mediaCard.visible ? mediaCard.bottom : clockSection.bottom
            topMargin: 22
        }
        spacing: 6
        visible: LyricsService.status === "ok"
            && (LyricsService.slots[LyricsService.before] ?? "") !== ""
            && root.activePlayer !== null && Config.options.lock.showMedia
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 420
            text: LyricsService.slots[LyricsService.before] ?? ""
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.75)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 420
            text: LyricsService.slots[LyricsService.before + 1] ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Qt.rgba(1, 1, 1, 0.38)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: text !== ""
        }
    }

    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured
            visible: active

            sourceComponent: MaterialSymbol {
                id: fingerprintIcon
                fill: 1
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ToolbarTextField {
            id: passwordBox
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                root.context.resetClearTimer();
            }
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // Shake when wrong password
            ErrorShakeAnimation {
                id: wrongPasswordShakeAnim
                target: passwordBox
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: root.context.tryUnlock()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        visible: Config.options.lock.showToolbars
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            visible: true
            text: SystemInfo.username
        }


        // Keyboard layout (Xkb)
        Loader {
            Layout.rightMargin: 8
            Layout.fillHeight: true
            visible: true

            sourceComponent: Row {
                spacing: 8

                MaterialSymbol {
                    id: keyboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    fill: 1
                    text: "keyboard_alt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: StyledText {
                        text: HyprlandXkb.currentLayoutCode
                        color: Appearance.colors.colOnSurfaceVariant
                        animateChange: true
                    }
                }
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        visible: Config.options.lock.showToolbars
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        IconAndTextPair {
            visible: Battery.available
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        }

        IconToolbarButton {
            id: sleepButton
            onClicked: Session.suspend()
            text: "dark_mode"
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }
}
