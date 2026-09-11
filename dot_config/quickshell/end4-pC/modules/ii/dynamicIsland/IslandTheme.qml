pragma Singleton
import QtQuick
import Quickshell

// 主题常量：数值提取自 Bolt 版设计参数。
QtObject {
    id: theme

    // 图标字体：复用 end4-pC 自带资源，避免重复分发大字体文件
    readonly property FontLoader iconFontLoader: FontLoader {
        source: Qt.resolvedUrl(`${Quickshell.shellPath("assets/fonts")}/MaterialSymbolsRounded.ttf`)
    }
    readonly property string iconFontFamily: iconFontLoader.name.length > 0
        ? iconFontLoader.name : "Material Symbols Rounded"

    // ===== 颜色 =====
    readonly property color surface: "#000000"
    readonly property color text: "#FFFFFF"
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.60)
    readonly property color textTertiary: Qt.rgba(1, 1, 1, 0.50)
    readonly property color textDisabled: Qt.rgba(1, 1, 1, 0.40)
    readonly property color track: Qt.rgba(1, 1, 1, 0.15)
    readonly property color trackStrong: Qt.rgba(1, 1, 1, 0.25)
    readonly property color danger: "#F87171"
    readonly property color success: "#4ADE80"
    readonly property color warning: "#FACC15"

    // ===== 字体 =====
    readonly property string fontFamily: "SF Pro Text"
    readonly property int fontTiny: 10
    readonly property int fontSmall: 12
    readonly property int fontBody: 13
    readonly property int fontTitle: 15

    // ===== 动画 =====
    // 300ms + OutQuint：干脆利落，没有拖沓的尾巴
    readonly property int durationExpand: 300
    readonly property int durationContentFade: 140
    readonly property int durationQuick: 220

    // ===== 尺寸映射（Compact）=====
    readonly property var compactSizes: ({
        idle:         { w: 126, h: 37, r: 19 },
        music:        { w: 200, h: 37, r: 19, maxW: 340 },
        volume:       { w: 180, h: 37, r: 19 },
        notification: { w: 220, h: 37, r: 19 }
    })

    // ===== 尺寸映射（Expanded）=====
    readonly property var expandedSizes: ({
        idle:         { w: 126, h: 37,  r: 19 },
        music:        { w: 320, h: 168, r: 28 },
        volume:       { w: 300, h: 140, r: 28 },
        notification: { w: 320, h: 120, r: 28 }
    })

    function sizeFor(type, expanded) {
        const map = expanded ? expandedSizes : compactSizes
        const s = map[type]
        return s !== undefined ? s : map.idle
    }
}
