import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * GitHub 项目页（设置 → GitHub）。
 *
 * 填一个 GitHub 用户名 → 用 `gh` CLI 拉该用户的仓库列表 → 点任意仓库在浏览器打开。
 *
 * 为什么用 `gh` 而不是直接打 api.github.com：
 *   - `gh` 已经在本机登录（~/.config/gh/hosts.yml），token 由它管理，页面里不碰凭据；
 *   - 顺带带上 GitHub 的速率限制额度（匿名请求 60/h，登录后 5000/h）；
 *   - 私有仓库也能列出来（属于自己或已授权时）。
 * 因此前提是本机装好并登录了 `gh`（`gh auth login`）。
 */
ContentPage {
    id: page
    forceWidth: true

    property string usernameInput: Config.options.github.username
    property var repos: []
    property bool loading: false
    property string errorText: ""
    // 记住上一次成功拉取的用户名，用于判断「输入改了但还没拉」
    property string loadedFor: ""

    readonly property string effectiveUser: Config.options.github.username.trim()
    readonly property bool dirty: page.usernameInput.trim() !== page.effectiveUser

    // 已拉到的仓库按配置过滤 + 截断
    readonly property var visibleRepos: {
        const limit = Config.options.github.repoLimit;
        const list = (page.repos ?? []).filter(r => {
            if (!Config.options.github.includeForks && r.fork)
                return false;
            if (!Config.options.github.includeArchived && r.archived)
                return false;
            return true;
        });
        return list.slice(0, limit);
    }

    function fetchRepos() {
        const user = Config.options.github.username.trim();
        if (user.length === 0) {
            page.repos = [];
            page.errorText = "";
            page.loadedFor = "";
            return;
        }
        page.loading = true;
        page.errorText = "";
        // 先停再起：Process 改 command 前必须确保不在运行
        ghProc.running = false;
        ghProc.command = [
            "gh", "api",
            `users/${user}/repos?per_page=100&sort=updated`,
            "--jq", "[.[] | {name, description, html_url, language, stargazers_count, forks_count, updated_at, private, fork, archived, homepage, topics}]"
        ];
        ghProc.running = true;
    }

    function openRepo(url) {
        if (!url || url.length === 0)
            return;
        Quickshell.execDetached(["xdg-open", url]);
    }


    Process {
        id: ghProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                page.loading = false;
                const out = text.trim();
                if (out.length === 0) {
                    page.repos = [];
                    page.errorText = Translation.tr("No data returned. Is the username correct?");
                    return;
                }
                try {
                    const parsed = JSON.parse(out);
                    page.repos = Array.isArray(parsed) ? parsed : [];
                    page.loadedFor = Config.options.github.username.trim();
                    if (page.repos.length === 0)
                        page.errorText = Translation.tr("This user has no public repositories.");
                } catch (e) {
                    page.repos = [];
                    page.errorText = Translation.tr("Failed to parse GitHub response.");
                    console.log("[GitHub] parse failed:", e);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = text.trim();
                if (err.length > 0 && page.repos.length === 0) {
                    page.loading = false;
                    page.errorText = err;
                }
            }
        }
        onExited: (code, status) => {
            page.loading = false;
            if (code !== 0 && page.errorText.length === 0)
                page.errorText = Translation.tr("gh exited with code %1. Did you run `gh auth login`?").arg(code);
        }
    }

    Component.onCompleted: {
        if (Config.options.github.username.trim().length > 0)
            page.fetchRepos();
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
                    id: usernameField
                    Layout.fillWidth: true
                    buttonIcon: "alternate_email"
                    text: Translation.tr("GitHub username")
                    placeholderText: Translation.tr("e.g. torvalds")
                    value: page.usernameInput
                    onValueChanged: {
                        page.usernameInput = value;
                        usernameDebounce.restart();
                    }

                    Timer {
                        id: usernameDebounce
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.github.username = page.usernameInput.trim();
                            page.fetchRepos();
                        }
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
                        enabled: page.effectiveUser.length > 0 && !page.loading
                        onClicked: page.fetchRepos()
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "open_in_new"
                        mainText: Translation.tr("Open profile")
                        enabled: page.effectiveUser.length > 0
                        onClicked: page.openRepo(`https://github.com/${page.effectiveUser}`)
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

                // 状态行
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialLoadingIndicator {
                        visible: page.loading
                        loading: page.loading
                        implicitSize: 18
                        colBg: Appearance.colors.colPrimaryContainer
                        colShape: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (page.loading)
                                return Translation.tr("Loading…");
                            if (page.errorText.length > 0)
                                return page.errorText;
                            if (page.effectiveUser.length === 0)
                                return Translation.tr("Enter a username above to list repositories.");
                            return `${page.visibleRepos.length} / ${page.repos.length} ` + Translation.tr("repositories");
                        }
                        color: page.errorText.length > 0
                            ? Appearance.colors.colError
                            : Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        visible: page.loadedFor.length > 0 && page.dirty
                        text: Translation.tr("(input changed, reloading…)")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }

                // 空状态
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    visible: !page.loading && page.visibleRepos.length === 0
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
                            text: page.effectiveUser.length === 0
                                ? Translation.tr("No username set")
                                : Translation.tr("Nothing to show")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }

                // 两列卡片：每行一个 RowLayout，delegate 显式给 implicitHeight
                Repeater {
                    model: Math.ceil(page.visibleRepos.length / 2)

                    delegate: RowLayout {
                        required property int index
                        Layout.fillWidth: true
                        spacing: 10

                        Repeater {
                            model: {
                                const base = index * 2;
                                const list = page.visibleRepos;
                                return [list[base] ?? null, list[base + 1] ?? null];
                            }

                            delegate: Item {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                implicitHeight: modelData ? 118 : 0
                                visible: modelData !== null

                                RepoCard {
                                    anchors.fill: parent
                                    visible: parent.modelData !== null
                                    repo: parent.modelData ?? ({})
                                    onActivated: url => page.openRepo(url)
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
