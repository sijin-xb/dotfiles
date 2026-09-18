pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import "../components"
import "../components/controls"
import "../shim"
import qs.services

/**
 * 岛屿「进程」页。
 *
 * 数据全部来自 `ProcessList` 单例（它背后是常驻的
 * scripts/processes/process_sampler.py，直接读 /proc 做增量差值）。
 *
 * 开销：本页只会在**是当前页签时**被创建（见 Content.qml 的页签懒加载），
 * 而且只有 `panelOpen` 为真才打开采样开关 —— 面板收起 / 切到别的页签时
 * 采样脚本不运行，开销为 0。
 *
 * 交互：
 *   - 顶部搜索框按 名称 / 完整命令行 / 用户名 / PID 过滤；
 *   - 点列头（CPU / 内存 / GPU / 名称）切换排序；
 *   - 每行右侧的 ✕ ：**左键 = SIGTERM**（礼貌退出），
 *     **右键 = SIGKILL**（强杀）。列表里都有提示。
 */
Item {
    id: root

    // 由 Content.qml 注入：岛屿面板是否展开
    required property bool panelOpen

    implicitWidth: Tokens.sizes.dashboard.mediaTabWidth

    // 可视高度由宿主（Content）注入，不要写死。
    // 写死会比真实可用高度大几像素 —— 外层 viewWrapper 是 ClippingRectangle，
    // 超出的部分直接被裁掉，表现为底栏「70 processes」只剩上半截字。
    required property real availableHeight
    implicitHeight: availableHeight

    property string query: ""

    // 过滤结果缓存成属性：ListView.model 只读这一处，
    // 否则 query 每变一次都会连带重新求值整个列表。
    readonly property var visibleProcesses: ProcessList.filtered(root.query)

    readonly property var _sortKeys: [
        { key: "cpu", label: Tr.tr("CPU") },
        { key: "mem", label: Tr.tr("Memory") },
        { key: "gpu", label: Tr.tr("GPU") },
        { key: "name", label: Tr.tr("Name") }
    ]

    // ── 采样开关 ────────────────────────────────────────────────────────
    // 只有面板展开时才让脚本跑。本页被销毁（切走页签）时也关掉。
    function syncSampling() {
        ProcessList.autoRefresh = root.panelOpen && !root.paused
    }

    property bool paused: false
    onPanelOpenChanged: root.syncSampling()
    onPausedChanged: root.syncSampling()
    Component.onCompleted: {
        root.syncSampling()
        if (root.panelOpen)
            ProcessList.requestRefresh()
    }
    Component.onDestruction: ProcessList.autoRefresh = false

    // 列宽。数值列固定宽度，保证表头与内容对齐。
    readonly property int colPid: 66
    readonly property int colUser: 92
    readonly property int colNum: 68
    readonly property int colAction: 34

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        // ── 工具行：搜索 + 排序 + 暂停 ──────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            SearchBar {
                id: search

                Layout.fillWidth: true
                placeholderText: Tr.tr("Search by name, command line, user or PID")

                onTextChanged: root.query = text
            }

            Repeater {
                model: root._sortKeys

                delegate: IconTextButton {
                    required property var modelData

                    Layout.alignment: Qt.AlignVCenter
                    icon: {
                        if (ProcessList.sortKey !== modelData.key)
                            return "";
                        return modelData.key === "name" ? "arrow_upward" : "arrow_downward";
                    }
                    text: modelData.label
                    type: IconTextButton.Tonal
                    isToggle: true
                    checked: ProcessList.sortKey === modelData.key
                    onClicked: ProcessList.setSortKey(modelData.key)
                }
            }

            IconButton {
                Layout.alignment: Qt.AlignVCenter
                icon: root.paused ? "play_arrow" : "pause"
                type: IconButton.Tonal
                isToggle: true
                checked: root.paused
                onClicked: root.paused = !root.paused
            }
        }

        // ── 表头 ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.medium
            Layout.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Name")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            StyledText {
                Layout.preferredWidth: root.colPid
                text: "PID"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            StyledText {
                Layout.preferredWidth: root.colUser
                text: Tr.tr("User")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Repeater {
                // 用与排序按钮一致的译名，避免表头写 MEM、按钮写「内存」
                model: [Tr.tr("CPU"), Tr.tr("Memory"), Tr.tr("GPU")]

                delegate: StyledText {
                    required property string modelData

                    Layout.preferredWidth: root.colNum
                    text: modelData
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    horizontalAlignment: Text.AlignRight
                }
            }

            Item {
                Layout.preferredWidth: root.colAction
            }
        }

        // ── 列表 ────────────────────────────────────────────────────────
        StyledClippingRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ListView {
                id: list

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.extraSmall
                anchors.rightMargin: Tokens.padding.extraSmall
                anchors.topMargin: Tokens.padding.extraSmall
                anchors.bottomMargin: Tokens.padding.extraSmall

                // 让「行高」去适配可视高度，而不是反过来。
                // 可视高度一般不是行高的整数倍，两种天真的做法都不行：
                //   1) 直接裁 —— 最后一行被下边缘切一半，文字看着像被裁断；
                //   2) 把余量留成空白 —— 底栏上方出现一条和行等高的空白带，
                //      看着像少了一节。
                // 所以先算出最多能放下几行，再把行高定成「可视高度 ÷ 行数」，
                // 这样行数正好铺满，既没有半行也没有空带。
                // 44 是「两行 body.small + 内边距」的舒适下限；行高会在此基础上
                // 略微放大到正好铺满，所以实际行高通常比 44 略大。
                readonly property real usableHeight: Math.max(0, height)
                readonly property int visibleRows: Math.max(1, Math.floor(usableHeight / 44))
                readonly property real rowHeight: usableHeight > 0 ? usableHeight / visibleRows : 44

                // 用 count 变化驱动重定位，避免每次采样都跳回顶部
                model: root.visibleProcesses
                clip: true
                // 行高已经把可用高度平分掉了，再留 spacing 就会溢出
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds

                // 注意是 StyledScrollBar.vertical（附加属性），
                // 不是 ScrollBar.vertical —— 后者要额外 import QtQuick.Controls。
                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: list
                }

                delegate: StyledRect {
                    id: row

                    required property var modelData

                    width: list.width
                    // 由列表按可用高度算出来的行高（约 44~48），
                    // 保证正好铺满、不留半行也不留空带
                    implicitHeight: list.rowHeight
                    radius: Tokens.rounding.medium
                    color: hover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

                    Behavior on color {
                        CAnim {}
                    }

                    HoverHandler {
                        id: hover
                        cursorShape: Qt.PointingHandCursor
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        // 名称 + 命令行（命令行作为副标题，省一列）
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.name || "?"
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.args || ""
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                                opacity: 0.75
                                visible: text.length > 0
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: root.colPid
                            text: String(row.modelData.pid)
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.preferredWidth: root.colUser
                            text: row.modelData.user || ""
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.preferredWidth: root.colNum
                            text: Number(row.modelData.cpu).toFixed(1) + "%"
                            // 高占用染成主色，一眼能看到谁在烧 CPU
                            color: row.modelData.cpu >= 25 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            horizontalAlignment: Text.AlignRight
                        }

                        StyledText {
                            Layout.preferredWidth: root.colNum
                            text: Number(row.modelData.mem).toFixed(1) + "%"
                            color: row.modelData.mem >= 10 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            horizontalAlignment: Text.AlignRight
                        }

                        StyledText {
                            Layout.preferredWidth: root.colNum
                            // 拿不到 GPU 数值时显示占位，不要假装是 0
                            text: row.modelData.gpu === null || row.modelData.gpu === undefined
                                  ? "—"
                                  : Number(row.modelData.gpu).toFixed(1) + "%"
                            color: (row.modelData.gpu ?? 0) >= 25 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            horizontalAlignment: Text.AlignRight
                        }

                        // 终止按钮：左键 TERM / 右键 KILL。
                        // 这里不用 IconButton —— 它内部自己吃鼠标事件，拿不到右键。
                        Item {
                            Layout.preferredWidth: root.colAction
                            Layout.preferredHeight: root.colAction

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: killHover.hovered
                                       ? Qt.alpha(Colours.palette.m3error, 0.22)
                                       : Qt.alpha(Colours.palette.m3onSurface, 0.06)

                                Behavior on color {
                                    CAnim {}
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "close"
                                    color: killHover.hovered ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.builders.small.build()
                                }
                            }

                            HoverHandler {
                                id: killHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => ProcessList.killProcess(
                                    row.modelData.pid,
                                    mouse.button === Qt.RightButton ? "KILL" : "TERM")
                            }
                        }
                    }
                }
            }

            // 空态 / 加载态
            StyledText {
                anchors.centerIn: parent
                visible: root.visibleProcesses.length === 0
                text: ProcessList.loading ? Tr.tr("Loading...")
                                          : (ProcessList.lastError.length > 0 ? ProcessList.lastError
                                                                              : Tr.tr("No processes found"))
                color: Colours.palette.m3outline
                font: Tokens.font.body.medium
            }
        }

        // ── 底栏：计数 + 提示 ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.medium
            Layout.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            StyledText {
                text: Tr.tr("%1 processes").arg(root.visibleProcesses.length)
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: Tr.tr("Left click: TERM · Right click: KILL")
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            StyledText {
                visible: root.paused
                text: Tr.tr("Paused")
                color: Colours.palette.m3error
                font: Tokens.font.body.small
            }
        }
    }
}
