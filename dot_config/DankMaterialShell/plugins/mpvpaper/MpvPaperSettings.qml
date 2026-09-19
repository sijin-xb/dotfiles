import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import qs.Modals.FileBrowser

PluginSettings {
    id: root
    pluginId: "mpvpaper"

    readonly property int settingLabelWidth: 180
    readonly property real settingTitleSize: Theme.fontSizeSmall
    readonly property real settingDescriptionSize: Theme.fontSizeSmall * 0.9

    property string language: "en"
    property var monitors: Quickshell.screens.map(screen => screen.name)
    property string selectedMonitor: monitors.length > 0 ? monitors[0] : ""
    property int playlistVersion: 0
    property int currentVideoRefresh: 0
    property bool sameOnAllMonitors: pluginData.sameOnAllMonitors || false

    function syncLanguage() {
        language = loadValue("language", "en")
        MpvPaperI18n.language = language
    }

    function syncAdvancedSettings() {
        if (!pluginService) return
        disableUserScriptsToggle.checked = loadValue("disableUserScripts", true)
        if (!customMpvOptionsField.activeFocus)
            customMpvOptionsField.text = loadValue("customMpvOptions", "")
    }

    Component.onCompleted: Qt.callLater(() => {
        syncLanguage()
        syncAdvancedSettings()
    })

    onPluginServiceChanged: Qt.callLater(() => {
        syncLanguage()
        syncAdvancedSettings()
    })

    Connections {
        target: pluginService
        enabled: pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === pluginId) {
                root.syncLanguage()
                root.syncAdvancedSettings()
                currentVideoRefresh++
            }
        }
    }

    onSelectedMonitorChanged: playlistVersion++

    StyledText {
        text: MpvPaperI18n.tr("MpvPaper Plugin", "mpvpaper")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: MpvPaperI18n.tr("General", "mpvpaper")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Language", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankDropdown {
            width: parent.width - root.settingLabelWidth - Theme.spacingM
            options: [
                MpvPaperI18n.tr("English", "mpvpaper"),
                MpvPaperI18n.tr("Simplified Chinese", "mpvpaper")
            ]
            currentValue: root.language === "zh_CN"
                ? MpvPaperI18n.tr("Simplified Chinese", "mpvpaper")
                : MpvPaperI18n.tr("English", "mpvpaper")
            compactMode: true
            onValueChanged: value => {
                const nextLanguage = value === MpvPaperI18n.tr("Simplified Chinese", "mpvpaper") ? "zh_CN" : "en"
                if (nextLanguage === root.language) return
                root.language = nextLanguage
                MpvPaperI18n.language = nextLanguage
                root.saveValue("language", nextLanguage)
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM
        visible: root.monitors.length > 1

        StyledText {
            text: MpvPaperI18n.tr("Same on all monitors", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankToggle {
            id: sameOnAllMonitorsSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root.sameOnAllMonitors

            onToggled: isChecked => {
                if (isChecked === root.sameOnAllMonitors) return
                if (isChecked && !root.loadValue("allMonitorsVideo", "")) {
                    const monitorVideos = root.loadValue("monitorVideos", {})
                    const sourceVideo = monitorVideos[root.selectedMonitor] || ""
                    if (sourceVideo) root.saveValue("allMonitorsVideo", sourceVideo)
                }
                root.sameOnAllMonitors = isChecked
                if (pluginService)
                    pluginService.savePluginData("mpvpaper", "sameOnAllMonitors", isChecked)
                currentVideoRefresh++
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM
        visible: root.monitors.length > 1

        StyledText {
            text: MpvPaperI18n.tr("Monitor", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.sameOnAllMonitors ? 0.4 : 1.0
            Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }
        }

        DankDropdown {
            width: parent.width - root.settingLabelWidth - Theme.spacingM
            visible: !root.sameOnAllMonitors
            options: root.monitors
            currentValue: root.selectedMonitor || MpvPaperI18n.tr("No Monitors", "mpvpaper")
            enabled: root.monitors.length > 1
            compactMode: true
            onValueChanged: value => root.selectedMonitor = value
        }

        Rectangle {
            width: parent.width - root.settingLabelWidth - Theme.spacingM
            height: 36
            visible: root.sameOnAllMonitors
            color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
            border.width: 1
            border.color: Theme.outlineHeavy
            radius: Theme.cornerRadius
            opacity: 0.4

            StyledText {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                text: MpvPaperI18n.tr("All Monitors", "mpvpaper")
                font.pixelSize: Theme.fontSizeMedium
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: {
            currentVideoRefresh
            const playlist = getPlaylist()
            return playlist.length > 0
                ? MpvPaperI18n.tr("Video List (%1 videos)", "mpvpaper").arg(playlist.length)
                : MpvPaperI18n.tr("Video List (Empty)", "mpvpaper")
        }
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        wrapMode: Text.Wrap
    }

    GridView {
        id: videoGridView
        width: parent.width
        cellWidth: width / 3
        cellHeight: cellWidth * 9 / 16
        height: Math.max(cellHeight, Math.ceil(getPlaylist().length / 3) * cellHeight)
        clip: true
        interactive: false
        highlightFollowsCurrentItem: true
        highlightMoveDuration: Theme.shortDuration

        highlight: Item {
            z: 1000
            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                color: "transparent"
                border.width: 3
                border.color: Theme.primary
                radius: Theme.cornerRadius
            }
        }

        model: {
            playlistVersion
            currentVideoRefresh
            return getPlaylist()
        }

        onModelChanged: {
            const currentPath = getCurrentVideoPath()
            const playlist = getPlaylist()
            currentIndex = playlist.indexOf(currentPath)
        }

        delegate: Item {
            width: videoGridView.cellWidth
            height: videoGridView.cellHeight

            required property string modelData
            required property int index
            property bool isSelected: videoGridView.currentIndex === index

            Rectangle {
                id: videoCard
                anchors.fill: parent
                anchors.margins: Theme.spacingXS
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                clip: true

                Rectangle {
                    id: maskRect
                    width: thumbnailImage.width
                    height: thumbnailImage.height
                    radius: Theme.cornerRadius
                    visible: false
                    layer.enabled: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                    radius: parent.radius
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: isSelected ? 3 : 0
                    border.color: Theme.primary
                    radius: parent.radius
                    Behavior on border.width {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Theme.standardEasing
                        }
                    }
                }

                Image {
                    id: thumbnailImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                        maskSource: maskRect
                    }

                    property string videoPath: modelData
                    property string thumbnailPath: ""

                    Component.onCompleted: generateThumbnail()

                    function generateThumbnail() {
                        const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "")
                        const cacheDir = cacheHome + "/DankMaterialShell/mpvpaper_thumbnails"
                        const hash = videoPath.split('').reduce((a, b) => {
                            a = ((a << 5) - a) + b.charCodeAt(0)
                            return a & a
                        }, 0)

                        thumbnailPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
                        playlistThumbCheckProcess.thumbnailPath = thumbnailPath
                        playlistThumbCheckProcess.videoPath = videoPath
                        playlistThumbCheckProcess.cacheDir = cacheDir
                        playlistThumbCheckProcess.command = ["test", "-f", thumbnailPath]
                        playlistThumbCheckProcess.running = true
                    }

                    Process {
                        id: playlistThumbCheckProcess
                        property string thumbnailPath: ""
                        property string videoPath: ""
                        property string cacheDir: ""

                        onExited: code => {
                            if (code === 0) {
                                thumbnailImage.source = "file://" + thumbnailPath
                            } else {
                                playlistThumbGenProcess.thumbnailPath = thumbnailPath
                                playlistThumbGenProcess.videoPath = videoPath
                                playlistThumbGenProcess.cacheDir = cacheDir
                                playlistThumbGenProcess.command = [
                                    "bash", "-c",
                                    'mkdir -p -- "$1" && ffmpeg -loglevel error -i "$2" -ss 00:00:01 -vframes 1 -vf "scale=320:180:force_original_aspect_ratio=increase,crop=320:180" -q:v 3 "$3" -y',
                                    "mpvpaper-thumbnail", cacheDir, videoPath, thumbnailPath
                                ]
                                playlistThumbGenProcess.running = true
                            }
                        }
                    }

                    Process {
                        id: playlistThumbGenProcess
                        property string thumbnailPath: ""
                        property string videoPath: ""
                        property string cacheDir: ""

                        onExited: code => {
                            if (code === 0) thumbnailImage.source = "file://" + thumbnailPath
                            else console.warn("MpvPaper Settings: Failed to generate thumbnail for", videoPath, "exit code:", code)
                        }
                    }
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: "movie"
                    size: 32
                    color: Theme.primary
                    visible: thumbnailImage.status === Image.Null || thumbnailImage.status === Image.Error
                }

                StateLayer {
                    anchors.fill: parent
                    cornerRadius: parent.radius
                    stateColor: Theme.primary
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        videoGridView.currentIndex = index
                        setCurrentVideo(modelData)
                    }
                }

                Rectangle {
                    id: removeButton
                    width: 24
                    height: 24
                    radius: 12
                    color: "#D32F2F"
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    visible: removeMouseArea.containsMouse
                    z: 100

                    DankIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: 16
                        color: "white"
                    }

                    MouseArea {
                        id: removeMouseArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: removeFromPlaylist(index)
                    }
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankButton {
            text: MpvPaperI18n.tr("Add Video", "mpvpaper")
            width: (parent.width - Theme.spacingM * 2) / 3
            onClicked: openSystemFilePicker()
        }

        DankButton {
            text: MpvPaperI18n.tr("Add Folder", "mpvpaper")
            width: (parent.width - Theme.spacingM * 2) / 3
            onClicked: openSystemDirectoryPicker()
        }

        DankButton {
            text: MpvPaperI18n.tr("Clear List", "mpvpaper")
            width: (parent.width - Theme.spacingM * 2) / 3
            enabled: getPlaylist().length > 0
            onClicked: clearPlaylist()
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: MpvPaperI18n.tr("Video Settings", "mpvpaper")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Hardware Decoding", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankDropdown {
            id: hwdecDropdown
            width: parent.width - root.settingLabelWidth - Theme.spacingM
            options: ["auto", "no", "vaapi", "vdpau", "nvdec"]
            compactMode: true

            Binding {
                target: hwdecDropdown
                property: "currentValue"
                value: getVideoSetting("hwdec", "auto")
            }

            onValueChanged: value => saveVideoSetting("hwdec", value)
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Tiling Mode", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankDropdown {
            id: panscanDropdown
            width: parent.width - root.settingLabelWidth - Theme.spacingM
            options: [
                MpvPaperI18n.tr("Fill Screen (Crop)", "mpvpaper"),
                MpvPaperI18n.tr("Fit Screen (Letterbox)", "mpvpaper"),
                MpvPaperI18n.tr("Stretch Fill", "mpvpaper")
            ]
            compactMode: true

            Binding {
                target: panscanDropdown
                property: "currentValue"
                value: {
                    const panscan = getVideoSetting("panscan", 1.0)
                    if (panscan === 1.0) return MpvPaperI18n.tr("Fill Screen (Crop)", "mpvpaper")
                    if (panscan === 0.0) return MpvPaperI18n.tr("Fit Screen (Letterbox)", "mpvpaper")
                    return MpvPaperI18n.tr("Stretch Fill", "mpvpaper")
                }
            }

            onValueChanged: value => {
                if (value === MpvPaperI18n.tr("Fill Screen (Crop)", "mpvpaper")) saveVideoSetting("panscan", 1.0)
                else if (value === MpvPaperI18n.tr("Fit Screen (Letterbox)", "mpvpaper")) saveVideoSetting("panscan", 0.0)
                else saveVideoSetting("panscan", 0.5)
            }
        }
    }

    Timer {
        id: volumeDebounceTimer
        interval: 500
        repeat: false
        onTriggered: saveVideoSetting("volume", Math.round(volumeSlider.value))
    }

    Row {
        width: parent.width
        height: 24
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Volume", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankSlider {
            id: volumeSlider
            width: parent.width - root.settingLabelWidth - Theme.spacingM - volumeValueText.width - Theme.spacingM
            minimum: 0
            maximum: 100
            showValue: false
            anchors.verticalCenter: parent.verticalCenter

            Binding {
                target: volumeSlider
                property: "value"
                value: getVideoSetting("volume", 0)
            }

            onSliderValueChanged: newValue => volumeDebounceTimer.restart()
        }

        StyledText {
            id: volumeValueText
            text: Math.round(volumeSlider.value)
            font.pixelSize: root.settingTitleSize
            width: 40
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: MpvPaperI18n.tr("Playback & Power", "mpvpaper")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Lock Screen Behavior", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankDropdown {
            id: lockBehaviorDropdown
            width: parent.width - root.settingLabelWidth - Theme.spacingM
            options: [
                MpvPaperI18n.tr("Close Player", "mpvpaper"),
                MpvPaperI18n.tr("Pause Playback", "mpvpaper")
            ]
            compactMode: true

            Binding {
                target: lockBehaviorDropdown
                property: "currentValue"
                value: root.loadValue("lockBehavior", "stop") === "pause"
                    ? MpvPaperI18n.tr("Pause Playback", "mpvpaper")
                    : MpvPaperI18n.tr("Close Player", "mpvpaper")
            }

            onValueChanged: value => {
                const behavior = value === MpvPaperI18n.tr("Pause Playback", "mpvpaper") ? "pause" : "stop"
                if (behavior !== root.loadValue("lockBehavior", "stop"))
                    root.saveValue("lockBehavior", behavior)
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: MpvPaperI18n.tr("Pause on Fullscreen", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            width: root.settingLabelWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        DankToggle {
            id: pauseOnFullscreenToggle
            anchors.verticalCenter: parent.verticalCenter

            Binding {
                target: pauseOnFullscreenToggle
                property: "checked"
                value: root.loadValue("pauseOnFullscreen", true)
            }

            onToggled: isChecked => {
                if (isChecked !== root.loadValue("pauseOnFullscreen", true))
                    root.saveValue("pauseOnFullscreen", isChecked)
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: MpvPaperI18n.tr("Scheduled Restart Interval", "mpvpaper")
                font.pixelSize: root.settingTitleSize
                font.weight: Font.Medium
                width: root.settingLabelWidth
                anchors.verticalCenter: parent.verticalCenter
            }

            DankDropdown {
                id: restartIntervalDropdown
                width: parent.width - root.settingLabelWidth - Theme.spacingM
                options: [
                    MpvPaperI18n.tr("Disabled", "mpvpaper"),
                    MpvPaperI18n.tr("10 Minutes", "mpvpaper"),
                    MpvPaperI18n.tr("30 Minutes", "mpvpaper"),
                    MpvPaperI18n.tr("1 Hour", "mpvpaper"),
                    MpvPaperI18n.tr("2 Hours", "mpvpaper")
                ]
                compactMode: true

                Binding {
                    target: restartIntervalDropdown
                    property: "currentValue"
                    value: {
                        const interval = loadValue("restartInterval", 60)
                        if (interval === 0) return MpvPaperI18n.tr("Disabled", "mpvpaper")
                        if (interval === 10) return MpvPaperI18n.tr("10 Minutes", "mpvpaper")
                        if (interval === 30) return MpvPaperI18n.tr("30 Minutes", "mpvpaper")
                        if (interval === 60) return MpvPaperI18n.tr("1 Hour", "mpvpaper")
                        if (interval === 120) return MpvPaperI18n.tr("2 Hours", "mpvpaper")
                        return MpvPaperI18n.tr("1 Hour", "mpvpaper")
                    }
                }

                onValueChanged: value => {
                    let interval = 60
                    if (value === MpvPaperI18n.tr("Disabled", "mpvpaper")) interval = 0
                    else if (value === MpvPaperI18n.tr("10 Minutes", "mpvpaper")) interval = 10
                    else if (value === MpvPaperI18n.tr("30 Minutes", "mpvpaper")) interval = 30
                    else if (value === MpvPaperI18n.tr("1 Hour", "mpvpaper")) interval = 60
                    else if (value === MpvPaperI18n.tr("2 Hours", "mpvpaper")) interval = 120
                    saveValue("restartInterval", interval)
                }
            }
        }

        StyledText {
            text: MpvPaperI18n.tr("Periodically restart mpv process to prevent potential memory leaks", "mpvpaper")
            font.pixelSize: root.settingDescriptionSize
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineStrong
    }

    StyledText {
        text: MpvPaperI18n.tr("Advanced MPV Settings", "mpvpaper")
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Column {
                width: parent.width - disableUserScriptsToggle.width - Theme.spacingM
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: MpvPaperI18n.tr("Disable user MPV scripts", "mpvpaper")
                    font.pixelSize: root.settingTitleSize
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: MpvPaperI18n.tr("Prevent mpv-mpris, uosc, and other local MPV scripts from loading in wallpaper processes. Recommended.", "mpvpaper")
                    font.pixelSize: root.settingDescriptionSize
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }

            DankToggle {
                id: disableUserScriptsToggle
                anchors.verticalCenter: parent.verticalCenter
                onToggled: isChecked => {
                    if (isChecked !== root.loadValue("disableUserScripts", true))
                        root.saveValue("disableUserScripts", isChecked)
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: MpvPaperI18n.tr("Custom MPV Options", "mpvpaper")
            font.pixelSize: root.settingTitleSize
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: MpvPaperI18n.tr("These options are appended after the plugin-generated MPV options.", "mpvpaper")
            font.pixelSize: root.settingDescriptionSize
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        DankTextField {
            id: customMpvOptionsField
            width: parent.width
            placeholderText: "profile=..."
            onEditingFinished: {
                if (text !== root.loadValue("customMpvOptions", ""))
                    root.saveValue("customMpvOptions", text)
            }
            onActiveFocusChanged: {
                if (!activeFocus && text !== root.loadValue("customMpvOptions", ""))
                    root.saveValue("customMpvOptions", text)
            }
        }
    }

    function openSystemFilePicker() {
        systemFilePickerProcess.selectedFile = ""
        systemFilePickerProcess.running = true
    }

    Process {
        id: systemFilePickerProcess
        property string selectedFile: ""

        command: ["bash", "-c",
            `if command -v zenity >/dev/null 2>&1; then
                zenity --file-selection --multiple --separator=$'\n' --title="${MpvPaperI18n.tr("Select Video Files", "mpvpaper")}" --file-filter="${MpvPaperI18n.tr("Video Files", "mpvpaper")} | *.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v" --file-filter="${MpvPaperI18n.tr("All Files", "mpvpaper")} | *"
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --getopenfilename ~ "*.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v|${MpvPaperI18n.tr("Video Files", "mpvpaper")}" --multiple --separate-output
            else
                echo "ERROR: No file picker available"
                exit 1
            fi`
        ]

        stdout: SplitParser {
            onRead: data => systemFilePickerProcess.selectedFile += data + "\n"
        }

        onExited: code => {
            const trimmedOutput = selectedFile.trim()
            if (code === 0 && trimmedOutput !== "") {
                const files = trimmedOutput.split('\n').map(f => f.trim()).filter(f => f !== "")
                if (files.length > 0) {
                    const addedCount = addMultipleToPlaylist(files)
                    if (addedCount > 0) {
                        ToastService.showInfo(
                            MpvPaperI18n.tr("Video Added", "mpvpaper"),
                            MpvPaperI18n.tr("Successfully added %1 videos", "mpvpaper").arg(addedCount)
                        )
                    }
                }
            } else if (trimmedOutput.includes("ERROR")) {
                console.log("MpvPaper: System file picker not available, using DMS file browser")
                videoFileBrowser.open()
            }
            selectedFile = ""
        }
    }

    function openSystemDirectoryPicker() {
        systemDirectoryPickerProcess.selectedDir = ""
        systemDirectoryPickerProcess.running = true
    }

    Process {
        id: systemDirectoryPickerProcess
        property string selectedDir: ""

        command: ["bash", "-c",
            `if command -v zenity >/dev/null 2>&1; then
                zenity --file-selection --directory --title="${MpvPaperI18n.tr("Select Video Folder", "mpvpaper")}" 
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --getexistingdirectory ~
            else
                echo "ERROR: No file picker available"
                exit 1
            fi`
        ]

        stdout: SplitParser {
            onRead: data => systemDirectoryPickerProcess.selectedDir += data
        }

        onExited: code => {
            const trimmedDir = selectedDir.trim()
            if (code === 0 && trimmedDir !== "") scanAndAddFolder(trimmedDir)
            selectedDir = ""
        }
    }

    function scanAndAddFolder(dirPath) {
        folderScanProcess.scanOutput = ""
        folderScanProcess.command = [
            "find", dirPath, "-type", "f", "-regextype", "posix-extended",
            "-iregex", ".*\\.(mp4|mkv|webm|avi|mov|flv|wmv|m4v)"
        ]
        folderScanProcess.running = true
    }

    Process {
        id: folderScanProcess
        property string scanOutput: ""

        stdout: SplitParser {
            onRead: data => folderScanProcess.scanOutput += data + "\n"
        }

        onExited: code => {
            if (code === 0 && scanOutput.trim() !== "") {
                const files = scanOutput.trim().split('\n').filter(f => f.trim() !== "")
                if (files.length > 0) {
                    const addedCount = addMultipleToPlaylist(files)
                    if (addedCount > 0) {
                        ToastService.showInfo(
                            MpvPaperI18n.tr("Folder Added", "mpvpaper"),
                            MpvPaperI18n.tr("Added %1 videos from directory", "mpvpaper").arg(addedCount)
                        )
                    }
                } else {
                    ToastService.showWarning(
                        MpvPaperI18n.tr("No Videos Found", "mpvpaper"),
                        MpvPaperI18n.tr("No supported video files found in selected folder", "mpvpaper")
                    )
                }
            }
            scanOutput = ""
        }
    }

    function addMultipleToPlaylist(videoPaths) {
        if (!videoPaths || videoPaths.length === 0) return 0

        var library = getPlaylist().slice()
        let addedCount = 0
        for (const path of videoPaths) {
            const trimmedPath = path.trim()
            if (trimmedPath && library.indexOf(trimmedPath) === -1) {
                library.push(trimmedPath)
                addedCount++
            }
        }

        if (addedCount > 0) {
            saveValue("videoLibrary", library)
            playlistVersion++
        }
        return addedCount
    }

    function addToPlaylist(videoPath) {
        addMultipleToPlaylist([videoPath])
    }

    function setCurrentVideo(videoPath) {
        if (!videoPath || getPlaylist().indexOf(videoPath) === -1) return

        if (sameOnAllMonitors) {
            saveValue("allMonitorsVideo", videoPath)
        } else {
            var monitorVideos = loadValue("monitorVideos", {})
            if (selectedMonitor) monitorVideos[selectedMonitor] = videoPath
            saveValue("monitorVideos", monitorVideos)
        }

        videoGridView.currentIndex = getPlaylist().indexOf(videoPath)
        currentVideoRefresh++
    }

    function removeFromPlaylist(index) {
        var library = getPlaylist().slice()
        if (index < 0 || index >= library.length) return

        const videoPath = library[index]
        deleteThumbnailCache(videoPath)
        library.splice(index, 1)
        saveValue("videoLibrary", library)

        var monitorVideos = loadValue("monitorVideos", {})
        let assignmentsChanged = false
        for (const monitor in monitorVideos) {
            if (monitorVideos[monitor] === videoPath) {
                delete monitorVideos[monitor]
                assignmentsChanged = true
            }
        }
        if (assignmentsChanged) saveValue("monitorVideos", monitorVideos)
        if (loadValue("allMonitorsVideo", "") === videoPath)
            saveValue("allMonitorsVideo", "")

        playlistVersion++
        currentVideoRefresh++
        videoGridView.currentIndex = library.indexOf(getCurrentVideoPath())
    }

    function deleteThumbnailCache(videoPath) {
        const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "")
        const cacheDir = cacheHome + "/DankMaterialShell/mpvpaper_thumbnails"
        const hash = videoPath.split('').reduce((a, b) => {
            a = ((a << 5) - a) + b.charCodeAt(0)
            return a & a
        }, 0)
        const thumbPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
        const previewPath = cacheDir + "/" + Math.abs(hash) + "_preview.jpg"
        thumbnailDeleteProcess.command = ["rm", "-f", "--", thumbPath, previewPath]
        thumbnailDeleteProcess.running = true
    }

    Process {
        id: thumbnailDeleteProcess
        command: []
    }

    function clearPlaylist() {
        const library = getPlaylist()
        for (const videoPath of library) deleteThumbnailCache(videoPath)

        saveValue("videoLibrary", [])
        saveValue("monitorVideos", {})
        saveValue("allMonitorsVideo", "")
        playlistVersion++
        currentVideoRefresh++
        videoGridView.currentIndex = -1
    }

    function getVideoSettings() {
        const videoPath = getCurrentVideoPath()
        if (!videoPath) return {}
        const allSettings = loadValue("videoSettings", {})
        return allSettings[videoPath] || {}
    }

    function getVideoSetting(key, defaultValue) {
        const settings = getVideoSettings()
        return settings[key] !== undefined ? settings[key] : defaultValue
    }

    function saveVideoSetting(key, value) {
        const videoPath = getCurrentVideoPath()
        if (!videoPath) return

        var allSettings = loadValue("videoSettings", {})
        if (!allSettings[videoPath]) allSettings[videoPath] = {}
        allSettings[videoPath][key] = value
        saveValue("videoSettings", allSettings)
    }

    function getCurrentVideoPath() {
        const monitorVideos = loadValue("monitorVideos", {})
        if (sameOnAllMonitors) return loadValue("allMonitorsVideo", "")
        return monitorVideos[selectedMonitor] || ""
    }

    function getPlaylist() {
        const library = loadValue("videoLibrary", [])
        return Array.isArray(library) ? library : []
    }

    FileBrowserSurfaceModal {
        id: videoFileBrowser
        browserTitle: MpvPaperI18n.tr("Select Video Files", "mpvpaper")
        browserIcon: "movie"
        browserType: "mpvpaper-video"
        showHiddenFiles: true
        fileExtensions: ["*.mp4", "*.mkv", "*.webm", "*.avi", "*.mov", "*.flv", "*.wmv", "*.m4v"]

        onFileSelected: videoPath => {
            root.addToPlaylist(videoPath)
            close()
        }
    }
}
