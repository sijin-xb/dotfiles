import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions as CF
import qs.services

/**
 * Universal Desktop Lyrics Overlay with Multi-Player Offset Compensation.
 *
 * Automatically adapts to any active MPRIS player (KA Music, Spotify, MoeKoe,
 * browsers, etc.) via MprisController.activePlayer.
 *
 * Fetches high-precision Kugou KRC lyrics via python3 scripts/lyrics/kugou_lyrics.py
 * with local caching and lrclib fallback.
 *
 * Features automatic per-player latency compensation (Spotify +450ms, browsers +300ms,
 * KA Music +150ms) plus runtime manual fine-tuning via IPC commands.
 *
 * IPC commands:
 *   qs -c end4-pC ipc call desktoplyrics toggle
 *   qs -c end4-pC ipc call desktoplyrics offset_faster   (advance lyrics +0.1s)
 *   qs -c end4-pC ipc call desktoplyrics offset_slower   (delay lyrics -0.1s)
 *   qs -c end4-pC ipc call desktoplyrics set_offset 0.3  (set manual offset in seconds)
 *   qs -c end4-pC ipc call desktoplyrics offset_reset    (reset manual offset)
 *   qs -c end4-pC ipc call desktoplyrics get_offset      (print current offset info)
 */
PanelWindow {
    id: root

    readonly property bool enabled: Config.options.desktopLyricsEnabled
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: (activePlayer?.isPlaying ?? false) && (activePlayer?.playbackState === MprisPlaybackState.Playing || activePlayer?.playbackState === 1 || activePlayer?.isPlaying === true)

    property bool connected: true // Kept for backwards compatibility

    // Base playback progress (seconds) from MPRIS
    property real currentTime: 0

    // Song-level offset from [offset:ms] tag in lyric file
    property real rawLyricOffset: 0

    // Player-specific automatic latency compensation (in seconds, positive = lead/earlier)
    readonly property real playerOffset: {
        if (!activePlayer) return 0.0;
        const id = ((activePlayer.identity ?? "") + " " + (activePlayer.dbusName ?? "")).toLowerCase();
        // Spotify on Linux has known audio output buffer latency (~400-500ms)
        if (id.includes("spotify")) return 0.45;
        // Web browsers (Firefox, Chrome/Chromium) audio pipeline delay (~300ms)
        if (id.includes("firefox") || id.includes("chromium") || id.includes("chrome")) return 0.30;
        // KA Music (KugouAvaloniaPlayer) BASS audio engine buffer (~150ms)
        if (id.includes("kugou") || id.includes("ka music")) return 0.15;
        return 0.15; // General IPC/compositor latency compensation
    }

    // Runtime manual adjustment via IPC (in seconds)
    property real manualOffset: 0.0

    // Effective total offset (positive = lyrics show earlier, negative = lyrics show later)
    readonly property real effectiveOffset: rawLyricOffset + playerOffset + (Config.options.desktopLyricsOffset ?? 0.0) + manualOffset

    // Backwards-compatible alias for Pet.qml
    readonly property real lyricOffset: effectiveOffset

    property string songName: ""
    property string lastSongKey: ""
    property string lastRawLyrics: ""
    property var lyricLines: [] // [{ start: seconds, text: string, trans: string, words: [...] }]
    property int currentLineIndex: -1

    readonly property string currentText: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? lyricLines[currentLineIndex].text : ""
    readonly property string currentTrans: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? lyricLines[currentLineIndex].trans : ""
    readonly property string nextText: (currentLineIndex + 1 >= 0 && currentLineIndex + 1 < lyricLines.length) ? lyricLines[currentLineIndex + 1].text : ""
    readonly property bool shouldShow: enabled && isPlaying && currentText.length > 0

    function base64Decode(input) {
        const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const bytes = [];
        let buffer = 0;
        let bits = 0;
        for (let i = 0; i < input.length; i++) {
            const c = chars.indexOf(input[i]);
            if (c === -1)
                continue;
            buffer = (buffer << 6) | c;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                bytes.push((buffer >> bits) & 0xFF);
            }
        }
        return bytes;
    }

    function utf8Decode(bytes) {
        let out = "";
        let i = 0;
        while (i < bytes.length) {
            const b = bytes[i];
            if (b < 0x80) {
                out += String.fromCharCode(b);
                i += 1;
            } else if (b < 0xE0) {
                out += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
                i += 2;
            } else if (b < 0xF0) {
                out += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
                i += 3;
            } else {
                const cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
                const c = cp - 0x10000;
                out += String.fromCharCode(0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF));
                i += 4;
            }
        }
        return out;
    }

    function parseTranslations(lrcText) {
        const result = [];
        const match = lrcText.match(/\[language:([A-Za-z0-9+/=]*)\]/);
        if (!match)
            return result;
        try {
            let b64 = match[1];
            while (b64.length % 4 !== 0) b64 += "=";
            const bytes = base64Decode(b64);
            const json = JSON.parse(utf8Decode(bytes));
            const contents = json?.content ?? [];
            for (const block of contents)
                for (const line of (block?.lyricContent ?? []))
                    result.push(Array.isArray(line) ? line.join(" ") : String(line));
        } catch (e) {
            console.log("[DesktopLyrics] translation parse failed:", e);
        }
        return result;
    }

    function parseLyrics(lrcText) {
        const lines = [];
        if (!lrcText || typeof lrcText !== "string")
            return lines;
        const translations = parseTranslations(lrcText);
        const krcRe = /^\[(\d+),(\d+)(?:,\d+)?\]/;
        const lrcRe = /^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/;
        let transIndex = 0;
        for (let raw of lrcText.split("\n")) {
            raw = raw.replace(/\r/g, "").trim();
            if (raw.length === 0)
                continue;
            let start = -1;
            let text = "";
            let words = null;
            const krc = raw.match(krcRe);
            const lrc = raw.match(lrcRe);
            if (krc) {
                start = Number(krc[1]) / 1000;
                const body = raw.slice(krc[0].length);
                words = [];
                const wordRe = /<(\d+),(\d+),\d+>([^<]*)/g;
                let word;
                while ((word = wordRe.exec(body)) !== null) {
                    if (word[3].length === 0)
                        continue;
                    const rawStart = Number(word[1]);
                    const wordStart = rawStart >= krc[1] ? rawStart / 1000 : start + rawStart / 1000;
                    words.push({
                        text: word[3],
                        start: wordStart,
                        dur: Number(word[2]) / 1000
                    });
                    text += word[3];
                }
                text = text.trim();
            } else if (lrc) {
                const frac = lrc[3] !== undefined ? Number("0." + lrc[3]) : 0;
                start = Number(lrc[1]) * 60 + Number(lrc[2]) + frac;
                text = raw.slice(lrc[0].length).trim();
            } else {
                continue;
            }
            if (text.length === 0)
                continue;
            const trans = translations.length > 0 ? (translations[transIndex] ?? "") : "";
            transIndex += 1;
            lines.push({
                start: start,
                text: text,
                trans: (trans !== text) ? trans.trim() : "",
                words: (words && words.length > 0) ? words : null
            });
        }
        lines.sort((a, b) => a.start - b.start);
        return lines;
    }

    function updateCurrentLine() {
        const t = currentTime + effectiveOffset;
        let index = -1;
        for (let i = 0; i < lyricLines.length; i++) {
            if (lyricLines[i].start <= t + 0.05)
                index = i;
            else
                break;
        }
        currentLineIndex = index;
    }

    function fetchLyrics() {
        if (!enabled)
            return;

        const title = (activePlayer?.trackTitle ?? "").trim();
        const artist = (activePlayer?.trackArtist ?? "").trim();
        const dur = activePlayer?.length ?? 0;

        if (!title) {
            lyricLines = [];
            lastRawLyrics = "";
            lastSongKey = "";
            currentLineIndex = -1;
            return;
        }

        const songKey = `${title} - ${artist}`;
        if (songKey === lastSongKey && lyricLines.length > 0) {
            return;
        }

        lastSongKey = songKey;
        songName = title;

        lyricsProc.running = false;
        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/kugou_lyrics.py`,
            title,
            artist,
            String(Math.floor(dur))
        ];
        lyricsProc.running = true;
    }

    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function buildLineHtml(line) {
        if (!line.words)
            return escapeHtml(line.text);
        const t = currentTime + effectiveOffset;
        let html = "";
        for (const w of line.words) {
            const sung = t >= w.start + w.dur - 0.02;
            const color = sung ? Appearance.colors.colPrimary : Appearance.colors.colSecondary;
            html += `<font color="${color}">${escapeHtml(w.text)}</font>`;
        }
        return html;
    }

    Process {
        id: lyricsProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw) {
                    root.lyricLines = [];
                    root.currentLineIndex = -1;
                    return;
                }
                if (raw !== root.lastRawLyrics) {
                    root.lastRawLyrics = raw;
                    root.lyricLines = root.parseLyrics(raw);
                    const offsetMatch = raw.match(/\[offset:(-?\d+)\]/);
                    root.rawLyricOffset = offsetMatch ? -Number(offsetMatch[1]) / 1000 : 0;
                }
                root.updateCurrentLine();
            }
        }
    }

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() {
            root.currentTime = root.activePlayer?.position ?? 0;
            root.fetchLyrics();
        }
        function onTrackArtistChanged() {
            root.fetchLyrics();
        }
        function onPlaybackStateChanged() {
            const pos = root.activePlayer?.position ?? 0;
            if (pos > 0) root.currentTime = pos;
            root.updateCurrentLine();
        }
        function onPositionChanged() {
            const pos = root.activePlayer?.position ?? 0;
            if (Math.abs(root.currentTime - pos) > 0.25) {
                root.currentTime = pos;
                root.updateCurrentLine();
            }
        }
    }

    onActivePlayerChanged: {
        if (activePlayer) {
            currentTime = activePlayer.position ?? 0;
            fetchLyrics();
        } else {
            lyricLines = [];
            currentLineIndex = -1;
        }
    }

    onEnabledChanged: {
        if (enabled) {
            fetchLyrics();
        } else {
            lyricsProc.running = false;
            lyricLines = [];
            currentLineIndex = -1;
        }
    }

    Component.onCompleted: {
        if (enabled && activePlayer) {
            currentTime = activePlayer.position ?? 0;
            fetchLyrics();
        }
    }

    onCurrentTimeChanged: updateCurrentLine()
    onLyricLinesChanged: updateCurrentLine()
    onEffectiveOffsetChanged: updateCurrentLine()

    // 1. High-precision MPRIS poll timer: actively pulls updated position from D-Bus every 350ms
    Timer {
        id: mprisSyncTimer
        interval: 350
        repeat: true
        running: root.shouldShow && root.isPlaying && root.activePlayer !== null
        onTriggered: {
            if (root.activePlayer) {
                root.activePlayer.positionChanged();
                const realPos = root.activePlayer.position ?? 0;
                if (realPos > 0) {
                    const diff = realPos - root.currentTime;
                    // Smoothly pull currentTime towards real position if minor drift
                    if (Math.abs(diff) > 0.05 && Math.abs(diff) <= 0.5) {
                        root.currentTime += diff * 0.4;
                    } else if (Math.abs(diff) > 0.5) {
                        root.currentTime = realPos;
                    }
                    root.updateCurrentLine();
                }
            }
        }
    }

    // 2. Fluid 100ms local interpolation timer: smooth character-by-character color fill
    Timer {
        interval: 100
        running: root.shouldShow && root.isPlaying
        repeat: true
        onTriggered: {
            if (root.lyricLines.length > 0) {
                root.currentTime += 0.1;
            }
        }
    }

    IpcHandler {
        target: "desktoplyrics"
        function toggle(): void {
            Config.options.desktopLyricsEnabled = !Config.options.desktopLyricsEnabled;
        }
        function show(): void {
            Config.options.desktopLyricsEnabled = true;
            root.fetchLyrics();
        }
        function hide(): void {
            Config.options.desktopLyricsEnabled = false;
        }
        function open(): void {
            Config.options.desktopLyricsEnabled = true;
            root.fetchLyrics();
        }

        // 偏移微调命令：正数提前（快），负数延后（慢）
        function offset_faster(): string {
            root.manualOffset += 0.1;
            root.updateCurrentLine();
            const totalMs = (root.effectiveOffset * 1000).toFixed(0);
            return `歌词已提前 +100ms | 当前播放器: ${root.activePlayer?.identity ?? "未知"} | 总时间补偿: ${totalMs}ms`;
        }
        function offset_slower(): string {
            root.manualOffset -= 0.1;
            root.updateCurrentLine();
            const totalMs = (root.effectiveOffset * 1000).toFixed(0);
            return `歌词已延后 -100ms | 当前播放器: ${root.activePlayer?.identity ?? "未知"} | 总时间补偿: ${totalMs}ms`;
        }
        function set_offset(seconds: real): string {
            root.manualOffset = seconds;
            root.updateCurrentLine();
            const totalMs = (root.effectiveOffset * 1000).toFixed(0);
            return `手动偏移已设为: ${seconds}s | 总时间补偿: ${totalMs}ms`;
        }
        function offset_reset(): string {
            root.manualOffset = 0.0;
            root.updateCurrentLine();
            const totalMs = (root.effectiveOffset * 1000).toFixed(0);
            return `手动偏移已重置为 0s | 自动播放器补偿: ${totalMs}ms`;
        }
        function get_offset(): string {
            const pName = root.activePlayer?.identity ?? (root.activePlayer?.dbusName ?? "无播放器");
            const pComp = (root.playerOffset * 1000).toFixed(0);
            const mComp = (root.manualOffset * 1000).toFixed(0);
            const gComp = ((Config.options.desktopLyricsOffset ?? 0.0) * 1000).toFixed(0);
            const tagComp = (root.rawLyricOffset * 1000).toFixed(0);
            const totalMs = (root.effectiveOffset * 1000).toFixed(0);
            return `[歌词时间信息] 播放器: ${pName} | 自动补偿: ${pComp}ms | 手动偏移: ${mComp}ms | 全局设置: ${gComp}ms | 歌曲标签偏移: ${tagComp}ms | 总提前量: ${totalMs}ms`;
        }
    }

    anchors {
        bottom: true
        left: true
        right: true
    }
    margins.bottom: 90
    implicitHeight: 180
    exclusiveZone: -1
    mask: Region {}

    color: "transparent"

    visible: root.shouldShow || fadeOutLinger.running
    Timer {
        id: fadeOutLinger
        interval: 400
        running: !root.shouldShow
    }

    Item {
        id: lyricWrap
        anchors.fill: parent

        opacity: root.shouldShow ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.InOutQuad
            }
        }

        ListView {
            id: lyricList
            anchors.fill: parent
            clip: true
            interactive: false
            model: root.lyricLines
            currentIndex: root.currentLineIndex
            spacing: 7
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: height / 2 - 20
            preferredHighlightEnd: height / 2 + 20
            highlightMoveDuration: 420
            highlightMoveVelocity: -1
            snapMode: ListView.SnapToItem

            delegate: Column {
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === lyricList.currentIndex

                width: lyricList.width
                spacing: 3

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.isCurrent ? root.buildLineHtml(parent.modelData) : root.escapeHtml(parent.modelData.text)
                    textFormat: Text.RichText
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: parent.isCurrent ? 21 : 14
                    font.weight: parent.isCurrent ? Font.DemiBold : Font.Normal
                    color: parent.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    opacity: {
                        const d = Math.abs(index - lyricList.currentIndex);
                        return parent.isCurrent ? 1 : Math.max(0.14, 0.4 - d * 0.08);
                    }
                    horizontalAlignment: Text.AlignHCenter

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 300
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: parent.isCurrent && parent.modelData.trans.length > 0
                    text: parent.modelData.trans
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 13
                    color: Appearance.colors.colSecondary
                    opacity: 0.85
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
