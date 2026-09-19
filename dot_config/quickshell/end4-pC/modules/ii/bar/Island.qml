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

    // 展开为 dashboard 浮层时维持基准槽位宽度，非展开态跟随目标尺寸动态撑开槽位
    implicitWidth: IslandState.islandState === "dashboard"
        ? IslandState.capsuleWidth
        : IslandState.targetWidth
    implicitHeight: Appearance.sizes.baseBarHeight

    // ── 收起态胶囊：现在真的画在 Bar 里 ────────────────────────────────
    // 以前这里是纯透明占位，真正的胶囊由 IslandHost 那个 Overlay 层窗口绘制
    // —— 后果是「连收起态都是一层独立浮层」，而 Overlay 层不会被全屏窗口压掉，
    // 打游戏时那颗胶囊就一直杵在画面上。
    //
    // 改成由 Bar 自己画之后：胶囊就是 Bar 的一个普通组件，Bar 隐藏（含被全屏
    // 压掉）它跟着消失；点它会弹出 IslandHost 的仪表盘面板 —— 展开态仍然要
    // 独立窗口，因为 Bar 这条 layer surface 只有 40px 高，装不下 930×590。
    Rectangle {
        id: capsule

        anchors.centerIn: parent
        width: root.width
        // 与左右邻居胶囊同高（baseBarHeight - BarGroup 上下各 4px）
        height: IslandState.capsuleHeight
        radius: IslandState.targetRadius
        color: IslandState.targetColor

        // hover 反馈 —— 与原先 IslandHost 收起态一致
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Appearance.colors.colOnPrimaryContainer
            opacity: capsuleHover.hovered ? 0.12 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
    }

    // 胶囊内容（时间 / 音乐 / 计时器 / 秒表 / 录屏 轮播）。
    // 它自带 TapHandler 负责开合面板，写的是 Popups.dashboardOpen；
    // Popups.qml 里有与 IslandState.open 的双向桥接，所以能带动 IslandHost。
    CenterContent {
        anchors.centerIn: capsule
    }

    HoverHandler {
        id: capsuleHover
        enabled: !IslandState.open
        cursorShape: Qt.PointingHandCursor

        // ── 悬停触发展开 ──────────────────────────────────────────────
        // 触发方式由「点击」改为「悬停」：鼠标移入胶囊即展开面板，
        // 移出面板即收起（收起逻辑在 IslandHost 的 panelHover）。
        // 写 Popups.dashboardOpen 而不是 IslandState.open：Popups.qml
        // 里有两者的双向桥接，写哪边都会同步到另一边。
        onHoveredChanged: {
            if (hovered && !IslandState.open)
                Popups.dashboardOpen = true
        }
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: IslandState.animDuration
            easing.type: IslandState.animEasing
        }
    }
}
