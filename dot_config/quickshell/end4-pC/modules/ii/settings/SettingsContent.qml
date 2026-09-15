import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.settings.pages
import qs.modules.common.widgets
import qs.modules.common.functions as CF

Item {
    id: root
    property real contentPadding: 8
    property int currentPage: 0
    property bool showingProfile: false
    property bool isMinimal: Config.options.settings.style === "minimal"

    Connections {
        target: GlobalStates
        function onSettingsPageChanged() {
            if (GlobalStates.settingsPage === "") return
            
            let parts = GlobalStates.settingsPage.split(":");
            let pageName = parts[0];
            let searchTerm = parts.length > 1 ? parts[1] : "";

            const idx = root.pages.findIndex(p => p.name.toLowerCase() === pageName.toLowerCase());
            
            if (idx >= 0) {
                root.currentPage = idx;
                root.showingProfile = false;
                
                if (searchTerm !== "") {
                    let loader = pagesRepeater.itemAt(idx);
                    if (loader && loader.item && typeof loader.item.goTo === "function") {
                        loader.item.goTo(searchTerm);
                    } else if (loader) {
                        loader.onLoaded.connect(function() {
                            if (loader.item && typeof loader.item.goTo === "function") {
                                loader.item.goTo(searchTerm);
                            }
                        });
                    }
                }
            }
            GlobalStates.settingsPage = "";
        }
    }

    // ─── 设置搜索 ───────────────────────────────────────────────
    // 索引由 scripts/settings/build-search-index.py 生成（页面 → 小节标题 key），
    // 运行时用 Translation.tr 翻成当前语言再匹配，所以中文/英文都能搜。
    // 命中后复用已有的 GlobalStates.settingsPage = "页面:小节" 深链，
    // 由上面的 Connections 负责跳页 + 调页面自己的 goTo() 滚动定位。
    property var settingsSearchIndex: []
    FileView {
        id: settingsSearchIndexFile
        path: Quickshell.shellPath("modules/ii/settings/settingsSearchIndex.json")
        onLoaded: {
            try { root.settingsSearchIndex = JSON.parse(text()); }
            catch (e) { root.settingsSearchIndex = []; }
        }
        onLoadFailed: root.settingsSearchIndex = []
    }
    property string settingsSearchQuery: ""
    readonly property var settingsSearchResults: {
        const q = root.settingsSearchQuery.trim().toLowerCase();
        if (q.length === 0) return [];
        const out = [];
        for (const page of root.settingsSearchIndex) {
            const pageName = Translation.tr(page.page);
            if (pageName.toLowerCase().includes(q))
                out.push({ page: page.page, section: "", label: pageName });
            for (const section of page.sections) {
                const sectionName = Translation.tr(section);
                if (sectionName.toLowerCase().includes(q) || section.toLowerCase().includes(q))
                    out.push({ page: page.page, section: section, label: pageName + " · " + sectionName });
            }
        }
        return out.slice(0, 12);
    }
    function activateSearchResult(result) {
        // 注意：深链那边比较的是 pages[i].name（翻译后的名字，如「桌面」），
        // 传英文 key 会 findIndex 返回 -1、什么都不发生。
        const pageName = Translation.tr(result.page);
        GlobalStates.settingsPage = result.section.length > 0
            ? pageName + ":" + Translation.tr(result.section)
            : pageName;
        root.settingsSearchQuery = "";
        settingsSearchInput.text = "";
    }

    onCurrentPageChanged: {
        const pageName = root.pages[currentPage]?.name ?? ""
        if (pageName === Translation.tr("About")) {
            if (SystemInfo.cpu === "") SystemInfo.refresh()
            Updates.refresh()
        }
    }
    
    property var pages: {
        let list = [
            { name: Translation.tr("Quick"),      icon: "instant_mix",    component: Qt.resolvedUrl("pages/QuickConfig.qml") },
            { name: Translation.tr("General"),    icon: "browse",         component: Qt.resolvedUrl("pages/GeneralConfig.qml") },
            { name: Translation.tr("Bar"),        icon: "toast",          iconRotation: 180, component: Qt.resolvedUrl("pages/BarConfig.qml") },
            { name: Translation.tr("Desktop"),    icon: "texture",        component: Qt.resolvedUrl("pages/BackgroundConfig.qml") },
            { name: Translation.tr("Interface"),  icon: "bottom_app_bar", component: Qt.resolvedUrl("pages/InterfaceConfig.qml") },
            { name: Translation.tr("Services"),   icon: "settings",       component: Qt.resolvedUrl("pages/ServicesConfig.qml") },
        ]
        if (WM.compositor === "hyprland") {
                    list.push({ name: Translation.tr("Hyprland"), icon: "select_window_2", component: Qt.resolvedUrl("pages/HyprlandConfig.qml") })
                }
        if (WM.compositor === "niri") {
                    list.push({ name: Translation.tr("Niri"), icon: "select_window_2", component: Qt.resolvedUrl("pages/NiriConfig.qml") })
                }
        list.push({ name: Translation.tr("About"), icon: "info", component: Qt.resolvedUrl("pages/About.qml") })
        return list
    }

    Component.onCompleted: {
        Config.readWriteDelay = 0
        Qt.callLater(() => {
            for (let i = 0; i < root.pages.length; i++) {
                let loader = pagesRepeater.itemAt(i)
                if (loader) loader.active = true
            }
            if (profileLoader) profileLoader.active = true
        })
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            Rectangle {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 0
                implicitWidth: navRail.expanded ? 195 : fab.baseSize
                color: isMinimal ? "transparent" : Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.normal

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                NavigationRail {
                    id: navRail
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 20 }
                    spacing: 10
                    expanded: root.width > 900

                    RowLayout {
                        visible: true
                        spacing: 10
                        Layout.fillWidth: true
                        Layout.margins: isMinimal ? 0 : 5
                        Layout.topMargin: 15
                        Layout.bottomMargin: isMinimal ? -30 : 0

                        Rectangle {
                            id: avatarRect
                            width: 48
                            height: 48
                            radius: width / 2
                            color: Appearance.colors.colPrimaryContainer

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: Config.options.profile.avatarPath !== "" 
                                    ? "file://" + Config.options.profile.avatarPicture 
                                    : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                                sourceSize.width: avatarImage.width * 2
                                sourceSize.height: avatarImage.height * 2
                                fillMode: Image.PreserveAspectCrop
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: avatarRect.width
                                        height: avatarRect.height
                                        radius: avatarRect.radius
                                    }
                                }
                                onStatusChanged: {
                                    if (status === Image.Error)
                                        visible = false
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "account_circle"
                                iconSize: 32
                                color: Appearance.colors.colOnPrimaryContainer
                                visible: avatarImage.status === Image.Error
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            visible: !isMinimal

                            StyledText {
                                text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100
                            }

                            StyledText {
                                id: distroText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100

                                text: {
                                    const d = Config.options.profile.descriptionText
                                    if (d === "::uptime::") return Translation.tr("Up • %1").arg(DateTime.uptime)
                                    return SystemInfo.distroName
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showingProfile = !root.showingProfile
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: isMinimal ? 50 : 160
                        Layout.topMargin: isMinimal ? 30 : -5
                        Layout.bottomMargin: isMinimal ? -30 : 0
                        height: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.2; color: Appearance.colors.colOutline }
                            GradientStop { position: 0.8; color: Appearance.colors.colOutline }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.15
                    }

                    FloatingActionButton {
                        id: fab
                        visible: !isMinimal
                        Layout.bottomMargin: -25
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }
                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: fab.justCopied = false
                        }
                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    // 搜索框：用与侧栏一致的扁平样式（Material 的填充式输入框在这里太突兀），
                    // 边距对齐导航项（NavigationRail 左缩进 20 + 内容 margins 5）。
                    // 注：StyledTextInput 的根是 TextInput，没有 placeholderText，
                    // 所以占位文字用一个单独的 StyledText 覆盖。
                    Rectangle {
                        id: settingsSearchBox
                        Layout.fillWidth: true
                        // 与「配置文件」按钮、导航项一致：满宽（它们都没有左右边距）
                        // 注意：「配置文件」那个 FloatingActionButton 有 bottomMargin: -25，
                        // 会把后面的元素往上吸，这里要补回 25 再加一点间距，否则会重叠。
                        Layout.topMargin: 33
                        Layout.bottomMargin: 10
                        visible: navRail.expanded
                        implicitHeight: 38
                        // colLayer2 和侧栏底色太接近，几乎看不出是个输入框，补一层描边
                        readonly property bool focused: settingsSearchInput.activeFocus
                        color: focused ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
                        border.width: 1
                        border.color: Appearance.colors.colOutline
                        radius: Appearance.rounding.normal

                        Behavior on color {
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        // 聚焦时的强调描边（用透明度做动画，避免对 border.color 直接做 Behavior）
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colPrimary
                            opacity: settingsSearchBox.focused ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                        }

                        MaterialSymbol {
                            id: settingsSearchIcon
                            anchors {
                                left: parent.left
                                leftMargin: 9
                                verticalCenter: parent.verticalCenter
                            }
                            text: "search"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.55
                        }

                        StyledText {
                            anchors {
                                left: settingsSearchIcon.right
                                leftMargin: 7
                                right: parent.right
                                rightMargin: 9
                                verticalCenter: parent.verticalCenter
                            }
                            visible: settingsSearchInput.text.length === 0
                            text: Translation.tr("Search settings")
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.5
                        }

                        // 有内容时出现的清空按钮
                        MaterialSymbol {
                            id: settingsSearchClear
                            anchors {
                                right: parent.right
                                rightMargin: 9
                                verticalCenter: parent.verticalCenter
                            }
                            text: "close"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer1
                            opacity: settingsSearchInput.text.length > 0 ? 0.7 : 0
                            visible: opacity > 0.01
                            Behavior on opacity {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    settingsSearchInput.text = "";
                                    root.settingsSearchQuery = "";
                                }
                            }
                        }

                        StyledTextInput {
                            id: settingsSearchInput
                            anchors {
                                left: settingsSearchIcon.right
                                leftMargin: 7
                                right: settingsSearchClear.left
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            Keys.onEscapePressed: {
                                text = "";
                                root.settingsSearchQuery = "";
                            }
                            onTextChanged: root.settingsSearchQuery = text
                            onAccepted: {
                                const results = root.settingsSearchResults;
                                if (results.length > 0)
                                    root.activateSearchResult(results[0]);
                            }
                        }
                    }

                    ListView {
                        id: settingsSearchResultsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 5
                        // 用透明度驱动显隐：visible 直接跟查询长度会让淡入动画来不及播
                        opacity: navRail.expanded && root.settingsSearchQuery.trim().length > 0 ? 1 : 0
                        visible: opacity > 0.01
                        clip: true
                        spacing: 2
                        model: root.settingsSearchResults
                        Behavior on opacity {
                            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                        }
                        delegate: NavigationRailButton {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            expanded: true
                            buttonIcon: "search"
                            buttonText: modelData.label
                            showToggledHighlight: false
                            onPressed: root.activateSearchResult(modelData)

                            // 结果项错开进场（每项延迟 25ms，最多累计 150ms）
                            opacity: 0
                            Component.onCompleted: appearTimer.start()
                            Timer {
                                id: appearTimer
                                interval: Math.min(index * 25, 150)
                                onTriggered: parent.opacity = 1
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    // 导航项放进可滚动容器：加了搜索框之后，侧栏内容变高，
                    // 窗口不够高时最后一项（关于）会溢出面板外。
                    Flickable {
                        id: settingsNavScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: settingsNavArray.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        NavigationRailTabArray {
                        id: settingsNavArray
                        width: settingsNavScroll.width
                        visible: !(navRail.expanded && root.settingsSearchQuery.trim().length > 0)
                        currentIndex: root.currentPage
                        expanded: navRail.expanded
                        colToggled: root.showingProfile ? "transparent" : Appearance.colors.colSecondaryContainer
                        Repeater {
                            model: root.pages
                            NavigationRailButton {
                                required property var index
                                required property var modelData
                                toggled: root.currentPage === index && !root.showingProfile
                                onPressed: {
                                    root.currentPage = index
                                    root.showingProfile = false
                                }
                                expanded: navRail.expanded
                                buttonIcon: modelData.icon
                                buttonIconRotation: modelData.iconRotation || 0
                                buttonText: modelData.name
                                showToggledHighlight: false
                            }
                        }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut

                Item {
                    anchors.fill: parent

                    Repeater {
                        id: pagesRepeater
                        model: root.pages
                        Loader {
                            id: pageLoader
                            required property var modelData
                            required property var index
                            source: modelData.component

                            active: Config.ready && (root.currentPage === index || item !== null)

                            anchors.fill: parent

                            property bool isActive: root.currentPage === index && !root.showingProfile
                            opacity: isActive ? 1 : 0
                            enabled: isActive
                            visible: isActive
                            anchors.topMargin: isActive ? 0 : 12

                            onLoaded: {
                                if (root.currentPage === index) {
                                    GlobalStates.currentPageInstance = item;
                                }
                            }

                            onIsActiveChanged: {
                                if (isActive && item) {
                                    GlobalStates.currentPageInstance = item;
                                } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                    GlobalStates.currentPageInstance = null;
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.topMargin {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Loader {
                        id: profileLoader
                        active: false
                        anchors.fill: parent
                        source: Qt.resolvedUrl("pages/Profile.qml")

                        property bool isActive: root.showingProfile
                        opacity: isActive ? 1 : 0
                        enabled: isActive
                        visible: isActive
                        anchors.topMargin: isActive ? 0 : 12

                        onIsActiveChanged: {
                            if (isActive && item) {
                                GlobalStates.currentPageInstance = item;
                            } else if (!isActive && GlobalStates.currentPageInstance === item) {
                                GlobalStates.currentPageInstance = null;
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on anchors.topMargin {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }
}