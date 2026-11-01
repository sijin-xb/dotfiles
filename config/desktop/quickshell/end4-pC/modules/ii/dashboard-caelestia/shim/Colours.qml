pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

/**
 * 上游 Caelestia 锁屏的配色入口。
 *
 * 上游用的是 `Caelestia.Config` 里的 `Colours`；本仓库整套配色由 matugen 生成、
 * 落在 `Appearance.m3colors`。这里做一层同名映射，于是上游文件里的
 * `Colours.palette.m3primary` 这类写法一个字都不用改，就能跟随壁纸取色。
 *
 * `tPalette` 是终端调色板（上游拿它做锁屏的次级容器底色），
 * 本仓库没有对应物，用 M3 的 surface container 系列顶上。
 * `layer` 是上游的层叠底色数组，映射到 M3 的 surface container 阶梯。
 */
Singleton {
    id: root

    readonly property bool light: !Appearance.m3colors.darkmode

    readonly property QtObject palette: QtObject {
        property color m3background: Appearance.m3colors.m3background
        property color m3onBackground: Appearance.m3colors.m3onBackground
        property color m3surface: Appearance.m3colors.m3surface
        property color m3surfaceDim: Appearance.m3colors.m3surfaceDim
        property color m3surfaceBright: Appearance.m3colors.m3surfaceBright
        property color m3surfaceContainerLowest: Appearance.m3colors.m3surfaceContainerLowest
        property color m3surfaceContainerLow: Appearance.m3colors.m3surfaceContainerLow
        property color m3surfaceContainer: Appearance.m3colors.m3surfaceContainer
        property color m3surfaceContainerHigh: Appearance.m3colors.m3surfaceContainerHigh
        property color m3surfaceContainerHighest: Appearance.m3colors.m3surfaceContainerHighest
        property color m3onSurface: Appearance.m3colors.m3onSurface
        property color m3surfaceVariant: Appearance.m3colors.m3surfaceVariant
        property color m3onSurfaceVariant: Appearance.m3colors.m3onSurfaceVariant
        property color m3inverseSurface: Appearance.m3colors.m3inverseSurface
        property color m3inverseOnSurface: Appearance.m3colors.m3inverseOnSurface
        property color m3outline: Appearance.m3colors.m3outline
        property color m3outlineVariant: Appearance.m3colors.m3outlineVariant
        property color m3shadow: Appearance.m3colors.m3shadow
        property color m3scrim: Appearance.m3colors.m3scrim
        property color m3surfaceTint: Appearance.m3colors.m3surfaceTint
        property color m3primary: Appearance.m3colors.m3primary
        property color m3onPrimary: Appearance.m3colors.m3onPrimary
        property color m3primaryContainer: Appearance.m3colors.m3primaryContainer
        property color m3onPrimaryContainer: Appearance.m3colors.m3onPrimaryContainer
        property color m3inversePrimary: Appearance.m3colors.m3inversePrimary
        property color m3secondary: Appearance.m3colors.m3secondary
        property color m3onSecondary: Appearance.m3colors.m3onSecondary
        property color m3secondaryContainer: Appearance.m3colors.m3secondaryContainer
        property color m3onSecondaryContainer: Appearance.m3colors.m3onSecondaryContainer
        property color m3tertiary: Appearance.m3colors.m3tertiary
        property color m3onTertiary: Appearance.m3colors.m3onTertiary
        property color m3tertiaryContainer: Appearance.m3colors.m3tertiaryContainer
        property color m3onTertiaryContainer: Appearance.m3colors.m3onTertiaryContainer
        property color m3error: Appearance.m3colors.m3error
        property color m3onError: Appearance.m3colors.m3onError
        property color m3errorContainer: Appearance.m3colors.m3errorContainer
        property color m3onErrorContainer: Appearance.m3colors.m3onErrorContainer
    }

    // 上游拿 tPalette 做「比 surface 稍深一档」的容器底色
    readonly property QtObject tPalette: QtObject {
        property color m3surfaceContainer: Appearance.m3colors.m3surfaceContainerLow
        property color m3surfaceContainerHigh: Appearance.m3colors.m3surfaceContainer
        property color m3surfaceContainerHighest: Appearance.m3colors.m3surfaceContainerHigh
    }

    // 上游的层叠底色不是数组，而是两个函数：
    //   layer(c, layer)  按层级把颜色调暗/加透明度（layer=0 用 base，其余按 layers 递进）
    //   on(c)            取「落在该颜色之上的内容色」
    // 上游 12 处调用的是函数形式，写成数组会报 “Property 'layer' is not a function”。
    // 这里映射到本仓库的透明度体系：开着透明度时逐层加一点，关着就原样返回。
    readonly property QtObject transparency: QtObject {
        readonly property bool enabled: Config.options.appearance.transparency.enable
        readonly property real base: Config.options.appearance.transparency.backgroundTransparency
        readonly property real layers: Config.options.appearance.transparency.contentTransparency
    }

    function layer(c, layerIndex) {
        if (!root.transparency.enabled)
            return c;
        const depth = (layerIndex === undefined || layerIndex === null) ? 1 : layerIndex;
        if (depth === 0)
            return Qt.alpha(c, root.transparency.base);
        // 逐层往 surface 方向混一点，层级越深越不透明
        const mixAmount = Math.min(0.9, root.transparency.layers + depth * 0.08);
        return ColorUtils.mix(c, Appearance.m3colors.m3surface, mixAmount);
    }

    function on(c) {
        // 上游用它取「叠在该色之上的前景色」，本仓库没有对应概念，原样返回
        return c;
    }
}
