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

    // 手动覆盖用的输入框本地状态：停顿一下再提交，避免每敲一个字母发一次请求
    property string usernameInput: Config.options.github.username
    // PAT 登录输入框（只在「改用访问令牌」折叠区里）
    property string tokenInput: ""
    property bool tokenPanelOpen: false

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

        // ── 账号（登录走 gh，不再让用户手输账号当登录）──────────────────
        ContentSection {
            icon: "person"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("GitHub account")

            GroupedList {
                // ── 1. gh 未安装 ────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: GitHub.authChecked && !GitHub.ghInstalled

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "error"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colError
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("GitHub CLI (gh) is not installed.")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: "sudo pacman -S github-cli"
                            color: Appearance.colors.colOnSurfaceVariant
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignVCenter
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy")
                        onClicked: Quickshell.clipboardText = "sudo pacman -S github-cli"
                    }
                }

                // ── 2. 已登录 ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: GitHub.loggedIn

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        clip: true

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: GitHub.loginAvatar
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !avatarImage.visible
                            text: "account_circle"
                            iconSize: 28
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: 6
                            StyledText {
                                text: `@${GitHub.loginName}`
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: badgeRow.implicitWidth + 12
                                implicitHeight: 18
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimaryContainer
                                RowLayout {
                                    id: badgeRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "verified"
                                        iconSize: 12
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                    StyledText {
                                        text: Translation.tr("Signed in via GitHub CLI")
                                        color: Appearance.colors.colOnPrimaryContainer
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: GitHub.authError.length > 0
                                ? GitHub.authError
                                : Translation.tr("Token is managed by gh and stored in its own credential store.")
                            color: GitHub.authError.length > 0
                                ? Appearance.colors.colError
                                : Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: GitHub.loggedIn

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "swap_horiz"
                        mainText: Translation.tr("Switch account in terminal")
                        onClicked: GitHub.login()
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "logout"
                        mainText: Translation.tr("Sign out")
                        enabled: !GitHub.authBusy
                        onClicked: GitHub.logout()
                    }
                }

                // ── 3. 未登录 ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: GitHub.ghInstalled && GitHub.authChecked && !GitHub.loggedIn

                    MaterialLoadingIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        visible: GitHub.awaitingTerminalLogin
                        loading: GitHub.awaitingTerminalLogin
                        implicitSize: 18
                        colBg: Appearance.colors.colPrimaryContainer
                        colShape: Appearance.colors.colOnPrimaryContainer
                    }
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: !GitHub.awaitingTerminalLogin
                        text: "login"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: GitHub.awaitingTerminalLogin
                                ? Translation.tr("Waiting for the terminal to finish `gh auth login`…")
                                : Translation.tr("Not signed in. Sign in with GitHub CLI to list your repositories.")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.WordWrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: GitHub.authError.length > 0
                            text: GitHub.authError
                            color: Appearance.colors.colError
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    visible: GitHub.ghInstalled && GitHub.authChecked && !GitHub.loggedIn
                    materialIcon: "login"
                    mainText: Translation.tr("Sign in with GitHub CLI")
                    enabled: !GitHub.awaitingTerminalLogin
                    onClicked: GitHub.login()
                }

                // ── 4. PAT 兜底（同样落到 gh 的凭据存储）────────────────
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    visible: GitHub.ghInstalled && GitHub.authChecked && !GitHub.loggedIn
                    materialIcon: page.tokenPanelOpen ? "expand_less" : "expand_more"
                    mainText: Translation.tr("Use an access token instead")
                    onClicked: page.tokenPanelOpen = !page.tokenPanelOpen
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: GitHub.ghInstalled && GitHub.authChecked
                        && !GitHub.loggedIn && page.tokenPanelOpen

                    ConfigTextArea {
                        Layout.fillWidth: true
                        buttonIcon: "key"
                        text: Translation.tr("Personal access token")
                        placeholderText: "ghp_… / github_pat_…"
                        value: page.tokenInput
                        onValueChanged: page.tokenInput = value
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Needs `repo` scope. Stored by gh, never written to the shell config.")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        wrapMode: Text.WordWrap
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "login"
                        mainText: Translation.tr("Sign in with token")
                        enabled: page.tokenInput.trim().length > 0 && !GitHub.authBusy
                        onClicked: GitHub.loginWithToken(page.tokenInput)
                    }
                }

                // ── 5. 手动覆盖（可选，留空则用 gh 当前账号）────────────
                ConfigTextArea {
                    Layout.fillWidth: true
                    buttonIcon: "alternate_email"
                    text: Translation.tr("Override username (optional)")
                    description: GitHub.loggedIn
                        ? Translation.tr("Leave empty to use the gh account: %1").arg(GitHub.loginName)
                        : Translation.tr("Leave empty to use the signed-in gh account.")
                    placeholderText: Translation.tr("e.g. torvalds")
                    value: page.usernameInput
                    onValueChanged: {
                        page.usernameInput = value;
                        usernameDebounce.restart();
                    }
                }

                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Include private repositories")
                    checked: Config.options.github.includePrivate
                    onCheckedChanged: {
                        Config.options.github.includePrivate = checked;
                        GitHub.fetch();
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    text: GitHub.isSelf
                        ? Translation.tr("Fetching through the authenticated endpoint, so your private repositories show up.")
                        : Translation.tr("Private repositories only appear while showing the signed-in gh account (%1).").arg(
                            GitHub.loggedIn ? GitHub.loginName : Translation.tr("none"))
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    wrapMode: Text.WordWrap
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
                        enabled: GitHub.effectiveUser.length > 0 && !GitHub.loading
                        onClicked: GitHub.fetch()
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "open_in_new"
                        mainText: Translation.tr("Open profile")
                        enabled: GitHub.effectiveUser.length > 0
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
                            if (GitHub.effectiveUser.length === 0)
                                return Translation.tr("Sign in with GitHub CLI above to list your repositories.");
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
                            text: GitHub.effectiveUser.length === 0
                                ? Translation.tr("Not signed in")
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
