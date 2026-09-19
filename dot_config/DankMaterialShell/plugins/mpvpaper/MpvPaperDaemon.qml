import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "mpvpaper"

    property bool isLocked: IdleService.isShellLocked

    property var monitorVideos: pluginData.monitorVideos || {}
    property bool sameOnAllMonitors: pluginData.sameOnAllMonitors || false
    property string allMonitorsVideo: pluginData.allMonitorsVideo || ""

    property var processes: ({})
    property var ipcSockets: ({})
    property var ipcConnectTimers: ({})
    property var pendingSwitches: ({})
    property var pendingLaunches: ({})
    property var transitions: ({})
    property var transitionOverlays: ({})
    property var transitionTimers: ({})
    property var appliedPauseStates: ({})
    property int nextRequestId: 1

    property var previousScreenNames: []
    property bool ready: false
    property bool isSyncing: false
    property var liveNiriWorkspaces: null
    property bool liveNiriQueryInFlight: false

    property var restartTimers: ({})
    property var recoveryTimers: ({})
    property var stabilityTimers: ({})
    property var recoveryAttempts: ({})
    property var recoveryKeys: ({})
    property int maxRecoveryAttempts: 5
    property int restartInterval: ((pluginData.restartInterval === undefined || pluginData.restartInterval === null)
        ? 60
        : Number(pluginData.restartInterval)) * 60000
    readonly property string lockBehavior: pluginData.lockBehavior === "pause" ? "pause" : "stop"
    readonly property bool pauseOnFullscreen: (pluginData.pauseOnFullscreen === undefined || pluginData.pauseOnFullscreen === null)
        ? true
        : !!pluginData.pauseOnFullscreen

    // Sockets and one-shot frames are runtime state only. Never fall back to
    // GenericCacheLocation: if RuntimeLocation is unavailable, hot switching
    // and palette extraction degrade gracefully instead of writing persistently.
    readonly property string runtimeBaseDir: StandardPaths.writableLocation(StandardPaths.RuntimeLocation).toString().replace("file://", "")
    property string lastPaletteVideoPath: ""
    property string lastPaletteFramePath: ""
    property string paletteTargetVideoPath: ""

    onIsLockedChanged: {
        if (isLocked) {
            if (lockBehavior === "pause") {
                console.info("MpvPaper: Screen locked - pausing videos")
                pauseAllVideosForLock()
            } else {
                console.info("MpvPaper: Screen locked - stopping all videos")
                appliedPauseStates = ({})
                stopAllVideos()
            }
        } else {
            console.info("MpvPaper: Screen unlocked - restoring playback state")
            resumeVideosAfterLock()
        }
    }

    onPluginDataChanged: {
        MpvPaperI18n.language = pluginData.language || "en"
        if (!ready || isSyncing) return

        const newInterval = ((pluginData.restartInterval === undefined || pluginData.restartInterval === null)
            ? 60
            : Number(pluginData.restartInterval)) * 60000
        if (newInterval !== restartInterval) {
            restartInterval = newInterval
            console.info("MpvPaper: Restart interval changed to", newInterval / 60000, "minutes")
            for (const monitor in processes) setupRestartTimer(monitor)
        }

        if (isLocked && lockBehavior === "stop") {
            stopAllVideos()
            return
        }

        syncDebounce.restart()
        pauseStateDebounce.restart()
    }

    Timer {
        id: syncDebounce
        interval: 50
        repeat: false
        onTriggered: syncVideosWithData()
    }

    Timer {
        id: pauseStateDebounce
        interval: 50
        repeat: false
        onTriggered: syncPauseStates()
    }

    // NiriService can retain an old active_window_id while a horizontal page
    // changes. Refresh only the state used by the pause predicate.
    Timer {
        id: niriPausePoll
        interval: 500
        repeat: true
        running: root.ready
            && root.pauseOnFullscreen
            && CompositorService.isNiri
            && !root.isLocked
        onTriggered: root.refreshLiveNiriWorkspaces()
    }

    Connections {
        target: CompositorService

        function onToplevelsChanged() {
            if (root.ready) pauseStateDebounce.restart()
        }

        function onCompositorChanged() {
            if (root.ready) pauseStateDebounce.restart()
        }
    }

    // Niri exposes the active workspace/window geometry through NiriService.
    // Signals provide fast updates; the low-rate poll above is the recovery
    // path for missed or reordered layout notifications.
    Connections {
        target: NiriService
        enabled: CompositorService.isNiri

        function onAllWorkspacesChanged() {
            if (root.ready) pauseStateDebounce.restart()
        }

        function onWindowsChanged() {
            if (root.ready) pauseStateDebounce.restart()
        }

        function onOutputsChanged() {
            if (root.ready) pauseStateDebounce.restart()
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            const currentScreenNames = Quickshell.screens.map(screen => screen.name)
            const removedScreens = previousScreenNames.filter(name => !currentScreenNames.includes(name))
            const newScreens = currentScreenNames.filter(name => !previousScreenNames.includes(name))

            for (const screenName of removedScreens) {
                console.info("MpvPaper: Display disconnected:", screenName)
                appliedPauseStates = mapWithout(appliedPauseStates, screenName)
                stopMpvPaper(screenName)
            }

            for (const screenName of newScreens) {
                const videoPath = getEffectiveVideo(screenName)
                if (!isLocked && videoPath) {
                    console.info("MpvPaper: Display connected:", screenName, "- restoring", videoPath)
                    launchMpvPaper(screenName, videoPath)
                }
            }

            previousScreenNames = currentScreenNames
            pauseStateDebounce.restart()
        }
    }

    function mapWith(source, key, value) {
        const copy = Object.assign({}, source)
        copy[key] = value
        return copy
    }

    function mapWithout(source, key) {
        const copy = Object.assign({}, source)
        delete copy[key]
        return copy
    }

    function deepEqual(a, b) {
        if (a === b) return true
        if (a === null || b === null) return false
        if (typeof a !== "object" || typeof b !== "object") return false

        const aIsArray = Array.isArray(a)
        const bIsArray = Array.isArray(b)
        if (aIsArray !== bIsArray) return false

        const aKeys = Object.keys(a)
        const bKeys = Object.keys(b)
        if (aKeys.length !== bKeys.length) return false

        for (let i = 0; i < aKeys.length; ++i) {
            const key = aKeys[i]
            if (!Object.prototype.hasOwnProperty.call(b, key)) return false
            if (!deepEqual(a[key], b[key])) return false
        }
        return true
    }

    function migrateLegacyVideoLibrary() {
        const canSave = pluginService && pluginService.savePluginData
        const existingLibrary = Array.isArray(pluginData.videoLibrary) ? pluginData.videoLibrary : []
        const library = []

        for (const path of existingLibrary) {
            if (path && library.indexOf(path) === -1) library.push(path)
        }

        const legacyPlaylists = pluginData.monitorPlaylists || {}
        const legacyIndices = pluginData.playlistIndices || {}
        const videos = Object.assign({}, pluginData.monitorVideos || {})

        for (const monitor in legacyPlaylists) {
            const list = legacyPlaylists[monitor]
            if (!Array.isArray(list)) continue

            for (const path of list) {
                if (path && library.indexOf(path) === -1) library.push(path)
            }

            if (list.length > 0) {
                let index = legacyIndices[monitor] ?? 0
                if (index < 0 || index >= list.length) index = 0
                if (list[index]) videos[monitor] = list[index]
            }
        }

        for (const monitor in videos) {
            const path = videos[monitor]
            if (path && library.indexOf(path) === -1) library.push(path)
        }

        if (!deepEqual(existingLibrary, library)) {
            pluginData.videoLibrary = library
            if (canSave) pluginService.savePluginData(pluginId, "videoLibrary", library)
        }

        if (!deepEqual(pluginData.monitorVideos || {}, videos)) {
            pluginData.monitorVideos = videos
            if (canSave) pluginService.savePluginData(pluginId, "monitorVideos", videos)
        }

        if (Object.keys(legacyPlaylists).length > 0) {
            pluginData.monitorPlaylists = {}
            if (canSave) pluginService.savePluginData(pluginId, "monitorPlaylists", {})
        }
        if (Object.keys(legacyIndices).length > 0) {
            pluginData.playlistIndices = {}
            if (canSave) pluginService.savePluginData(pluginId, "playlistIndices", {})
        }
    }

    function getEffectiveVideo(monitor) {
        if (sameOnAllMonitors && allMonitorsVideo) return allMonitorsVideo
        return monitorVideos[monitor] || ""
    }

    function getVideoSettings(videoPath) {
        const allSettings = pluginData.videoSettings || {}
        return allSettings[videoPath] || {}
    }

    function getEffectiveSettings(videoPath) {
        const settings = Object.assign({}, getVideoSettings(videoPath))
        settings.disableUserScripts = pluginData.disableUserScripts !== undefined ? pluginData.disableUserScripts : true
        settings.customMpvOptions = pluginData.customMpvOptions || ""
        return settings
    }

    function processSettingsKey(settings) {
        return JSON.stringify({
            disableUserScripts: settings.disableUserScripts !== false,
            customMpvOptions: (settings.customMpvOptions || "").trim()
        })
    }

    function buildFileLocalOptions(settings) {
        const panscan = settings.panscan === undefined || settings.panscan === null ? 1.0 : settings.panscan
        const volume = settings.volume === undefined || settings.volume === null ? 0 : settings.volume
        return {
            hwdec: String(settings.hwdec || "auto"),
            panscan: String(panscan),
            volume: String(volume)
        }
    }

    function recoveryKeyFor(videoPath, settings) {
        return videoPath + "\n" + JSON.stringify(settings || {})
    }

    function updateRecoveryKey(monitor, videoPath, settings) {
        const key = recoveryKeyFor(videoPath, settings)
        if (recoveryKeys[monitor] === key) return

        resetRecovery(monitor)
        recoveryKeys = mapWith(recoveryKeys, monitor, key)
    }

    function allocateRequestId() {
        const id = nextRequestId
        nextRequestId += 1
        if (nextRequestId >= 2147483647) nextRequestId = 1
        return id
    }

    function sanitizeMonitorName(monitor) {
        return monitor.replace(/[^A-Za-z0-9_.-]/g, "_")
    }

    function createIpcPath(monitor) {
        if (!runtimeBaseDir) return ""
        return runtimeBaseDir + "/dms-mpvpaper-" + sanitizeMonitorName(monitor) + "-" + Date.now() + "-" + Math.floor(Math.random() * 1000000) + ".sock"
    }

    function createTransitionFramePath(monitor, requestId) {
        if (!runtimeBaseDir) return ""
        return runtimeBaseDir + "/dms-mpvpaper-transition-" + sanitizeMonitorName(monitor) + "-" + requestId + ".png"
    }

    function createPaletteFramePath(videoPath) {
        if (!runtimeBaseDir) return ""
        const hash = videoPath.split('').reduce((a, b) => {
            a = ((a << 5) - a) + b.charCodeAt(0)
            return a & a
        }, 0)
        return runtimeBaseDir + "/dms-mpvpaper-palette-" + Math.abs(hash) + ".jpg"
    }

    function screenForMonitor(monitor) {
        for (const screen of Quickshell.screens) {
            if (screen.name === monitor) return screen
        }
        return null
    }

    function refreshLiveNiriWorkspaces() {
        if (!ready || !CompositorService.isNiri || liveNiriQueryInFlight) return

        liveNiriQueryInFlight = true
        Proc.runCommand(
            "mpvpaper.niri.workspaces",
            ["niri", "msg", "-j", "workspaces"],
            (stdout, exitCode) => {
                liveNiriQueryInFlight = false
                if (exitCode !== 0) return

                try {
                    const workspaces = JSON.parse((stdout || "").trim())
                    if (!Array.isArray(workspaces)) return
                    liveNiriWorkspaces = workspaces
                    syncPauseStates()
                } catch (error) {
                    return
                }
            },
            0,
            1000,
            root
        )
    }

    function niriActiveWindowCoversMonitor(monitor) {
        const workspaces = liveNiriWorkspaces || NiriService.allWorkspaces
        const windows = NiriService.windows
        const activeWorkspace = workspaces.find(
            workspace => workspace.output === monitor && workspace.is_active
        )
        if (!activeWorkspace
                || activeWorkspace.active_window_id === null
                || activeWorkspace.active_window_id === undefined) {
            return false
        }

        const window = windows.find(
            candidate => candidate && candidate.id === activeWorkspace.active_window_id
        )
        if (!window || window.is_floating) return false

        const output = NiriService.outputs ? NiriService.outputs[monitor] : null
        const logical = output ? output.logical : null
        if (!logical || logical.width === undefined || logical.height === undefined)
            return false

        const size = window.layout?.tile_size || window.layout?.window_size
        if (!size || size.length < 2) return false

        const width = Number(size[0])
        const height = Number(size[1])
        const outputWidth = Number(logical.width)
        const outputHeight = Number(logical.height)
        if (!Number.isFinite(width) || !Number.isFinite(height)
                || !Number.isFinite(outputWidth) || !Number.isFinite(outputHeight)) {
            return false
        }

        const tolerance = 1
        return Math.abs(width - outputWidth) <= tolerance
            && Math.abs(height - outputHeight) <= tolerance
    }

    function genericFullscreenOnMonitor(monitor) {
        if (typeof CompositorService.fullscreenToplevelOnScreen === "function")
            return CompositorService.fullscreenToplevelOnScreen(monitor)
        return false
    }

    function isFullscreenOnMonitor(monitor) {
        if (!pauseOnFullscreen || !monitor) return false
        if (CompositorService.isNiri) return niriActiveWindowCoversMonitor(monitor)
        return genericFullscreenOnMonitor(monitor)
    }

    function shouldPauseMonitor(monitor) {
        if (isLocked && lockBehavior === "pause") return true
        if (isLocked) return false
        return isFullscreenOnMonitor(monitor)
    }

    function pauseReasonForMonitor(monitor) {
        if (isLocked && lockBehavior === "pause") return "lock"
        if (!isLocked && isFullscreenOnMonitor(monitor)) return "fullscreen"
        return ""
    }

    function applyMonitorPauseState(monitor, force) {
        const process = processes[monitor]
        if (!process) {
            appliedPauseStates = mapWithout(appliedPauseStates, monitor)
            return false
        }

        const shouldPause = shouldPauseMonitor(monitor)
        if (shouldPause && transitions[monitor]) return false

        const socket = ipcSockets[monitor]
        if (!socket || !socket.connected || socket.ipcPath !== process.ipcPath) {
            appliedPauseStates = mapWithout(appliedPauseStates, monitor)

            if (shouldPause && isLocked && lockBehavior === "pause") {
                console.warn("MpvPaper: Cannot pause", monitor, "through IPC - stopping player instead")
                stopMpvPaper(monitor, false)
            } else if (process.ipcPath) {
                ensureIpcConnection(monitor, process.ipcPath)
            }
            return false
        }

        const currentState = appliedPauseStates[monitor]
        if (!force
                && currentState
                && currentState.ipcPath === process.ipcPath
                && currentState.paused === shouldPause) {
            return true
        }

        sendIpc(socket, {
            command: ["set_property", "pause", shouldPause]
        })
        appliedPauseStates = mapWith(appliedPauseStates, monitor, {
            ipcPath: process.ipcPath,
            paused: shouldPause
        })

        if (shouldPause) {
            stopRestartTimer(monitor)
            console.info("MpvPaper: Paused", monitor, "for", pauseReasonForMonitor(monitor))
        } else {
            setupRestartTimer(monitor)
            console.info("MpvPaper: Resumed", monitor)
        }
        return true
    }

    function syncPauseStates() {
        if (!ready) return

        const connectedMonitors = Quickshell.screens.map(screen => screen.name)
        for (const monitor in appliedPauseStates) {
            if (connectedMonitors.indexOf(monitor) === -1 || !processes[monitor])
                appliedPauseStates = mapWithout(appliedPauseStates, monitor)
        }

        for (const monitor of connectedMonitors) {
            if (processes[monitor]) applyMonitorPauseState(monitor, false)
        }
    }

    function pendingMatches(monitor, videoPath, settings) {
        const pending = pendingSwitches[monitor]
        return pending
            && pending.videoPath === videoPath
            && deepEqual(pending.settings || {}, settings || {})
    }

    function clearPendingIfMatches(monitor, videoPath, settings) {
        if (pendingMatches(monitor, videoPath, settings)) {
            pendingSwitches = mapWithout(pendingSwitches, monitor)
        }
    }

    function syncVideosWithData() {
        if (isLocked) {
            console.info("MpvPaper: Screen is locked, skipping video sync")
            return
        }
        if (isSyncing) {
            console.warn("MpvPaper: Sync already in progress, skipping")
            return
        }

        isSyncing = true
        try {
            if (Object.keys(pluginData.monitorPlaylists || {}).length > 0 || Object.keys(pluginData.playlistIndices || {}).length > 0) {
                migrateLegacyVideoLibrary()
            }

            monitorVideos = pluginData.monitorVideos || {}
            sameOnAllMonitors = pluginData.sameOnAllMonitors || false
            allMonitorsVideo = pluginData.allMonitorsVideo || ""

            const connectedMonitors = Quickshell.screens.map(screen => screen.name)
            for (const monitor of connectedMonitors) {
                const newVideoPath = getEffectiveVideo(monitor)
                const process = processes[monitor]

                if (!newVideoPath) {
                    if (process) stopMpvPaper(monitor)
                    continue
                }

                const newSettings = getEffectiveSettings(newVideoPath)
                const alreadyCurrent = process
                    && process.videoPath === newVideoPath
                    && deepEqual(process.settings || {}, newSettings || {})
                if (alreadyCurrent) continue

                const transition = transitions[monitor]
                const transitionMatches = transition
                    && transition.videoPath === newVideoPath
                    && deepEqual(transition.settings || {}, newSettings || {})
                if (transitionMatches || pendingMatches(monitor, newVideoPath, newSettings) || pendingLaunches[monitor]) continue

                launchMpvPaper(monitor, newVideoPath)
            }
        } finally {
            isSyncing = false
        }
    }

    function launchMpvPaper(monitor, videoPath) {
        if (isLocked || !videoPath) {
            console.info("MpvPaper: Refusing launch while locked or without a video for", monitor)
            return
        }

        const settings = getEffectiveSettings(videoPath)
        const process = processes[monitor]

        if (!process) {
            startMpvPaper(monitor, videoPath, settings)
            return
        }

        if (process.videoPath === videoPath && deepEqual(process.settings || {}, settings || {})) return

        if (transitions[monitor]) {
            pendingSwitches = mapWith(pendingSwitches, monitor, {
                videoPath: videoPath,
                settings: settings
            })
            console.info("MpvPaper: Transition already active on", monitor, "- deferring", videoPath)
            return
        }

        if (process.launchSettingsKey === processSettingsKey(settings)) {
            queueHotSwitch(monitor, videoPath, settings)
        } else {
            console.info("MpvPaper: Process-level settings changed on", monitor, "- restarting player")
            forceRestartMpvPaper(monitor, videoPath, settings)
        }
    }

    function startMpvPaper(monitor, videoPath, settings) {
        if (pendingLaunches[monitor]) return

        pendingLaunches = mapWith(pendingLaunches, monitor, true)
        updateRecoveryKey(monitor, videoPath, settings)

        const ipcPath = createIpcPath(monitor)
        console.info("MpvPaper: Starting player for", monitor, "video:", videoPath)
        if (ipcPath) console.info("MpvPaper: IPC socket for", monitor, "is", ipcPath)
        else console.warn("MpvPaper: RuntimeLocation unavailable - IPC hot switching disabled for", monitor)

        const process = mpvProcessComponent.createObject(root, {
            monitor: monitor,
            videoPath: videoPath,
            settings: settings,
            ipcPath: ipcPath,
            launchSettingsKey: processSettingsKey(settings)
        })

        if (!process) {
            console.error("MpvPaper: Failed to create process object for", monitor)
            pendingLaunches = mapWithout(pendingLaunches, monitor)
            return
        }

        processes = mapWith(processes, monitor, process)
        process.running = true
        pendingLaunches = mapWithout(pendingLaunches, monitor)
        clearPendingIfMatches(monitor, videoPath, settings)

        if (ipcPath) ensureIpcConnection(monitor, ipcPath)
        scheduleStabilityReset(monitor, videoPath, settings)
        setupRestartTimer(monitor)
        updateWallpaperPalette(monitor, videoPath)
    }

    function forceRestartMpvPaper(monitor, videoPath, settings) {
        cancelTransition(monitor)
        stopMpvPaper(monitor, false)
        if (!isLocked && videoPath) startMpvPaper(monitor, videoPath, settings || getEffectiveSettings(videoPath))
    }

    function stopMpvPaper(monitor, stopRestart) {
        if (stopRestart === undefined) stopRestart = true

        if (stopRestart) stopRestartTimer(monitor)
        cancelTransition(monitor)
        destroyIpcConnection(monitor)
        pendingSwitches = mapWithout(pendingSwitches, monitor)
        pendingLaunches = mapWithout(pendingLaunches, monitor)
        appliedPauseStates = mapWithout(appliedPauseStates, monitor)

        const process = processes[monitor]
        if (process) {
            process.stopping = true
            process.running = false
            cleanupRuntimePath(process.ipcPath)
            process.destroy()
            processes = mapWithout(processes, monitor)
        }
    }

    function stopAllVideos() {
        for (const monitor in restartTimers) stopRestartTimer(monitor)
        const monitors = Object.keys(processes)
        for (const monitor of monitors) stopMpvPaper(monitor, false)

        for (const monitor in ipcSockets) destroyIpcConnection(monitor)
        for (const monitor in transitionOverlays) cancelTransition(monitor)
        processes = ({})
        pendingSwitches = ({})
        pendingLaunches = ({})
        appliedPauseStates = ({})
    }

    function pauseAllVideosForLock() {
        for (const monitor in restartTimers) stopRestartTimer(monitor)

        const monitors = Object.keys(processes)
        for (const monitor of monitors) {
            cancelTransition(monitor)
            applyMonitorPauseState(monitor, true)
        }
    }

    function resumeVideosAfterLock() {
        const monitors = Object.keys(processes)
        for (const monitor of monitors) applyMonitorPauseState(monitor, true)

        Qt.callLater(() => {
            if (!isLocked) {
                syncVideosWithData()
                pauseStateDebounce.restart()
            }
        })
    }

    function queueHotSwitch(monitor, videoPath, settings) {
        pendingSwitches = mapWith(pendingSwitches, monitor, {
            videoPath: videoPath,
            settings: settings
        })

        if (transitions[monitor]) return

        const process = processes[monitor]
        if (!process) {
            pendingSwitches = mapWithout(pendingSwitches, monitor)
            startMpvPaper(monitor, videoPath, settings)
            return
        }

        if (!process.ipcPath) {
            pendingSwitches = mapWithout(pendingSwitches, monitor)
            forceRestartMpvPaper(monitor, videoPath, settings)
            return
        }

        const socket = ipcSockets[monitor]
        if (socket && socket.ipcPath === process.ipcPath && socket.connected) {
            flushPendingSwitch(monitor)
        } else {
            console.info("MpvPaper: IPC not ready on", monitor, "- queueing switch")
            ensureIpcConnection(monitor, process.ipcPath)
        }
    }

    function flushPendingSwitch(monitor) {
        if (transitions[monitor]) return

        const pending = pendingSwitches[monitor]
        const process = processes[monitor]
        const socket = ipcSockets[monitor]
        if (!pending || !process || !socket || !socket.connected) return
        if (socket.ipcPath !== process.ipcPath) return

        if (process.launchSettingsKey !== processSettingsKey(pending.settings)) {
            pendingSwitches = mapWithout(pendingSwitches, monitor)
            forceRestartMpvPaper(monitor, pending.videoPath, pending.settings)
            return
        }

        if (shouldPauseMonitor(monitor)) {
            directHotSwitch(monitor, pending.videoPath, pending.settings)
            return
        }

        beginTransition(monitor, pending.videoPath, pending.settings)
    }

    function beginTransition(monitor, videoPath, settings) {
        const process = processes[monitor]
        const socket = ipcSockets[monitor]
        if (!process || !socket || !socket.connected || socket.ipcPath !== process.ipcPath) {
            directHotSwitch(monitor, videoPath, settings)
            return
        }

        const requestId = allocateRequestId()
        const framePath = createTransitionFramePath(monitor, requestId)
        if (!framePath) {
            directHotSwitch(monitor, videoPath, settings)
            return
        }

        transitions = mapWith(transitions, monitor, {
            phase: "capturing",
            videoPath: videoPath,
            settings: settings,
            framePath: framePath,
            screenshotRequestId: requestId,
            loadRequestId: 0,
            verifyRequestId: 0
        })

        console.info("MpvPaper: Capturing transition guard on", monitor)
        sendIpc(socket, {
            command: ["screenshot-to-file", framePath, "window"],
            request_id: requestId,
            async: true
        })
        armTransitionTimeout(monitor, "capturing", 1500)
    }

    function sendIpc(socket, message) {
        socket.write(JSON.stringify(message) + "\n")
        socket.flush()
    }

    function directHotSwitch(monitor, videoPath, settings) {
        const process = processes[monitor]
        const socket = ipcSockets[monitor]
        if (!process || !socket || !socket.connected || socket.ipcPath !== process.ipcPath) {
            forceRestartMpvPaper(monitor, videoPath, settings)
            return
        }

        console.info("MpvPaper: Hot-switching without transition on", monitor, "to", videoPath)
        sendIpc(socket, {
            command: [
                "loadfile",
                videoPath,
                "replace",
                -1,
                buildFileLocalOptions(settings)
            ]
        })

        process.videoPath = videoPath
        process.settings = settings
        clearPendingIfMatches(monitor, videoPath, settings)
        updatePlaybackStateAfterSwitch(monitor, videoPath, settings)
        applyMonitorPauseState(monitor, true)
    }

    function updatePlaybackStateAfterSwitch(monitor, videoPath, settings) {
        updateRecoveryKey(monitor, videoPath, settings)
        scheduleStabilityReset(monitor, videoPath, settings)
        setupRestartTimer(monitor)
        updateWallpaperPalette(monitor, videoPath)
    }

    function handleIpcMessage(monitor, ipcPath, message) {
        const process = processes[monitor]
        if (!process || process.ipcPath !== ipcPath) return

        let payload
        try {
            payload = JSON.parse(message)
        } catch (e) {
            console.debug("MpvPaper: Ignoring malformed IPC message on", monitor)
            return
        }

        if (payload.event === "playback-restart") {
            handlePlaybackRestart(monitor)
            return
        }

        if (payload.request_id !== undefined && payload.request_id !== null) {
            handleIpcReply(monitor, payload)
        }
    }

    function handleIpcReply(monitor, payload) {
        const transition = transitions[monitor]
        if (!transition) return

        if (transition.phase === "capturing" && payload.request_id === transition.screenshotRequestId) {
            clearTransitionTimeout(monitor)
            if (payload.error === "success") {
                createTransitionOverlay(monitor)
            } else {
                console.warn("MpvPaper: Guard capture failed on", monitor, "-", payload.error)
                fallbackTransitionToDirectSwitch(monitor)
            }
            return
        }

        if (transition.phase === "waitingPlayback" && payload.request_id === transition.loadRequestId && payload.error !== "success") {
            console.warn("MpvPaper: loadfile failed during transition on", monitor, "-", payload.error)
            fallbackTransitionToDirectSwitch(monitor)
            return
        }

        if (transition.phase === "verifyingPlayback" && payload.request_id === transition.verifyRequestId) {
            clearTransitionTimeout(monitor)
            if (payload.error === "success" && payload.data === transition.videoPath) {
                console.info("MpvPaper: Verified loaded path on", monitor, "after playback timeout")
                completeTransitionPlayback(monitor)
            } else {
                console.warn("MpvPaper: Could not verify loaded path on", monitor, "- falling back")
                fallbackTransitionToDirectSwitch(monitor)
            }
        }
    }

    function createTransitionOverlay(monitor) {
        const transition = transitions[monitor]
        if (!transition || transition.phase !== "capturing") return

        const screen = screenForMonitor(monitor)
        if (!screen) {
            console.warn("MpvPaper: Cannot resolve screen for transition on", monitor)
            fallbackTransitionToDirectSwitch(monitor)
            return
        }

        transitions = mapWith(transitions, monitor, Object.assign({}, transition, {
            phase: "waitingGuard"
        }))
        armTransitionTimeout(monitor, "waitingGuard", 1000)

        // Create the window before assigning the image path so a synchronous
        // Image.Ready signal cannot race transitionOverlays registration.
        const overlay = transitionOverlayComponent.createObject(root, {
            screenRef: screen,
            monitor: monitor,
            framePath: ""
        })
        if (!overlay) {
            console.warn("MpvPaper: Failed to create transition overlay on", monitor)
            fallbackTransitionToDirectSwitch(monitor)
            return
        }

        transitionOverlays = mapWith(transitionOverlays, monitor, overlay)
        overlay.framePath = transition.framePath
    }

    function handleTransitionCovered(monitor) {
        const transition = transitions[monitor]
        const process = processes[monitor]
        const socket = ipcSockets[monitor]
        if (!transition || transition.phase !== "waitingGuard") return

        clearTransitionTimeout(monitor)
        if (!process || !socket || !socket.connected || socket.ipcPath !== process.ipcPath) {
            fallbackTransitionToDirectSwitch(monitor)
            return
        }

        const requestId = allocateRequestId()
        transitions = mapWith(transitions, monitor, Object.assign({}, transition, {
            phase: "waitingPlayback",
            loadRequestId: requestId
        }))

        console.info("MpvPaper: Guard ready on", monitor, "- loading", transition.videoPath)
        sendIpc(socket, {
            command: [
                "loadfile",
                transition.videoPath,
                "replace",
                -1,
                buildFileLocalOptions(transition.settings)
            ],
            request_id: requestId
        })
        armTransitionTimeout(monitor, "waitingPlayback", 5000)
    }

    function handlePlaybackRestart(monitor) {
        const transition = transitions[monitor]
        if (!transition || (transition.phase !== "waitingPlayback" && transition.phase !== "verifyingPlayback")) return
        completeTransitionPlayback(monitor)
    }

    function completeTransitionPlayback(monitor) {
        const transition = transitions[monitor]
        if (!transition) return

        const process = processes[monitor]
        if (!process) {
            cancelTransition(monitor)
            return
        }

        clearTransitionTimeout(monitor)
        process.videoPath = transition.videoPath
        process.settings = transition.settings
        clearPendingIfMatches(monitor, transition.videoPath, transition.settings)
        updatePlaybackStateAfterSwitch(monitor, transition.videoPath, transition.settings)

        transitions = mapWith(transitions, monitor, Object.assign({}, transition, {
            phase: "revealing"
        }))

        const overlay = transitionOverlays[monitor]
        if (overlay) {
            console.info("MpvPaper: Playback ready on", monitor, "- revealing new wallpaper")
            overlay.reveal()
        } else {
            finishTransition(monitor)
        }
    }

    function handleTransitionOverlayFailed(monitor) {
        console.warn("MpvPaper: Transition guard image failed to load on", monitor)
        fallbackTransitionToDirectSwitch(monitor)
    }

    function fallbackTransitionToDirectSwitch(monitor) {
        const transition = transitions[monitor]
        if (!transition) return

        const videoPath = transition.videoPath
        const settings = transition.settings
        cancelTransition(monitor)
        directHotSwitch(monitor, videoPath, settings)
    }

    function finishTransition(monitor) {
        const transition = transitions[monitor]
        if (!transition) return

        clearTransitionTimeout(monitor)

        const overlay = transitionOverlays[monitor]
        if (overlay) overlay.destroy()
        transitionOverlays = mapWithout(transitionOverlays, monitor)
        transitions = mapWithout(transitions, monitor)

        cleanupRuntimePath(transition.framePath)
        applyMonitorPauseState(monitor, true)
        Qt.callLater(() => {
            if (!isLocked) syncVideosWithData()
        })
    }

    function cancelTransition(monitor) {
        const transition = transitions[monitor]
        clearTransitionTimeout(monitor)

        const overlay = transitionOverlays[monitor]
        if (overlay) overlay.destroy()
        transitionOverlays = mapWithout(transitionOverlays, monitor)
        transitions = mapWithout(transitions, monitor)

        if (transition && transition.framePath) cleanupRuntimePath(transition.framePath)
    }

    function cleanupRuntimePath(targetPath) {
        if (!targetPath) return
        const cleaner = cleanupProcessComponent.createObject(root, {
            targetPath: targetPath
        })
        if (cleaner) cleaner.running = true
    }

    Component {
        id: cleanupProcessComponent

        Process {
            property string targetPath: ""
            command: ["rm", "-f", "--", targetPath]
            onExited: destroy()
        }
    }

    Component {
        id: transitionOverlayComponent

        MpvPaperTransition {
            onCovered: root.handleTransitionCovered(monitor)
            onFinished: root.finishTransition(monitor)
            onFailed: root.handleTransitionOverlayFailed(monitor)
        }
    }

    function armTransitionTimeout(monitor, phase, interval) {
        clearTransitionTimeout(monitor)
        const timer = transitionTimeoutComponent.createObject(root, {
            monitor: monitor,
            phase: phase,
            interval: interval
        })
        if (!timer) return
        transitionTimers = mapWith(transitionTimers, monitor, timer)
        timer.start()
    }

    function clearTransitionTimeout(monitor) {
        const timer = transitionTimers[monitor]
        if (!timer) return
        timer.stop()
        timer.destroy()
        transitionTimers = mapWithout(transitionTimers, monitor)
    }

    function handleTransitionTimeout(monitor, phase) {
        transitionTimers = mapWithout(transitionTimers, monitor)
        const transition = transitions[monitor]
        if (!transition || transition.phase !== phase) return

        if (phase === "capturing") {
            console.warn("MpvPaper: Guard capture timed out on", monitor)
            fallbackTransitionToDirectSwitch(monitor)
            return
        }

        if (phase === "waitingGuard") {
            console.warn("MpvPaper: Guard display timed out on", monitor)
            fallbackTransitionToDirectSwitch(monitor)
            return
        }

        if (phase === "waitingPlayback") {
            const process = processes[monitor]
            const socket = ipcSockets[monitor]
            if (!process || !socket || !socket.connected || socket.ipcPath !== process.ipcPath) {
                console.warn("MpvPaper: Playback timed out and IPC is unavailable on", monitor)
                fallbackTransitionToDirectSwitch(monitor)
                return
            }

            const requestId = allocateRequestId()
            transitions = mapWith(transitions, monitor, Object.assign({}, transition, {
                phase: "verifyingPlayback",
                verifyRequestId: requestId
            }))
            console.warn("MpvPaper: playback-restart timed out on", monitor, "- verifying loaded path")
            sendIpc(socket, {
                command: ["get_property", "path"],
                request_id: requestId
            })
            armTransitionTimeout(monitor, "verifyingPlayback", 1000)
            return
        }

        if (phase === "verifyingPlayback") {
            console.warn("MpvPaper: Loaded-path verification timed out on", monitor)
            fallbackTransitionToDirectSwitch(monitor)
        }
    }

    Component {
        id: transitionTimeoutComponent

        Timer {
            property string monitor: ""
            property string phase: ""
            repeat: false
            onTriggered: {
                root.handleTransitionTimeout(monitor, phase)
                destroy()
            }
        }
    }

    function createIpcSocketAttempt(monitor, ipcPath) {
        const oldSocket = ipcSockets[monitor]
        if (oldSocket) {
            oldSocket.connected = false
            oldSocket.destroy()
            ipcSockets = mapWithout(ipcSockets, monitor)
        }

        const socket = ipcSocketComponent.createObject(root, {
            monitor: monitor,
            ipcPath: ipcPath,
            path: ipcPath
        })
        if (!socket) {
            console.error("MpvPaper: Failed to create IPC socket for", monitor)
            return
        }

        ipcSockets = mapWith(ipcSockets, monitor, socket)
        socket.connected = true
    }

    function ensureIpcConnection(monitor, ipcPath) {
        const process = processes[monitor]
        if (!process || process.ipcPath !== ipcPath || !ipcPath) return

        const existing = ipcSockets[monitor]
        if (existing && existing.ipcPath === ipcPath && existing.connected) {
            flushPendingSwitch(monitor)
            return
        }

        if (!ipcConnectTimers[monitor]) {
            startIpcRetryTimer(monitor, ipcPath)
        }

        createIpcSocketAttempt(monitor, ipcPath)
    }

    function startIpcRetryTimer(monitor, ipcPath) {
        const oldTimer = ipcConnectTimers[monitor]
        if (oldTimer) {
            oldTimer.stop()
            oldTimer.destroy()
        }

        const timer = ipcRetryTimerComponent.createObject(root, {
            monitor: monitor,
            ipcPath: ipcPath
        })
        if (!timer) return

        ipcConnectTimers = mapWith(ipcConnectTimers, monitor, timer)
        timer.start()
    }

    function finishIpcRetry(monitor, ipcPath) {
        const timer = ipcConnectTimers[monitor]
        if (!timer || timer.ipcPath !== ipcPath) return

        timer.stop()
        timer.destroy()
        ipcConnectTimers = mapWithout(ipcConnectTimers, monitor)
    }

    function destroyIpcConnection(monitor, expectedPath) {
        const timer = ipcConnectTimers[monitor]
        if (timer && (!expectedPath || timer.ipcPath === expectedPath)) {
            timer.stop()
            timer.destroy()
            ipcConnectTimers = mapWithout(ipcConnectTimers, monitor)
        }

        const socket = ipcSockets[monitor]
        if (socket && (!expectedPath || socket.ipcPath === expectedPath)) {
            socket.connected = false
            socket.destroy()
            ipcSockets = mapWithout(ipcSockets, monitor)
        }
    }

    function handleIpcConnected(monitor, ipcPath) {
        const process = processes[monitor]
        const socket = ipcSockets[monitor]
        if (!process || process.ipcPath !== ipcPath) return
        if (!socket || socket.ipcPath !== ipcPath || !socket.connected) return

        console.info("MpvPaper: IPC connected for", monitor)
        finishIpcRetry(monitor, ipcPath)
        flushPendingSwitch(monitor)
        if (!transitions[monitor]) applyMonitorPauseState(monitor, false)
    }

    function handleIpcUnavailable(monitor, ipcPath) {
        const process = processes[monitor]
        if (!process || process.ipcPath !== ipcPath) return

        finishIpcRetry(monitor, ipcPath)

        const pending = pendingSwitches[monitor]
        if (!pending) {
            console.warn("MpvPaper: IPC unavailable for", monitor, "- playback continues without hot switching")
            return
        }

        console.warn("MpvPaper: IPC unavailable for", monitor, "- falling back to process restart")
        pendingSwitches = mapWithout(pendingSwitches, monitor)
        forceRestartMpvPaper(monitor, pending.videoPath, pending.settings)
    }

    Component {
        id: ipcSocketComponent

        Socket {
            property string monitor: ""
            property string ipcPath: ""

            parser: SplitParser {
                onRead: message => root.handleIpcMessage(monitor, ipcPath, message)
            }

            onConnectedChanged: {
                if (connected) root.handleIpcConnected(monitor, ipcPath)
            }

            onError: error => {
                console.debug("MpvPaper: IPC connection attempt failed for", monitor, "-", error)
            }
        }
    }

    Component {
        id: ipcRetryTimerComponent

        Timer {
            property string monitor: ""
            property string ipcPath: ""
            property int attempts: 0

            interval: 200
            repeat: true

            onTriggered: {
                const process = root.processes[monitor]
                if (!process || process.ipcPath !== ipcPath) {
                    root.finishIpcRetry(monitor, ipcPath)
                    return
                }

                const socket = root.ipcSockets[monitor]
                if (socket && socket.ipcPath === ipcPath && socket.connected) {
                    root.handleIpcConnected(monitor, ipcPath)
                    return
                }

                attempts += 1
                if (attempts >= 25) {
                    root.handleIpcUnavailable(monitor, ipcPath)
                    return
                }

                // A failed QLocalSocket is not reused. Create a fresh client
                // for every retry so a socket created after mpv startup can
                // be connected reliably.
                root.createIpcSocketAttempt(monitor, ipcPath)
            }
        }
    }

    Component {
        id: mpvProcessComponent

        Process {
            id: mpvProc

            property string monitor: ""
            property string videoPath: ""
            property var settings: ({})
            property string ipcPath: ""
            property string launchSettingsKey: ""
            property bool stopping: false

            command: {
                const args = ["mpvpaper", "-l", "background"]
                const mpvOptions = []

                // mpvpaper writes -o values into an mpv config file. Keep every
                // built-in option in mpv.conf syntax (no leading --).
                mpvOptions.push("loop")

                const hwdec = settings.hwdec || "auto"
                mpvOptions.push("hwdec=" + hwdec)
                mpvOptions.push("hwdec-codecs=all")

                mpvOptions.push("profile=fast")
                mpvOptions.push("video-sync=display-resample")
                mpvOptions.push("interpolation=no")
                mpvOptions.push("scale=bilinear")
                mpvOptions.push("cscale=bilinear")
                mpvOptions.push("dscale=bilinear")
                mpvOptions.push("correct-downscaling=no")
                mpvOptions.push("linear-downscaling=no")
                mpvOptions.push("sigmoid-upscaling=no")
                mpvOptions.push("vd-lavc-threads=1")
                mpvOptions.push("cache=no")
                mpvOptions.push("demuxer-max-bytes=10M")
                mpvOptions.push("demuxer-readahead-secs=1")
                mpvOptions.push("vd-lavc-dr=yes")
                mpvOptions.push("opengl-pbo")
                mpvOptions.push("swapchain-depth=1")
                mpvOptions.push("audio-display=no")
                mpvOptions.push("osc=no")
                mpvOptions.push("osd-bar=no")
                mpvOptions.push("input-default-bindings=no")
                mpvOptions.push("input-cursor=no")
                mpvOptions.push("cursor-autohide=no")
                mpvOptions.push("keepaspect-window=no")

                if (settings.disableUserScripts !== false) mpvOptions.push("load-scripts=no")

                const panscan = settings.panscan === undefined || settings.panscan === null ? 1.0 : settings.panscan
                const volume = settings.volume === undefined || settings.volume === null ? 0 : settings.volume
                mpvOptions.push("panscan=" + panscan)
                mpvOptions.push("volume=" + volume)

                if (ipcPath) mpvOptions.push("input-ipc-server=" + ipcPath)

                const customMpvOptions = (settings.customMpvOptions || "").trim()
                if (customMpvOptions) mpvOptions.push(customMpvOptions)

                args.push("-o")
                args.push(mpvOptions.join(" "))
                args.push(monitor)
                args.push(videoPath)
                return args
            }

            onExited: (code) => {
                const isCurrentProcess = root.processes[monitor] === mpvProc
                root.cleanupRuntimePath(ipcPath)

                if (isCurrentProcess) {
                    root.cancelTransition(monitor)
                    root.processes = root.mapWithout(root.processes, monitor)
                    root.destroyIpcConnection(monitor, ipcPath)
                    root.appliedPauseStates = root.mapWithout(root.appliedPauseStates, monitor)
                }

                if (!stopping && code !== 0) {
                    console.warn("MpvPaper: Process exited with code", code, "for", monitor)
                    ToastService.showError(
                        MpvPaperI18n.tr("MpvPaper Error", "mpvpaper"),
                        MpvPaperI18n.tr("Video playback failed on %1", "mpvpaper").arg(monitor)
                    )
                }

                if (!stopping && isCurrentProcess && !root.isLocked && root.getEffectiveVideo(monitor)) {
                    const desiredVideo = root.getEffectiveVideo(monitor)
                    root.scheduleRecovery(monitor, desiredVideo, root.getEffectiveSettings(desiredVideo))
                }
            }
        }
    }

    Component {
        id: recoveryTimerComponent

        Timer {
            property string monitor: ""
            interval: 1500
            repeat: false
            onTriggered: {
                root.recoveryTimers = root.mapWithout(root.recoveryTimers, monitor)
                destroy()
                if (!root.isLocked) root.syncVideosWithData()
            }
        }
    }

    function scheduleRecovery(monitor, videoPath, settings) {
        if (recoveryTimers[monitor]) return

        const key = recoveryKeyFor(videoPath, settings)
        if (recoveryKeys[monitor] !== key) {
            resetRecovery(monitor)
            recoveryKeys = mapWith(recoveryKeys, monitor, key)
        }

        const attempt = (recoveryAttempts[monitor] || 0) + 1
        recoveryAttempts = mapWith(recoveryAttempts, monitor, attempt)

        if (attempt > maxRecoveryAttempts) {
            console.error("MpvPaper: Giving up recovery for", monitor, "after", maxRecoveryAttempts, "attempts")
            ToastService.showError(
                MpvPaperI18n.tr("MpvPaper Error", "mpvpaper"),
                MpvPaperI18n.tr("Video playback failed on %1", "mpvpaper").arg(monitor)
            )
            return
        }

        const delay = 1500 * Math.pow(2, attempt - 1)
        console.warn("MpvPaper: Scheduling recovery", attempt, "of", maxRecoveryAttempts, "for", monitor, "in", delay, "ms")
        const timer = recoveryTimerComponent.createObject(root, {
            monitor: monitor,
            interval: delay
        })
        recoveryTimers = mapWith(recoveryTimers, monitor, timer)
        timer.start()
    }

    function resetRecovery(monitor) {
        const timer = recoveryTimers[monitor]
        if (timer) {
            timer.stop()
            timer.destroy()
        }
        recoveryTimers = mapWithout(recoveryTimers, monitor)
        recoveryAttempts = mapWithout(recoveryAttempts, monitor)
        recoveryKeys = mapWithout(recoveryKeys, monitor)
    }

    Component {
        id: stabilityTimerComponent

        Timer {
            property string monitor: ""
            property string recoveryKey: ""
            interval: 30000
            repeat: false
            onTriggered: {
                root.stabilityTimers = root.mapWithout(root.stabilityTimers, monitor)
                destroy()
                if (root.recoveryKeys[monitor] === recoveryKey && root.processes[monitor]) {
                    console.info("MpvPaper: Playback stable on", monitor, "- clearing recovery count")
                    root.recoveryAttempts = root.mapWithout(root.recoveryAttempts, monitor)
                }
            }
        }
    }

    function scheduleStabilityReset(monitor, videoPath, settings) {
        const existing = stabilityTimers[monitor]
        if (existing) {
            existing.stop()
            existing.destroy()
        }

        const timer = stabilityTimerComponent.createObject(root, {
            monitor: monitor,
            recoveryKey: recoveryKeyFor(videoPath, settings)
        })
        stabilityTimers = mapWith(stabilityTimers, monitor, timer)
        timer.start()
    }

    function setupRestartTimer(monitor) {
        stopRestartTimer(monitor)
        if (restartInterval <= 0) {
            console.info("MpvPaper: Auto-restart disabled for", monitor)
            return
        }
        if (shouldPauseMonitor(monitor)) {
            console.info("MpvPaper: Auto-restart suspended while paused for", monitor)
            return
        }

        const timer = restartTimerComponent.createObject(root, {
            monitor: monitor,
            interval: restartInterval
        })
        restartTimers = mapWith(restartTimers, monitor, timer)
        timer.start()
        console.info("MpvPaper: Set up restart timer for", monitor, "-", restartInterval / 60000, "minutes")
    }

    Component {
        id: restartTimerComponent

        Timer {
            property string monitor: ""
            repeat: false
            onTriggered: {
                const videoPath = root.getEffectiveVideo(monitor)
                if (!root.isLocked && !root.shouldPauseMonitor(monitor) && videoPath) {
                    console.info("MpvPaper: Scheduled restart for", monitor)
                    root.forceRestartMpvPaper(monitor, videoPath, root.getEffectiveSettings(videoPath))
                }
            }
        }
    }

    function stopRestartTimer(monitor) {
        const timer = restartTimers[monitor]
        if (!timer) return
        timer.stop()
        timer.destroy()
        restartTimers = mapWithout(restartTimers, monitor)
    }

    function updateWallpaperPalette(monitor, videoPath) {
        if (videoPath === paletteTargetVideoPath) return
        paletteTargetVideoPath = videoPath

        if (videoPath === lastPaletteVideoPath) {
            console.info("MpvPaper: Palette already up-to-date for", videoPath)
            return
        }

        const stillPath = createPaletteFramePath(videoPath)
        if (!stillPath) {
            console.warn("MpvPaper: RuntimeLocation unavailable - skipping palette frame extraction")
            return
        }

        console.info("MpvPaper: Extracting runtime still frame for palette from", videoPath)
        const extractor = stillFrameExtractorComponent.createObject(root, {
            videoPath: videoPath,
            outputPath: stillPath
        })
        if (!extractor) {
            paletteTargetVideoPath = ""
            return
        }
        extractor.running = true
    }

    Component {
        id: stillFrameExtractorComponent

        Process {
            property string videoPath: ""
            property string outputPath: ""

            command: [
                "ffmpeg",
                "-loglevel", "error",
                "-i", videoPath,
                "-ss", "00:00:02",
                "-vframes", "1",
                "-vf", "scale=1280:-1",
                "-q:v", "2",
                outputPath,
                "-y"
            ]

            onExited: (code) => {
                if (videoPath !== root.paletteTargetVideoPath) {
                    root.cleanupRuntimePath(outputPath)
                    destroy()
                    return
                }

                if (code === 0) {
                    console.info("MpvPaper: Runtime still frame extracted for palette:", outputPath)
                    if (typeof Theme !== "undefined" && Theme.currentTheme === Theme.dynamic) {
                        const isLight = typeof SessionData !== "undefined" ? SessionData.isLightMode : false
                        const iconTheme = typeof SettingsData !== "undefined" && SettingsData.iconTheme
                            ? SettingsData.iconTheme
                            : "System Default"
                        const matugenType = typeof SettingsData !== "undefined" && SettingsData.matugenScheme
                            ? SettingsData.matugenScheme
                            : "scheme-tonal-spot"

                        Theme.setDesiredTheme("image", outputPath, isLight, iconTheme, matugenType)
                    }

                    if (root.lastPaletteFramePath && root.lastPaletteFramePath !== outputPath)
                        root.cleanupRuntimePath(root.lastPaletteFramePath)
                    root.lastPaletteFramePath = outputPath
                    root.lastPaletteVideoPath = videoPath
                } else {
                    console.warn("MpvPaper: Failed to extract still frame (exit code:", code, ") from", videoPath)
                    root.cleanupRuntimePath(outputPath)
                }

                root.paletteTargetVideoPath = ""
                destroy()
            }
        }
    }

    Component.onCompleted: {
        MpvPaperI18n.language = pluginData.language || "en"
        migrateLegacyVideoLibrary()

        previousScreenNames = Quickshell.screens.map(screen => screen.name)
        processes = ({})
        ipcSockets = ({})
        ipcConnectTimers = ({})
        pendingSwitches = ({})
        pendingLaunches = ({})
        transitions = ({})
        transitionOverlays = ({})
        transitionTimers = ({})
        appliedPauseStates = ({})
        recoveryTimers = ({})
        stabilityTimers = ({})
        recoveryAttempts = ({})
        recoveryKeys = ({})

        console.info("MpvPaper Daemon: Starting...")
        ready = true
        syncVideosWithData()
        pauseStateDebounce.restart()
    }

    Component.onDestruction: {
        console.info("MpvPaper Daemon: Stopping, cleaning up")

        for (const monitor in restartTimers) {
            if (restartTimers[monitor]) {
                restartTimers[monitor].stop()
                restartTimers[monitor].destroy()
            }
        }
        for (const monitor in recoveryTimers) {
            if (recoveryTimers[monitor]) {
                recoveryTimers[monitor].stop()
                recoveryTimers[monitor].destroy()
            }
        }
        for (const monitor in stabilityTimers) {
            if (stabilityTimers[monitor]) {
                stabilityTimers[monitor].stop()
                stabilityTimers[monitor].destroy()
            }
        }
        for (const monitor in transitionTimers) {
            if (transitionTimers[monitor]) {
                transitionTimers[monitor].stop()
                transitionTimers[monitor].destroy()
            }
        }
        for (const monitor in transitionOverlays) {
            if (transitionOverlays[monitor]) transitionOverlays[monitor].destroy()
        }
        for (const monitor in ipcConnectTimers) {
            if (ipcConnectTimers[monitor]) {
                ipcConnectTimers[monitor].stop()
                ipcConnectTimers[monitor].destroy()
            }
        }
        for (const monitor in ipcSockets) {
            if (ipcSockets[monitor]) {
                ipcSockets[monitor].connected = false
                ipcSockets[monitor].destroy()
            }
        }
        for (const monitor in processes) {
            if (processes[monitor]) {
                cleanupRuntimePath(processes[monitor].ipcPath)
                processes[monitor].stopping = true
                processes[monitor].running = false
                processes[monitor].destroy()
            }
        }

        cleanupRuntimePath(lastPaletteFramePath)
    }
}
