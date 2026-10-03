import qs.modules.common
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property bool vertical: false
    property real crossAxisSize: 32
    property real mainAxisPadding: 10
    property real contentSpacing: 3
    property real contentTopMargin: 3
    property color bgColor: Appearance.colors.colPrimaryContainer

    default property alias content: contentLayout.children

    color: root.bgColor
    radius: Appearance.rounding.full
    implicitWidth: root.vertical
        ? root.crossAxisSize
        : contentLayout.implicitWidth + root.mainAxisPadding
    implicitHeight: root.vertical
        ? contentLayout.implicitHeight + root.mainAxisPadding
        : root.crossAxisSize

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.vertical ? root.contentTopMargin / 2 : 0
        columns: root.vertical ? 1 : -1
        rowSpacing: root.contentSpacing
        columnSpacing: root.contentSpacing
    }
}