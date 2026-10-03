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

    // ── 单一核心状态驱动 ────────────────────────────────────────────────
    // 支持 "compact"（收起态）, "media"（播控态）, "osd"（提示态）, "dashboard"（仪表盘展开态）
    property string islandState: "compact"

    // 兼容现有代码的双向绑定
    property bool open: islandState === "dashboard"
    onOpenChanged: {
        if (open && islandState !== "dashboard") {
            islandState = "dashboard";
        } else if (!open && islandState === "dashboard") {
            islandState = "compact";
        }
    }
    onIslandStateChanged: {
        if (islandState === "dashboard" && !open) {
            open = true;
        } else if (islandState !== "dashboard" && open) {
            open = false;
            root.page = "home";
        }
    }

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
    //
    // 面板宽度不再由这里固定：Caelestia dashboard 每个 tab 的内容宽度不同
    // （Media 1000 / Performance ~950 / Weather ≥840 / Dashboard ~800），
    // 固定值要么裁切要么留空。面板宽度改为跟随当前 tab 内容自适应，
    // 见 IslandHost.qml 的 contentIntrinsicWidth（读 Content.implicitWidth）。
    // ⚠ 与上游的差异：Brain_Shell 的 dashboardHeight 是 520，那边 Home 页
    // 没有歌词窗。岛屿的 PlayerCard 多了「可拖拽进度条 + 5 行歌词」（约 278px），
    // 520 下 PlayerCard 只剩 213px 放不下，所以在**上游令牌之上**加 70。
    // Theme.qml 里的 dashboardHeight 保持 520 不动，令牌层仍然和上游一致。
    readonly property int panelHeight: Theme.dashboardHeight + 70                    // 590
    readonly property int panelInset: Theme.notchRadius + 8                           // 23
    readonly property int panelBottomInset: 8
    // 展开后的圆角：Brain_Shell 用 Theme.cornerRadius(17)，不是 end4-pC 的 large(23)
    readonly property int panelRadius: Theme.cornerRadius

    // ── 状态驱动的目标视觉映射 ──────────────────────────────────────────
    readonly property real targetWidth: {
        switch (root.islandState) {
            case "dashboard": return root.capsuleWidth;
            case "media":     return 380;
            case "osd":       return 280;
            default:          return root.capsuleWidth;
        }
    }

    readonly property real targetHeight: {
        switch (root.islandState) {
            case "dashboard": return root.panelHeight;
            default:          return root.capsuleHeight;
        }
    }

    readonly property real targetRadius: {
        switch (root.islandState) {
            case "dashboard": return root.panelRadius;
            default:          return root.capsuleHeight / 2;
        }
    }

    readonly property color targetColor: {
        switch (root.islandState) {
            case "dashboard": return Appearance.colors.colLayer1Base;
            case "media":     return Appearance.colors.colSecondaryContainer;
            case "osd":       return Appearance.colors.colTertiaryContainer;
            default:          return Appearance.colors.colPrimaryContainer;
        }
    }

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

    // ── 收起态宽度：跟随内容，不再写死 ──────────────────────────────────
    // 旧实现直接取 Brain_Shell 的 notch 最小宽度（300）。屏幕实测：岛屿胶囊
    // 300px，里面的时钟文字只有约 135px —— 左右各空 82px；而同一条栏上的邻居
    // 是**内容自适应**的（media 101 / sysTray 93 / resources 80），内容到边缘
    // 只留 BarGroup.padding = 5px。两者并排看就是「岛屿又胖又空」。
    //
    // 所以收起态宽度改成：内容自然宽度 + 两侧留白，并夹在上下限之间。
    //   下限 → 保证点击区域不至于小到点不中
    //   上限 → 内容异常宽时不至于把 Bar 撑爆、盖住左右两组
    //
    // ⚠ sidePadding 定格在 14：
    //   10 是 300 时代的虚胖；但收到 5/8 用户实测「太窄、无感」—— 这个胶囊的
    //   内容只有一行小字，两侧需要明显的空气感才不显得局促。14 = 内容 107px
    //   时胶囊约 135px，比全部邻居都宽一档，视觉上是「从容」而不是「空旷」。
    readonly property int capsuleSidePadding: 14
    // 下限从 150 收到 100：短日期 + 12 号字后 clock 内容自然宽约 110px，
    // 若下限还是 150，胶囊永远被卡在 150 ——「跟随内容」就名存实亡。
    // 100 仍够点按区域（≈ 3 颗邻居胶囊的宽度），music/record_setup 等
    // 未上报宽度的项走 Theme.cNotchMinWidth(300)，不受这个下限影响。
    readonly property int capsuleMinWidth: 100
    readonly property int capsuleMaxWidth: 360

    /** 由内容自然宽度算出收起态胶囊宽度 */
    function capsuleWidthFor(contentWidth) {
        const inner = (contentWidth > 0) ? contentWidth : root.capsuleMinWidth;
        return Math.max(root.capsuleMinWidth,
            Math.min(root.capsuleMaxWidth, Math.round(inner) + root.capsuleSidePadding * 2));
    }

    // 展开态（dashboard）时 Bar 里那段槽位的基准宽度：保持 Brain_Shell 的 300，
    // 因为面板是独立窗口、宽度由内容决定，这里只需要一个稳定的占位宽。
    readonly property int capsuleWidth: Theme.cNotchMinWidth    // 300

    // ── 动画 ────────────────────────────────────────────────────────────
    // 对齐 Caelestia 规范：400ms OutQuint 缓动
    readonly property int animDuration: 400
    readonly property int animEasing: Easing.OutQuint
    // 内容淡入比尺寸动画快一半，淡出更快（对齐 Brain_Shell Dashboard.qml 的 0.5 / 0.15 系数）
    readonly property int fadeInDuration: Math.round(root.animDuration * 0.5)
    // 原来是 0.15（60ms）—— 面板改为「淡出而非缩回胶囊」后，内容 60ms 就没了、
    // 只剩空壳在淡，观感很突兀。放到 0.5（200ms）与淡入对称，收起才看得清。
    readonly property int fadeOutDuration: Math.round(root.animDuration * 0.5)

    // ── 操作 ────────────────────────────────────────────────────────────
    function toggle() {
        root.islandState = (root.islandState === "dashboard" ? "compact" : "dashboard")
    }

    function close() {
        root.islandState = "compact"
    }
}
