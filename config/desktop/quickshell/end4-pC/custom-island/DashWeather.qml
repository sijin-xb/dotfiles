import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services

// ─────────────────────────────────────────────────────────────────────────
// 仪表盘「天气」页。
//
// 数据来自 end4-pC 的 Weather 单例（import qs.services），
// 字段与 ClockDashboard 的天气页一致（temp / description / city /
// tempFeelsLike / humidity / wind / precip / visib / press / cr / sunrise /
// sunset / uv / lastRefresh）。
//
// 与 ClockDashboard 天气页的差异：那边是「左列文字 + 竖分隔线 + 右列 6 行」
// 的两栏文字表，放进岛屿后左右两侧高度差太大、右下角空一大块。
// 这里改成卡片网格：左侧一张 Hero 卡 + 2×2 小卡，右侧 2×3 指标卡，
// 全部用岛屿统一的 StatCard，和系统页 / Home 页的视觉语言对齐。
//
// 图标走 Material Symbols（Icons.getWeatherIcon 返回的就是 Material 名），
// 所以字体族用 Theme.iconFontFamily 而不是 nerdFontFamily。
// ─────────────────────────────────────────────────────────────────────────

Item {
    id: root

    readonly property var    d:   Weather.data
    readonly property int    gap: 8
    readonly property string heroIcon: Icons.getWeatherIcon(root.d.wCode) ?? "cloud"

    function _uvLabel(v) {
        const n = Number(v) || 0
        if (n <= 2)  return Translation.tr("Low")
        if (n <= 5)  return Translation.tr("Moderate")
        if (n <= 7)  return Translation.tr("High")
        if (n <= 10) return Translation.tr("Very High")
        return Translation.tr("Extreme")
    }

    // 左侧 2×2 小卡的数据
    readonly property var _minis: [
        { icon: "wb_sunny", label: Translation.tr("Sunrise"), value: root.d.sunrise ?? "--" },
        { icon: "dark_mode", label: Translation.tr("Sunset"),  value: root.d.sunset  ?? "--" },
        { icon: "light_mode", label: Translation.tr("UV Index"),
          value: `${root.d.uv ?? 0} · ${root._uvLabel(root.d.uv)}` },
        { icon: "schedule", label: Translation.tr("Updated"),
          // Weather.lastRefresh 的格式是 "HH:MM:SS • DD/MM/YYYY"，
          // 整串在 164px 宽的小卡里放不下会顶出卡片，只取时间部分。
          value: (root.d.lastRefresh ?? "--").split(" • ")[0] }
    ]

    // 右侧 2×3 指标卡的数据
    readonly property var _metrics: [
        { icon: "water_drop", label: Translation.tr("Humidity"),      value: `${root.d.humidity ?? "--"}` },
        { icon: "air",        label: Translation.tr("Wind"),          value: `${root.d.wind ?? "--"}` },
        { icon: "umbrella",   label: Translation.tr("Precipitation"), value: `${root.d.precip ?? "--"}` },
        { icon: "visibility", label: Translation.tr("Visibility"),    value: `${root.d.visib ?? "--"}` },
        { icon: "speed",      label: Translation.tr("Pressure"),      value: `${root.d.press ?? "--"}` },
        { icon: "cloud",      label: Translation.tr("Clouds"),        value: `${root.d.cr ?? "--"}` }
    ]

    Row {
        anchors.fill: parent
        spacing: root.gap

        // ── 左列：Hero + 2×2 小卡 ────────────────────────────────────────
        Column {
            width:  340
            height: parent.height
            spacing: root.gap

            // Hero
            StatCard {
                id: heroCard
                width:   parent.width
                height:  246
                padding: 16

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            Layout.alignment: Qt.AlignTop
                            text:           root.heroIcon
                            font.family:    Theme.iconFontFamily
                            font.pixelSize: 54
                            color:          Theme.active
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: -4

                            Text {
                                Layout.fillWidth: true
                                text:  root.d.temp ?? "--"
                                elide: Text.ElideRight
                                color: Theme.text
                                font.pixelSize: 42
                                font.weight:    Font.Bold
                            }

                            Text {
                                Layout.fillWidth: true
                                text:  root.d.description ?? ""
                                elide: Text.ElideRight
                                color: Theme.subtext
                                font.pixelSize: 12
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        text:  root.d.city ?? ""
                        elide: Text.ElideRight
                        color: Theme.text
                        font.pixelSize: 14
                        font.weight:    Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        text:  Translation.tr("Feels like") + " " + (root.d.tempFeelsLike ?? "--")
                        elide: Text.ElideRight
                        color: Theme.subtext
                        font.pixelSize: 11
                    }

                    // 刷新按钮
                    Rectangle {
                        Layout.topMargin: 12
                        implicitWidth:  96
                        implicitHeight: 30
                        radius: height / 2
                        color: refreshHover.hovered
                               ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.30)
                               : Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.18)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "refresh"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: 14
                                color: Theme.active
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Refresh")
                                font.pixelSize: 11
                                color: Theme.active
                            }
                        }

                        HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Weather.getData()
                        }
                    }
                }
            }

            // 2×2 小卡
            Grid {
                id: miniGrid
                width:  parent.width
                height: parent.height - heroCard.height - root.gap
                columns: 2
                rowSpacing:    root.gap
                columnSpacing: root.gap

                readonly property real cellW: (width  - columnSpacing) / 2
                readonly property real cellH: (height - rowSpacing)    / 2

                Repeater {
                    model: root._minis

                    delegate: StatCard {
                        required property var modelData

                        width:   miniGrid.cellW
                        height:  miniGrid.cellH
                        padding: 10

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text:           modelData.icon
                                font.family:    Theme.iconFontFamily
                                font.pixelSize: 18
                                color:          Theme.active
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text:           modelData.value
                                color:          Theme.text
                                font.pixelSize: 14
                                font.weight:    Font.DemiBold
                                font.family:    Theme.monoFontFamily
                                font.features: { "tnum": 1 }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text:           modelData.label
                                color:          Theme.subtext
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }

        // ── 右列：2×3 指标卡 ─────────────────────────────────────────────
        Grid {
            id: metricGrid
            width:  parent.width - 340 - root.gap
            height: parent.height
            columns: 2
            rowSpacing:    root.gap
            columnSpacing: root.gap

            readonly property real cellW: (width  - columnSpacing) / 2
            readonly property real cellH: (height - rowSpacing * 2) / 3

            Repeater {
                model: root._metrics

                delegate: StatCard {
                    required property var modelData

                    width:   metricGrid.cellW
                    height:  metricGrid.cellH
                    padding: 14

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:           modelData.icon
                            font.family:    Theme.iconFontFamily
                            font.pixelSize: 24
                            color:          Qt.rgba(1, 1, 1, 0.45)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:           modelData.value
                            color:          Theme.active
                            font.pixelSize: 22
                            font.weight:    Font.Bold
                            font.family:    Theme.monoFontFamily
                            font.features: { "tnum": 1 }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:           modelData.label
                            color:          Theme.subtext
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
