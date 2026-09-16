import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * 按键显示浮层。
 *
 * 数据来自 KeycapDisplay（它起 scripts/keyboard/keycap-reader.py 读 evdev）。
 * 这里只负责画：一排圆角键帽，按下即出现，全部松开后延迟淡出。
 *
 * 修饰键（Ctrl / Shift / Alt / Super）用主色描边区分开，组合键一眼能看出
 * 哪个是修饰键。浮层不吃输入：mask 只覆盖键帽本身，键帽上也没有 MouseArea，
 * 所以点击会穿透到下面的窗口。
 */
Scope {
    id: root

    // 不用可选链（?. / ??）：qmllint 的 JS 解析器还不认，会整片报 Syntax error，
    // 把真正的语法问题淹掉。写成显式判断，lint 输出保持干净。
    property var focusedScreen: {
        const monitor = Hyprland.focusedMonitor;
        let found = null;
        if (monitor)
            found = Quickshell.screens.find(s => s.name === monitor.name);
        return (found !== undefined && found !== null) ? found : Quickshell.screens[0];
    }

    readonly property bool enabled: Config.options.keycapDisplay.enable
    readonly property string position: Config.options.keycapDisplay.position

    readonly property var modifierNames: ["Ctrl", "Shift", "Alt", "Super", "Caps", "Num", "Scroll"]

    function isModifier(label) {
        return root.modifierNames.indexOf(label) !== -1;
    }

    PanelWindow {
        id: overlay
        screen: root.focusedScreen
        color: "transparent"
        visible: root.enabled && KeycapDisplay.showing

        WlrLayershell.namespace: "quickshell:keycapDisplay"
        WlrLayershell.layer: WlrLayer.Overlay
        // 完全不抢键盘焦点，也不占位置
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
            top: root.position !== "bottom"
            bottom: root.position === "bottom"
        }

        // 只让键帽本身占输入区域，其余部分点击穿透
        mask: Region {
            item: keycapRow
        }

        RowLayout {
            id: keycapRow
            spacing: 8

            anchors {
                horizontalCenter: parent.horizontalCenter
                top: root.position !== "bottom" ? parent.top : undefined
                bottom: root.position === "bottom" ? parent.bottom : undefined
                topMargin: root.position !== "bottom" ? 48 : 0
                bottomMargin: root.position === "bottom" ? 64 : 0
            }

            // 淡入淡出 + 轻微上浮，跟 OSD 的观感保持一致
            opacity: overlay.visible ? 1 : 0
            scale: overlay.visible ? 1 : 0.94
            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: KeycapDisplay.shownKeys

                delegate: Rectangle {
                    id: keycap
                    required property string modelData
                    required property int index

                    readonly property bool isModifier: root.isModifier(modelData)

                    Layout.preferredWidth: Math.max(42, keycapLabel.implicitWidth + 26)
                    Layout.preferredHeight: 42
                    radius: Appearance.rounding.normal
                    color: keycap.isModifier
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer3
                    border.width: 1
                    border.color: keycap.isModifier
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border

                    StyledText {
                        id: keycapLabel
                        anchors.centerIn: parent
                        text: keycap.modelData
                        color: keycap.isModifier
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnLayer3
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: keycap.isModifier ? Font.Medium : Font.Normal
                    }
                }
            }
        }
    }
}
