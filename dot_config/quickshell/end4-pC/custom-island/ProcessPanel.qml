import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.services

// ─────────────────────────────────────────────────────────────────────────
// 进程列表面板（系统页右侧通高卡片的内容）。
//
// 从 ClockDashboard.qml 的系统页「进程列表」段（第 1248-1507 行）搬过来，
// 但做了三处适配：
//   1. 配色/字体令牌换成岛屿的 Theme（上游用 Appearance）；
//   2. 排序按钮与 kill 按钮从 RippleButton / MaterialSymbol 换成自绘的
//      Rectangle + Nerd Font 字形 —— 岛屿里没有 MaterialSymbol 这套依赖；
//   3. kill 按钮用 opacity 而不是 visible 控制显隐：RowLayout 里 visible
//      切换会让进程名那一列宽度来回跳，鼠标扫过列表时整行文字都在抖。
//
// 数据来源是 end4-pC 的 ProcessList 单例（import qs.services）。
// ─────────────────────────────────────────────────────────────────────────

Item {
    id: root

    // 只有面板打开且停在系统页时才允许后台轮询，避免收起时白跑 ps
    property bool active: false

    onActiveChanged: {
        ProcessList.autoRefresh = root.active
        if (root.active)
            ProcessList.requestRefresh()
    }

    Component.onCompleted: {
        if (root.active) {
            ProcessList.autoRefresh = true
            ProcessList.requestRefresh()
        }
    }

    property string query: ""

    // 把过滤结果缓存成属性：ListView.model 每帧只读这一处，
    // 否则 query 每变一次都会连带重新求值
    readonly property var visibleProcesses: ProcessList.filtered(root.query)

    readonly property var _sortKeys: [
        { key: "cpu",  label: "CPU" },
        { key: "mem",  label: Translation.tr("Memory") },
        { key: "name", label: Translation.tr("Name") }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── 标题 + 排序 + 刷新 ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: Translation.tr("Processes")
                color: Theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Text {
                text: `${ProcessList.list.length}`
                color: Theme.active
                font.pixelSize: 10
                font.family: Theme.monoFontFamily
                font.features: { "tnum": 1 }
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: root._sortKeys

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool isActive: ProcessList.sortKey === modelData.key

                    implicitWidth:  sortLabel.implicitWidth + 14
                    implicitHeight: 22
                    radius: height / 2
                    color: isActive
                           ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.20)
                           : sortHover.hovered ? Qt.rgba(1,1,1,0.10) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        id: sortLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: isActive ? Theme.active : Theme.subtext
                        font.pixelSize: 10
                        font.weight: isActive ? Font.DemiBold : Font.Normal
                    }

                    HoverHandler { id: sortHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: ProcessList.setSortKey(modelData.key)
                    }
                }
            }

            // 手动刷新
            Rectangle {
                implicitWidth:  22
                implicitHeight: 22
                radius: height / 2
                color: refreshHover.hovered ? Qt.rgba(1,1,1,0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰑓"
                    font.pixelSize: 12
                    font.family: Theme.nerdFontFamily
                    color: Theme.subtext
                }

                HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked: ProcessList.requestRefresh()
                }
            }
        }

        // ── 搜索框 ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: procSearch.activeFocus ? 1 : 1
            border.color: procSearch.activeFocus
                          ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.6)
                          : Qt.rgba(1, 1, 1, 0.08)
            Behavior on border.color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill:    parent
                anchors.leftMargin:  10
                anchors.rightMargin: 6
                spacing: 6

                Text {
                    text: "󰍉"
                    font.pixelSize: 12
                    font.family: Theme.nerdFontFamily
                    color: Theme.subtext
                }

                TextField {
                    id: procSearch
                    Layout.fillWidth: true
                    background: null
                    text: root.query
                    placeholderText: Translation.tr("Filter processes…")
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.28)
                    color: Theme.text
                    font.pixelSize: 11
                    selectByMouse: true
                    onTextChanged: root.query = text
                }

                Text {
                    visible: procSearch.text.length > 0
                    text: "󰅖"
                    font.pixelSize: 11
                    font.family: Theme.nerdFontFamily
                    color: clearHover.hovered ? Theme.text : Theme.subtext

                    HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: {
                            procSearch.text = ""
                            root.query = ""
                        }
                    }
                }
            }
        }

        // ── 进程列表 ──────────────────────────────────────────────────────
        // 用 ListView + reuseItems 而不是 Repeater + Flickable：
        // Repeater 每次模型变化会销毁重建全部 delegate（200 行），
        // 后台 3s 刷一次、搜索每敲一字都重建 → 卡顿。
        // ListView 复用 delegate item，只更新可见的 ~12 行。
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: procListView
                anchors.fill: parent
                clip: true
                spacing: 2
                model: root.visibleProcesses
                reuseItems: true
                cacheBuffer: 400
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: procRow
                    required property var modelData

                    width:  procListView.width
                    height: 30
                    radius: 6
                    color: procRowHover.hovered
                           ? Qt.rgba(1, 1, 1, 0.07)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    MouseArea {
                        id: procRowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        // 只跟踪 hover，不吃点击事件，让后面的 kill 按钮能拿到点击
                        acceptedButtons: Qt.NoButton
                    }

                    RowLayout {
                        anchors.fill:        parent
                        anchors.leftMargin:  8
                        anchors.rightMargin: 4
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 44
                            text: `${modelData.pid}`
                            elide: Text.ElideRight
                            color: Theme.subtext
                            font.pixelSize: 9
                            font.family: Theme.monoFontFamily
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.pixelSize: 11
                        }

                        Text {
                            Layout.preferredWidth: 42
                            horizontalAlignment: Text.AlignRight
                            text: `${modelData.cpu.toFixed(1)}%`
                            color: modelData.cpu > 20 ? "#f38ba8" : Theme.active
                            font.pixelSize: 9
                            font.family: Theme.monoFontFamily
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            Layout.preferredWidth: 42
                            horizontalAlignment: Text.AlignRight
                            text: `${modelData.mem.toFixed(1)}%`
                            color: Theme.subtext
                            font.pixelSize: 9
                            font.family: Theme.monoFontFamily
                            font.features: { "tnum": 1 }
                        }

                        // kill —— 用 opacity 而非 visible，避免 RowLayout 重排导致文字抖动
                        Rectangle {
                            implicitWidth:  22
                            implicitHeight: 22
                            radius: height / 2
                            opacity: procRowHover.hovered ? 1 : 0
                            color: killHover.hovered ? Qt.rgba(0.95, 0.55, 0.66, 0.22) : "transparent"
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Behavior on color   { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.pixelSize: 11
                                font.family: Theme.nerdFontFamily
                                color: "#f38ba8"
                            }

                            HoverHandler { id: killHover; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: ProcessList.killProcess(modelData.pid, "TERM")
                            }
                        }
                    }
                }
            }

            // 空状态覆盖层（独立于 ListView，不参与 delegate 池）
            Rectangle {
                anchors.fill: parent
                visible: root.visibleProcesses.length === 0
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.04)

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (!ProcessList.ready)
                            return Translation.tr("Loading…")
                        if (root.query.length > 0)
                            return Translation.tr("No matching process")
                        return Translation.tr("No process")
                    }
                    color: Theme.subtext
                    font.pixelSize: 11
                }
            }
        }
    }
}
