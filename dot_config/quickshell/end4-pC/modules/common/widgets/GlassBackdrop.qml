import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Wayland._Screencopy
import qs.modules.common

/**
 * 限定在自身范围内的真实背景模糊 —— **不依赖合成器的全局模糊**。
 *
 * 和 `layerrule = blur` 的区别：那个是让 Hyprland 替我们模糊整个图层，
 * 这里是自己把「面板背后那块屏幕」抓下来、自己糊、自己裁，
 * 所以模糊严格只发生在面板覆盖的区域，屏幕其余部分完全不受影响。
 *
 * 四个步骤：
 *   1. `ScreencopyView` 抓当前输出的完整画面（wlr-screencopy 协议）
 *   2. 把抓到的整屏纹理按**屏幕坐标**摆好（x/y 取负的本组件屏幕位置）
 *   3. `MultiEffect` 对这块纹理做高斯模糊
 *   4. 父级（玻璃面板）的 `clip` + 圆角把它裁成面板形状
 *
 * 关键约束：**抓帧时自己必须还没画出来**，否则会抓到面板自己造成自反馈。
 * 所以调用方要把面板的 `opacity` 挂在 `ready` 上，见 ClockDashboard 的用法。
 */
Item {
    id: root

    /** 要抓的输出，传 PanelWindow 的 screen */
    property var screen
    /** 模糊半径（MultiEffect.blur） */
    property real blurRadius: 56
    /** 模糊半径上限，同时决定 MultiEffect 的 blurMax（越大越糊也越贵） */
    property real blurMax: 96
    /** 是否持续抓帧。静态壁纸保持 false 最省；视频壁纸要 true（代价明显更高） */
    property bool live: false
    /** 整体强度 0~1；0 等于不画，退化成纯玻璃底色 */
    property real intensity: 1.0
    /** 抓取光标 */
    property bool paintCursor: false
    /**
     * 色彩校正：高斯模糊会把互补色混成灰泥，视觉上就是「背景发脏」。
     * 轻微提饱和 + 抬一点亮度 + 加一点对比，是磨砂玻璃抵消发灰的标准做法
     * （苹果的材质也是往这个方向偏）。都是相对量：0 = 不变。
     */
    property real saturation: 0.18
    property real brightness: 0.04
    property real contrast: 0.06

    /** 纹理是否已经到位（抓帧是异步的，首帧到达前 hasContent 为 false） */
    readonly property bool ready: capture.hasContent
    /** 是否应该显示模糊层 */
    readonly property bool active: root.intensity > 0 && root.ready

    clip: true
    visible: root.intensity > 0

    /**
     * 重新抓一帧。live=false 时用；live=true 由 ScreencopyView 自己持续更新。
     * 面板尺寸/位置变了、或者背后的内容变了（切页、切工作区）都可以调一次。
     */
    function refresh() {
        if (root.live)
            return;
        if (typeof capture.captureFrame === "function")
            capture.captureFrame();
    }

    // 本组件在屏幕上的左上角坐标。PanelWindow 铺满整屏时，
    // 窗口坐标 == 该输出的屏幕坐标，所以取负的自身位置即可对齐纹理。
    readonly property real screenOffsetX: -root.mapToItem(null, 0, 0).x
    readonly property real screenOffsetY: -root.mapToItem(null, 0, 0).y

    ScreencopyView {
        id: capture
        x: root.screenOffsetX
        y: root.screenOffsetY
        width: root.screen?.width ?? 0
        height: root.screen?.height ?? 0
        captureSource: root.screen
        live: root.live
        paintCursor: root.paintCursor
        // 纹理只作为 MultiEffect 的 source，自己不直接画
        visible: false
    }

    MultiEffect {
        x: root.screenOffsetX
        y: root.screenOffsetY
        width: root.screen?.width ?? 0
        height: root.screen?.height ?? 0
        source: capture
        visible: root.active
        blurEnabled: true
        blur: Math.min(root.blurRadius, root.blurMax)
        blurMax: root.blurMax
        // 抵消模糊带来的灰泥感，见 saturation / brightness / contrast 的注释
        saturation: root.saturation
        brightness: root.brightness
        contrast: root.contrast
        // 让模糊层自身也带一点透明度，玻璃底色才有地方透出来
        opacity: 0.95 * root.intensity
    }

    // 抓帧到位之前先垫一层中性底，避免闪出一帧未模糊的原图
    Rectangle {
        anchors.fill: parent
        visible: !root.ready
        color: Appearance.colors.colLayer1Base
        opacity: 0.7
    }
}
