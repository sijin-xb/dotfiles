//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1
import "modules/common"
import "modules/ii/desktopLyrics"
import "modules/ii/dynamicIsland"
import "services"
import "panelFamilies"
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    ReloadPopup {}

    Process {
        id: autostartProc
        command: ["python3", `${Directories.scriptPath}/hyprland/autostart.py`]
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return

            if (WM.compositor === "niri") {
                Config.options.background.lockWall = ""
                Config.options.overview.enable = false
            }

            if (Config.options.hyprland.autostartApps.enable &&
                Config.options.hyprland.autostartApps.apps.length > 0) {
                autostartProc.running = true
            }
        }
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        LyricsService.restartLyrics()
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    DesktopLyrics { id: desktopLyrics }

    // 灵动岛：统一承载音乐 / 音量 / 录屏等活动
    // 歌词页与桌面歌词浮层共用同一份数据源（LyricsService = 通用桌面歌词源）
    //
    // ⚠ 用 LazyLoader 而不是给 DynamicIslandHost 加 visible：它是 Item，
    // 里面真正的 PanelWindow 不受父 Item 的 visible 控制，加 visible 关不掉。
    // 用 LazyLoader 的 active 才能真正创建 / 销毁，开关即时生效。
    LazyLoader {
        active: Config.options.dynamicIsland.enable
        component: DynamicIslandHost {
            lyricsProvider: LyricsService
        }
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        active: Config.ready && Config.options.panelFamily === identifier
    }
}