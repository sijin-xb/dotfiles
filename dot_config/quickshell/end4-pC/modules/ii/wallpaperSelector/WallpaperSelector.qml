import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool reallyOpen: false

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen) {
                closeAnimTimer.stop();
                root.reallyOpen = true;
            } else {
                closeAnimTimer.restart();
            }
        }
    }

    Timer {
        id: closeAnimTimer
        interval: Appearance.animation.sidebarSlideExit.duration
        onTriggered: root.reallyOpen = false
    }

    // 注意：Loader 必须常驻（active: true）。若把 active 绑到 reallyOpen，
    // 每次打开都会重建 PanelWindow，新 surface 以 0 尺寸创建再长到全高，
    // 在底部锚定下顶边被向上顶，表现为整块面板位移。常驻后 surface 尺寸
    // 只在启动时求解一次，开关只切 visible。
    Loader {
        id: wallpaperSelectorLoader
        active: true

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property var monitor: WM.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: WM.compositor === "hyprland"
                ? (Hyprland.focusedMonitor?.name == monitor?.name)
                : (WM.focusedMonitor?.name == monitor?.name)

            visible: root.reallyOpen
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.bottom: true
            margins {
                bottom: Config?.options.bar.vertical
                    ? Appearance.sizes.hyprlandGapsOut
                    : (Config?.options.bar.bottom
                        ? Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
                        : Appearance.sizes.hyprlandGapsOut)
            }

            mask: Region {
                item: content
            }

            implicitHeight: Appearance.sizes.wallpaperSelectorHeight
            implicitWidth: Appearance.sizes.wallpaperSelectorWidth

            Connections {
                target: root
                function onReallyOpenChanged() {
                    if (root.reallyOpen) {
                        GlobalFocusGrab.addDismissable(panelWindow);
                        Qt.callLater(() => content.slideIn());
                    } else {
                        GlobalFocusGrab.removeDismissable(panelWindow);
                    }
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.wallpaperSelectorOpen = false;
                }
            }

            // 面板位置由 anchors.bottom 决定，surface 尺寸固定。
            // 内容只做淡入淡出，不做任何位移。
            WallpaperSelectorContent {
                id: content
                width: parent.width
                height: parent.height
                x: 0
                y: 0
                // 无位移。入场用 opacity + 极轻微 scale，让面板"长出来"而不是
                // 直接盖在壁纸上；scale 从 0.97 起，肉眼几乎察觉不到尺寸变化，
                // 但比纯淡入有重量。时长偏长（460ms），避免出现得太突兀。
                opacity: 0
                scale: 0.97
                transformOrigin: Item.Center

                ParallelAnimation {
                    id: appearAnim
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        to: 1
                        duration: 460
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.sidebarSlideEnter.bezierCurve
                    }
                    NumberAnimation {
                        target: content
                        property: "scale"
                        to: 1
                        duration: 520
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.sidebarSlideEnter.bezierCurve
                    }
                }

                ParallelAnimation {
                    id: disappearAnim
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        to: 0
                        duration: 280
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.sidebarSlideExit.bezierCurve
                    }
                    NumberAnimation {
                        target: content
                        property: "scale"
                        to: 0.98
                        duration: 280
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animation.sidebarSlideExit.bezierCurve
                    }
                }

                function slideIn() {
                    appearAnim.stop();
                    disappearAnim.stop();
                    appearAnim.start();
                }

                function slideOut() {
                    appearAnim.stop();
                    disappearAnim.stop();
                    disappearAnim.start();
                }

                Connections {
                    target: GlobalStates
                    function onWallpaperSelectorOpenChanged() {
                        if (!GlobalStates.wallpaperSelectorOpen) content.slideOut();
                    }
                }
            }
        }
    }

    function toggleWallpaperSelector() {
        if (Config.options.wallpaperSelector.useSystemFileDialog) {
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
            return;
        }
        GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
    }

    IpcHandler {
        target: "wallpaperSelector"

        function toggle(): void {
            root.toggleWallpaperSelector();
        }

        function random(): void {
            Wallpapers.randomFromCurrentFolder();
        }
    }

    CompositorGlobalShortcut {
        name: "wallpaperSelectorToggle"
        description: "Toggle wallpaper selector"
        onPressed: {
            root.toggleWallpaperSelector();
        }
    }

    CompositorGlobalShortcut {
        name: "wallpaperSelectorRandom"
        description: "Select random wallpaper in current folder"
        onPressed: {
            Wallpapers.randomFromCurrentFolder();
        }
    }
}
