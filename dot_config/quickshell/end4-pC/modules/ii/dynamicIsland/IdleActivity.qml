import QtQuick

Item {
    id: root
    property bool expanded: false
    property var payload: ({})
    signal dismissed()

    // 空闲态：只显示一条极淡的提示，实际使用时可留空
    Rectangle {
        anchors.centerIn: parent
        width: 60
        height: 5
        radius: 2.5
        color: IslandTheme.trackStrong
    }
}
