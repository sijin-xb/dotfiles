import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
// Caelestia dashboard 原版（vendor 于 modules/ii/dashboard-caelestia/）
import "../modules/ii/dashboard-caelestia/dashboard"
import "../modules/ii/dashboard-caelestia/components/filedialog"
import "../modules/ii/dashboard-caelestia/shim"

/**
 * 岛屿 + 仪表盘的宿主窗口。
 *
 * ── 它复刻了 Brain_Shell 的哪套架构 ──────────────────────────────────
 * Brain_Shell 里「点一下从 Bar 中间长出一个面板」是由两个东西合成的：
 *   1. TopBar.qml 里 centerNotch 的宽度从 300 动画到 900（Behavior on cWidth），
 *      同时 SeamlessBarShape 重绘整条 Bar，让中间那段 notch 无缝变宽；
 *   2. Dashboard.qml 是一个独立 PanelWindow，sizer 从 notchHeight/2 长到
 *      dashboardHeight(520)，用 PopupShape 的顶部 flare 和 Bar 融在一起。
 * 两者用同一个 Popups.dashboardOpen 驱动，所以看起来是「一颗胶囊撑开成面板」。
 *
 * end4-pC 的 Bar 是普通 Rectangle（不是 Canvas 无缝形状），没法只重绘中间一段，
 * 所以这里把两件事合并进同一个窗口：岛屿胶囊和面板是同一个 Item，
 * 宽度/高度一起动画 —— 视觉结果一致，而且完全不碰 Bar 的绘制代码。
 *
 * ── 状态机 ──────────────────────────────────────────────────────────
 *   IslandState.open == false → 窗口 mask 只覆盖胶囊，点它开
 *   IslandState.open == true  → 窗口 mask 铺满全屏，点面板外 / Esc 关
 * 这个 mask 切换手法沿用同仓库的 DynamicIslandHost 与 ClockDashboard。
 */
