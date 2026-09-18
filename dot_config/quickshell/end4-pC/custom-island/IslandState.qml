pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

/**
 * 岛屿 + 仪表盘的共享状态单例。
 *
 * 设计对齐 Brain_Shell 的 Popups 单例（src/state/Popups.qml）：
 * 用一个布尔量 dashboardOpen 控制「岛屿 → 仪表盘」的展开/收起，
 * 岛屿胶囊与面板都订阅它，从而保证两边动画同步。
 *
 * 与 Brain_Shell 的差异：那边把「页面宽度」也放在同一个单例里
 * （Popups.dashboardPageWidth），用来让 Bar 中间那段 notch 跟着一起变宽。
 * 这里沿用同一思路，pageWidths 决定展开后岛屿的宽度。
 */
Singleton {
    id: root

    // ── 开合状态 ────────────────────────────────────────────────────────
    // 点击岛屿胶囊时切换；Esc / 点面板外也会置 false
    property bool open: false

    // ── 当前页 ──────────────────────────────────────────────────────────
    property string page: "home"

    // ── 尺寸 ────────────────────────────────────────────────────────────
    // 逐字对齐 Brain_Shell 的 Dashboard.qml，那边是：
    //   sizer.width  = Popups.dashboardPageWidth + 2 * Theme.notchRadius  = 900 + 30
    //   sizer.height = Theme.dashboardHeight                              = 520
    //   content 内缩  = 左右 fw+8、上 fh+8、下 8                        （fw=fh=15）
    //   → 内容区 884 x 489，扣掉 40px 页签后页面区 884 x 449
    // 面板高度就保持 520：System 页的 Disks 列表超出时 DiskPanel 自带滚动条，
    // 不需要为了塞下多几行挂载点把面板撑高。
    readonly property int panelWidth: Theme.dashboardWidth + Theme.notchRadius * 2   // 930
    // ⚠ 与上游的差异：Brain_Shell 的 dashboardHeight 是 520，那边 Home 页
    // 没有歌词窗。岛屿的 PlayerCard 多了「可拖拽进度条 + 5 行歌词」（约 278px），
    // 520 下 PlayerCard 只剩 213px 放不下，所以在**上游令牌之上**加 70。
    // Theme.qml 里的 dashboardHeight 保持 520 不动，令牌层仍然和上游一致。
    readonly property int panelHeight: Theme.dashboardHeight + 70                    // 590
    readonly property int panelInset: Theme.notchRadius + 8                           // 23
    readonly property int panelBottomInset: 8
    // 展开后的圆角：Brain_Shell 用 Theme.cornerRadius(17)，不是 end4-pC 的 large(23)
    readonly property int panelRadius: Theme.cornerRadius

    // ── 收起态几何 ──────────────────────────────────────────────────────
    // 收起态不是"一颗悬浮胶囊"，而是 Bar 中间那段 notch 本身。要和左右邻居
    // 平齐，就得用邻居的真实几何，两层边距都要算上：
    //   1. Bar 窗口在 cornerStyle 3 下距屏幕边 5px（Bar.qml 的 margins.top/bottom）
    //   2. BarGroup 的背景又在内容区上下各留 4px（BarGroup.qml 的 topMargin/bottomMargin）
    //   → 一颗 Bar 胶囊的可见范围是 5+4 .. 5+40-4，即高 32px
    // 屏幕实测佐证：邻居胶囊落在 y=9..41，Bar 自己的大容器落在 y=6..43。
    readonly property int barEdgeMargin: Config.options.bar.cornerStyle === 3 ? 5 : 0
    readonly property int groupInset: 4
    readonly property int capsuleHeight: Appearance.sizes.baseBarHeight - root.groupInset * 2   // 32
    readonly property int capsuleOffset: root.barEdgeMargin + root.groupInset                   // 9

    // 收起态宽度：对齐 Brain_Shell 中间 notch 的最小宽度
    readonly property int capsuleWidth: Theme.cNotchMinWidth    // 300

    // ── 动画 ────────────────────────────────────────────────────────────
    // 时长取自主题（Appearance.animation.elementResize.duration = 300），
    // 曲线沿用 Brain_Shell 的 InOutCubic，展开/收起对称
    readonly property int animDuration: Appearance.animation.elementResize.duration
    // 内容淡入比尺寸动画快一半，淡出更快（对齐 Brain_Shell Dashboard.qml 的 0.5 / 0.15 系数）
    readonly property int fadeInDuration: Math.round(root.animDuration * 0.5)
    readonly property int fadeOutDuration: Math.round(root.animDuration * 0.15)

    // ── 操作 ────────────────────────────────────────────────────────────
    function toggle() {
        root.open = !root.open
    }

    function close() {
        root.open = false
    }

    // 关闭后把页面复位，下次打开总是回到首页
    onOpenChanged: {
        if (!root.open)
            root.page = "home"
    }
}
