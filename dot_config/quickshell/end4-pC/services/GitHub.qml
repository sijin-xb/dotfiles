pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * GitHub 仓库数据源（设置 → GitHub 与 仪表盘 GitHub 页共用）。
 *
 * 用 `gh` CLI 拉仓库列表，而不是直连 api.github.com：
 *   - `gh` 自己管理 token（~/.config/gh/hosts.yml 或系统 keyring），这里不碰任何凭据
 *   - 吃登录后的速率额度（匿名 60/h，登录 5000/h）
 *   - 属于自己或已授权的私有仓库也能列出来
 *
 * ── 登录也走 gh ────────────────────────────────────────────────────────
 * 本服务不实现任何 OAuth / PAT 表单，登录状态**完全以 `gh auth status` 为准**：
 *   - 已登录 → loginName 就是当前活动账号，仓库列表按它拉，不需要用户手输
 *   - 未登录 → 提供 login()（在终端里跑 `gh auth login`）与
 *              loginWithToken()（把 PAT 喂给 `gh auth login --with-token`）
 * 两条路都落到 gh 自己的凭据存储上，本服务只负责读状态、发指令。
 * 这样「登录」只有一份真相来源，也不会把 token 落在 config.json 里。
 */
Singleton {
    id: root

    /** 已经拉取成功的那次用户名（用于「输入改了但还没拉」的提示） */
    property string loadedFor: ""
    property var repos: []
    property bool loading: false
    property string errorText: ""

    // ── gh 安装 / 登录状态 ─────────────────────────────────────────────
    property bool ghInstalled: false
    property bool authChecked: false      // 至少跑过一次检测，避免首帧误显示「未登录」
    property bool loggedIn: false
    property string loginName: ""         // gh 当前活动账号
    property string authError: ""
    property bool authBusy: false         // 登录/登出进行中
    property bool awaitingTerminalLogin: false

    /** 头像：gh 没有直接给，用 github.com/<login>.png 这个稳定入口 */
    readonly property string loginAvatar: root.loginName.length > 0
        ? `https://github.com/${root.loginName}.png?size=160` : ""

    /** 手动覆盖（设置里的「用户名覆盖」）。留空时用 gh 账号。 */
    readonly property string username: (Config.options.github.username ?? "").trim()

    /** 实际用于取数的账号：手动覆盖优先，否则用 gh 当前账号 */
    readonly property string effectiveUser: root.username.length > 0 ? root.username : root.loginName

    /** 是否处于「手动覆盖」状态 */
    readonly property bool usingOverride: root.username.length > 0

    /** 按配置过滤（fork / 归档）并截断到 repoLimit 之后的列表 */
    readonly property var visibleRepos: {
        const limit = Config.options.github.repoLimit ?? 30;
        const list = (root.repos ?? []).filter(r => {
            if (!Config.options.github.includeForks && r.fork)
                return false;
            if (!Config.options.github.includeArchived && r.archived)
                return false;
            return true;
        });
        return list.slice(0, limit);
    }

    /** 输入框里的值是否和「已拉取的用户名」不一致 */
    readonly property bool dirty: root.effectiveUser !== root.loadedFor && root.loadedFor.length > 0

    // ── 私有仓库可见性 ─────────────────────────────────────────────────
    // ⚠ GitHub 的 users/<login>/repos 是**公开端点**：即使请求带了 token，
    //   它也只会返回该用户的公开仓库（实测同一个账号：公开端点 5 个、私有 0 个）。
    //   要拿到私有仓库必须走已认证的 user/repos。
    //   所以「查自己」和「查别人」是两条不同的端点，不能混用。
    /** 展示的账号是否就是 gh 当前登录账号 */
    readonly property bool isSelf: root.loggedIn
        && root.effectiveUser.length > 0
        && root.effectiveUser === root.loginName

    /** 是否走已认证端点（能带出私有仓库） */
    readonly property bool useAuthenticatedEndpoint: root.isSelf
        && (Config.options.github.includePrivate ?? true)

    function setUsername(value) {
        Config.options.github.username = String(value ?? "").trim();
    }

    // ── 登录状态检测 ───────────────────────────────────────────────────
    /** 读 gh 的活动账号。只读操作，可随时调用。 */
    function checkAuth() {
        authStatusProc.running = false;
        authStatusProc.running = true;
    }

    /** 在终端里跑交互式 `gh auth login`（推荐：协议/方式都由用户选） */
    function login() {
        if (!root.ghInstalled) {
            root.authError = Translation.tr("gh is not installed. Install it with: sudo pacman -S github-cli");
            return;
        }
        root.authError = "";
        root.awaitingTerminalLogin = true;
        // 用 bash -lc 让 gh 拿到登录 shell 的 PATH（gh 常在 ~/.local/bin）
        Quickshell.execDetached([
            "kitty", "--title", "gh auth login",
            "bash", "-lc",
            "gh auth login; "
            + "printf '\\n──── gh auth login 已结束 ────\\n'; "
            + "gh auth status; "
            + "printf '\\n按回车关闭此窗口… '; read -r _"
        ]);
        authPollTimer.restart();
    }

    /** 用 PAT 登录（等价于 `gh auth login --with-token`） */
    function loginWithToken(token) {
        const t = String(token ?? "").trim();
        if (t.length === 0)
            return;
        root.authBusy = true;
        root.authError = "";
        // 改 command 前先确保进程不在跑
        tokenProc.running = false;
        tokenProc.command = [
            "gh", "auth", "login",
            "--hostname", "github.com",
            "--git-protocol", "https",
            "--with-token"
        ];
        tokenProc.running = true;
        // stdinEnabled 下 write() 会把内容写进子进程 stdin，末尾必须带换行
        tokenProc.write(t + "\n");
    }

    /** 退出登录。GH_PROMPT_DISABLED 防止它在没有 TTY 时挂住等确认。 */
    function logout() {
        if (root.loginName.length === 0)
            return;
        root.authBusy = true;
        root.authError = "";
        logoutProc.running = false;
        // 用 bash -c + "$1" 传账号，避免把账号拼进命令串（登录名本身虽安全，
        // 但保持「永不拼字符串进 shell」的习惯）。
        // GH_PROMPT_DISABLED=1：没有 TTY 时 gh 会卡在确认提示上，必须关掉。
        logoutProc.command = [
            "bash", "-c",
            'GH_PROMPT_DISABLED=1 exec gh auth logout --hostname github.com --user "$1"',
            "gh", root.loginName
        ];
        logoutProc.running = true;
    }

    function fetch() {
        const user = root.effectiveUser;
        if (user.length === 0) {
            root.repos = [];
            root.errorText = "";
            root.loadedFor = "";
            return;
        }
        root.loading = true;
        root.errorText = "";
        // 端点二选一（原因见 useAuthenticatedEndpoint 的注释）：
        //   自己 → user/repos，带私有仓库
        //   别人 / 未登录 → users/<login>/repos，只有公开仓库
        const endpoint = root.useAuthenticatedEndpoint
            ? "user/repos?per_page=100&sort=updated&visibility=all&affiliation=owner"
            : `users/${user}/repos?per_page=100&sort=updated`;
        // 改 command 前必须先确保进程不在跑
        ghProc.running = false;
        ghProc.command = [
            "gh", "api", endpoint,
            "--jq", "[.[] | {name, full_name, description, html_url, language, stargazers_count, forks_count, updated_at, private, fork, archived, homepage, topics}]"
        ];
        ghProc.running = true;
    }

    function openRepo(url) {
        if (!url || url.length === 0)
            return;
        Quickshell.execDetached(["xdg-open", url]);
    }

    function openProfile() {
        if (root.effectiveUser.length === 0)
            return;
        root.openRepo(`https://github.com/${root.effectiveUser}`);
    }

    /** 相对时间：today / yesterday / N days ago / N months ago / N years ago */
    function relativeDate(iso) {
        if (!iso)
            return "";
        const then = new Date(iso).getTime();
        if (isNaN(then))
            return "";
        const days = Math.floor((Date.now() - then) / 86400000);
        if (days <= 0) return Translation.tr("today");
        if (days === 1) return Translation.tr("yesterday");
        if (days < 30) return `${days} ` + Translation.tr("days ago");
        if (days < 365) return `${Math.floor(days / 30)} ` + Translation.tr("months ago");
        return `${Math.floor(days / 365)} ` + Translation.tr("years ago");
    }

    // ── gh 是否安装 ────────────────────────────────────────────────────
    Process {
        id: versionProc
        command: ["gh", "--version"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.ghInstalled = text.trim().length > 0
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.ghInstalled = false;
            root.checkAuth();
        }
    }

    // ── 读活动账号（--json hosts 比解析人类可读输出稳）──────────────────
    Process {
        id: authStatusProc
        running: false
        // gh 的 jq 表达式里含双引号，用单引号包住整段，避免 QML 字符串转义地狱
        command: [
            "gh", "auth", "status", "--json", "hosts",
            "--jq", '.hosts."github.com"[] | select(.active == true) | .login'
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim().split("\n")[0] ?? "";
                root.loginName = name;
                root.loggedIn = name.length > 0;
                root.authChecked = true;
                if (root.loggedIn) {
                    root.awaitingTerminalLogin = false;
                    authPollTimer.stop();
                    root.authError = "";
                    // 登录完成后自动拉一次列表（用 effectiveUser，尊重手动覆盖）
                    if (root.effectiveUser.length > 0 && root.effectiveUser !== root.loadedFor)
                        root.fetch();
                }
            }
        }
        onExited: (code, status) => {
            root.authChecked = true;
            if (code !== 0) {
                root.loggedIn = false;
                root.loginName = "";
            }
        }
    }

    // 终端登录期间轮询（最多约 5 分钟），检测到登录即停
    Timer {
        id: authPollTimer
        interval: 2000
        repeat: true
        onTriggered: {
            if (authPollCount++ > 150) {
                root.awaitingTerminalLogin = false;
                stop();
                return;
            }
            root.checkAuth();
        }
        property int authPollCount: 0
        onRunningChanged: if (running) authPollCount = 0
    }

    // ── PAT 登录 ───────────────────────────────────────────────────────
    Process {
        id: tokenProc
        running: false
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                const err = text.trim();
                if (err.length > 0)
                    root.authError = err;
            }
        }
        onExited: (code, status) => {
            root.authBusy = false;
            if (code !== 0) {
                if (root.authError.length === 0)
                    root.authError = Translation.tr("gh auth login failed (code %1).").arg(code);
                return;
            }
            root.authError = "";
            root.checkAuth();
        }
    }

    // ── 登出 ───────────────────────────────────────────────────────────
    Process {
        id: logoutProc
        running: false
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                const err = text.trim();
                if (err.length > 0)
                    root.authError = err;
            }
        }
        onExited: (code, status) => {
            root.authBusy = false;
            if (code !== 0 && root.authError.length === 0)
                root.authError = Translation.tr("gh auth logout failed (code %1).").arg(code);
            root.checkAuth();
        }
    }

    Process {
        id: ghProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const out = text.trim();
                if (out.length === 0) {
                    root.repos = [];
                    root.errorText = Translation.tr("No data returned. Is the username correct?");
                    return;
                }
                try {
                    const parsed = JSON.parse(out);
                    root.repos = Array.isArray(parsed) ? parsed : [];
                    root.loadedFor = root.effectiveUser;
                    if (root.repos.length === 0)
                        root.errorText = Translation.tr("This user has no public repositories.");
                } catch (e) {
                    root.repos = [];
                    root.errorText = Translation.tr("Failed to parse GitHub response.");
                    console.log("[GitHub] parse failed:", e);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = text.trim();
                if (err.length > 0 && root.repos.length === 0) {
                    root.loading = false;
                    root.errorText = err;
                }
            }
        }
        onExited: (code, status) => {
            root.loading = false;
            if (code !== 0 && root.errorText.length === 0)
                root.errorText = Translation.tr("gh exited with code %1. Did you run `gh auth login`?").arg(code);
        }
    }

    Component.onCompleted: {
        // 启动即检测登录状态；检测完再按 effectiveUser 决定是否取数
    }
}
