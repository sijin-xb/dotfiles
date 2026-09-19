pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import "../components"
import "../components/controls"
import "../shim"
import qs.services

/**
 * 岛屿「GitHub」页。
 *
 * 数据全部来自 `GitHub` 单例（services/GitHub.qml，底层走 `gh api`），
 * 与「设置 → GitHub」共用同一个服务 —— 两处只有布局不同。
 *
 * 视觉语言刻意与仪表盘其它页（Weather / Performance / Processes）保持一致：
 *   · 卡片用 StyledRect + Tokens.rounding / Colours.tPalette
 *   · 文字用 StyledText + Tokens.font.*
 *   · 图标用 MaterialIcon
 *   · 间距一律 Tokens.spacing / Tokens.padding
 * （早期版本复用了 custom-island 的 StatCard，那是岛屿另一套画风，已废弃。）
 *
 * 命名叫 GitHubTab 而不是 GitHub：避免与 qs.services 的 `GitHub` 单例
 * 在本文件里撞名（同目录的 WeatherTab.qml 也是同样考虑）。
 */
Item {
    id: root

    // 可用高度由 Content 注入（= 中间 Flickable 的高度）。
    // 页签不要自己写死 implicitHeight，否则底部会被 ClippingRectangle 切掉。
    required property real availableHeight

    implicitWidth: Math.max(layout.implicitWidth, 840)
    implicitHeight: availableHeight

    Component.onCompleted: {
        if (GitHub.username.length > 0 && GitHub.repos.length === 0 && !GitHub.loading)
            GitHub.fetch();
    }

    // GitHub 官方语言配色（常见语言），未知语言退回 onSurfaceVariant
    function langColor(lang) {
        const map = {
            "QML": "#44a51c", "JavaScript": "#f1e05a", "TypeScript": "#3178c6",
            "Python": "#3572A5", "C++": "#f34b7d", "C": "#555555",
            "Rust": "#dea584", "Go": "#00ADD8", "Java": "#b07219",
            "Shell": "#89e051", "HTML": "#e34c26", "CSS": "#563d7c",
            "Vue": "#41b883", "Svelte": "#ff3e00", "Lua": "#000080",
            "Kotlin": "#A97BFF", "Swift": "#F05138", "Ruby": "#701516",
            "PHP": "#4F5D95", "C#": "#178600", "Dart": "#00B4AB",
            "Nix": "#7e7eff", "Zig": "#ec915c", "Haskell": "#5e5086"
        };
        return map[lang] ?? Colours.palette.m3onSurfaceVariant;
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        // ── 标题行 ────────────────────────────────────────────────────
        RowLayout {
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            Column {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Tr.tr("GitHub")
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: GitHub.username.length > 0
                        ? GitHub.username
                        : Tr.tr("Set a username in Settings to get started")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // 打开主页
            StyledRect {
                implicitWidth: openRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 34
                radius: Tokens.rounding.medium
                color: openHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
                visible: GitHub.username.length > 0

                HoverHandler {
                    id: openHover
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: GitHub.openProfile()
                }

                Row {
                    id: openRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        text: "open_in_new"
                        font: Tokens.font.icon.builders.small.build
                        color: Colours.palette.m3onSurface
                    }
                    StyledText {
                        text: Tr.tr("Open profile")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            // 刷新
            StyledRect {
                implicitWidth: reloadRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 34
                radius: Tokens.rounding.medium
                color: reloadHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
                opacity: GitHub.username.length > 0 && !GitHub.loading ? 1 : 0.4
                enabled: GitHub.username.length > 0 && !GitHub.loading

                HoverHandler {
                    id: reloadHover
                    cursorShape: Qt.PointingHandCursor
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: GitHub.fetch()
                }

                Row {
                    id: reloadRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        text: "refresh"
                        font: Tokens.font.icon.builders.small.build
                        color: Colours.palette.m3onSurface
                    }
                    StyledText {
                        text: Tr.tr("Reload")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                    }
                }
            }
        }

        // ── 状态：加载中 / 错误 / 数据过期 ────────────────────────────
        StyledText {
            visible: GitHub.loading
            Layout.leftMargin: Tokens.padding.large
            text: Tr.tr("Loading...")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            visible: !GitHub.loading && GitHub.errorText.length > 0
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.fillWidth: true
            text: GitHub.errorText
            wrapMode: Text.WordWrap
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        StyledText {
            visible: !GitHub.loading && GitHub.dirty
            Layout.leftMargin: Tokens.padding.large
            text: Tr.tr("(reload to refresh)")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        // ── 仓库网格（自带滚动，两列铺开）────────────────────────────
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            contentHeight: grid.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            GridLayout {
                id: grid

                width: parent.width
                columns: 2
                rowSpacing: Tokens.spacing.medium
                columnSpacing: Tokens.spacing.medium

                Repeater {
                    model: GitHub.visibleRepos

                    delegate: StyledRect {
                        id: card

                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: cardCol.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.medium
                        color: cardHover.hovered ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer

                        Behavior on color {
                            CAnim {}
                        }

                        HoverHandler {
                            id: cardHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: GitHub.openRepo(card.modelData.html_url)
                        }

                        ColumnLayout {
                            id: cardCol

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: 4

                            // 仓库名 + 私有标记
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.name ?? ""
                                    elide: Text.ElideRight
                                    font: Tokens.font.body.medium
                                    color: Colours.palette.m3onSurface
                                }

                                MaterialIcon {
                                    visible: card.modelData.private ?? false
                                    text: "lock"
                                    font: Tokens.font.icon.builders.small.build
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            // 描述
                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: card.modelData.description ?? "—"
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                                lineHeight: 1.15
                            }

                            // 语言 / 星标 / fork / 更新时间
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: 10

                                Row {
                                    visible: (card.modelData.language ?? "").length > 0
                                    spacing: 5

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.langColor(card.modelData.language)
                                    }
                                    StyledText {
                                        text: card.modelData.language ?? ""
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                Row {
                                    spacing: 3

                                    MaterialIcon {
                                        text: "star"
                                        font: Tokens.font.icon.builders.small.build
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                    StyledText {
                                        text: card.modelData.stargazers_count ?? 0
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                Row {
                                    spacing: 3

                                    MaterialIcon {
                                        text: "fork_right"
                                        font: Tokens.font.icon.builders.small.build
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                    StyledText {
                                        text: card.modelData.forks_count ?? 0
                                        font: Tokens.font.body.small
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: GitHub.relativeDate(card.modelData.updated_at)
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
