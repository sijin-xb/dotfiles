import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.cheatsheet
import qs.modules.ii.dock
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
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    // 快捷键管理器：常驻挂载（面板本身按需创建），否则 IPC target 会随面板一起消失
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { component: Background {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Lock {} }
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

    // 岛屿 + 仪表盘：常驻挂载，收起时只有一颗胶囊占位
    PanelLoader { component: IslandHost {} }
    // 按键显示浮层：只在开启时创建，关掉就不占一个常驻的 layer surface
    PanelLoader { extraCondition: Config.options.keycapDisplay.enable; component: KeycapOverlay {} }
}
