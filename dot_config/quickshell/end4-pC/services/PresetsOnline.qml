pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    readonly property string thumbsDir: `${Quickshell.env("HOME")}/.cache/quickshell/presets_online_thumbs`
    readonly property string indexPath: `${Quickshell.env("HOME")}/.cache/quickshell/presets_online_index.json`
    readonly property real staleAfterMs: 6 * 60 * 60 * 1000

    property var entries: []
    property real lastFetched: 0
    readonly property bool stale: Date.now() - lastFetched > staleAfterMs
    property string error: ""
    property bool loading: false
    property string downloadingName: ""
    property int previewLimit: 3

    readonly property var thumbSet: {
        const names = new Set();
        for (let i = 0; i < thumbsModel.count; i++)
            names.add(thumbsModel.get(i, "fileName"));
        return names;
    }

    function thumbFor(entry) {
        return root.thumbSet.has(entry.name + ".jpg") ? `${root.thumbsDir}/${entry.name}.jpg` : "";
    }

    property int thumbAttempts: 0

    function generateThumbs() {
        if (thumbProc.running) return;
        const missing = root.entries.filter(e => !root.thumbSet.has(e.name + ".jpg"));
        if (missing.length === 0) {
            root.thumbAttempts = 0;
            return;
        }
        const dir = root.thumbsDir;
        let script = `D=${root.shQuote(dir)}; gen() { out="$D/$1.jpg"; [ -s "$out" ] && return; if curl -sSL -m 40 -o "$D/.$1.src" "$2" && magick "$D/.$1.src" -auto-orient -resize 720x -quality 82 "jpg:$D/.$1.part" && mv -f "$D/.$1.part" "$out"; then echo "THUMB ok $1"; else echo "THUMB fail $1"; fi; rm -f "$D/.$1.src" "$D/.$1.part"; }; `;
        missing.forEach((e, i) => {
            script += `gen ${root.shQuote(e.name)} ${root.shQuote(e.screenshot)} & `;
            if (i % 4 === 3) script += "wait; ";
        });
        script += "wait";
        thumbProc.command = ["bash", "-c", script];
        thumbProc.running = true;
    }

    function ensureFresh() {
        if (root.loading) return;
        if (root.entries.length === 0 || root.stale) root.refresh();
        else root.generateThumbs();
    }

    FolderListModel {
        id: thumbsModel
        folder: ""
        showDirs: false
        nameFilters: ["*.jpg"]
    }

    FileView {
        id: indexFile
        path: root.indexPath
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(indexFile.text());
                if (Array.isArray(saved.entries)) {
                    root.entries = saved.entries;
                    root.lastFetched = saved.time ?? 0;
                }
            } catch (e) {}
        }
    }

    Process {
        id: prepareProc
        running: true
        command: ["bash", "-c", `mkdir -p ${root.shQuote(root.thumbsDir)} && for f in ${root.shQuote(root.thumbsDir)}/*.jpg; do [ -e "$f" ] || continue; magick identify -quiet "$f" >/dev/null 2>&1 || rm -f "$f"; done; rm -f ${root.shQuote(root.thumbsDir)}/.*.part ${root.shQuote(root.thumbsDir)}/.*.src ${root.shQuote(root.thumbsDir)}/.*.tmp`]
        onExited: {
            thumbsModel.folder = Qt.resolvedUrl(root.thumbsDir);
            root.generateThumbs();
        }
    }

    Process {
        id: thumbProc
        onExited: code => {
            root.thumbAttempts++;
            if (root.thumbAttempts < 3) Qt.callLater(root.generateThumbs);
        }
    }

    readonly property var pending: {
        const downloaded = new Set();
        for (let i = 0; i < Presets.onlineFolderModel.count; i++)
            downloaded.add(Presets.onlineFolderModel.get(i, "fileName").replace(".json", ""));
        return root.entries.filter(p => !downloaded.has(p.name));
    }

    function refresh() {
        root.loading = true;
        root.error = "";
        listProc.running = false;
        listProc.running = true;
    }

    function rawUrl(path) {
        return `https://raw.githubusercontent.com/Blapples/wallpapers/main/${path.split("/").map(encodeURIComponent).join("/")}`;
    }

    function cacheDir() {
        return `${Quickshell.env("HOME")}/.cache/quickshell/presets`;
    }

    function assetDir(name) {
        return `${root.cacheDir()}/assets/${name}`;
    }

    function shQuote(str) {
        return "'" + String(str).replace(/'/g, "'\"'\"'") + "'";
    }

    function fail(message) {
        root.error = message;
        root.downloadingName = "";
    }

    function startAssets(name, stagingJsonPath, folderAssets, wallpaperFiles) {
        const dir = root.assetDir(name);
        assetsProc.entryName = name;
        assetsProc.stagingJsonPath = stagingJsonPath;
        assetsProc.assetCacheDirPath = dir;

        const wallpaperAssets = wallpaperFiles.map(f => ({ filename: f.split("/").pop(), url: root.rawUrl(f) }));
        const seen = new Set();
        const toDownload = [...wallpaperAssets, ...folderAssets].filter(a => {
            if (seen.has(a.filename)) return false;
            seen.add(a.filename);
            return true;
        });
        assetsProc.assetFilenames = toDownload.map(a => a.filename);

        let cmd = `mkdir -p ${root.shQuote(dir)}`;
        for (const asset of toDownload)
            cmd += ` && curl -sSL ${root.shQuote(asset.url)} -o ${root.shQuote(dir + "/" + asset.filename)}`;
        assetsProc.command = ["bash", "-c", cmd];
        assetsProc.running = true;
    }

    function download(entry) {
        if (root.downloadingName !== "") return;
        root.error = "";
        root.downloadingName = entry.name;
        const staging = `${root.cacheDir()}/.${entry.name}.online.json.tmp`;
        jsonProc.entryName = entry.name;
        jsonProc.entryAssets = entry.assets;
        jsonProc.metaUrl = entry.metaUrl;
        jsonProc.stagingJsonPath = staging;
        jsonProc.command = ["bash", "-c",
            `mkdir -p ${root.shQuote(root.cacheDir())} && curl -sSL ${root.shQuote(entry.jsonUrl)} -o ${root.shQuote(staging)}`];
        jsonProc.running = true;
    }

    Process {
        id: listProc
        command: ["curl", "-sSL", "-w", "\nHTTP_STATUS:%{http_code}",
            "-H", "Accept: application/vnd.github+json",
            "-H", "User-Agent: end4-pC-quickshell",
            "https://api.github.com/repos/Blapples/wallpapers/git/trees/main?recursive=1"]
        stdout: StdioCollector { id: listCollector }
        onExited: code => {
            root.loading = false;
            const raw = listCollector.text;
            const statusMatch = raw.match(/HTTP_STATUS:(\d+)\s*$/);
            const body = statusMatch ? raw.slice(0, statusMatch.index) : raw;
            try {
                const data = JSON.parse(body);
                if (!Array.isArray(data.tree)) throw new Error("unexpected response");

                const prefix = "presets/";
                const imageExt = /\.(png|jpe?g|webp)$/i;
                const groups = {};

                for (const entry of data.tree) {
                    if (entry.type !== "blob" || !entry.path.startsWith(prefix)) continue;
                    const rel = entry.path.slice(prefix.length);
                    const slashIdx = rel.indexOf("/");
                    if (slashIdx === -1) continue;
                    const folder = rel.slice(0, slashIdx);
                    const filename = rel.slice(slashIdx + 1);
                    if (filename.includes("/")) continue;

                    if (!groups[folder]) groups[folder] = { images: [], assets: [], jsonPath: "", metaPath: "" };
                    if (filename.toLowerCase() === "meta.json") {
                        groups[folder].metaPath = entry.path;
                    } else if (/\.json$/i.test(filename)) {
                        groups[folder].jsonPath = entry.path;
                    } else {
                        groups[folder].assets.push({ path: entry.path, filename });
                        if (imageExt.test(filename)) groups[folder].images.push({ path: entry.path, filename });
                    }
                }

                const presets = [];
                for (const folder in groups) {
                    const g = groups[folder];
                    if (!g.jsonPath || g.images.length === 0) continue;

                    const exactPreview = /^preview\.png$/i;
                    const genericPreview = /^preview?\.png$/i;
                    const nonGeneric = g.images.filter(img => !genericPreview.test(img.filename));
                    const mainCandidates = nonGeneric.length > 0 ? nonGeneric : g.images;
                    const main = g.images.find(img => exactPreview.test(img.filename))
                        || mainCandidates.find(img => /desktop/i.test(img.filename))
                        || mainCandidates.find(img => !/pfp|avatar|banner/i.test(img.filename))
                        || mainCandidates[0];

                    presets.push({
                        name: folder,
                        title: folder.replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                        jsonUrl: root.rawUrl(g.jsonPath),
                        metaUrl: g.metaPath ? root.rawUrl(g.metaPath) : "",
                        screenshot: root.rawUrl(main.path),
                        assets: g.assets.map(a => ({ filename: a.filename, url: root.rawUrl(a.path) }))
                    });
                }
                presets.sort((a, b) => a.title.localeCompare(b.title));
                root.previewLimit = 3;
                root.entries = presets;
                root.lastFetched = Date.now();
                indexFile.setText(JSON.stringify({ time: root.lastFetched, entries: presets }));
                root.generateThumbs();
            } catch (e) {
                root.entries = [];
                root.error = Translation.tr("Failed to load online presets");
            }
        }
    }

    Process {
        id: jsonProc
        property string entryName: ""
        property var entryAssets: []
        property string metaUrl: ""
        property string stagingJsonPath: ""
        onExited: code => {
            if (code !== 0) {
                root.fail(Translation.tr("Failed to download preset"));
                return;
            }
            if (jsonProc.metaUrl !== "") {
                metaProc.entryName = jsonProc.entryName;
                metaProc.entryAssets = jsonProc.entryAssets;
                metaProc.stagingJsonPath = jsonProc.stagingJsonPath;
                metaProc.command = ["curl", "-sSL", jsonProc.metaUrl];
                metaProc.running = true;
            } else {
                root.startAssets(jsonProc.entryName, jsonProc.stagingJsonPath, jsonProc.entryAssets, []);
            }
        }
    }

    Process {
        id: metaProc
        property string entryName: ""
        property var entryAssets: []
        property string stagingJsonPath: ""
        stdout: StdioCollector { id: metaCollector }
        onExited: code => {
            let wallpaperFiles = [];
            if (code === 0) {
                try {
                    const meta = JSON.parse(metaCollector.text);
                    if (Array.isArray(meta.wallpapers)) wallpaperFiles = meta.wallpapers;
                } catch (e) {}
            }
            root.startAssets(metaProc.entryName, metaProc.stagingJsonPath, metaProc.entryAssets, wallpaperFiles);
        }
    }

    Process {
        id: assetsProc
        property string entryName: ""
        property string stagingJsonPath: ""
        property string assetCacheDirPath: ""
        property var assetFilenames: []
        onExited: code => {
            if (code !== 0) {
                root.fail(Translation.tr("Failed to download preset assets"));
                return;
            }
            const finalJsonPath = `${root.cacheDir()}/${assetsProc.entryName}.json`;
            const jqFilter = '$files as $files | walk(if type == "string" then ((split("/") | last) as $base | if ($files | index($base)) then ($dir + "/" + $base) else . end) else . end) | if has("profile") then .profile.avatarPath = $dir else . end | ._presetMeta.source = "online"';
            const filesJson = JSON.stringify(assetsProc.assetFilenames);
            const cmd = `jq --arg dir ${root.shQuote(assetsProc.assetCacheDirPath)} --argjson files ${root.shQuote(filesJson)} ${root.shQuote(jqFilter)} ${root.shQuote(assetsProc.stagingJsonPath)} > ${root.shQuote(finalJsonPath)} && rm -f ${root.shQuote(assetsProc.stagingJsonPath)}`;
            rewriteProc.command = ["bash", "-c", cmd];
            rewriteProc.running = true;
        }
    }

    Process {
        id: rewriteProc
        onExited: code => {
            if (code === 0) {
                Presets.refreshOnline();
                root.downloadingName = "";
            } else {
                root.fail(Translation.tr("Failed to finalize preset"));
            }
        }
    }
}
