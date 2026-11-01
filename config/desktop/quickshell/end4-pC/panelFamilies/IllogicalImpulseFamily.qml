import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.cheatsheet
import qs.modules.ii.dock
import qs.modules.ii.equalizer
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.settings
import qs.modules.ii.regionSelector
import qs.modules.ii.screenCorners
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebarRight
import qs.modules.ii.overlay
import qs.modules.ii.verticalBar
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.desktopMenu
import qs.modules.ii.dropover
import qs.modules.ii.frame
import qs.modules.ii.keycapDisplay
// 岛屿 + 仪表盘（Brain_Shell 风格，见 custom-island/）
import "../custom-island"

Scope {
    // Caelestia QML 插件（Caelestia.Config）可用性探针 —— 只有「锁屏」与
    // 「灵动岛」两个面板硬依赖它，见 CaelestiaPluginProbe.qml 的说明。
    CaelestiaPluginProbe { id: caelestiaPlugin }

    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    // 快捷键管理器：常驻挂载（面板本身按需创建），否则 IPC target 会随面板一起消失
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { component: Background {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    // ⚠ 必须用 source:（运行时按 URL 创建）而不是 component: Lock {}。
    //   Lock 内部 → CaelestiaLockSurface → `import Caelestia.Config`，
    //   内联 component 会在**本文件编译期**解析 Lock 的类型，插件缺失时
    //   整份 IllogicalImpulseFamily 直接 unavailable，连锁把 shell.qml 拖垮。
    //   改成运行时创建后，插件缺失只损失锁屏，其余面板照常。
    PanelLoader {
        extraCondition: caelestiaPlugin.available
        source: "../modules/ii/lock/Lock.qml"
    }
    // 上游 10-02 新增的均衡器弹窗（模块已随树同步）。注意它不依赖 caelestia
    // 插件，用上游同款内联 component —— 类型在编译期可解析，无 Lock 那个坑。
    PanelLoader { component: EqualizerPopup {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: Settings {} }
    PanelLoader { component: DesktopMenu {} }
    PanelLoader { component: DropShelfPanel {} }
    PanelLoader { component: NiriBackdrop {} }
    PanelLoader { component: ScreenFrame {} }
    // 居中时钟的仪表盘：常驻挂载，避免栏隐藏时连同 IPC 一起被销毁
    // 已被 custom-island 的 IslandHost 取代（见下），如需回退取消注释即可
    // PanelLoader { component: ClockDashboard {} }

    // 岛屿 + 仪表盘：常驻挂载，收起时只有一颗胶囊占位。
    // 同 Lock：必须走 source: 运行时创建（IslandHost → FileDialog →
    // Sidebar → `import Caelestia.Config`）。
    PanelLoader {
        extraCondition: caelestiaPlugin.available
        source: "../custom-island/IslandHost.qml"
    }
    // 按键显示浮层：只在开启时创建，关掉就不占一个常驻的 layer surface
    PanelLoader { extraCondition: Config.options.keycapDisplay.enable; component: KeycapOverlay {} }
}
