pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * 上游 `utils/SysInfo` 里 dashboard 用到的四个成员。
 *
 * 上游版本还带完整 OS logo 探测 / kernel / hostname / DMI 等，
 * end4-pC 已有的 `qs.services.SystemInfo` 覆盖了另一批场景，
 * 两边合起来功能重叠但语义不同，所以这里只为 dashboard 做最小代理：
 *   - isDefaultLogo   固定 true → 走 dashboard 内置的 Caelestia Logo 组件
 *   - osLogo          对应 osLogo 分支，走默认 logo 时不用
 *   - uptimeShort     从 /proc/uptime 算「Xd Yh」，15 秒刷新
 *   - wm              直接取 XDG_CURRENT_DESKTOP
 */
Singleton {
    id: root

    readonly property bool isDefaultLogo: true
    readonly property string osLogo: ""

    // 用户头像路径：优先用户配的，否则退回 ~/.face。
    // 上游 User.qml 直接写 `~/.face`；本仓库其它组件（UserCardWidget /
    // Media / 锁屏）都走 Config.options.profile 约定，这里对齐。
    // 由于 User.qml 里的 `Config` 会被 Caelestia.Config 抢注，所以把这个
    // 派生逻辑收在 shim 里，User.qml 直接用 SysInfo.avatarPath。
    readonly property string avatarPath: Config.options.profile.avatarPath !== ""
        ? Config.options.profile.avatarPicture
        : `${Quickshell.env("HOME")}/.face`

    readonly property string wm: Quickshell.env("XDG_CURRENT_DESKTOP")
        || Quickshell.env("XDG_SESSION_DESKTOP")
        || "Hyprland"

    property string uptimeShort: ""

    FileView {
        id: uptimeFile

        path: "/proc/uptime"
        onLoaded: {
            const up = parseInt(text().split(" ")[0] ?? 0);
            const days = Math.floor(up / 86400);
            const hours = Math.floor((up % 86400) / 3600);
            const minutes = Math.floor((up % 3600) / 60);

            const parts = [];
            if (days > 0)
                parts.push(days + "d");
            if (hours > 0)
                parts.push(hours + "h");
            if (minutes > 0 || parts.length === 0)
                parts.push(minutes + "m");

            root.uptimeShort = parts.slice(0, 2).join(" ");
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: uptimeFile.reload()
    }
}
