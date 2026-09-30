import QtQuick
import qs.modules.common
import "../../../custom-island"

/**
 * 岛屿在 Bar 组件列表里的占位件。
 *
 * ── 为什么是「占位」而不是真的把面板画在这里 ──────────────────────────────
 * Bar 里的组件都只能活在 Bar 这条 layer surface 内（高 40px）。而岛屿展开后
 * 要长到 930×590，并且必须盖在 Bar 之上 —— 这在 Bar 窗口里画不出来。
 * 所以展开后的面板由 custom-island/IslandHost.qml 那个独立 PanelWindow
 * 负责（layer Overlay），这里只负责两件事：
 *   1. 让 Bar 的中间区留出和胶囊一样宽的槽位，岛屿胶囊正好落在这个槽位上，
 *      和左右邻居的间距看起来是 Bar 自己排出来的；
 *   2. 让「岛屿」出现在 设置 → Bar → 组件列表 里，可以自由增删。
 *
 * ── 视觉上会不会叠两层 ────────────────────────────────────────────────────
 * 不会。BarContent.shouldPaintMaterialPill() 的黑名单里加了 "island"，
 * 所以 BarGroup 不会给它画材质胶囊底（padding 也随之变成 0），这里就是纯透明。
 * 屏幕上看到的胶囊始终是这里画的这一颗。
 *
 * ── 移除后会发生什么 ──────────────────────────────────────────────────────
 * IslandHost.visible 绑定了 middleLayout 是否包含 "island"，
 * 所以从列表里删掉这一项，整座岛屿（胶囊 + 面板）一起消失。
 */
Item {
    id: root

    // ── 槽位宽度 ────────────────────────────────────────────────────────
    // 收起态：跟随内容自然宽度（由 CenterContent 上报），而不是写死 300。
    //   屏幕实测旧实现：胶囊 300px、时钟文字约 135px → 左右各空 82px；
    //   而同一条栏上的邻居是内容自适应的（media 101 / sysTray 93 / resources 80）。
    //   两者并排就是「岛屿又胖又空」—— 这是「度量不统一」的根因。
    // 展开态：保持基准宽（面板是独立窗口，宽度由面板内容决定，这里只要一个
    //   稳定的槽位宽，避免开合时 Bar 中间那段来回跳）。
    implicitWidth: IslandState.islandState === "dashboard"
        ? IslandState.capsuleWidth
        : centerContent.requiredWidth
    implicitHeight: Appearance.sizes.baseBarHeight

    // ── 收起态胶囊 ──────────────────────────────────────────────────────
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

        // hover 反馈 —— 与原先 IslandHost 收起态一致。
        // 注意：这只是「可点击」的视觉暗示，**不再触发展开**（见下面的说明）。
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Appearance.colors.colOnPrimaryContainer
            opacity: capsuleHover.hovered ? 0.12 : 0
            Behavior on opacity {
                animation: Appearance.animation.expressiveFastEffects.numberAnimation.createObject(this)
            }
        }
    }

    // 胶囊内容（时间 / 音乐 / 计时器 / 秒表 / 录屏 轮播）。
    // 它自带 TapHandler 负责开合面板，写的是 Popups.dashboardOpen；
    // Popups.qml 里有与 IslandState.open 的双向桥接，所以能带动 IslandHost。
    CenterContent {
        id: centerContent
        anchors.centerIn: capsule
    }

    HoverHandler {
        id: capsuleHover
        cursorShape: Qt.PointingHandCursor

        // ── 展开触发方式：左键单击 ────────────────────────────────────────
        // 曾经这里挂的是 HoverHandler 的 onHoveredChanged → 鼠标移入即展开。
        // 那个做法有两个问题：
        //   1. 想点胶囊里的按钮（计时器 / 秒表 / 录屏）时，鼠标一进去面板就
        //      弹出来把胶囊盖住了，那些按钮根本点不到；
        //   2. 展开后鼠标必须一直留在面板里，稍一移出就收起 —— 想边看面板
        //      边操作别的地方就做不到。
        // 现在展开/收起统一由 CenterContent 的 TapHandler 处理（左键单击切换），
        // 这里只保留指针形状。
        //
        // ⚠ 不要再把展开逻辑挪回这个 HoverHandler。要改交互请改
        //   CenterContent 的 TapHandler 与 IslandHost 的关闭入口（点面板外 / Esc）。
    }

    // 宽度变化（内容换了 / 跨月导致日期串变长）用令牌动画，与 Bar 其它组件同一套节奏。
    // ⚠ 这里刻意用 standard 曲线（不过冲）而不是 elementResize 的 emphasized：
    //   胶囊左右紧挨着邻居，过冲会让它在动画中途压到邻居身上。
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animationCurves.durationNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }
}
