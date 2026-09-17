import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * GitHub 项目页（设置 → GitHub）。
 *
 * 数据与「仪表盘的 GitHub 页」共用 services/GitHub.qml —— 两处只有布局不同，
 * 取数、过滤、状态文案、相对时间都在服务里。
 *
 * 为什么用 `gh` 而不是直接打 api.github.com：见 services/GitHub.qml 的注释。
 */
ContentPage {
    id: page
    forceWidth: true

    // 输入框本地状态：停顿一下再提交，避免每敲一个字母发一次请求
    property string usernameInput: Config.options.github.username

    Timer {
        id: usernameDebounce
        interval: 700
        repeat: false
        onTriggered: {
            if (page.usernameInput.trim() === GitHub.username)
                return;
            GitHub.setUsername(page.usernameInput);
            GitHub.fetch();
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        // ── 账号 ────────────────────────────────────────────────────────
        ContentSection {
            icon: "person"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("GitHub account")

            GroupedList {
                ConfigTextArea {
                    Layout.fillWidth: true
                    buttonIcon: "alternate_email"
                    text: Translation.tr("GitHub username")
                    placeholderText: Translation.tr("e.g. torvalds")
                    value: page.usernameInput
                    onValueChanged: {
                        page.usernameInput = value;
                        usernameDebounce.restart();
                    }
                }

                ConfigSwitch {
                    buttonIcon: "call_split"; text: Translation.tr("Include forks")
                    checked: Config.options.github.includeForks
                    onCheckedChanged: { Config.options.github.includeForks = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "archive"; text: Translation.tr("Include archived")
                    checked: Config.options.github.includeArchived
                    onCheckedChanged: { Config.options.github.includeArchived = checked; }
                }
                ConfigSpinBox {
                    icon: "format_list_numbered"
                    text: Translation.tr("Max repositories")
                    value: Config.options.github.repoLimit
                    from: 5
                    to: 100
                    stepSize: 5
                    onValueChanged: { Config.options.github.repoLimit = value; }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "refresh"
                        mainText: Translation.tr("Reload")
                        enabled: GitHub.username.length > 0 && !GitHub.loading
                        onClicked: GitHub.fetch()
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "open_in_new"
                        mainText: Translation.tr("Open profile")
                        enabled: GitHub.username.length > 0
                        onClicked: GitHub.openProfile()
                    }
                }
            }
        }

        // ── 仓库列表 ────────────────────────────────────────────────────
        ContentSection {
            icon: "folder_code"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Repositories")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialLoadingIndicator {
                        visible: GitHub.loading
                        loading: GitHub.loading
                        implicitSize: 18
                        colBg: Appearance.colors.colPrimaryContainer
                        colShape: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (GitHub.loading)
                                return Translation.tr("Loading…");
                            if (GitHub.errorText.length > 0)
                                return GitHub.errorText;
                            if (GitHub.username.length === 0)
                                return Translation.tr("Enter a username above to list repositories.");
                            return `${GitHub.visibleRepos.length} / ${GitHub.repos.length} ` + Translation.tr("repositories");
                        }
                        color: GitHub.errorText.length > 0
                            ? Appearance.colors.colError
                            : Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        visible: GitHub.dirty
                        text: Translation.tr("(input changed, reloading…)")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    visible: !GitHub.loading && GitHub.visibleRepos.length === 0
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "code"
                            iconSize: 28
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: GitHub.username.length === 0
                                ? Translation.tr("No username set")
                                : Translation.tr("Nothing to show")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                // 两列卡片：外层按 ceil(n/2) 生成行，delegate 必须显式给 implicitHeight
                Repeater {
                    model: Math.ceil(GitHub.visibleRepos.length / 2)

                    delegate: RowLayout {
                        required property int index
                        Layout.fillWidth: true
                        spacing: 10

                        Repeater {
                            model: {
                                const base = index * 2;
                                const list = GitHub.visibleRepos;
                                return [list[base] ?? null, list[base + 1] ?? null];
                            }

                            delegate: Item {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                implicitHeight: modelData ? 118 : 0
                                visible: modelData !== null

                                GitHubRepoCard {
                                    anchors.fill: parent
                                    repo: parent.modelData ?? ({})
                                    onActivated: url => GitHub.openRepo(url)
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
