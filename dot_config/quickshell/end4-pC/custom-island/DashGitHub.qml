import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.modules.common
import qs.services

// ─────────────────────────────────────────────────────────────────────────
// 仪表盘「GitHub」页。
//
// 数据来自 end4-pC 的 GitHub 单例（底层走 `gh api`，见 services/GitHub.qml）。
//
// 与 ClockDashboard 的 GitHub 页的差异：
//   1. 那边复用 GitHubRepoCard（end4-pC 自己的仓库卡，视觉是另一套语言），
//      这里按计划用岛屿统一的 StatCard 重做，和天气页 / 系统页对齐；
//   2. 加载指示从 MaterialLoadingIndicator 换成自绘的旋转字形
//      —— 岛屿里没有那套依赖；
//   3. 语言名前面加了一颗 GitHub 官方配色的圆点（纯装饰，颜色表在 _langColor）。
// ─────────────────────────────────────────────────────────────────────────

Item {
    id: root

    readonly property int gap: 8

    // GitHub 官方语言配色（常见语言），未知语言退回灰
    function _langColor(lang) {
        const map = {
            "QML": "#44a51c", "JavaScript": "#f1e05a", "TypeScript": "#3178c6",
            "Python": "#3572A5", "C++": "#f34b7d", "C": "#555555",
            "Rust": "#dea584", "Go": "#00ADD8", "Java": "#b07219",
            "Shell": "#89e051", "HTML": "#e34c26", "CSS": "#563d7c",
            "Vue": "#41b883", "Svelte": "#ff3e00", "Lua": "#000080",
            "Kotlin": "#A97BFF", "Swift": "#F05138", "Ruby": "#701516",
            "PHP": "#4F5D95", "C#": "#178600", "Dart": "#00B4AB",
            "Nix": "#7e7eff", "Zig": "#ec915c", "Haskell": "#5e5086"
        }
        return map[lang] ?? "#8b949e"
    }

    // 仓库按两列铺开，所以行数 = ceil(n/2)
    readonly property int repoRows: Math.ceil(GitHub.visibleRepos.length / 2)

    ColumnLayout {
        anchors.fill: parent
        spacing: root.gap

        // ── 账号条 ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: ghInput.activeFocus
                              ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.6)
                              : Qt.rgba(1, 1, 1, 0.08)
                Behavior on border.color { ColorAnimation { duration: 150 } }

                TextField {
                    id: ghInput
                    anchors {
                        fill:        parent
                        leftMargin:  12
                        rightMargin: 12
                    }
                    background: null
                    text: Config.options.github.username
                    placeholderText: Translation.tr("GitHub username")
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.28)
                    color: Theme.text
                    font.pixelSize: 11
                    selectByMouse: true
                    // 回车或失焦时提交，避免每敲一个字母就发一次请求
                    onEditingFinished: {
                        GitHub.setUsername(ghInput.text)
                        GitHub.fetch()
                    }
                }
            }

            // 重新拉取
            Rectangle {
                implicitWidth:  reloadRow.implicitWidth + 22
                implicitHeight: 34
                radius: height / 2
                opacity: GitHub.username.length > 0 && !GitHub.loading ? 1 : 0.4
                color: reloadHover.hovered
                       ? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.30)
                       : Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.18)
                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    id: reloadRow
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
                        text: Translation.tr("Reload")
                        font.pixelSize: 11
                        color: Theme.active
                    }
                }

                HoverHandler { id: reloadHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    enabled: GitHub.username.length > 0 && !GitHub.loading
                    onClicked: GitHub.fetch()
                }
            }

            // 打开主页
            Rectangle {
                implicitWidth:  profileRow.implicitWidth + 22
                implicitHeight: 34
                radius: height / 2
                opacity: GitHub.username.length > 0 ? 1 : 0.4
                color: profileHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    id: profileRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "open_in_new"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                        color: Theme.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Open profile")
                        font.pixelSize: 11
                        color: Theme.text
                    }
                }

                HoverHandler { id: profileHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    enabled: GitHub.username.length > 0
                    onClicked: GitHub.openProfile()
                }
            }
        }

        // ── 状态行 ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                visible: GitHub.loading
                text: "refresh"
                font.family: Theme.iconFontFamily
                font.pixelSize: 13
                color: Theme.active

                RotationAnimation on rotation {
                    running: GitHub.loading
                    from: 0; to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (GitHub.loading)
                        return Translation.tr("Loading…")
                    if (GitHub.errorText.length > 0)
                        return GitHub.errorText
                    if (GitHub.username.length === 0)
                        return Translation.tr("Type a GitHub username and press Enter.")
                    return `${GitHub.visibleRepos.length} / ${GitHub.repos.length} ` + Translation.tr("repositories")
                }
                color: GitHub.errorText.length > 0 ? "#f38ba8" : Theme.subtext
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Text {
                visible: GitHub.dirty
                text: Translation.tr("(reload to refresh)")
                color: Theme.subtext
                font.pixelSize: 9
            }
        }

        // ── 仓库网格（页内滚动）────────────────────────────────────────────
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: ghGrid.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Grid {
                id: ghGrid
                width: parent.width
                columns: 2
                rowSpacing:    root.gap
                columnSpacing: root.gap
                height: root.repoRows * (cardH + rowSpacing) - (root.repoRows > 0 ? rowSpacing : 0)

                readonly property real cardH: 118
                readonly property real cardW: (width - columnSpacing) / 2

                Repeater {
                    model: GitHub.visibleRepos

                    delegate: StatCard {
                        id: repoCard
                        required property var modelData

                        width:   ghGrid.cardW
                        height:  ghGrid.cardH
                        padding: 12

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.cornerRadius
                            color: repoHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        HoverHandler { id: repoHover; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: GitHub.openRepo(repoCard.modelData.html_url)
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // 仓库名 + 私有标记
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    Layout.fillWidth: true
                                    text:  repoCard.modelData.name ?? ""
                                    elide: Text.ElideRight
                                    color: Theme.active
                                    font.pixelSize: 13
                                    font.weight:    Font.DemiBold
                                }

                                Text {
                                    visible: repoCard.modelData.private ?? false
                                    text: "lock"
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 11
                                    color: Theme.subtext
                                }
                            }

                            // 描述
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                text: repoCard.modelData.description ?? "—"
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                color: Theme.subtext
                                font.pixelSize: 10
                                lineHeight: 1.15
                            }

                            Item { Layout.fillHeight: true }

                            // 语言 · 星标 · fork
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Row {
                                    spacing: 4
                                    visible: (repoCard.modelData.language ?? "") !== ""

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8; height: 8; radius: 4
                                        color: root._langColor(repoCard.modelData.language)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: repoCard.modelData.language ?? ""
                                        color: Theme.subtext
                                        font.pixelSize: 10
                                    }
                                }

                                Row {
                                    spacing: 3

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "star"
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 11
                                        color: Theme.subtext
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: `${repoCard.modelData.stargazers_count ?? 0}`
                                        color: Theme.subtext
                                        font.pixelSize: 10
                                        font.family: Theme.monoFontFamily
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                Row {
                                    spacing: 3

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "fork_right"
                                        font.family: Theme.iconFontFamily
                                        font.pixelSize: 11
                                        color: Theme.subtext
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: `${repoCard.modelData.forks_count ?? 0}`
                                        color: Theme.subtext
                                        font.pixelSize: 10
                                        font.family: Theme.monoFontFamily
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: GitHub.relativeDate(repoCard.modelData.updated_at)
                                    color: Theme.subtext
                                    font.pixelSize: 9
                                    opacity: 0.75
                                }
                            }
                        }
                    }
                }
            }

            // 空状态
            Rectangle {
                anchors.fill: parent
                visible: !GitHub.loading && GitHub.visibleRepos.length === 0
                radius: Theme.cornerRadius
                color: Qt.rgba(1, 1, 1, 0.04)

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "code"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 28
                        color: Qt.rgba(1, 1, 1, 0.25)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: GitHub.username.length === 0
                              ? Translation.tr("No username set")
                              : Translation.tr("Nothing to show")
                        color: Theme.subtext
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
