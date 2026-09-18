// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/state/Popups.qml
//
// 改动：
//   1. 删除相对 import（原文件 `import "../"`），改为标准 import。
//   2. 根类型 QtObject → Singleton（对齐本目录 Theme.qml / IslandState.qml 的
//      单例写法；qmldir 里也声明为 singleton）。
//   3. 其余逐字保留 —— 它引用的 Theme.animDuration 由同目录 Theme.qml 提供。
//
// 说明：end4-pC 里没有叫 Popups 的单例（它的弹窗开合状态在 GlobalStates），
//       所以这里占用 Popups 这个名字不会与现有代码冲突。仪表盘只会用到
//       closeAll() 和少数几个布尔量，但整个文件照搬，方便以后跟上游对比。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // ── Per-popup open state ───────────────────────────────────────────────────
    property bool audioOpen:         false
    property bool networkOpen:       false
    property bool batteryOpen:       false
    property bool notificationsOpen: false
    property bool archMenuOpen:      false
    property bool dashboardOpen:     false
    property bool wallpaperOpen:     false
    property bool notificationToastOpen:    false
    property bool quickOpen: false
    property bool clipboardOpen:     false

    // ── Dashboard — per-page state ───────────────────────────────────────────
    property int    dashboardPageWidth: 900
    property string dashboardPage:      "home"

    // ── Audio popup — per-page state ─────────────────────────────────────────
    property string audioPage: "output"

    // ── Network popup — per-page content (string key) ─────────────────────────
    property string networkPage: "wifi"

    // ── Per-popup trigger hover state ─────────────────────────────────────────
    property bool archMenuTriggerHovered: false
    property bool audioTriggerHovered:         false
    property bool networkTriggerHovered:       false
    property bool batteryTriggerHovered:       false
    property bool notificationsTriggerHovered: false
    property bool wallpaperTriggerHovered:     false
    property bool quickTriggerHovered: false

    // ── Universal popup behavior settings ─────────────────────────────────────
    property int  slideDuration:  Theme.animDuration
    property int  hoverCloseDelay: Theme.animDuration + 200   // delay after hover leaves before closing

    // ── Confirm dialog ────────────────────────────────────────────────────────
    property bool   confirmOpen:    false
    property string confirmTitle:   ""
    property string confirmMessage: ""
    property string confirmLabel:   "Confirm"
    property string confirmAction:  ""
    property string confirmGfxMode: ""
    property bool   confirmRunning: false

    function showConfirm(title, message, label, action, gfxMode) {
        confirmTitle   = title
        confirmMessage = message
        confirmLabel   = label
        confirmAction  = action
        confirmGfxMode = gfxMode ?? ""
        confirmOpen    = true
    }

    function cancelConfirm() {
        confirmOpen    = false
        confirmAction  = ""
        confirmGfxMode = ""
    }

    // ── Global state ──────────────────────────────────────────────────────────
    readonly property bool anyOpen: audioOpen || networkOpen || batteryOpen
                                    || notificationsOpen || archMenuOpen
                                    || dashboardOpen || wallpaperOpen || quickOpen
                                    || clipboardOpen

    function closeAll() {
        audioOpen         = false
        networkOpen       = false
        batteryOpen       = false
        notificationsOpen = false
        archMenuOpen      = false
        dashboardOpen     = false
        wallpaperOpen     = false
        quickOpen         = false
        clipboardOpen     = false
    }

    // ── 与 IslandState 双向桥接 ───────────────────────────────────────────────
    // CenterContent 里的 TapHandler 直接写 Popups.dashboardOpen（上游就是这写的），
    // 而面板的展开动画由 IslandState.open 驱动。两边必须保持同步，
    // 否则点岛屿没反应、Esc 关闭后 Popups 又还停在 true。
    // 用「值不等才写」的双向同步，避免绑定环。
    Connections {
        target: IslandState
        function onOpenChanged() {
            if (root.dashboardOpen !== IslandState.open)
                root.dashboardOpen = IslandState.open;
        }
        function onPageChanged() {
            if (root.dashboardPage !== IslandState.page)
                root.dashboardPage = IslandState.page;
        }
    }

    onDashboardOpenChanged: {
        if (IslandState.open !== root.dashboardOpen)
            IslandState.open = root.dashboardOpen;
    }

    onDashboardPageChanged: {
        if (IslandState.page !== root.dashboardPage)
            IslandState.page = root.dashboardPage;
    }
}