PanelWindow {
    id: root

    readonly property bool open: IslandState.open
    readonly property bool barAtBottom: Config.options.bar.bottom
    readonly property real barHeight: Appearance.sizes.barHeight

    // ── 生长尺寸 ────────────────────────────────────────────────────────
    // 收起 = Bar 中间那段 notch 本身（高度与左右胶囊一致）；
    // 展开 = 同一块表面向下长成面板，总高度就是 Brain_Shell 的 dashboardHeight
    // （那边 sizer 从 notch 顶部开始算 520，内容再内缩，见 IslandState）
    //
    // 宽度不再固定：Caelestia 每个 tab 内容宽不同（Media 1000 / Performance ~950
    // / Weather ≥840 / Dashboard ~800），固定值要么裁切要么空。
    // 跟 Caelestia 原版 Wrapper 一致：面板宽度 = 当前 tab 内容的 implicitWidth。
    // Content.implicitWidth 会随 tab 切换实时变化（见 Content.qml 的 nonAnimWidth）。
    // 800 是兜底最小值：首次加载时 currentItem 还是 null（implicitWidth=0）。
    readonly property real contentIntrinsicWidth: Math.max(caelestiaContent.implicitWidth, 800)

    // ⚠ 这里必须用 (open || closing) 而不是只判 open：
    // 收起态的胶囊已经交给 Bar 绘制（modules/ii/bar/Island.qml），本窗口
    // 一旦在 closing 期间缩回 capsuleWidth×capsuleHeight，就会在 Bar 那颗
    // 胶囊的正上方（同一个 y=capsuleOffset）再画一颗「没有时钟」的同形胶囊
    // —— 因为 header/CenterContent 是 visible:false 的。closing 又让它多留
    // 460ms，于是看起来像「展开/关闭时冒出一颗幻影胶囊，然后飞走」。
    // 所以：可见期间一律保持面板尺寸，由 opacity 淡出，绝不变回胶囊几何。
    readonly property real surfaceWidth: (root.open || root.closing)
        ? root.contentIntrinsicWidth + root.contentMargin * 2
        : IslandState.targetWidth
    readonly property real surfaceHeight: (root.open || root.closing)
        ? IslandState.panelHeight
        : IslandState.targetHeight

    // 收起时距离屏幕边 9px（Bar 的 5px 外边距 + BarGroup 的 4px 内缩），
    // 与左右邻居的胶囊完全对齐；展开时也从这个位置往下长
    readonly property int capsuleOffset: IslandState.capsuleOffset

    // 面板内容四周留白 —— 与 Brain_Shell Dashboard.qml 的
    // topMargin/leftMargin/rightMargin = fh+8 / fw+8 / fw+8 一致
    readonly property int contentMargin: IslandState.panelInset
    readonly property int contentBottomMargin: IslandState.panelBottomInset

    // 是否跟随 Bar 的液态玻璃材质（BarContent 里 isMaterial 的判定条件）
    readonly property bool glassy: Config.options.bar.cornerStyle === 3

    readonly property real surfaceRadius: IslandState.targetRadius
    readonly property color surfaceColor: IslandState.targetColor

    // 是否挂在 Bar 的中间区。
    // 岛屿已经进了 设置 → Bar 的组件列表（见 modules/ii/bar/Island.qml），
    // 从那里删掉 "island" 这一项，整座岛屿（胶囊 + 面板）就一起隐藏。
    readonly property bool inBarLayout:
        (Config.options.bar.layouts.middleLayout ?? []).includes("island")

    // ── 可见性 ────────────────────────────────────────────────────────
    // 收起态的胶囊已经交给 Bar 绘制（见 modules/ii/bar/Island.qml），
    // 这里只负责展开后的面板。
    //
    // ⚠ 但**不能**直接写 visible: open —— 那样一收起窗口就瞬间消失，
    // 收缩动画完全看不到。所以收起后要再留一个动画时长再隐藏。
    property bool closing: false

    // 悬停展开后，是否已经确认「鼠标确实在面板内」。
    // 防止刚展开那一帧 hovered 还没置位，被误判成「移出」而立刻收起。
    property bool panelHoverArmed: false

    // 全屏判定：与 Bar.qml 同一套写法（Top 层会被全屏窗口压掉，但本窗口是
    // Overlay 层，全屏时照样悬在画面上 —— 这正是「打游戏时岛一直杵着」的原因）
    readonly property var thisMonitorData: HyprlandData.monitors.find(m => m.name === root.screen?.name)
    readonly property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false

    onOpenChanged: {
        if (root.open) {
            root.closing = false;
        } else {
            root.closing = true;
            closeGraceTimer.restart();
        }
    }

    // 进入全屏时立刻收掉面板，别等 grace 计时器
    onMonitorHasFullscreenChanged: if (root.monitorHasFullscreen) IslandState.close()

    Timer {
        id: closeGraceTimer
        interval: IslandState.animDuration + 60
        repeat: false
        onTriggered: root.closing = false
    }

    color: "transparent"
    visible: root.inBarLayout && !root.monitorHasFullscreen && (root.open || root.closing)

    // 被移出组件列表时顺手把展开态收掉，
    // 否则下次加回来会直接是一个敞着的面板
    onInBarLayoutChanged: if (!root.inBarLayout) IslandState.close()

    // 不参与 Hyprland 的窗口排布，纯浮层
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:island"
    WlrLayershell.layer: WlrLayer.Overlay
    // 展开时抢键盘焦点，Esc 才收得到；收起时立刻归还
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ── 输入区域 ────────────────────────────────────────────────────────
    // 收起：只让胶囊吃事件，其它位置穿透给 Bar / 桌面
    // 展开：铺满全屏，用来捕获「点面板外关闭」
    mask: Region {
        item: root.open ? outsideArea : surface
    }

    // ── 点面板外关闭 ────────────────────────────────────────────────────
    MouseArea {
        id: outsideArea
        anchors.fill: parent
        enabled: root.open
        onClicked: IslandState.close()
    }

    // ── 岛屿本体（胶囊 ↔ 面板 是同一个 Item）───────────────────────────
    Item {
        id: surface

        anchors.horizontalCenter: parent.horizontalCenter
        // 收起时和左右邻居的胶囊同一条水平线
        y: root.barAtBottom
            ? parent.height - root.capsuleOffset - height
            : root.capsuleOffset

        width: root.surfaceWidth
        height: root.surfaceHeight
        // 展开时把还没长出来的部分裁掉，形成「从 Bar 里推出来」的观感
        clip: true

        // 收起时整块淡出（而不是缩回胶囊 —— 见 surfaceWidth 的注释）。
        // 淡出走完整 animDuration，和上面尺寸动画同时结束。
        opacity: root.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? IslandState.fadeInDuration : IslandState.animDuration
                easing.type: Easing.InOutQuad
            }
        }

        // 补一点「往回缩」的动感：只缩放 3%，且从顶边中点缩，
        // 观感是面板朝 Bar 方向收回去。绝不变回胶囊几何（那是之前幻影的根因）。
        scale: root.open ? 1 : 0.97
        transformOrigin: Item.Top
        Behavior on scale {
            NumberAnimation {
                duration: IslandState.animDuration
                easing.type: IslandState.animEasing
            }
        }

        // 状态驱动生长动画：400ms OutQuint
        Behavior on width {
            NumberAnimation {
                duration: IslandState.animDuration
                easing.type: IslandState.animEasing
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: IslandState.animDuration
                easing.type: IslandState.animEasing
            }
        }

        // ── 背景 ────────────────────────────────────────────────────────
        // 材质选择沿用 ClockDashboard 的结论：面板必须是**不透明实体材质**。
        // 那边把 GlassBackdrop.intensity 设成 0，注释写明「避免终端文字和壁纸
        // 颜色穿透卡片」—— 同一块屏幕上，半透明玻璃会让背后的代码/网页文字
        // 直接透进面板，可读性很差。
        //
        // 展开态：material 模式（cornerStyle 3）用 LiquidGlass 的实体档
        // （specular 关掉，只留高光边），其它模式用同色实底。
        LiquidGlass {
            id: glassBg
            anchors.fill: parent
            visible: root.glassy && root.open
            level: 1
            radius: root.surfaceRadius
            tint: Qt.rgba(root.surfaceColor.r,
                          root.surfaceColor.g,
                          root.surfaceColor.b, 1.0)
            // 大面板上斜向高光带会横跨整个宽度，视觉太抢；只保留边缘高光
            specular: false
            edgeHighlight: true
            Behavior on radius {
                NumberAnimation {
                    duration: IslandState.animDuration
                    easing.type: IslandState.animEasing
                }
            }
        }

        // 收起态（以及非材质模式）：纯色块。
        // 画法刻意跟 Bar 右侧那几颗胶囊保持一致 —— BarGroup 的背景就是一个
        // bgColor 的 Rectangle，无渐变、无描边；LiquidGlass 在收起态会多出
        // 一层顶部渐亮，并排看就露馅了（实测 y=10 是 #5c487c 而邻居是 #513c73）。
        Rectangle {
            id: flatBg
            anchors.fill: parent
            visible: !root.glassy || !root.open
            radius: root.surfaceRadius
            color: root.surfaceColor
            // 展开成面板时才需要一圈边界，把它和背后的窗口分开
            border.width: root.open ? 1 : 0
            border.color: Appearance.colors.colLayer0Border
            Behavior on radius {
                NumberAnimation {
                    duration: IslandState.animDuration
                    easing.type: IslandState.animEasing
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: IslandState.animDuration
                    easing.type: IslandState.animEasing
                }
            }
        }

        // 收起态的悬停暗示：整块底色不能变（要保证不透明），
        // 所以在上面叠一层极淡的前景色。
        // 用 onPrimaryContainer 而不是 colPrimary —— 底色已经是 primaryContainer，
        // 再叠 primary（同一色系、亮度也接近）hover 几乎看不出变化。
        Rectangle {
            anchors.fill: parent
            radius: root.surfaceRadius
            visible: !root.open
            color: Appearance.colors.colOnPrimaryContainer
            opacity: surfaceHover.hovered ? 0.12 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        HoverHandler {
            id: surfaceHover
            enabled: !root.open
            cursorShape: Qt.PointingHandCursor
        }

        // 吸收面板内部的点击，避免穿透到 outsideArea 把面板关掉。
        // 收起时 Bar 那个胶囊（Island.qml）才是交互入口；这里全铺满不会影响它。
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: 0
            onClicked: {}
        }

        // ── 悬停触发：移出面板即收起 ──────────────────────────────────
        // 展开由 Bar 胶囊的 hover 触发（见 modules/ii/bar/Island.qml），
        // 这里只负责「移出即收起」。
        // 面板区域完全覆盖胶囊（胶囊 300 宽居中，面板 ≥846 宽；
        // 纵向 y=9..41 也落在面板 9..599 内），所以移出面板时必然也离开了
        // 胶囊，不会出现「收起→又被胶囊 hover 打开」的抖动。
        HoverHandler {
            id: panelHover
            enabled: root.open
            onHoveredChanged: {
                if (hovered) {
                    root.panelHoverArmed = true
                } else if (root.panelHoverArmed && root.open) {
                    root.panelHoverArmed = false
                    IslandState.close()
                }
            }
        }

        // ── 顶部条带 = Bar 中间那段 notch ────────────────────────────────
