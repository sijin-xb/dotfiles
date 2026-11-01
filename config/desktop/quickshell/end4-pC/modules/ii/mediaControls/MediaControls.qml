pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return MprisController.filterDuplicatePlayers(realPlayers)
        const filtered = realPlayers.filter(p =>
            (p.identity ?? "").toLowerCase().includes(preferred) ||
            (p.desktopEntry ?? "").toLowerCase().includes(preferred)
        )
        if (filtered.length === 0) return MprisController.filterDuplicatePlayers(realPlayers)
        return MprisController.filterDuplicatePlayers(filtered)
    }
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    readonly property string mediaPosition: {
        if (Config.options.bar.layouts.leftLayout.includes("media")) return "left"
        if (Config.options.bar.layouts.middleLayout.includes("media")) return "center"
        if (Config.options.bar.layouts.rightLayout.includes("media")) return "right"
        return "center"
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real gap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property bool cornerStyleReducesGap: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 2
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    // ── 频谱数据源 ────────────────────────────────────────────────────────────
    // 以前这里直接挂着一个常驻的 `cava` 子进程。现在优先走 Caelestia 的 C++
    // cava 插件（说明见 services/CaelestiaCava.qml 开头），只有插件不可用时才
    // 退回子进程。
    //
    // 用 Loader 而不是直接 import，是因为 `import Caelestia.Services` 在插件
    // 缺失（没编译 / QML2_IMPORT_PATH 没指对）时会让**整个文件**加载失败 ——
    // 那样连 Bar 上的媒体控件都会一起没掉。挂到 Loader 上，失败只表现为
    // cavaBridge.status 变成 Error，下面的 Process 自然会接手。
    readonly property bool cavaWanted: (GlobalStates.mediaControlsOpen ||
        GlobalStates.sidebarRightOpen ||
        (GlobalStates.sidebarLeftOpen && !GlobalStates.mediaLyricsVisible) ||
        Config.options.bar.layouts.leftLayout.includes("visualizer") ||
        Config.options.bar.layouts.middleLayout.includes("visualizer") ||
        Config.options.bar.layouts.rightLayout.includes("visualizer") ||
        Config.options.background.widgets.visualizer.enable)
        && MprisController.activePlayer !== null

    Loader {
        id: cavaBridge
        active: true
        source: Qt.resolvedUrl("../../../services/CaelestiaCava.qml")

        readonly property bool ready: status === Loader.Ready && item !== null

        Binding {
            target: cavaBridge.item
            property: "active"
            value: root.cavaWanted
            when: cavaBridge.ready
        }
    }

    // 桥就绪后由它接管 visualizerPoints；cavaProc 那边会因为 ready 而自动停掉
    Binding {
        target: GlobalStates
        property: "visualizerPoints"
        value: cavaBridge.ready ? cavaBridge.item.points : []
        when: cavaBridge.ready
    }

    // 插件不可用时的兜底：原来的实现原样保留
    Process {
        id: cavaProc
        running: !cavaBridge.ready && root.cavaWanted
        onRunningChanged: {
            if (!cavaProc.running && !cavaBridge.ready) {
                GlobalStates.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                GlobalStates.visualizerPoints = points;
            }
        }
    }

    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: true
                left: true
            }
            margins {
                top: {
                    if (root.barEdge === "top") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap -6 : root.gap)
                    if (root.barEdge === "bottom") return panelWindow.screen.height - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - playerColumnLayout.implicitHeight
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.height - playerColumnLayout.implicitHeight - root.gap
                    return (panelWindow.screen.height - playerColumnLayout.implicitHeight) / 2
                }
                left: {
                    if (root.barEdge === "left") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap : root.gap)
                    if (root.barEdge === "right") return panelWindow.screen.width - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - root.widgetWidth
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.width - root.widgetWidth - root.gap
                    return (panelWindow.screen.width - root.widgetWidth) / 2
                }
            }

            mask: Region {
                item: playerColumnLayout
            }

            Component.onCompleted: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!Config.options.bar.media.alwaysVisible)
                        GlobalStates.mediaControlsOpen = false;
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: Player {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: GlobalStates.visualizerPoints  
                        implicitWidth: root.widgetWidth
                        implicitHeight: showLyrics ? 290 : Appearance.sizes.mediaControlsHeight
                        radius: root.popupRounding
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            mediaControlsLoader.active = !mediaControlsLoader.active;
            if (mediaControlsLoader.active)
                Notifications.timeoutAll();
        }

        function close(): void {
            mediaControlsLoader.active = false;
        }

        function open(): void {
            mediaControlsLoader.active = true;
            Notifications.timeoutAll();
        }
    }

    CompositorGlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    CompositorGlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    CompositorGlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
