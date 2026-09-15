pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.images
import qs.modules.ii.background.widgets.resources
import qs.modules.ii.background.widgets.visualizer
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.worldclock
import qs.modules.ii.background.widgets.usercard
import qs.modules.ii.background.widgets.notes
import qs.modules.ii.background.widgets.todo
import qs.modules.ii.background.widgets.timers

Variants {
    id: root
    model: Quickshell.screens

    function getShapeFromName(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie7Sided
        }
    }

    function getColorFromName(name) {
        switch (name) {
            case "primary":            return Appearance.colors.colPrimary
            case "secondary":          return Appearance.colors.colSecondary
            case "tertiary":           return Appearance.colors.colTertiary
            case "primaryContainer":   return Appearance.colors.colPrimaryContainer
            case "secondaryContainer": return Appearance.colors.colSecondaryContainer
            case "tertiaryContainer":  return Appearance.colors.colTertiaryContainer
            case "layer0":             return Appearance.colors.colLayer0
            case "layer1":             return Appearance.colors.colLayer1
            default:                  return Appearance.colors.colPrimaryContainer
        }
    }

    PanelWindow {
        id: bgRoot

        required property var modelData
        property string currentWallpaperSource: Config.options.background.wallpaperPath
        property string previousWallpaperSource: Config.options.background.wallpaperPath
        property bool videoRevealed: false

        readonly property real splitFraction: {
            switch (Config.options.background.splitRatio) {
                case "25": return 0.28
                case "50": return 0.54
                default:   return 1.0
            }
        }
        readonly property bool overviewBlurActive: Config.options.overview.style === "niri" && GlobalStates.overviewOpen && Config.options.overview.enable
        readonly property bool userBlurActive: Config.options.background.showBlur && !bgRoot.wallpaperIsVideo
        readonly property bool blurFullScreen: bgRoot.overviewBlurActive || bgRoot.splitFraction >= 1.0

        //centered Wallpaper
        property bool centeredWallpaperEnabled: Config.options.background.centeredWallpaper && (!Config.options.background.centeredWallpaperOnlyWhenLocked || GlobalStates.screenLocked)
        property int centeredWallpaperShape: getShapeFromName(Config.options.background.centeredWallpaperShape)
        property int centeredWallpaperSize: Config.options.background.centeredWallpaperSize
        property color centeredWallpaperColor: root.getColorFromName(Config.options.background.centeredWallpaperColor)

        property var shaderList: ["circlePit", "circleSelect", "magic", "Doom", "Peel", "transition", "pixelate", "stripes", "crt", "dissolve", "glitch", "ripple", "shatter"]
        property string currentShader: "pixelate"
        property string wallpaperAnimation: Config.options.background.wallpaperAnimation ?? "random"

        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: true

        // ─── 壁纸视差引擎 ────────────────────────────────
        readonly property bool parallaxEnabled: Config.options.background.parallax.enable
        // 壳内壁纸层（静态图 / 视频缩略图）视差：居中壁纸模式下禁用
        readonly property bool wallpaperParallaxEnabled: parallaxEnabled && !bgRoot.centeredWallpaperEnabled

        // 壁纸缩放：既要覆盖「工作区平移」，也要覆盖「侧栏平移」的最大位移，
        // 这样任何分辨率下可移动余量都刚好够用，不会出现位移被 clamp 截断。
        readonly property real parallaxZoom: {
            if (!parallaxEnabled) return 1.0;
            var zoom = Math.max(1.0, Config.options.background.parallax.workspaceZoom);
            var sw = Math.max(1, bgRoot.screen ? bgRoot.screen.width : 0);
            if (Config.options.background.parallax.enableSidebar) {
                // movableX >= sidebarShift
                zoom = Math.max(zoom, 1.0 + Config.options.background.parallax.sidebarShift * 2.0 / sw);
            }
            // 启用视差时至少缩放 2%，确保 movableX > 0
            return Math.max(zoom, 1.02);
        }
        readonly property real movableX: Math.max(0, bgRoot.screen.width * (parallaxZoom - 1) / 2)
        readonly property real movableY: Math.max(0, bgRoot.screen.height * (parallaxZoom - 1) / 2)

        // 工作区位置→偏移
        readonly property int activeWorkspaceId: Hyprland.focusedWorkspace?.id ?? 1
        readonly property bool isVerticalLayout: Config.options.background.parallax.autoVertical
            ? (Config.options.overview.columns <= Config.options.overview.rows)
            : Config.options.background.parallax.vertical
        // 已经出现过的最大工作区号（用于自动探测工作区总数）
        readonly property int observedWorkspaceCount: {
            var maxId = 1;
            var list = Hyprland.workspaces.values;
            for (var i = 0; i < list.length; ++i) {
                var id = list[i] ? list[i].id : 0;
                if (id > maxId && id < 1000) maxId = id;
            }
            return maxId;
        }
        // 参与视差映射的工作区总数：配置值优先，其次自动探测，
        // 且至少覆盖概览网格的一行，保证每个工作区都有独立的视差位置。
        readonly property int workspaceCount: {
            var configured = Config.options.background.parallax.workspaceCount;
            var count = configured > 0 ? configured : Config.options.overview.columns;
            return Math.max(2, count, bgRoot.observedWorkspaceCount);
        }
        readonly property real wsNormIndex: {
            if (bgRoot.workspaceCount <= 1) return 0;
            var idx = Math.min(Math.max(bgRoot.activeWorkspaceId, 1), bgRoot.workspaceCount) - 1;
            return idx / (bgRoot.workspaceCount - 1) * 2 - 1; // -1 .. 1
        }
        readonly property real wsNormX: {
            if (!Config.options.background.parallax.enableWorkspace || !parallaxEnabled) return 0;
            if (bgRoot.isVerticalLayout) return 0;
            return bgRoot.wsNormIndex;
        }
        readonly property real wsNormY: {
            if (!Config.options.background.parallax.enableWorkspace || !parallaxEnabled) return 0;
            if (!bgRoot.isVerticalLayout) return 0;
            return bgRoot.wsNormIndex;
        }

        // 侧栏偏移
        readonly property real sidebarOffsetX: {
            if (!Config.options.background.parallax.enableSidebar || !parallaxEnabled) return 0;
            var shift = Config.options.background.parallax.sidebarShift;
            if (GlobalStates.sidebarLeftOpen) return shift;
            if (GlobalStates.sidebarRightOpen) return -shift;
            return 0;
        }

        // 光标跟随偏移
        property real cursorRawX: 0
        property real cursorRawY: 0
        readonly property real cursorNormX: {
            if (!Config.options.background.parallax.enableCursor || !parallaxEnabled) return 0;
            var sw = bgRoot.screen.width;
            return sw > 0 ? (cursorRawX / sw - 0.5) * 2 : 0;
        }
        readonly property real cursorNormY: {
            if (!Config.options.background.parallax.enableCursor || !parallaxEnabled) return 0;
            var sh = bgRoot.screen.height;
            return sh > 0 ? (cursorRawY / sh - 0.5) * 2 : 0;
        }

        // 偏移 clamp
        function clampedOffsetX(raw) { return Math.max(-movableX, Math.min(movableX, raw)) }
        function clampedOffsetY(raw) { return Math.max(-movableY, Math.min(movableY, raw)) }

        // 融合最终偏移
        readonly property real parallaxOffsetX: parallaxEnabled ? clampedOffsetX(
            -wsNormX * movableX + sidebarOffsetX + cursorNormX * movableX * Config.options.background.parallax.cursorSensitivity
        ) : 0
        readonly property real parallaxOffsetY: parallaxEnabled ? clampedOffsetY(
            -wsNormY * movableY + cursorNormY * movableY * Config.options.background.parallax.cursorSensitivity
        ) : 0

        // 转场/锁屏时冻结视差（用显式更新避免 QML binding loop 误报）
        property bool parallaxFrozen: true
        function _updateParallaxFrozen() {
            parallaxFrozen = bgRoot.transitionProgress < 1.0
                || GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered;
        }
        Connections {
            target: GlobalStates
            function onScreenLockedChanged() { bgRoot._updateParallaxFrozen() }
        }
        Connections {
            target: bgRoot
            function onWallpaperSafetyTriggeredChanged() { bgRoot._updateParallaxFrozen() }
        }

        // 光标轮询（Hyprland）
        Process {
            id: cursorPosProcess
            command: ["hyprctl", "cursorpos"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    var parts = text.trim().split(", ");
                    if (parts.length === 2) {
                        bgRoot.cursorRawX = parseInt(parts[0]) || 0;
                        bgRoot.cursorRawY = parseInt(parts[1]) || 0;
                    }
                }
            }
        }
        Timer {
            interval: Math.max(16, Config.options.background.parallax.cursorPollInterval)
            running: Config.options.background.parallax.enableCursor && parallaxEnabled
            repeat: true
            onTriggered: { cursorPosProcess.running = true }
        }

        // ─── 视频壁纸视差（mpv IPC）─────────────────────────
        // 视频壁纸由 mpvpaper 在后景层播放，quickshell 的壁纸容器管不到它。
        // switchwall.sh 会给每个显示器的 mpvpaper 加 input-ipc-server，
        // 这里连上该 socket，用 video-zoom / video-align-x / video-align-y
        // 复刻静态壁纸的缩放与平移（align ±1 正好对应 ±movableX/Y）。
        readonly property bool videoParallaxEnabled: parallaxEnabled
            && Appearance.wallpaperIsVideo && Config.options.background.parallax.enableVideo
        readonly property string videoSocketDir: {
            var configured = Config.options.background.parallax.videoSocketDir;
            if (configured && configured.length > 0) return configured.replace(/\/+$/, "");
            // 与 switchwall.sh 的 MPVPAPER_IPC_DIR 保持一致（都基于 XDG 缓存目录）
            return CF.FileUtils.trimFileProtocol(`${Directories.cache}/mpvpaper`);
        }
        readonly property string videoSocketPath:
            `${bgRoot.videoSocketDir}/mpvpaper-${bgRoot.screen ? bgRoot.screen.name : "unknown"}.sock`
        readonly property bool videoParallaxActive: bgRoot.videoParallaxEnabled
            && !bgRoot.parallaxFrozen && bgRoot.transitionProgress >= 1.0

        property real lastVideoZoom: -1
        property real lastVideoAlignX: -2
        property real lastVideoAlignY: -2
        // 只要「已应用的壁纸」是视频，mpvpaper 就在跑，就保持连接，
        // 这样关掉视差时还能把视频复位回中性状态。
        readonly property bool videoSocketWanted: Appearance.wallpaperIsVideo
        property bool videoSocketLoaderActive: false
        readonly property var mpvIpc: mpvIpcLoader.item
        readonly property bool mpvConnected: bgRoot.mpvIpc ? bgRoot.mpvIpc.connected : false

        function armVideoSocket() {
            bgRoot.videoSocketLoaderActive = bgRoot.videoSocketWanted;
        }
        onVideoSocketWantedChanged: bgRoot.armVideoSocket()

        // 静态壁纸下不创建 Socket，避免无意义的连接尝试与告警
        Loader {
            id: mpvIpcLoader
            active: bgRoot.videoSocketLoaderActive
            sourceComponent: Socket {
                path: bgRoot.videoSocketPath
                connected: true
                // 消费 mpv 的回包，避免 socket 缓冲区堆积
                parser: SplitParser {
                    onRead: (line) => {}
                }
                onConnectionStateChanged: {
                    if (connected) bgRoot.pushVideoParallax(true);
                }
            }
        }
        // Quickshell 的 Socket 连接失败后不会自己重连（socket 对象仍留在内部），
        // 所以重试的方式是重建整个 Socket。
        Timer {
            id: videoSocketRetryTimer
            interval: 2000
            repeat: true
            running: bgRoot.videoSocketLoaderActive && !bgRoot.mpvConnected
            onTriggered: {
                bgRoot.videoSocketLoaderActive = false;
                Qt.callLater(bgRoot.armVideoSocket);
            }
        }

        function mpvCommand(command) {
            if (!bgRoot.mpvConnected) return;
            bgRoot.mpvIpc.write(JSON.stringify({ command: command }) + "\n");
            bgRoot.mpvIpc.flush();
        }

        // 视频视差偏移：跟着壁纸层的过渡曲线做插值。直接把目标值丢给 mpv 会让
        // 视频在切换工作区时"瞬移"，看起来就是视差不够流畅。
        property real videoOffsetX: bgRoot.parallaxOffsetX
        property real videoOffsetY: bgRoot.parallaxOffsetY
        // 与壁纸层用同一条曲线，视频和静态壁纸的运动才一致
        Behavior on videoOffsetX {
            enabled: !parallaxFrozen
            NumberAnimation {
                duration: GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
                    ? 200 : Config.options.background.parallax.workspaceAnimationDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on videoOffsetY {
            enabled: !parallaxFrozen
            NumberAnimation {
                duration: GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
                    ? 200 : Config.options.background.parallax.workspaceAnimationDuration
                easing.type: Easing.OutCubic
            }
        }
        readonly property bool videoAnimating: Math.abs(bgRoot.videoOffsetX - bgRoot.parallaxOffsetX) > 0.05
            || Math.abs(bgRoot.videoOffsetY - bgRoot.parallaxOffsetY) > 0.05

        // 把当前视差状态推给 mpvpaper；force 时忽略节流直接发送。
        // 只发送真正变化的属性：动画期间 align 每帧都在变，如果顺手把没变的
        // video-zoom 也重发一遍，mpv 每帧都要重配视频链，画面就会卡。
        function pushVideoParallax(force) {
            if (!bgRoot.mpvConnected) return;
            var active = bgRoot.videoParallaxActive;
            // mpv 的 video-zoom 是 log2 倍率：0 = 原尺寸，1 = 200%
            var zoom = active ? Math.log(bgRoot.parallaxZoom) / Math.LN2 : 0;
            // 注意：mpv 的 video-align-x/y 与 QML 里 x/y 的符号相反
            //（align = +1 表示视频右边缘贴窗口右边，画面是往左露），所以取负号，
            // 否则视频壁纸的移动方向会和静态壁纸相反。
            var alignX = (active && movableX > 0)
                ? -Math.max(-1, Math.min(1, bgRoot.videoOffsetX / movableX)) : 0;
            var alignY = (active && movableY > 0)
                ? -Math.max(-1, Math.min(1, bgRoot.videoOffsetY / movableY)) : 0;

            if (force || Math.abs(zoom - bgRoot.lastVideoZoom) >= 0.0002) {
                bgRoot.lastVideoZoom = zoom;
                bgRoot.mpvCommand(["set_property", "video-zoom", zoom]);
            }
            if (force || Math.abs(alignX - bgRoot.lastVideoAlignX) >= 0.0004) {
                bgRoot.lastVideoAlignX = alignX;
                bgRoot.mpvCommand(["set_property", "video-align-x", alignX]);
            }
            if (force || Math.abs(alignY - bgRoot.lastVideoAlignY) >= 0.0004) {
                bgRoot.lastVideoAlignY = alignY;
                bgRoot.mpvCommand(["set_property", "video-align-y", alignY]);
            }
        }

        Timer {
            id: videoParallaxTimer
            // 过渡期间 ~50Hz 推送：mpv 每个 set_property 都会让 VO 重绘一次，
            // 推得比显示器刷新率还快只是白烧 GPU（滚轮连续切工作区时会明显卡）。
            // 50Hz 对只有十几~几十像素的位移已经足够平滑。
            interval: bgRoot.videoAnimating ? 20
                : Math.max(16, Config.options.background.parallax.cursorPollInterval)
            repeat: true
            running: bgRoot.videoParallaxActive && bgRoot.mpvConnected
            onTriggered: bgRoot.pushVideoParallax(false)
        }
        onVideoParallaxActiveChanged: bgRoot.pushVideoParallax(true)
        // ─── 视差引擎结束 ──────────────────────────────────

        readonly property bool hiddenForFullscreen: !GlobalStates.screenLocked
            && (activeWorkspaceWithFullscreen != undefined)
            && Config?.options.background.hideWhenFullscreen

        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

        property string effectiveWallpaperPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall;
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
        }

        property bool wallpaperIsVideo: bgRoot.effectiveWallpaperPath.endsWith(".mp4") || bgRoot.effectiveWallpaperPath.endsWith(".webm") || bgRoot.effectiveWallpaperPath.endsWith(".mkv") || bgRoot.effectiveWallpaperPath.endsWith(".avi") || bgRoot.effectiveWallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : bgRoot.effectiveWallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }

        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        property real transitionProgress: 1.0
        onTransitionProgressChanged: _updateParallaxFrozen()

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        WlrLayershell.keyboardFocus: GlobalStates.desktopWidgetKeyboardFocus
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Component.onCompleted: {
            previousWallpaper.source = ""
            wallpaper.source = bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
            bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
            bgRoot.previousWallpaperSource = ""
            bgRoot.transitionProgress = 1.0
            if (bgRoot.wallpaperAnimation !== "") {
                bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                    ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    : bgRoot.wallpaperAnimation
            }
            bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
            bgRoot.armVideoSocket()
            bgRoot._updateParallaxFrozen()
        }

        onWallpaperPathChanged: {
            bgRoot.videoRevealed = false
            if (wallpaperSafetyTriggered) {
                previousWallpaper.source = ""
                wallpaper.source = ""
                bgRoot.transitionProgress = 1.0
                return
            }
            if (bgRoot.wallpaperAnimation === "") {
                wallpaper.source = wallpaperPath
                bgRoot.currentWallpaperSource = wallpaperPath
                if (!bgRoot.wallpaperIsVideo) return
                bgRoot.videoRevealed = true
                return
            }

            previousWallpaper.source = bgRoot.currentWallpaperSource
            wallpaper.source = wallpaperPath
            bgRoot.currentWallpaperSource = wallpaperPath
            if (bgRoot.wallpaperAnimation === "random") {
                bgRoot.currentShader = bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
            } else {
                bgRoot.currentShader = bgRoot.wallpaperAnimation
            }
            bgRoot.transitionProgress = 0.0
        }

        NumberAnimation {
            id: transitionAnim
            target: bgRoot
            property: "transitionProgress"
            from: 0.0
            to: 1.0
            duration: 1200
            easing.type: Easing.InOutCubic
            onFinished: {
                previousWallpaper.source = ""
                bgRoot.previousWallpaperSource = ""
                bgRoot.transitionProgress = 1.0
                bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
            }
        }

        Timer {
            id: wallpaperChangeTimer
            interval: Config.options.wallpaperSelector.changeInterval
            running: Config.options.wallpaperSelector.changeInterval > 0
            repeat: true
            onTriggered: {
                if (Wallpapers.folderModel.count > 0) {
                    Wallpapers.randomFromCurrentFolder()
                }
            }
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (!GlobalStates.screenLocked) {
                    bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: bgRoot.hiddenForFullscreen ? 0 : 1
            enabled: !bgRoot.hiddenForFullscreen
            
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            // ─── 视差露出的部分：同一张壁纸的模糊副本 ──────────────
            // 平移视差需要"可移动余量"，传统做法是把壁纸放大（zoom）腾出余量，
            // 代价是壁纸被永久放大。这里改成：壁纸本体保持 1:1 不放大，
            // 后面垫一层同一张壁纸的模糊副本（静止不动 → layer 结果可缓存，
            // 只在换壁纸时渲染一次），平移露出来的就是虚化的同款画面。
            // 于是 workspaceZoom 退化成纯粹的"位移幅度旋钮"，不再造成放大。
            Image {
                id: parallaxBackdrop
                anchors.fill: parent
                anchors.margins: -80
                visible: wallpaperParallaxEnabled && !parallaxFrozen && !bgRoot.wallpaperIsVideo
                source: bgRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                cache: true
                asynchronous: true
                sourceSize.width: Math.ceil(width)
                sourceSize.height: Math.ceil(height)
                layer.enabled: visible
                layer.effect: FastBlur { radius: 64 }
            }

            // ─── 壁纸视差容器 ───────────────────────────────
            Item {
                id: wallpaperParallaxContainer
                width: parent.width
                height: parent.height
                // 不再用 zoom 放大本体：可移动余量由后面的模糊垫底层承接
                scale: 1
                transformOrigin: Item.Center
                x: wallpaperParallaxEnabled && !parallaxFrozen ? parallaxOffsetX : 0
                y: wallpaperParallaxEnabled && !parallaxFrozen ? parallaxOffsetY : 0

                // 注意：不要用 Easing.BezierSpline + 4 个值的 bezierCurve。
                // Qt 需要 3 个控制点（6 个值，末点必须是 1,1），少写终点会退化成
                // 匀速直线（实测 400ms 动画在 192ms 才走到 50%），壁纸就会"慢半拍"。
                // OutCubic：52ms 走 39%、192ms 走 88%、352ms 收尾，前段跟手、尾巴短。
                Behavior on x {
                    enabled: !parallaxFrozen
                    NumberAnimation {
                        duration: GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
                            ? 200 : Config.options.background.parallax.workspaceAnimationDuration
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: !parallaxFrozen
                    NumberAnimation {
                        duration: GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
                            ? 200 : Config.options.background.parallax.workspaceAnimationDuration
                        easing.type: Easing.OutCubic
                    }
                }

            Image {
                id: previousWallpaper
                width: wallpaperParallaxContainer.width
                height: wallpaperParallaxContainer.height
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: true
                // 按缩放后的显示尺寸解码：既避免 4K/8K 壁纸整幅载入占用大量内存，
                // 又保证视差放大后依然清晰（长宽比不同时 Qt 会等比缩放）。
                // 解码尺寸已贴合显示尺寸，mipmap 不再有用（只在缩小时才生效）。
                sourceSize.width: Math.ceil(width)
                sourceSize.height: Math.ceil(height)
                mipmap: false
                layer.enabled: true
                visible: false
            }

            StyledImage {
                id: wallpaper
                width: wallpaperParallaxContainer.width
                height: wallpaperParallaxContainer.height
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                mipmap: false
                asynchronous: true
                sourceSize.width: Math.ceil(width)
                sourceSize.height: Math.ceil(height)
                layer.enabled: blurLoader.active
                visible: !blurLoader.active && !bgRoot.centeredWallpaperEnabled && !bgRoot.videoRevealed
                    && (bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0)
                onStatusChanged: {
                    if (status === Image.Ready && bgRoot.transitionProgress === 0.0) {
                        transitionAnim.restart()
                    }
                }
            }

            ShaderEffect {
                id: transitionEffect
                width: wallpaperParallaxContainer.width
                height: wallpaperParallaxContainer.height
                layer.enabled: blurLoader.active
                visible: !blurLoader.active && !bgRoot.centeredWallpaperEnabled && !bgRoot.videoRevealed
                    && bgRoot.wallpaperAnimation !== "" && bgRoot.transitionProgress < 1.0

                property var fromImage: previousWallpaper
                property var toImage: wallpaper
                property var source1: previousWallpaper
                property var source2: wallpaper
                property real time: 0.0
                property real progress: bgRoot.transitionProgress
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)

                fragmentShader: bgRoot.wallpaperAnimation !== ""
                    ? Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
                    : ""

                Timer {
                    interval: 16
                    repeat: true
                    running: transitionEffect.visible
                    onTriggered: transitionEffect.time += interval / 1000.0
                }
                onVisibleChanged: if (!visible) transitionEffect.time = 0.0
            }
            } // wallpaperParallaxContainer 结束

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                    && !(bgRoot.userBlurActive || bgRoot.overviewBlurActive)
                width: parent.width
                height: parent.height
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                x: wallpaperParallaxEnabled && !parallaxFrozen ? parallaxOffsetX : 0
                y: wallpaperParallaxEnabled && !parallaxFrozen ? parallaxOffsetY : 0
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                Behavior on x {
                    enabled: !parallaxFrozen
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: !parallaxFrozen
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
                sourceComponent: GaussianBlur {
                    source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: Config.options.lock.blur.size 
                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            Loader {
                id: fastBlurLoader
                active: (bgRoot.userBlurActive || bgRoot.overviewBlurActive)
                    && (!bgRoot.centeredWallpaperEnabled || bgRoot.blurFullScreen)
                width: parent.width
                height: parent.height
                scale: 1
                x: wallpaperParallaxEnabled && !parallaxFrozen ? parallaxOffsetX : 0
                y: wallpaperParallaxEnabled && !parallaxFrozen ? parallaxOffsetY : 0
                Behavior on x {
                    enabled: !parallaxFrozen
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: !parallaxFrozen
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
                sourceComponent: Item {
                    id: blurRoot
                    anchors.fill: parent

                    readonly property real fadeWidth: 140
                    readonly property real blurRadius: 48
                    readonly property bool alignRight: Config.options.background.splitSide === "right"
                    property real coreWidth: bgRoot.blurFullScreen ? blurRoot.width : blurRoot.width * bgRoot.splitFraction

                    Behavior on coreWidth {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    FastBlur {
                        id: blurLayer
                        anchors.fill: parent
                        source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                        radius: blurRoot.blurRadius

                        layer.enabled: !bgRoot.blurFullScreen
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: blurLayer.width
                                height: blurLayer.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: blurRoot.alignRight ? 1 - (blurRoot.coreWidth / blurRoot.width) : Math.max(0, (blurRoot.coreWidth - blurRoot.fadeWidth) / blurRoot.width); color: blurRoot.alignRight ? "transparent" : "white" }
                                    GradientStop { position: blurRoot.alignRight ? Math.min(1, 1 - (blurRoot.coreWidth - blurRoot.fadeWidth) / blurRoot.width) : Math.min(1, blurRoot.coreWidth / blurRoot.width); color: blurRoot.alignRight ? "white" : "transparent" }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: centeredWallpaperBg
                anchors.fill: parent
                color: bgRoot.centeredWallpaperColor
                opacity: bgRoot.centeredWallpaperEnabled ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            MaterialShape {
                id: centeredWallpaperShapeItem
                anchors.centerIn: parent
                width: bgRoot.centeredWallpaperSize
                height: bgRoot.centeredWallpaperSize
                color: bgRoot.centeredWallpaperColor
                shape: bgRoot.centeredWallpaperShape
                transformOrigin: Item.Center
                visible: opacity > 0

                state: bgRoot.centeredWallpaperEnabled ? "shown" : "hidden"

                states: [
                    State {
                        name: "shown"
                        PropertyChanges { target: centeredWallpaperShapeItem; scale: 1; opacity: 1 }
                    },
                    State {
                        name: "hidden"
                        PropertyChanges { target: centeredWallpaperShapeItem; scale: 1.4; opacity: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        to: "shown"
                        ParallelAnimation {
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "scale"; from: 0; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "opacity"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                        }
                    },
                    Transition {
                        to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "scale"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "opacity"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                        }
                    }
                ]

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: centeredWallpaperShapeItem.width
                        height: centeredWallpaperShapeItem.height
                        shape: bgRoot.centeredWallpaperShape
                    }
                }

                StyledImage {
                    anchors.fill: parent
                    source: bgRoot.wallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    mipmap: true
                    antialiasing: true
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                }
            }

            DropArea {
                id: wallpaperDropArea
                anchors.fill: parent
                keys: ["text/uri-list"]

                property var currentUrls: []

                onEntered: (drag) => {
                    drag.accepted = drag.hasUrls
                    wallpaperDropArea.currentUrls = drag.hasUrls ? drag.urls : []
                }

                onExited: {
                    wallpaperDropArea.currentUrls = []
                }

                onDropped: (drop) => {
                    if (!drop.hasUrls) {
                        drop.accepted = false
                        wallpaperDropArea.currentUrls = []
                        return
                    }

                    if (drop.urls.length === 1) {
                        const path = CF.FileUtils.trimFileProtocol(decodeURIComponent(drop.urls[0].toString()))
                        const validExt = /\.(png|jpe?g|webp|bmp|gif)$/i.test(path)
                        if (validExt) {
                            Wallpapers.select(path, Appearance.m3colors.darkmode)
                        } else {
                            const globalPos = wallpaperDropArea.mapToGlobal(drop.x, drop.y)
                            DropShelf.show(drop.urls, globalPos.x, globalPos.y)
                        }
                    } else {
                        const globalPos = wallpaperDropArea.mapToGlobal(drop.x, drop.y)
                        DropShelf.show(drop.urls, globalPos.x, globalPos.y)
                    }
                    drop.accept()
                    wallpaperDropArea.currentUrls = []
                }

                Rectangle {
                    id: dropOverlay
                    anchors.fill: parent
                    visible: wallpaperDropArea.containsDrag
                    color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)

                    property bool isSingleImage: wallpaperDropArea.currentUrls.length === 1
                        && /\.(png|jpe?g|webp|bmp|gif)$/i.test(
                            CF.FileUtils.trimFileProtocol(wallpaperDropArea.currentUrls[0].toString())
                        )

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: dropOverlay.isSingleImage ? "wallpaper" : "stacks"
                            iconSize: 64
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: dropOverlay.isSingleImage
                                ? Translation.tr("Drop to set as wallpaper")
                                : Translation.tr("Drop to add to shelf")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height

                // 部件只跟随侧栏开合做轻微景深位移。光标跟随仅作用于壁纸层，
                // 否则鼠标一动桌面部件就会跟着抖动；工作区切换时部件保持原位。
                x: parallaxEnabled && !parallaxFrozen
                    ? sidebarOffsetX * Config.options.background.parallax.widgetsFactor
                    : 0
                y: 0
                Behavior on x {
                    enabled: !parallaxFrozen
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }


                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.visualizer.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: VisualizerWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.customImage.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: CustomImage {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.calendar.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: CalendarWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                        && (GlobalStates.screenLocked
                            || Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.notes.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: NotesWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    id: mediaLoader
                    property bool enableLoading: true
                    shown: Config.options.background.widgets.media.enable && enableLoading
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: MediaWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                    onLoaded: {
                        if (item && item.requestReset) {
                            item.requestReset.connect(() => {
                                mediaLoader.enableLoading = false
                                mediaTimer.running = true
                            })
                        }
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.images.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ImageConverterWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.resources.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ResourcesWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.worldClock.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: WorldClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.userCard.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: UserCardWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.todo.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: TodoWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.timers.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: TimerWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                    }
                }
            }

            MouseArea {
                id: desktopRightClickArea
                anchors.fill: parent
                z: -2
                acceptedButtons: Qt.RightButton
                onClicked: (mouse) => {
                    GlobalStates.desktopMenuScreen = bgRoot.screen
                    GlobalStates.desktopMenuX = mouse.x
                    GlobalStates.desktopMenuY = mouse.y
                    GlobalStates.desktopMenuOpen = true
                }
            }
        }
    }
}