// 收起态胶囊已交给 Bar 自己绘制（modules/ii/bar/Island.qml），这里再画一份
// 就会出现「展开后被面板背景盖住、收起时飞出屏幕」的幻影。
// 留一个空 Item 占位以保持 expandedArea 的锚点引用不变（topMargin 已改为
// 0，见 MouseArea），但 visible:false 让 CenterContent 完全不渲染。
        Item {
            id: header
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: IslandState.capsuleHeight
            visible: false

            CenterContent {
                anchors.centerIn: parent
                visible: false
            }
        }

        // ── 展开内容 ────────────────────────────────────────────────────
        // 尺寸固定成目标尺寸，由 surface 的 clip 负责「揭示」，
        // 这样动画过程中内容不会被横向压扁
        Item {
            id: expandedArea

            x: root.contentMargin
            y: root.contentMargin
            width: root.contentIntrinsicWidth
            height: IslandState.panelHeight - root.contentMargin - root.contentBottomMargin

            opacity: root.open ? 1 : 0
            visible: opacity > 0
            // 淡入比尺寸动画快（0.5 系数），淡出更快（0.15 系数）—— 同 Brain_Shell
            Behavior on opacity {
                NumberAnimation {
                    duration: root.open ? IslandState.fadeInDuration : IslandState.fadeOutDuration
                    easing.type: Easing.OutCubic
                }
            }

            focus: root.open
            Keys.onEscapePressed: IslandState.close()

            // ── 展开内容 —— Caelestia dashboard 原版 ────────────────────
            // 页签 / Flickable 滑动 / Loader 懒加载全部由 Content 内部
            // 实现（vendor 于 modules/ii/dashboard-caelestia/dashboard/
            // Content.qml）。这里是集成点，不再自己组装 TabSwitcher +
            // Flickable。
            //
            // FileDialog 是 Content 的 required 依赖（点用户头像时弹出
            // 换头像的文件选择器），必须在这里实例化后传进去。
            FileDialog {
                id: facePicker
            }

            Content {
                id: caelestiaContent
                // 用自身 implicitWidth 而非 anchors.fill：面板宽度要跟着它走，
                // 不能反过来被容器锁定。高度仍跟随容器。
                width: implicitWidth
                height: parent.height
                facePicker: facePicker
                // 面板开合状态透给页签（进程页据此决定是否开启采样）
                panelOpen: root.open
            }

            // 点头像 → shim.Dashboard.closeRequested → 收起面板，然后
            // facePicker 已经在 User.qml 内部被 open()。
            Connections {
                target: Dashboard
                function onCloseRequested() {
                    IslandState.close();
                }
            }
        }
    }

    // ── IPC ─────────────────────────────────────────────────────────────
    // 目标名用 islanddashboard，避免和 DynamicIslandHost 的 "island" 撞名。
    // 调试：qs -c end4-pC ipc call islanddashboard toggle
    IpcHandler {
        target: "islanddashboard"

        function toggle(): void {
            IslandState.toggle();
        }

        // 注意：不要叫 show / hide，会和 qs ipc CLI 的保留字冲突
        function openPanel(): void {
            IslandState.open = true;
        }

        function closePanel(): void {
            IslandState.close();
        }

        function page(key: string): void {
            IslandState.page = key;
        }

        function status(): string {
            return IslandState.open ? "open:" + IslandState.page : "closed";
        }
    }
}
