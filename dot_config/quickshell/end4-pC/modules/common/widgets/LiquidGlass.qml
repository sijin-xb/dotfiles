import qs.modules.common
import QtQuick

/**
 * 液态玻璃表面（Liquid Glass）。
 *
 * 用来替换「纯透明」和「单调半透明」的底板。分层：
 *   1. 基底   —— 半透明但**绝不透明**的着色层（不会看到生硬的穿透感）
 *   2. 透光   —— 顶部柔和的高光渐变，模拟光从上方穿过玻璃
 *   3. 折射   —— 斜向的高光带 + 底部的回光，模拟厚度带来的偏折
 *   4. 高光边 —— 内外两层描边（上亮下暗），勾出玻璃的「厚度」
 *
 * 真正把背景糊掉的是合成器：Hyprland 的 `layerrule = blur, <namespace>`
 * 负责模糊这个 surface 后面的内容，这里只负责玻璃本身的质感。
 *
 * 用法：
 *   LiquidGlass {
 *       anchors.fill: parent
 *       radius: Appearance.rounding.large
 *       level: 1
 *   }
 */
Rectangle {
    id: root

    /** 表面层级，和 Appearance.colors.colLayer0/1/2 对应 */
    property int level: 1
    /** 玻璃底色；不设就按 level 取。传进来的透明色会被抬到 minAlpha 以上 */
    property color tint: root.level === 0
        ? Appearance.colors.colLayer0
        : root.level === 2
            ? Appearance.colors.colLayer2
            : Appearance.colors.colLayer1
    /** 整体强度，0 就退化成普通实心色块 */
    property real intensity: 1.0
    /** 斜向折射高光 */
    property bool specular: true
    /** 内外双层描边 */
    property bool edgeHighlight: true
    /** 底色最低不透明度：保证「不使用纯透明背景」 */
    readonly property real minAlpha: 0.55

    readonly property color sheenColor: "#ffffff"
    readonly property real alpha: Math.min(1, Math.max(root.minAlpha, root.tint.a))

    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.alpha)
    border.width: 0

    // 2. 顶部柔和透光
    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: parent.height * 0.6
        radius: parent.radius
        opacity: 0.55 * root.intensity
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.13)
            }
            GradientStop {
                position: 0.45
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.04)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.0)
            }
        }
    }

    // 3a. 底部回光（折射出来的那一点点亮）
    Rectangle {
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        height: parent.height * 0.35
        radius: parent.radius
        opacity: 0.4 * root.intensity
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.0)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.05)
            }
        }
    }

    // 3b. 斜向折射高光带：内缩，避免旋转后越界
    Rectangle {
        visible: root.specular && root.width > 120 && root.height > 24
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        anchors.leftMargin: parent.width * 0.06
        anchors.rightMargin: parent.width * 0.30
        anchors.topMargin: Math.max(1, parent.height * 0.10)
        height: Math.max(3, parent.height * 0.16)
        radius: height / 2
        rotation: -8
        transformOrigin: Item.Center
        opacity: 0.5 * root.intensity
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.0)
            }
            GradientStop {
                position: 0.5
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.09)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.0)
            }
        }
    }

    // 4. 多层高光边：外圈偏亮（受光），内圈偏暗（厚度）
    Rectangle {
        visible: root.edgeHighlight
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.sheenColor.r, root.sheenColor.g, root.sheenColor.b, 0.16 * root.intensity)
    }

    Rectangle {
        visible: root.edgeHighlight
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, parent.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, Appearance.m3colors.darkmode ? 0.22 * root.intensity : 0.08 * root.intensity)
    }
}
