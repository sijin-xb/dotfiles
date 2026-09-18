/**
 * 从 Brain_Shell 的 src/components/TabSwitcher.qml 移植。
 * 改动：1) 删掉 `import "../"`（Theme 单例走同目录隐式导入）；
 *      2) 原文件 vertical 段落用的是 Tab 缩进，这里统一成 4 空格，代码逻辑与数值零改动。
 */
import QtQuick

// Unified tab switcher — horizontal or vertical.
//
// orientation: "horizontal" (default) — Row, fills parent width, tabs spaced equally
//              "vertical"             — Column, fills parent height, tabs spaced equally
//
// Horizontal: icon + label pill, bottom divider. Used by Dashboard.
// Vertical:   icon-only solid pill. Used by ArchMenu.
//
// Model: [{ key: string, icon: string, label?: string }]
// label is optional — only rendered in horizontal orientation.
//
// Sizing contract:
//   Horizontal — parent MUST set width.  implicitHeight is 40.
//   Vertical   — parent MUST set height. implicitWidth  is 40.

Item {
    id: root

    property var    model:       []
    property string currentPage: ""
    property string orientation: "horizontal"   // "horizontal" | "vertical"

    // ⚠ 与上游的差异（必要适配）：
    // 上游靠应用级默认字体把 model 里的 icon 直接渲染出来，end4-pC 没有这个
    // 全局约定，不指定字体族就会把图标画成普通文字（"home Home"）。
    // 而且两处调用方的字形体系不同：
    //   IslandHost 用 Material 图标名（"home" / "monitor_heart"）
    //   ClockCard  用 Nerd Font 字形（"󰥔" / "󱎫" …）
    // 所以开一个 iconFont 口子由调用方指定，默认 Material（岛屿页签是主用法）。
    property string iconFont: Theme.iconFontFamily

    signal pageChanged(string key)

    // ── Default page & reset ──────────────────────────────────────────────────
    // defaultPage auto-resolves to the first model entry.
    // Call reset() from the popup's close handler to restore it off-screen.
    property string defaultPage: model.length > 0 ? model[0].key : ""

    function reset() {
        pageChanged(defaultPage)
    }

    implicitWidth:  orientation === "vertical"   ? 40 : 0
    implicitHeight: orientation === "horizontal" ? 40 : 0

    // ── Scroll cooldown ───────────────────────────────────────────────────────
    property bool scrollBusy: false

    Timer {
        id: scrollCooldown
        interval: 300
        repeat:   false
        onTriggered: root.scrollBusy = false
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            if (root.scrollBusy) return
            root.scrollBusy = true
            scrollCooldown.restart()
            var keys = root.model.map(function(m) { return m.key })
            var idx  = keys.indexOf(root.currentPage)
            if (event.angleDelta.y < 0)
            idx = (idx + 1) % keys.length
            else
            idx = (idx - 1 + keys.length) % keys.length
            root.pageChanged(keys[idx])
        }
    }

    // ── HORIZONTAL layout — Row ───────────────────────────────────────────────
    // 与上游的唯一差异：Brain_Shell 的仪表盘有 5 个页签，所以它把每个页签
    // 按 `hRow.width / model.length` 等分铺满整行。本移植只做 home + stats
    // 两个页签，等分后两个页签会被推到 900px 的两端、中间空一大片。
    // 因此这里改成「按内容宽度、整行居中」，页签数量变化时都不会散。
    Row {
        id: hRow
        anchors.fill: parent
        visible: root.orientation === "horizontal"

        Repeater {
            model: root.orientation === "horizontal" ? root.model : []

            delegate: Item {
                id: hTab
                readonly property bool isActive: root.currentPage === modelData.key

                width:  hRow.width / root.model.length
                height: hRow.height

                // Pill background
                Rectangle {
                    id: hBg
                    anchors.centerIn: parent
                    width:  hIcon.implicitWidth + hLabel.implicitWidth + 24
                    height: parent.height - 8
                    radius: height / 2

                    color: hTab.isActive
                    ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.18)
                    : (hHov.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent")

                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Icon + label
                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: hIcon
                        text:           modelData.icon
                        font.pixelSize: 14
                        // end4-pC 没有全局图标字体约定，必须显式指定，
                        // 否则 "home" 会被当普通文字画出来
                        font.family:    root.iconFont
                        anchors.verticalCenter: parent.verticalCenter
                        color: hTab.isActive
                        ? Theme.active
                        : (hHov.hovered ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.4))
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Text {
                        id: hLabel
                        visible:        modelData.label !== undefined
                        text:           modelData.label ?? ""
                        font.pixelSize: 12
                        font.weight:    hTab.isActive ? Font.Medium : Font.Normal
                        anchors.verticalCenter: parent.verticalCenter
                        color: hTab.isActive
                        ? Theme.active
                        : (hHov.hovered ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.4))
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                HoverHandler { id: hHov; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked:    root.pageChanged(modelData.key)
                }
            }
        }
    }

    // Bottom divider — horizontal only
    Rectangle {
        visible:        root.orientation === "horizontal"
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height:         1
        color:          Qt.rgba(1, 1, 1, 0.07)
    }

    // ── VERTICAL layout — Column ──────────────────────────────────────────────
        Column {
            id: vCol
            anchors.centerIn: parent
            visible: root.orientation === "vertical"
            width:   root.width
    
            readonly property int tabH: 60
            spacing: root.model.length > 1
                ? (root.height - root.model.length * tabH) / (root.model.length - 1)
                : 0
    
            readonly property bool hasLabels:
                root.model.length > 0 &&
                root.model[0].label !== undefined &&
                root.model[0].label !== ""
    
            Repeater {
                model: root.orientation === "vertical" ? root.model : []
    
                delegate: Rectangle {
                    id: vTab
                    readonly property bool isActive: root.currentPage === modelData.key
    
                    width:  vCol.width
                    height: vCol.tabH
                    radius: Theme.cornerRadius * 2
    
                    color: vTab.isActive
                        ? Theme.active
                        : (vHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
    
                    Behavior on color { ColorAnimation { duration: 120 } }
    
                    // Icon-only (no label)
                    Text {
                        visible:          !vCol.hasLabels
                        anchors.centerIn: parent
                        text:             modelData.icon
                        font.pixelSize:   16
                        font.family:      root.iconFont
                        color: vTab.isActive ? Theme.background : Theme.text
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
    
                    // Icon + label row
                    Row {
                        visible: vCol.hasLabels
                        anchors {
                            left:           parent.left
                            leftMargin:     16
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 12
    
                        Text {
                            text:           modelData.icon
                            font.pixelSize: 15
                            font.family:    root.iconFont
                            anchors.verticalCenter: parent.verticalCenter
                            color: vTab.isActive
                                ? Theme.background
                                : (vHov.hovered ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(1, 1, 1, 0.42))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
    
                        Text {
                            text:           modelData.label ?? ""
                            font.pixelSize: 12
                            font.weight:    vTab.isActive ? Font.Medium : Font.Normal
                            anchors.verticalCenter: parent.verticalCenter
                            color: vTab.isActive
                                ? Theme.background
                                : (vHov.hovered ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(1, 1, 1, 0.42))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
    
                    HoverHandler { id: vHov; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked:    root.pageChanged(modelData.key)
                    }
                }
            }
        }
    }

