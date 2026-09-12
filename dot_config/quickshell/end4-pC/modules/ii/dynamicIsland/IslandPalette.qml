pragma Singleton
import QtQuick
import Quickshell

// 取色中枢：媒体封面主色原本只在 MusicActivity 内部使用，
// 这里提升为全局共享状态，任何活动都能据此着色（频谱 / 进度条 / 副岛）。
Singleton {
    id: root

    // 媒体封面量化出的原始主色。无封面时为透明。
    property color mediaAccent: "transparent"

    readonly property bool hasAccent: mediaAccent.a > 0.01

    // 封面主色常偏暗（深色封面量化后尤其明显），直接用会导致高亮读不出来。
    // 给一个亮度下限并轻微提饱和，保留色相的同时保证任何封面都有足够对比度。
    readonly property real accentMinLightness: 0.62
    readonly property color effectiveAccent: {
        if (!hasAccent)
            return "#FFFFFF"
        const c = Qt.color(mediaAccent)
        if (c.hslLightness >= accentMinLightness)
            return c
        return Qt.hsla(c.hslHue,
                       Math.min(1.0, c.hslSaturation * 1.15),
                       accentMinLightness,
                       1.0)
    }

    // 活动配色入口：有主色用主色，否则回退到调用方给的主题色。
    function accentOr(fallback) {
        return hasAccent ? effectiveAccent : fallback
    }
}
