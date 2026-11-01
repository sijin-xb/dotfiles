pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * Local wallpaper browser in carousel form.
 *
 * Reads the same directory the grid uses (Wallpapers.folderModel) but presents
 * it as a skewed horizontal carousel, with a floating filter bar for
 * All / History / Video / per-colour buckets and inline search.
 */
Item {
    id: root

    signal wallpaperSelected(string path)

    property string currentFilter: "All"
    property bool searchOpen: false
    property string searchQuery: ""
    property var colourLookup: ({})
    property var availableBuckets: []
    property var historyList: []
    property bool loading: true

    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/wallpapers`)
    readonly property string historyPath: `${root.cacheDir}/history.txt`
    readonly property string indexerScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/wallpapers/index_colors.py`)
    readonly property string sourceDir: Wallpapers.effectiveDirectory

    ListModel { id: displayModel }

    function isVideoFile(fileName) {
        return Images.isValidVideoByName(String(fileName));
    }

    function rebuildModel() {
        displayModel.clear();
        carousel.ready = false;

        const folder = Wallpapers.folderModel;
        if (!folder || folder.count === 0) {
            root.availableBuckets = [];
            return;
        }

        let items = [];
        const seen = {};

        for (let i = 0; i < folder.count; i++) {
            if (folder.get(i, "fileIsDir")) continue;

            const fileName = String(folder.get(i, "fileName") || "");
            let filePath = folder.get(i, "filePath")
                || FileUtils.trimFileProtocol(String(folder.get(i, "fileURL") || ""));
            if (!fileName || !filePath || seen[fileName]) continue;
            seen[fileName] = true;

            const isVideo = root.isVideoFile(fileName);
            const lookup = root.colourLookup[fileName];
            items.push({
                "fileName": fileName,
                "filePath": filePath,
                "isVideo": isVideo,
                "bucket": isVideo ? "Video" : (lookup ? lookup.bucket : "Monochrome")
            });
        }

        const buckets = {};
        for (const it of items) if (!it.isVideo) buckets[it.bucket] = true;
        root.availableBuckets = Object.keys(buckets);

        let filtered = items;
        if (root.currentFilter === "Video") {
            filtered = items.filter(it => it.isVideo);
        } else if (root.currentFilter === "History") {
            const byName = {};
            for (const it of items) byName[it.fileName] = it;
            filtered = [];
            for (const name of root.historyList) {
                if (byName[name]) {
                    filtered.push(byName[name]);
                    delete byName[name];
                }
            }
        } else if (root.currentFilter !== "All") {
            filtered = items.filter(it => !it.isVideo && it.bucket === root.currentFilter);
        }

        for (const it of filtered) displayModel.append(it);

        Qt.callLater(() => {
            carousel.ready = displayModel.count > 0;
            carousel.positionOn(Config.options.background.wallpaperPath);
        });
    }

    function recordHistory(fileName) {
        const path = root.historyPath;
        const safe = String(fileName).replace(/'/g, "'\\''");
        const script =
            "mkdir -p \"$(dirname '" + path + "')\" && " +
            "{ if [ -f '" + path + "' ]; then " +
            "grep -v -F -x '" + safe + "' '" + path + "' > '" + path + ".tmp' 2>/dev/null || true; " +
            "printf '%s\\n' '" + safe + "' | cat - '" + path + ".tmp' > '" + path + "' 2>/dev/null; " +
            "rm -f '" + path + ".tmp'; " +
            "else printf '%s\\n' '" + safe + "' > '" + path + "'; fi; }";
        Quickshell.execDetached(["bash", "-c", script]);
    }

    function refreshIndex() {
        if (!root.sourceDir) return;
        root.loading = true;
        colourIndexer.running = false;
        colourIndexer.running = true;
    }

    function handleSelect(filePath) {
        if (!filePath || filePath.length === 0) return;
        const fileName = filePath.split("/").pop();
        root.recordHistory(fileName);
        root.wallpaperSelected(filePath);
    }

    Process {
        id: colourIndexer
        command: ["python3", root.indexerScript, root.sourceDir, root.cacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    const lookup = {};
                    for (const item of (data.items || [])) {
                        if (item.fileName) lookup[item.fileName] = { "hex": item.hex, "bucket": item.bucket };
                    }
                    root.colourLookup = lookup;
                } catch (error) {
                    console.log("[LocalWallpaperCarousel] colour index parse failed:", error);
                }
                root.loading = false;
                root.rebuildModel();
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.rebuildModel();
            }
        }
    }

    Process {
        id: historyReader
        command: ["bash", "-c", "mkdir -p '" + root.cacheDir + "'; cat '" + root.historyPath + "' 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.historyList = this.text.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                if (root.currentFilter === "History") root.rebuildModel();
            }
        }
    }

    Timer {
        id: indexDebounce
        interval: 200
        onTriggered: root.refreshIndex()
    }

    onSourceDirChanged: indexDebounce.restart()

    Component.onCompleted: {
        historyReader.running = true;
        root.refreshIndex();
    }

    Connections {
        target: Wallpapers
        function onChanged() { root.rebuildModel(); }
        function onThumbnailGenerated(directory) { root.rebuildModel(); }
    }

    Connections {
        target: Wallpapers.folderModel
        function onCountChanged() { indexDebounce.restart(); }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.topMargin: 6

            WallpaperFilterBar {
                anchors.centerIn: parent
                currentFilter: root.currentFilter
                availableBuckets: root.availableBuckets
                searchOpen: root.searchOpen
                searchQuery: root.searchQuery
                onFilterSelected: filter => {
                    root.currentFilter = filter;
                    root.rebuildModel();
                }
                onSearchTriggered: query => root.searchQuery = query
            }
        }

        WallpaperCarousel {
            id: carousel
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: displayModel
            onWallpaperSelected: (filePath, isVideo) => root.handleSelect(filePath)
        }
    }

    MaterialLoadingIndicator {
        anchors.centerIn: parent
        visible: root.loading && displayModel.count === 0
        loading: root.loading
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.loading && displayModel.count === 0
        text: root.currentFilter === "History"
            ? Translation.tr("Nothing here yet")
            : Translation.tr("No wallpapers found")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.large
    }

    function moveSelection(delta) { carousel.moveSelection(delta); }
    function activateCurrent() { carousel.activateCurrent(); }
}
