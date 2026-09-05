import QtQuick
import QtWebSockets
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * Desktop lyrics overlay for MoeKoe Music (萌音).
 *
 * Connects to MoeKoe Music's WebSocket API (ws://127.0.0.1:6520/) and displays
 * the current lyric line at the bottom of the screen, following the matugen
 * palette. The window is fully click-through and hides when playback stops.
 *
 * Lyrics pushed by MoeKoe are Kugou KRC style: "[startMs,durMs,0]<s,d,0>word..."
 * with an optional "[language:<base64 json>]" tag carrying per-line Chinese
 * translations. Standard LRC ([mm:ss.xx]) is also supported as a fallback.
 *
 * Toggle with: qs -c end4-pC ipc call desktoplyrics toggle
 */
PanelWindow {
    id: root

    readonly property string wsUrl: "ws://127.0.0.1:6520/"
    property bool enabled: true
    property bool connected: false
    property bool isPlaying: false
    property real currentTime: 0
    property real lyricOffset: 0
    property string songName: ""
    property var lyricLines: [] // [{ start: seconds, text: string, trans: string }]
    property int currentLineIndex: -1
    readonly property string currentText: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? lyricLines[currentLineIndex].text : ""
    readonly property string currentTrans: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? lyricLines[currentLineIndex].trans : ""
    readonly property string nextText: (currentLineIndex + 1 >= 0 && currentLineIndex + 1 < lyricLines.length) ? lyricLines[currentLineIndex + 1].text : ""
    readonly property bool shouldShow: enabled && connected && isPlaying && currentText.length > 0

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
            const krc = raw.match(krcRe);
            const lrc = raw.match(lrcRe);
            if (krc) {
                start = Number(krc[1]) / 1000;
                text = raw.slice(krc[0].length).replace(/<[^>]*>/g, "").trim();
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
                trans: (trans !== text) ? trans.trim() : ""
            });
        }
        lines.sort((a, b) => a.start - b.start);
        return lines;
    }

    function updateCurrentLine() {
        const t = currentTime + lyricOffset;
        let index = -1;
        for (let i = 0; i < lyricLines.length; i++) {
            if (lyricLines[i].start <= t + 0.05)
                index = i;
            else
                break;
        }
        currentLineIndex = index;
    }

    function handleMessage(message) {
        let msg;
        try {
            msg = JSON.parse(message);
        } catch (e) {
            return;
        }
        const data = msg?.data;
        if (msg.type === "lyrics" && data) {
            currentTime = data.currentTime ?? currentTime;
            const song = data.currentSong ?? {};
            songName = song.name ?? song.songName ?? song.title ?? "";
            lyricLines = parseLyrics(data.lyricsData ?? "");
            const offsetMatch = (data.lyricsData ?? "").match(/\[offset:(-?\d+)\]/);
            lyricOffset = offsetMatch ? -Number(offsetMatch[1]) / 1000 : 0;
            updateCurrentLine();
        } else if (msg.type === "playerState" && data) {
            isPlaying = data.isPlaying ?? isPlaying;
            // MoeKoe always pushes currentTime: 0 in playerState — ignore it,
            // real progress arrives in lyrics messages and is interpolated locally
            const t = data.currentTime;
            if (t > 0)
                currentTime = t;
            updateCurrentLine();
        }
    }

    onCurrentTimeChanged: updateCurrentLine()
    onLyricLinesChanged: updateCurrentLine()

    // Smooth progress between server updates
    Timer {
        interval: 250
        running: root.shouldShow && root.isPlaying
        repeat: true
        onTriggered: {
            if (root.lyricLines.length > 0) {
                root.currentTime = root.currentTime + 0.25;
                if (root.currentLineIndex >= 0 && root.currentLineIndex + 1 < root.lyricLines.length) {
                    const next = root.lyricLines[root.currentLineIndex + 1];
                    if (root.currentTime > next.start + 1.5) // drifted too far, wait for server
                        root.currentTime = next.start - 1.5;
                }
            }
        }
    }

    WebSocket {
        id: socket
        url: root.wsUrl
        onTextMessageReceived: message => root.handleMessage(message)
        onStatusChanged: status => {
            if (status === WebSocket.Open) {
                root.connected = true;
                reconnectTimer.stop();
            } else if (status === WebSocket.Closed || status === WebSocket.Error) {
                root.connected = false;
                root.lyricLines = [];
                root.currentLineIndex = -1;
                reconnectTimer.restart();
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 3000
        running: root.enabled
        repeat: true
        onTriggered: {
            if (root.enabled && !root.connected && socket.status !== WebSocket.Connecting) {
                socket.url = "";
                socket.url = root.wsUrl;
                socket.active = true;
            }
        }
    }

    IpcHandler {
        target: "desktoplyrics"
        function toggle(): void {
            root.enabled = !root.enabled;
        }
        function show(): void {
            root.enabled = true;
        }
        function hide(): void {
            root.enabled = false;
        }
    }

    anchors {
        bottom: true
        left: true
        right: true
    }
    // Sit above the dock bar
    margins.bottom: 90
    // Anchored children do not contribute implicit sizes: the window needs an
    // explicit height, otherwise it collapses to 0 and stays invisible
    // Anchored children do not contribute implicit sizes: the window needs an
    // explicit height, otherwise it collapses to 0 and stays invisible
    implicitHeight: 180
    exclusiveZone: -1
    // Fully click-through: lyrics never block the mouse
    mask: Region {}

    color: "transparent"

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
            // Keep the current line centered and scroll smoothly to it
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
                    text: parent.modelData.text
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
