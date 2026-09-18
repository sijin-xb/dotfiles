pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

/**
 * Brain_Shell 主题 API 的兼容层。
 *
 * 为什么要这一层：Brain_Shell 的组件（Speedometer / StatCard / ClockCard /
 * QuickSettings / DashStats / CenterContent …）通篇引用 `Theme.xxx`，共 40 余个
 * 属性、上千处。与其把每个文件里的 `Theme.active` 逐个改成
 * `Appearance.colors.colPrimary`（改动面大、容易改错、以后没法跟上游 diff），
 * 不如**保留 Theme 这个名字**，在这里把它映射到 end4-pC 的 Appearance 上。
 *
 * 效果：移植过来的组件**一行都不用改**，只要保证它们 import 到本目录即可。
 *
 * 命名安全性：end4-pC 没有叫 Theme 的单例（它叫 Appearance），
 * 所以这里占用 Theme 这个名字不会和现有代码冲突。
 *
 * 令牌来源：
 *   - 颜色类  → 映射到 end4-pC 的 Appearance（这是**有意**的替换，
 *               这样岛屿会跟随用户当前的主题配色，而不是写死 Brain_Shell 的）
 *   - 尺寸类  → 逐字照搬 Brain_Shell 的 src/theme/Metrics.qml
 *   - 工作区色 → 逐字照搬 Brain_Shell 的 src/theme/Colors.qml（那边本来就是硬编码）
 */
Singleton {
    id: root

    // ── 颜色（映射到 end4-pC 主题）────────────────────────────────────────
    property color background: Appearance.colors.colLayer1Base
    property color active:     Appearance.colors.colPrimary
    property color text:       Appearance.colors.colOnLayer1
    property color subtext:    Appearance.colors.colSubtext
    property color icon:       Appearance.colors.colOnLayer1
    property color border:     Appearance.colors.colLayer0Border
    property color iconFont:   Appearance.colors.colOnLayer1

    // ── 工作区配色（逐字照搬 Brain_Shell 的 Colors.qml）───────────────────
    property color wsBackground: "#20000000"
    property color wsActive:     "#FFFFFF"
    property color wsOccupied:   "#80FFFFFF"
    property color wsEmpty:      "#30FFFFFF"
    property color wsOverlay:    "#CC1e1e2e"
    property color wsUrgent:     "#fa6b94"

    // ── 图标字体 ────────────────────────────────────────────────────────
    // Brain_Shell 靠应用级默认字体把 "home" 这种名字渲染成 Material 图标；
    // end4-pC 没有这个全局约定，所以移植过来的组件必须显式指定字体族，
    // 否则图标名会被当普通文字画出来（"home Home"）。
    property string iconFontFamily: Appearance.font.family.iconMaterial

    // Brain_Shell 的 CenterContent 里混用了 Nerd Font 字形（"󰔟" "󰩺" 等）
    // 和 emoji。这些字形只有 Nerd Font 才有，而 end4-pC 的主字体（用户配的是
    // Google Sans Flex）不含它们，不指定就会渲染成豆腐块。
    property string nerdFontFamily: Appearance.font.family.iconNerd

    // Brain_Shell 的组件里还有一批 font.family: "JetBrains Mono" 的等宽数字
    // （计时器、秒表、日历日期）。end4-pC 里等宽字体由用户配置决定，
    // 所以映射过去，而不是写死上游那个字体名。
    property string monoFontFamily: Appearance.font.family.monospace

    // 专门给"大字号数字"用的字体（主题里的 appearance.fonts.numbers）。
    // 收起态时钟用它：monospace 是给计时器/表格那种需要严格对齐的场景准备的，
    // 单独一颗时钟用等宽字体会显得又瘦又硬。numbers 跟界面主字体是一套，
    // 观感统一，配合 font.features 的 tnum 同样不会在秒数跳动时抖宽度。
    property string numbersFontFamily: Appearance.font.family.numbers

    // ── 尺寸（逐字照搬 Metrics.qml）──────────────────────────────────────
    property bool barEnabled: false

    // -- Bar Sizes --
    property int borderWidth:   6
    property int cornerRadius:  17
    property int notchRadius:   15
    property int notchHeight:   40
    property int exclusionGap:  34
    property int spacing:       10

    // -- Notch Content Padding --
    property int notchPadding:           16
    property int notchHorizontalPadding: 20
    property int notchVerticalPadding:   10
    property int notchSideMargin:        10

    // -- Notch Width Constraints --
    property int lNotchMinWidth: 180
    property int lNotchMaxWidth: 360
    property int cNotchMinWidth: 300
    property int cNotchMaxWidth: 360
    property int rNotchMinWidth: 180
    property int rNotchMaxWidth: 360

    // -- Dashboard Dimensions --
    property int dashboardWidth:  900
    property int dashboardHeight: 520

    // -- Notifications Popup Width --
    property int notificationsWidth:     400
    property int notificationToastWidth: Math.round(root.notificationsWidth / 1.2)
    property int networkPopupWidth:      480

    // -- Popup Size Constraints --
    property int popupMinWidth:  160
    property int popupMaxWidth:  420
    property int popupMinHeight:  80
    property int popupMaxHeight: 520
    property int popupPadding:    16

    // -- Workspace Dot Sizes --
    property int wsDotSize:     10
    property int wsActiveWidth: 24
    property int wsSpacing:     6
    property int wsPadding:     8
    property int wsRadius:      16

    // -- Animations --
    // Brain_Shell 固定 320ms；这里也照搬，保证动画手感和上游一致
    property int animDuration: 320
}
