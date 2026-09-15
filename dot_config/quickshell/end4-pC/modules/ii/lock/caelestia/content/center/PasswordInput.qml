pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/PasswordInput.qml。
// pam.* -> LockContext：buffer 判定用 currentText，提交用 tryUnlock()。
// 键盘输入直接操作 currentText，Enter 触发 tryUnlock。
StyledRect {
    id: root

    required property real centerScale
    required property int centerWidth
    required property var lock

    readonly property bool hasInput: lock.currentText.length > 0

    implicitWidth: {
        const w = centerWidth * 0.8;
        return hasInput ? w : Math.min(w, inputField.placeholderWidth + iconWrapper.implicitWidth + enterButton.implicitWidth + input.spacing * 2 + Tokens.padding.medium * 2);
    }
    implicitHeight: input.implicitHeight + Tokens.padding.small

    color: Appearance.m3colors.m3surfaceContainer
    radius: Tokens.rounding.full

    focus: true
    onActiveFocusChanged: {
        if (!activeFocus)
            forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (root.lock.unlocking)
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            inputField.placeholder.animate = false;
            if (root.hasInput)
                root.lock.tryUnlock();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Backspace) {
            if (root.lock.currentText.length > 0)
                root.lock.currentText = root.lock.currentText.slice(0, -1);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            root.lock.currentText = "";
            event.accepted = true;
            return;
        }

        if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 0x20) {
            root.lock.currentText += event.text;
            event.accepted = true;
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    StateLayer {
        hoverEnabled: false
        cursorShape: Qt.IBeamCursor
        onClicked: parent.forceActiveFocus()
    }

    RowLayout {
        id: input

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        spacing: Tokens.spacing.medium

        Item {
            id: iconWrapper

            Layout.fillHeight: true
            implicitWidth: height

            MaterialIcon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: inputField.showPassword ? "visibility" : "lock"
                color: Appearance.m3colors.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale).build()
                fill: text === "visibility"

                StateLayer {
                    anchors.fill: undefined
                    anchors.centerIn: parent
                    implicitWidth: parent.implicitHeight + Tokens.padding.small * 2
                    implicitHeight: implicitWidth
                    radius: Tokens.rounding.full
                    onClicked: inputField.showPassword = !inputField.showPassword
                }
            }
        }

        InputField {
            id: inputField
            Layout.fillWidth: true
            Layout.fillHeight: true
            centerScale: root.centerScale
            lock: root.lock
        }

        Item {
            id: enterButton

            implicitWidth: implicitHeight
            implicitHeight: {
                const h = enterIcon.implicitHeight + Tokens.padding.extraSmall * 2;
                return h % 2 === 0 ? h : h + 1;
            }

            MaterialShape {
                anchors.fill: parent

                color: root.hasInput ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
                shape: root.hasInput ? MaterialShape.Arrow : MaterialShape.Circle
                scale: !root.hasInput ? 1 : mouse.pressed ? 0.6 : mouse.containsMouse ? 0.8 : 0.7
                rotation: 90

                Behavior on scale { Anim { type: Anim.FastSpatial } }
                Behavior on color { CAnim {} }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.hasInput ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.hasInput)
                            root.lock.tryUnlock();
                    }
                }
            }

            MaterialIcon {
                id: enterIcon
                anchors.centerIn: parent
                text: "arrow_forward"
                color: Appearance.m3colors.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.scale(root.centerScale * 1.2).build()
                opacity: root.hasInput ? 0 : 1
                Behavior on opacity { Anim { type: Anim.DefaultEffects } }
            }
        }
    }
}
