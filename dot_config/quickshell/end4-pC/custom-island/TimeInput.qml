import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 的 src/components/TimeInput.qml 移植。
//
// 改动：无（源文件只 import QtQuick，没有相对路径 import，也不引用 Theme）。
//
// 为什么要多移植这一个文件：ClockCard.qml 的「自定义时长」与「新建闹钟」两处都用
// TimeInput，而 end4-pC（qs.services / qs.modules.common.widgets / 本目录 qmldir）
// 里都没有等价控件。若只留裸引用会直接 ReferenceError，所以按原样补进来；
// 它没有列入 custom-island/qmldir，靠同目录隐式导入解析（Qt6 目录导入会扫描
// 目录下所有 .qml，qmldir 未列出不影响解析）。
// ─────────────────────────────────────────────────────────────────────────

// TimeInput — reusable HH:MM input
// Props : hours (int, readonly), minutes (int, readonly), minuteStep (int, default 1)
// Call  : initialize(h, m) to push values from outside

Item {
    id: root

    readonly property int hours:   hVal
    readonly property int minutes: mVal

    property int minuteStep: 1
    property int hVal: 0
    property int mVal: 0

    function initialize(h, m) { hVal = h; mVal = m }

    function zp(n)  { var s = "" + n; return s.length < 2 ? "0" + s : s }
    function incH() { hVal = hVal >= 23 ? 0  : hVal + 1 }
    function decH() { hVal = hVal <= 0  ? 23 : hVal - 1 }
    function incM() { var n = mVal + minuteStep; mVal = n > 59 ? 0 : n }
    function decM() { var n = mVal - minuteStep; mVal = n < 0 ? Math.floor(59 / minuteStep) * minuteStep : n }

    implicitWidth:  _row.implicitWidth
    implicitHeight: _row.implicitHeight

    Row {
        id: _row
        spacing: 8

        // ══ HOURS ═════════════════════════════════════════════════════════════
        Column {
            spacing: 2
            width: 36

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "HH"; font.pixelSize: 9; font.weight: Font.Medium
                font.family: Theme.monoFontFamily
                color: Qt.rgba(1,1,1,0.3)
            }

            Rectangle {
                width: parent.width; height: 22; radius: 6
                color: hUpH.hovered ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                border.color: Qt.rgba(1,1,1,0.08); border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4) }
                HoverHandler { id: hUpH; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.incH() }
            }

            Item {
                width: parent.width; height: 30

                Text {
                    anchors.centerIn: parent
                    text: root.zp(root.hVal)
                    font.pixelSize: 20; font.weight: Font.Bold
                    font.family: Theme.monoFontFamily
                    color: Qt.rgba(235/255, 240/255, 255/255, 0.9)
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(ev) {
                        ev.accepted = true
                        if (ev.angleDelta.y > 0) root.incH()
                        else                     root.decH()
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 22; radius: 6
                color: hDnH.hovered ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                border.color: Qt.rgba(1,1,1,0.08); border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4) }
                HoverHandler { id: hDnH; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.decH() }
            }
        }

        // Colon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 8
            text: ":"
            font.pixelSize: 22; font.weight: Font.Bold
            font.family: Theme.monoFontFamily
            color: Qt.rgba(1,1,1,0.3)
        }

        // ══ MINUTES ═══════════════════════════════════════════════════════════
        Column {
            spacing: 2
            width: 36

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "MM"; font.pixelSize: 9; font.weight: Font.Medium
                font.family: Theme.monoFontFamily
                color: Qt.rgba(1,1,1,0.3)
            }

            Rectangle {
                width: parent.width; height: 22; radius: 6
                color: mUpH.hovered ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                border.color: Qt.rgba(1,1,1,0.08); border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "▲"; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4) }
                HoverHandler { id: mUpH; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.incM() }
            }

            Item {
                width: parent.width; height: 30

                Text {
                    anchors.centerIn: parent
                    text: root.zp(root.mVal)
                    font.pixelSize: 20; font.weight: Font.Bold
                    font.family: Theme.monoFontFamily
                    color: Qt.rgba(235/255, 240/255, 255/255, 0.9)
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(ev) {
                        ev.accepted = true
                        if (ev.angleDelta.y > 0) root.incM()
                        else                     root.decM()
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 22; radius: 6
                color: mDnH.hovered ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                border.color: Qt.rgba(1,1,1,0.08); border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "▼"; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.4) }
                HoverHandler { id: mDnH; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.decM() }
            }
        }
    }
}
