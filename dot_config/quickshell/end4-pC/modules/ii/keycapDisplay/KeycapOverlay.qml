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
 * 三个容易踩的点，下面都标了注释：
 *  1. 距屏幕边缘的间距必须写在本窗口的 margins 上，不能写成子项的 anchors 边距 ——
 *     窗口高度是自适应子项的，子项再带边距就会把自己顶出窗口，表现为「边框被截断」。
 *  2. 底色用不透明的 M3 token，不能用 colLayer* —— 那些在开启透明度后是半透明的，
 *     浅色壁纸下文字会糊掉。
 *  3. 键帽新出现时弹一下（Component.onCompleted 触发），打字才有反馈。
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

    // 距屏幕边缘的间距，给键帽下面留一点呼吸空间
    readonly property int edgeMargin: 56
    // 窗口四周的留白，给键帽描边留余量（紧贴窗口边缘会显得被切掉）
    readonly property int windowPadding: 8
    readonly property int keycapHeight: 46

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

        // 关键：间距写在这里（窗口自己的 margins），不要写进子项的 anchors。
        // 窗口高度 = 子项高度，子项再带 topMargin 就会溢出到窗口外被裁掉。
        margins {
            top: root.position !== "bottom" ? root.edgeMargin : 0
            bottom: root.position === "bottom" ? root.edgeMargin : 0
        }

        implicitWidth: keycapRow.implicitWidth + root.windowPadding * 2
        implicitHeight: keycapRow.implicitHeight + root.windowPadding * 2

        // 只让键帽本身占输入区域，其余部分点击穿透
        mask: Region {
            item: keycapRow
        }

        RowLayout {
            id: keycapRow
            anchors.centerIn: parent
            spacing: 8

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

                    Layout.preferredWidth: Math.max(root.keycapHeight, keycapLabel.implicitWidth + 28)
                    Layout.preferredHeight: root.keycapHeight
                    radius: Appearance.rounding.normal

                    // 不透明底色：colLayer* 在开启透明度后是半透明的，
                    // 铺在浅色壁纸上文字会看不清。这里直接用 M3 的 surface / primary
                    // 容器色，两种明暗模式下对比度都有保证。
                    color: keycap.isModifier
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.m3colors.m3surfaceContainerHighest
                    border.width: 1
                    border.color: keycap.isModifier
                        ? Appearance.colors.colPrimary
                        : Appearance.m3colors.m3outlineVariant

                    // 打字反馈：键帽是新出现的时候弹一下。
                    // Repeater 按下标复用 delegate，所以「又按住一个键」只让新键帽动，
                    // 一直按住的 Ctrl 不会反复弹。
                    NumberAnimation {
                        id: popIn
                        target: keycap
                        property: "scale"
                        from: 0.72
                        to: 1.0
                        duration: 130
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.2
                    }
                    Component.onCompleted: popIn.start()

                    StyledText {
                        id: keycapLabel
                        anchors.centerIn: parent
                        text: keycap.modelData
                        color: keycap.isModifier
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.m3colors.m3onSurface
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: keycap.isModifier ? Font.Medium : Font.Normal
                    }
                }
            }
        }
    }
}
