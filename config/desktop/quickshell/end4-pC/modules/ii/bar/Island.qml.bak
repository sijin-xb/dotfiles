import QtQuick
import qs.modules.common
import "../../../custom-island"

/**
 * 岛屿在 Bar 组件列表里的占位件。
 *
 * ── 为什么是「占位」而不是真的把胶囊画在这里 ──────────────────────────────
 * Bar 里的组件都只能活在 Bar 这条 layer surface 内（高 40px）。而岛屿展开后
 * 要长到 930×590，并且必须盖在 Bar 之上 —— 这在 Bar 窗口里画不出来。
 * 所以真正的胶囊和面板由 custom-island/IslandHost.qml 那个独立 PanelWindow
 * 负责（layer Overlay），这里只负责两件事：
 *   1. 让 Bar 的中间区留出和胶囊一样宽的槽位，岛屿胶囊正好落在这个槽位上，
 *      和左右邻居的间距看起来是 Bar 自己排出来的；
 *   2. 让「岛屿」出现在 设置 → Bar → 组件列表 里，可以自由增删。
 *
 * ── 视觉上会不会叠两层 ────────────────────────────────────────────────────
 * 不会。BarContent.shouldPaintMaterialPill() 的黑名单里加了 "island"，
 * 所以 BarGroup 不会给它画材质胶囊底（padding 也随之变成 0），这里就是纯透明。
 * 屏幕上看到的胶囊始终是 IslandHost 画的那一颗。
 *
 * ── 移除后会发生什么 ──────────────────────────────────────────────────────
 * IslandHost.visible 绑定了 middleLayout 是否包含 "island"，
 * 所以从列表里删掉这一项，整座岛屿（胶囊 + 面板）一起消失。
 */
Item {
    id: root

    // 与 IslandHost 收起态胶囊同宽，保证槽位和胶囊严丝合缝
    implicitWidth:  IslandState.capsuleWidth
    implicitHeight: Appearance.sizes.baseBarHeight
}
