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
 *   - `gh` 自己管理 token（~/.config/gh/hosts.yml），这里不碰任何凭据
 *   - 吃登录后的速率额度（匿名 60/h，登录 5000/h）
 *   - 属于自己或已授权的私有仓库也能列出来
 * 因此前提是本机装好并登录了 `gh`（`gh auth login`）。
 */
Singleton {
    id: root

    /** 已经拉取成功的那次用户名（用于「输入改了但还没拉」的提示） */
    property string loadedFor: ""
    property var repos: []
    property bool loading: false
    property string errorText: ""

    readonly property string username: (Config.options.github.username ?? "").trim()

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
    readonly property bool dirty: root.username !== root.loadedFor && root.loadedFor.length > 0

    function setUsername(value) {
        Config.options.github.username = String(value ?? "").trim();
    }

    function fetch() {
        const user = root.username;
        if (user.length === 0) {
            root.repos = [];
            root.errorText = "";
            root.loadedFor = "";
            return;
        }
        root.loading = true;
        root.errorText = "";
        // 改 command 前必须先确保进程不在跑
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

    function openProfile() {
        if (root.username.length === 0)
            return;
        root.openRepo(`https://github.com/${root.username}`);
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
                    root.loadedFor = root.username;
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
        if (root.username.length > 0)
            root.fetch();
    }
}
