import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    // Keys.onPressed 需要活动焦点才能收到按键。原版把 focus 挂在作为背景的
    // wallpaperGridBackground 上，该节点已随去背景一起删除，这里直接由 root 承载。
    focus: true
    property int columns: Config.options.wallpaperSelector.columns || 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    property bool showControls: false
    property string source: "local"
    property string selectedResolution: "1080p"
    property string selectedColorGroup: ""
    property bool toolbarVisible: showControls || Config.options.wallpaperSelector.showSearchbar
    property bool filterFieldFocused: false
    // filterField 定义在 Loader.sourceComponent 内，那个 Component 有独立作用域，
    // root 层引用不到它的 id。这里显式暴露一份引用。
    property var filterFieldRef: null

    property var quickDirs: [
        { icon: "home",       name: "Home   ",       path: `${Directories.home}`,                alwaysVisible: Config.options.wallpaperSelector.showHomePath },
        { icon: "wallpaper",  name: "Wallpapers   ", path: `${Directories.pictures}/Wallpapers`, alwaysVisible: true },
        { icon: "imagesmode", name: "Homework   ",   path: `${Directories.pictures}/homework`,   alwaysVisible: Config.options.policies.weeb },
        { icon: "casino",     name: "Random   ",     path: `${Directories.pictures}/Random`,     alwaysVisible: true },
        { 
            icon: "image",     
            name: Config.options.wallpaperSelector.userPath?.trim().length > 0 
                ? Config.options.wallpaperSelector.userPath.split("/").filter(s => s.length > 0).pop() + "   "
                : "Custom   ",
            path: Config.options.wallpaperSelector.userPath, 
            alwaysVisible: Config.options.wallpaperSelector.userPath?.trim().length > 0 
        }
    ]

    function updateThumbnails() {
        const item = gridLoader.item;
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const cellW = item?.cellWidth ?? (gridDisplayRegion.width / root.columns);
        const cellH = item?.cellHeight ?? (cellW / root.previewCellAspectRatio);
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(cellW - totalImageMargin, cellH - totalImageMargin);
        Wallpapers.setDirectory(`${Directories.pictures}/Wallpapers`);
        Qt.callLater(() => Wallpapers.generateThumbnail(thumbnailSizeName));
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            if (GlobalStates.wallpaperSelectorTarget === "lockWall") {
                Wallpapers.select(filePath, root.useDarkMode, finalPath => {
                    Config.options.background.lockWall = finalPath;
                    GlobalStates.wallpaperSelectorTarget = "wallpaper";
                    GlobalStates.wallpaperSelectorOpen = false;
                });
            } else {
                // Stop preview FIRST so wallpaperPath reverts to the old wallpaper,
                // then select() sets confirmedPath to the new one — this causes
                // onWallpaperPathChanged to fire with the real transition animation.
                if (Config.options.background.enableWallpaperPreview)
                    Wallpapers.stopPreview();
                Wallpapers.select(filePath, root.useDarkMode);
            }
        }
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Wallpapers.stopPreview();
            GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
            root.handleFilePasting(event);
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            if (Config.options.wallpaperSelector.showSearchbar) {
                Config.options.wallpaperSelector.showSearchbar = false
                showControls = false
            } else {
                showControls = !showControls
            }
            event.accepted = true
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            if (!root.filterFieldFocused) gridLoader.item?.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            if (!root.filterFieldFocused && root.source !== "local") gridLoader.item?.moveSelection(-root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            if (!root.filterFieldFocused && root.source !== "local") gridLoader.item?.moveSelection(root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!root.filterFieldFocused) gridLoader.item?.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (!root.filterFieldFocused) {
                root.filterFieldRef?.forceActiveFocus();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            root.filterFieldRef?.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0 && !root.filterFieldFocused) {
                root.filterFieldRef.text += event.text;
                root.filterFieldRef.cursorPosition = root.filterFieldRef.text.length;
                root.filterFieldRef.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    RowLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 8
        spacing: -4
        z: 1

        ColumnLayout {
            id: gridColumnLayout
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: topBar
                Layout.fillWidth: true
                Layout.margins: 12
                Layout.leftMargin: 16
                implicitHeight: 56

                Toolbar {
                    id: titleBar
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    padding: 8

                    MaterialShapeWrappedMaterialSymbol {
                        wrappedShape: MaterialShape.Shape.Gem
                        text: "image"
                        iconSize: Appearance.font.pixelSize.larger
                    }

                    StyledText {
                        Layout.leftMargin: 6
                        text: Translation.tr("Wallpaper Selector")
                        font.pixelSize: Appearance.font.pixelSize.large
                    }
                }

                Toolbar {
                    anchors.centerIn: parent
                    visible: root.source !== "blapples" && root.source !== "naive"

                    Loader {
                        active: root.source === "local"
                        visible: active
                        sourceComponent: RowLayout {
                            spacing: 4
                            Repeater {
                                model: root.quickDirs
                                delegate: RippleButton {
                                    id: dirBtn
                                    required property var modelData
                                    implicitHeight: 38
                                    buttonRadius: height / 2
                                    visible: modelData.alwaysVisible
                                    toggled: Wallpapers.directory === Qt.resolvedUrl(modelData.path)
                                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                    onClicked: Wallpapers.setDirectory(modelData.path)
                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 6
                                        MaterialSymbol {
                                            text: dirBtn.modelData.icon
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: dirBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                            fill: dirBtn.toggled ? 1 : 0
                                        }
                                        StyledText {
                                            text: dirBtn.modelData.name
                                            color: dirBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        active: root.source !== "local" && root.source !== "blapples" && root.source !== "naive"
                        visible: active
                        sourceComponent: RowLayout {
                            spacing: 4
                            Repeater {
                                model: ["1080p", "2K", "4K"]
                                delegate: RippleButton {
                                    required property string modelData
                                    implicitHeight: 38
                                    buttonRadius: height / 2
                                    toggled: root.selectedResolution === modelData
                                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                                    onClicked: root.selectedResolution = modelData
                                    contentItem: StyledText {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: parent.toggled
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }

                Loader {
                    active: root.source === "naive"
                    visible: active
                    anchors.centerIn: parent
                    sourceComponent: CustomColorSelectionArray {
                        currentValue: root.selectedColorGroup
                        options: [
                                { value: "",       displayName: Translation.tr("All colors"), color: "transparent", rainbow: true },
                            { value: "red",    displayName: Translation.tr("Red"),        color: "#E0483E" },
                            { value: "orange", displayName: Translation.tr("Orange"),     color: "#E08A3E" },
                            { value: "yellow", displayName: Translation.tr("Yellow"),     color: "#E0C93E" },
                            { value: "green",  displayName: Translation.tr("Green"),      color: "#6CBF5C" },
                            { value: "blue",   displayName: Translation.tr("Blue"),       color: "#4C7FE0" },
                            { value: "purple", displayName: Translation.tr("Purple"),     color: "#8A5CE0" },
                        ]
                        onSelected: newValue => root.selectedColorGroup = newValue
                    }
                }

                RowLayout {
                    anchors {
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    StyledComboBox {
                        id: sourceCombo
                        implicitWidth: 120
                        model: [
                            { value: "local",     displayName: Translation.tr("Local") },
                            { value: "wallhaven", displayName: Translation.tr("Wallhaven") },
                            { value: "blapples",  displayName: Translation.tr("Blapples") },
                            { value: "naive",     displayName: Translation.tr("NA-ive") },
                            { value: "unsplash",  displayName: Translation.tr("Unsplash") },
                            { value: "pexels",    displayName: Translation.tr("Pexels") },
                        ]
                        textRole: "displayName"
                        onCurrentIndexChanged: {
                            root.source = model[currentIndex].value
                            root.forceActiveFocus()
                        }
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: height / 2
                        toggled: root.toolbarVisible
                        colBackground: Appearance.colors.colSecondaryContainer
                        onClicked: {
                            if (Config.options.wallpaperSelector.showSearchbar) {
                                Config.options.wallpaperSelector.showSearchbar = false
                                showControls = false
                            } else {
                                showControls = !showControls
                            }
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "search"
                            iconSize: Appearance.font.pixelSize.larger
                            color: root.toolbarVisible
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnSecondaryContainer
                        }
                        StyledToolTip {
                            text: Translation.tr("Toggle search toolbar (Ctrl+F)")
                        }
                    }
                }
            }

            Item {
                id: gridDisplayRegion
                Layout.fillWidth: true
                Layout.fillHeight: true

                Loader {
                    id: gridLoader
                    anchors.fill: parent
                    sourceComponent: {
                        if (root.source !== "local") return onlineGridComponent;
                        return Config.options.wallpaperSelector.viewMode === "carousel"
                            ? localCarouselComponent
                            : localGridComponent;
                    }
                }

                Component {
                    id: localGridComponent
                    LocalWallpaperGrid {
                        columns: root.columns
                        previewCellAspectRatio: root.previewCellAspectRatio
                        onWallpaperSelected: path => root.selectWallpaperPath(path)
                    }
                }

                Component {
                    id: localCarouselComponent
                    LocalWallpaperCarousel {
                        onWallpaperSelected: path => root.selectWallpaperPath(path)
                    }
                }

                Component {
                    id: onlineGridComponent
                    OnlineWallpaperGrid {
                        provider: root.source
                        resolution: root.selectedResolution
                        colorGroup: root.selectedColorGroup
                        onWallpaperSelected: path => root.selectWallpaperPath(path)
                        onUpdateThumbnailsRequested: root.updateThumbnails()
                    }
                }

                RowLayout {
                    id: extraOptions
                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                        bottomMargin: 8
                    }
                    spacing: 6
                    z: root.toolbarVisible ? 2 : -1
                    opacity: root.toolbarVisible ? 1 : 0
                    transform: Translate {
                        y: root.toolbarVisible ? 0 : 20
                        Behavior on y {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    Loader {
                        active: root.source === "local"
                        visible: active
                        sourceComponent: Toolbar {
                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: {
                                    Wallpapers.openFallbackPicker(root.useDarkMode);
                                    GlobalStates.wallpaperSelectorOpen = false;
                                }
                                altAction: () => {
                                    Wallpapers.openFallbackPicker(root.useDarkMode);
                                    GlobalStates.wallpaperSelectorOpen = false;
                                    Config.options.wallpaperSelector.useSystemFileDialog = true;
                                }
                                text: "open_in_new"
                                StyledToolTip {
                                    text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
                                }
                            }
                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: Wallpapers.randomFromCurrentFolder()
                                text: "ifl"
                                StyledToolTip {
                                    text: Translation.tr("Random wallpaper from current folder")
                                }
                            }
                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: root.useDarkMode = !root.useDarkMode
                                text: root.useDarkMode ? "dark_mode" : "light_mode"
                                StyledToolTip {
                                    text: root.useDarkMode
                                        ? Translation.tr("Switch to light mode")
                                        : Translation.tr("Switch to dark mode")
                                }
                            }
                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: root.updateThumbnails()
                                text: "reset_image"
                                StyledToolTip {
                                    text: Translation.tr("Update thumbnails")
                                }
                            }
                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: {
                                    Config.options.wallpaperSelector.viewMode =
                                        Config.options.wallpaperSelector.viewMode === "carousel" ? "grid" : "carousel";
                                }
                                text: Config.options.wallpaperSelector.viewMode === "carousel" ? "grid_view" : "view_carousel"
                                StyledToolTip {
                                    text: Config.options.wallpaperSelector.viewMode === "carousel"
                                        ? Translation.tr("Switch to grid view")
                                        : Translation.tr("Switch to carousel view")
                                }
                            }
                            ToolbarTextField {
                                id: filterField
                                Component.onCompleted: root.filterFieldRef = filterField
                                Component.onDestruction: {
                                    if (root.filterFieldRef === filterField) root.filterFieldRef = null
                                }
                                placeholderText: focus
                                    ? Translation.tr("Search wallpapers")
                                    : Translation.tr("Search wallpapers")
                                clip: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                onTextChanged: Wallpapers.searchQuery = text
                                onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                        root.handleFilePasting(event);
                                        event.accepted = true;
                                        return;
                                    }
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        event.accepted = true;
                                        return;
                                    }
                                    if (text.length !== 0) {
                                        if (event.key === Qt.Key_Down) { event.accepted = true; return; }
                                        if (event.key === Qt.Key_Up)   { event.accepted = true; return; }
                                    }
                                    event.accepted = false;
                                }
                            }
                        }
                    }

                    Loader {
                        active: root.source !== "local"
                        visible: active
                        sourceComponent: Toolbar {
                            ToolbarTextField {
                                id: onlineSearchField
                                placeholderText: Translation.tr("Search online wallpapers")
                                clip: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                onTextChanged: OnlineWallpapers.query = text
                                onAccepted: OnlineWallpapers.fetch()
                                onActiveFocusChanged: root.filterFieldFocused = activeFocus
                                Connections {
                                    target: GlobalStates
                                    function onWallpaperSelectorOpenChanged() {
                                        if (!GlobalStates.wallpaperSelectorOpen) onlineSearchField.text = ""
                                    }
                                }
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        event.accepted = true;
                                        return;
                                    }
                                    event.accepted = false;
                                }
                            }
                            IconToolbarButton {
                                implicitWidth: height
                                text: "refresh"
                                onClicked: OnlineWallpapers.fetch()
                            }
                        }
                    }

                    ToolbarPairedFab {
                        iconText: "close"
                        onClicked: {
                            Wallpapers.stopPreview();
                            GlobalStates.wallpaperSelectorOpen = false;
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen && monitorIsFocused) {
                // 必须把焦点给 root，而不是搜索框。搜索框一旦持有焦点，
                // filterFieldFocused 为 true，方向键会被文本框吞掉，
                // 无法再触发网格/轮播的 moveSelection。搜索框按需聚焦：
                // 按 / 或 Backspace，或直接输入字符（见 Keys.onPressed）。
                root.forceActiveFocus()
            } else if (!GlobalStates.wallpaperSelectorOpen) {
                Wallpapers.stopPreview();
            }
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            if (Config.options.wallpaperSelector.closeAfterSelection)
                GlobalStates.wallpaperSelectorOpen = false;
        }
    }
}
