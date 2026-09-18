// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/services/WallpaperService.qml（shim，包一层转接）
//
// 为什么要 shim：Brain_Shell 的 WallpaperService 自己拥有"列目录 + awww 应用 +
// 写 wallpaper.json + matugen 生成配色 + 改 Hyprland 边框色"整条流水线。
// end4-pC 已经有等价的 Wallpapers 服务（services/Wallpapers.qml），
// 它调用 scripts 里的 switchwall.sh 完成同样的工作，配置写在
// Config.options.background.wallpaperPath。所以这里只做转接，不重复实现。
//
// 字段来源：
//   wallpapers   转接 Wallpapers.wallpapers
//   currentWall  转接 Config.options.background.wallpaperPath
//   wallpaperDir 转接 Directories.pictures + "/Wallpapers"
//   previewWall  转接 Wallpapers.startPreview / stopPreview（写回时同步）
//   apply(path)  转接 Wallpapers.apply(path)
//   refresh()    转接 Wallpapers.load()
//   wallpaperApplied(path)  信号：由 Wallpapers.changed() 触发（见下）
//
// 诚实的降级 / 与上游的差异：
//   · applying：end4-pC 的 Wallpapers 不暴露"应用进行中"状态。这里在 apply()
//     时置 true，在 Wallpapers.changed() 时置 false；而 changed() 是在
//     execDetached 之后立刻发出的（不是脚本跑完），所以 applying 会很快回落，
//     它只表示"已派发"，不代表"已完成"。
//   · wallpaperApplied(path)：同理，是"已派发"而非"应用成功"（上游是等
//     applyProc 退出且 exitCode===0 才发）。
//   · scheme / schemes：end4-pC 的等价物是 Config.options.appearance.palette.type
//     （取值形如 "scheme-content"），语义和可写性都不完全一致，这里不做强行
//     映射，保留上游属性供上层 UI 使用，值为自持的 "content"。
//   · tempWalls：end4-pC 的列表来自 FolderListModel，没有"临时缓冲数组"这一步，
//     这里保留空数组仅为兼容上游引用。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common
import qs.services

Singleton {
    id: root

    // ── State ─────────────────────────────────────────────────────────────────
    property var    wallpapers:   Wallpapers.wallpapers
    property var    tempWalls:    []
    property string currentWall:  Config.options.background.wallpaperPath
    property string previewWall:  ""
    property string scheme:       "content"
    property bool   applying:     false
    property string wallpaperDir: Directories.pictures + "/Wallpapers"

    readonly property var schemes: [
        "content", "tonal-spot", "fidelity", "fruit-salad", "neutral", "monochrome"
    ]

    // Emitted when the apply pipeline has been dispatched (see header note).
    signal wallpaperApplied(string path)

    // ── 转接：预览 ────────────────────────────────────────────────────────────
    onPreviewWallChanged: {
        if (root.previewWall === "")
            Wallpapers.stopPreview()
        else
            Wallpapers.startPreview(root.previewWall)
    }

    // ── 转接：刷新列表 ────────────────────────────────────────────────────────
    function refresh() {
        Wallpapers.load()
    }

    // ── 转接：应用壁纸 ────────────────────────────────────────────────────────
    // 不在这里写 currentWall —— 让它继续绑定 Config，由 switchwall.sh 回写后自动更新。
    function apply(path) {
        if (path === "") return
        root.applying = true
        Wallpapers.apply(path)
    }

    // ── 转接：Wallpapers.changed() → applying 复位 + 转发信号 ─────────────────
    property var _wallpapersConn: Connections {
        target: Wallpapers
        function onChanged() {
            root.applying = false
            root.wallpaperApplied(root.currentWall)
        }
    }
}
