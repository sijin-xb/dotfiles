/**
 * 从 Brain_Shell 的 src/components/StatRow.qml 移植。
 * 改动：仅删掉 `import "../"`（Theme 单例走同目录隐式导入），其余逐字保留。
 */
import QtQuick

// A single horizontal label / value pair.
// Label is dimmed, value is bright by default.
// valueColor can be overridden for highlights (e.g. up/down arrows).

Item {
    id: root

    property string label:      ""
    property string value:      ""
    property color  valueColor: Theme.text

    implicitHeight: 20

    Text {
        anchors.left:           parent.left
        anchors.verticalCenter: parent.verticalCenter
        text:           root.label
        font.pixelSize: 11
        color:          Qt.rgba(1, 1, 1, 0.4)
    }

    Text {
        anchors.right:          parent.right
        anchors.verticalCenter: parent.verticalCenter
        text:           root.value
        font.pixelSize: 11
        color:          root.valueColor
    }
}
