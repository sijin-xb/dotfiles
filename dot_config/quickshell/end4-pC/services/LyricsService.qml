pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

/**
 * 统一歌词服务 —— 全 shell 唯一的歌词数据源。
 *
 * 数据源只有一条：用户的「通用桌面歌词源」
 *   scripts/desktopLyrics/splayer-ws.py   （SPlayer WebSocket 桥接，逐字 + 翻译 + 音译）
 * 拿不到 SPlayer 时退回 kugou_lyrics.py（按 MPRIS 元数据取词，MPRIS 没元数据时
 * 用音频指纹认歌）。
 *
 * 栏上的 Lyrics 组件、锁屏歌词、侧边栏播放器、桌面歌词浮层全部读这里，
 * 不再各自维护一份取词逻辑。
 *
 * 对外 API（旧接口保持兼容）：
 *   status        "loading" | "ok" | "not_found" | "no_info"
 *   slots         7 行窗口（当前行居中）
 *   before / after / total
 *   activeIndex   当前行在 lyricsLines 里的下标
 *   lyricsLines   [{ time, text, trans, roman, words }]
 *   restartLyrics()  强制重新取词
 *
 * 新增：
 *   source        "splayer" | "kugou" | "none"
 *   currentText / currentTrans / currentRoman / nextText
 *   currentTime / duration / isPlaying
 *   buildLineHtml(line)   逐字高亮 HTML（供桌面歌词浮层用）
 */
Singleton {
    id: root

    // ─── 播放器选择 ─────────────────────────────────────────────────────
    // 粘性：跟随正在播放的播放器，不被暂停的浏览器会话抢走
    // （Electron 播放器如 MoeKoeMusic 的 bus name 里带 chromium，会跟真浏览器打架）
    property MprisPlayer lyricPlayer: null
    readonly property MprisPlayer activePlayer: lyricPlayer ?? MprisController.activePlayer

    function pickPlayer() {
        const pool = MprisController.players ?? [];
        if (lyricPlayer) {
            if (pool.indexOf(lyricPlayer) === -1) {
                lyricPlayer = null;
            } else if (lyricPlayer.isPlaying) {
                return; // sticky: keep the current player while it plays
            }
        }
        const preferred = (Config.options.bar?.media?.preferredPlayer ?? "").trim().toLowerCase();
        let candidates = pool;
        if (preferred.length > 0) {
            const m = pool.filter(p =>
                ((p.identity ?? "") + " " + (p.desktopEntry ?? "")).toLowerCase().includes(preferred));
            if (m.length > 0)
                candidates = m;
        }
        const playing = candidates.filter(p => p.isPlaying);
        if (playing.length > 0) {
            if (playing.indexOf(lyricPlayer) === -1)
                lyricPlayer = playing[0];
        } else if (!lyricPlayer && candidates.length > 0) {
            lyricPlayer = candidates[0];
        }
    }

    // ─── 通用桌面歌词源：SPlayer WebSocket ──────────────────────────────
    readonly property bool splayerEnable: Config.options.desktopLyricsSplayerEnable ?? false
    property bool splayerConnected: false
    property bool splayerPlaying: false
    property string splayerSongLabel: ""
    // SPlayer 只在换歌/加载歌词时才推 lyric-change，刚连上时可能还没有歌词。
    // 必须等真的收到歌词才接管，否则会把 MPRIS + kugou 流程掐掉导致歌词空白。
    property bool splayerHasLyrics: false
    readonly property bool splayerActive: root.splayerEnable && root.splayerConnected && root.splayerHasLyrics

    // ─── 状态 ───────────────────────────────────────────────────────────
    property string source: "none" // "splayer" | "kugou" | "none"
    property string status: "loading"
    property string songTitle: ""
    property string songArtist: ""

    // 当前这首歌的身份是不是来自音频指纹（MPRIS 拿不到元数据时的兜底）。
    property bool usingFingerprint: false

    // 播放进度（秒）。SPlayer 用 progress 推；否则靠 MPRIS 轮询 + 本地插值。
    property real currentTime: 0
    property real duration: 0
    // 歌曲级偏移，来自歌词里的 [offset:ms] 标签
    property real rawLyricOffset: 0

    readonly property bool isPlaying: root.splayerActive
        ? root.splayerPlaying
        : (root.usingFingerprint
            ? AudioActivity.playing
            : ((activePlayer?.isPlaying ?? false)
                && (activePlayer?.playbackState === MprisPlaybackState.Playing
                    || activePlayer?.playbackState === 1
                    || activePlayer?.isPlaying === true)))

    // ─── 歌词行 ─────────────────────────────────────────────────────────
    property var lyricLines: [] // [{ start: 秒, text, trans, roman, words }]
    property int currentLineIndex: -1
    property string lastRawLyrics: ""
    property string lastSongKey: ""
    // 每次取词自增；脚本用 @@KRCGEN 回显，被顶掉的旧请求结果直接丢弃
    property int fetchGeneration: 0

    readonly property string currentText: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? lyricLines[currentLineIndex].text : ""
    readonly property string currentTrans: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? (lyricLines[currentLineIndex].trans ?? "") : ""
    readonly property string currentRoman: (currentLineIndex >= 0 && currentLineIndex < lyricLines.length) ? (lyricLines[currentLineIndex].roman ?? "") : ""
    readonly property string nextText: (currentLineIndex + 1 >= 0 && currentLineIndex + 1 < lyricLines.length) ? lyricLines[currentLineIndex + 1].text : ""
    readonly property bool hasLyrics: root.lyricLines.length > 0

    // ─── 7 行窗口（栏 / 锁屏 / 侧边栏用） ───────────────────────────────
    readonly property int before: 3
    readonly property int after: 3
    readonly property int total: 7
    readonly property int activeIndex: root.currentLineIndex
    property var slots: ["", "", "", "", "", "", ""]

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            const lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricLines.length)
                result.push(root.lyricLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    // ─── 时间补偿 ───────────────────────────────────────────────────────
    // 播放器自动补偿（正数 = 歌词提前）
    readonly property real playerOffset: {
        if (!activePlayer) return 0.0;
        const id = ((activePlayer.identity ?? "") + " " + (activePlayer.dbusName ?? "")).toLowerCase();
        // Spotify：MPRIS position 本身准确，旧版 +450ms 猜过头了
        if (id.includes("spotify")) return -0.05;
        // MoeKoeMusic 必须排在通用 chromium 规则前面（Electron 的 bus name 带 chromium）
        if (id.includes("moekoe")) return 0.0;
        // go-musicfox：实测超前 150ms，50ms 正好踩点
        if (id.includes("musicfox")) return 0.05;
        // 浏览器音频管线延迟
        if (id.includes("firefox") || id.includes("chromium") || id.includes("chrome")) return 0.30;
        // KA Music（BASS 引擎缓冲）
        if (id.includes("kugou") || id.includes("ka music")) return 0.15;
        return 0.15; // 通用 IPC/合成器延迟补偿
    }

    // 按播放器持久化的手动偏移
    property var perPlayerOffsets: ({})

    function playerKey(p) {
        if (!p) return "";
        const idPart = ((p.identity ?? "") + "").trim().toLowerCase();
        const dbusPart = ((p.dbusName ?? "") + "").trim().toLowerCase().replace(/\.instance\d+$/, "");
        if (idPart.length > 0) return idPart;
        return dbusPart;
    }

    readonly property string currentPlayerKey: root.playerKey(root.activePlayer)

    readonly property real manualOffset: {
        const k = root.currentPlayerKey;
        if (!k) return 0.0;
        const v = root.perPlayerOffsets[k];
        return (typeof v === "number" && isFinite(v)) ? v : 0.0;
    }

    // 总补偿（正数 = 歌词提前）
    readonly property real effectiveOffset: root.rawLyricOffset + root.playerOffset
        + (Config.options.desktopLyricsOffset ?? 0.0) + root.manualOffset
    // 兼容旧名字
    readonly property real lyricOffset: root.effectiveOffset
    readonly property real adjustedTime: root.currentTime + root.effectiveOffset

    function loadOffsets(txt) {
        try {
            const parsed = JSON.parse(txt);
            root.perPlayerOffsets = (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (e) {
            root.perPlayerOffsets = ({});
        }
    }

    function saveOffsets() {
        offsetsFile.setText(JSON.stringify(root.perPlayerOffsets, null, 2));
    }

    function adjustManualOffset(delta) {
        const k = root.currentPlayerKey;
        if (!k) return 0.0;
        const next = Math.round((root.manualOffset + delta) * 1000) / 1000;
        const copy = Object.assign({}, root.perPlayerOffsets);
        copy[k] = next;
        root.perPlayerOffsets = copy;
        root.saveOffsets();
        root.updateCurrentLine();
        return next;
    }

    function setManualOffsetForCurrent(seconds) {
        const k = root.currentPlayerKey;
        if (!k) return 0.0;
        const copy = Object.assign({}, root.perPlayerOffsets);
        copy[k] = seconds;
        root.perPlayerOffsets = copy;
        root.saveOffsets();
        root.updateCurrentLine();
        return seconds;
    }

    FileView {
        id: offsetsFile
        path: `${Directories.state}/user/lyrics_offsets.json`
        watchChanges: false
        onLoaded: root.loadOffsets(text())
        onLoadFailed: error => {
            root.perPlayerOffsets = ({});
            if (error === FileViewError.FileNotFound)
                offsetsFile.setText("{}");
        }
    }

    // ─── 当前行推进 ─────────────────────────────────────────────────────
    function updateCurrentLine() {
        const t = root.currentTime + root.effectiveOffset;
        let index = -1;
        for (let i = 0; i < root.lyricLines.length; i++) {
            if (root.lyricLines[i].start <= t + 0.05)
                index = i;
            else
                break;
        }
        if (index !== root.currentLineIndex) {
            root.currentLineIndex = index;
            root.slots = root.buildSlots(index);
        }
    }

    onCurrentTimeChanged: root.updateCurrentLine()
    onLyricLinesChanged: root.updateCurrentLine()
    onEffectiveOffsetChanged: root.updateCurrentLine()

    // ─── 通用桌面歌词源：SPlayer WebSocket 桥接 ─────────────────────────
    // SPlayer 打开「WebSocket 服务」后（默认 25885）推送 song-change /
    // lyric-change / progress-change，直接复用，省掉 kugou 抓取。
    // 脚本断开后自动重连，这里不需要重启逻辑。
    Process {
        id: splayerBridge
        running: root.splayerEnable
        command: ["python3", Quickshell.shellPath("scripts/desktopLyrics/splayer-ws.py"),
            "--port", String(Config.options.desktopLyricsSplayerPort ?? 25885)]
        stdout: SplitParser {
            onRead: line => root.handleSplayerMessage(line)
        }
        onExited: {
            root.splayerConnected = false;
            root.splayerPlaying = false;
        }
    }

    function handleSplayerMessage(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (msg.type) {
        case "hello":
            root.splayerConnected = true;
            break;
        case "disconnected":
            root.splayerConnected = false;
            root.splayerPlaying = false;
            root.splayerHasLyrics = false;
            if (root.source === "splayer")
                root.source = "none";
            break;
        case "song":
            root.splayerSongLabel = `${msg.title ?? ""}${msg.artist ? " - " + msg.artist : ""}`;
            root.songTitle = msg.title ?? "";
            root.songArtist = msg.artist ?? "";
            root.duration = (msg.duration ?? 0) / 1000;
            // 换歌后旧歌词作废，等新的 lyric-change 到达前先让 MPRIS 流程兜底
            root.splayerHasLyrics = false;
            break;
        case "lyric":
            // 脚本给的是毫秒，换算成秒，和 MPRIS 路径的 lyricLines 保持一致
            root.lyricLines = (msg.lines ?? []).map(l => ({
                start: (l.start ?? 0) / 1000,
                text: l.text ?? "",
                trans: l.translation ?? "",
                roman: l.roman ?? "",
                words: null
            }));
            root.rawLyricOffset = 0;
            root.currentLineIndex = -1;
            root.splayerHasLyrics = root.lyricLines.length > 0;
            root.source = root.splayerHasLyrics ? "splayer" : "none";
            root.status = root.splayerHasLyrics ? "ok" : "loading";
            root.updateCurrentLine();
            break;
        case "progress":
            if (typeof msg.position === "number")
                root.currentTime = msg.position / 1000;
            if (typeof msg.duration === "number" && msg.duration > 0)
                root.duration = msg.duration / 1000;
            break;
        case "state":
            root.splayerPlaying = !!msg.playing;
            break;
        }
    }

    // ─── MPRIS + kugou 兜底路径 ─────────────────────────────────────────
    property bool pendingRefresh: false

    Timer {
        id: fetchDebounce
        interval: 50
        onTriggered: root.doFetch(root.pendingRefresh)
    }

    function requestFetch(refresh) {
        if (refresh)
            root.pendingRefresh = true;
        fetchDebounce.restart();
    }

    function normalizeTitleArtist(title, artist) {
        // 有些播放器把 "艺人 - 歌名" 整个塞进 title（或 artist 为空）
        const m = title.match(/^(.{1,60}?)\s+[-–—]\s+(.+)$/);
        if (m) {
            const left = m[1].trim();
            const right = m[2].trim();
            if (artist.length === 0)
                return { title: right, artist: left };
            if (left.toLowerCase() === artist.toLowerCase())
                return { title: right, artist: artist };
        }
        return { title: title, artist: artist };
    }

    function doFetch(refresh) {
        root.pendingRefresh = false;
        // SPlayer 已经给了歌词，不要再抓一遍（会覆盖掉 WS 的数据）
        if (root.splayerActive)
            return;

        const rawTitle = (root.activePlayer?.trackTitle ?? "").trim();
        const rawArtist = (root.activePlayer?.trackArtist ?? "").trim();
        const norm = root.normalizeTitleArtist(rawTitle, rawArtist);
        let title = norm.title;
        let artist = norm.artist;
        let dur = root.activePlayer?.length ?? 0;
        let fromFingerprint = false;

        // MPRIS 给不出可用元数据 —— 浏览器网页播放器、游戏、视频播放器都会走到这里。
        // 用音频指纹认歌：recognize-music.sh 抓默认输出的 monitor 源，谁在出声都能录到。
        if (!title && LyricsIdentifier.enabled && AudioActivity.playing) {
            LyricsIdentifier.requestIdentify();
            if (LyricsIdentifier.hasIdentity) {
                title = LyricsIdentifier.title;
                artist = LyricsIdentifier.artist;
                // 指纹认不出时长，交给 kugou 用「歌名 + 艺人」匹配
                dur = 0;
                fromFingerprint = true;
            }
        }

        if (!title) {
            root.lyricLines = [];
            root.lastRawLyrics = "";
            root.lastSongKey = "";
            root.currentLineIndex = -1;
            root.usingFingerprint = false;
            root.source = "none";
            root.status = "no_info";
            root.slots = root.buildSlots(-1);
            return;
        }

        const songKey = `${title} - ${artist}`;
        if (!refresh && songKey === root.lastSongKey && root.lyricLines.length > 0) {
            root.usingFingerprint = fromFingerprint;
            return;
        }

        root.lastSongKey = songKey;
        root.songTitle = title;
        root.songArtist = artist;
        root.duration = dur;
        root.usingFingerprint = fromFingerprint;
        root.status = "loading";

        // 指纹来源没有播放器可问进度，从 0 开始自己走表
        if (fromFingerprint)
            root.currentTime = 0;

        // 换歌瞬间先显示占位，避免旧歌词停留
        root.lyricLines = [{
            start: 0,
            text: "♪ " + title + (artist.length > 0 ? " — " + artist : ""),
            trans: "",
            roman: "",
            words: null
        }];
        root.currentLineIndex = -1;
        root.slots = root.buildSlots(-1);

        root.fetchGeneration += 1;
        const cmd = ["python3", `${Directories.scriptPath}/lyrics/kugou_lyrics.py`];
        if (refresh)
            cmd.push("--refresh");
        cmd.push(title, artist, String(Math.floor(dur)), String(root.fetchGeneration));
        lyricsProc.running = false;
        lyricsProc.command = cmd;
        lyricsProc.running = true;
    }

    Process {
        id: lyricsProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text;
                let lyrics = "";
                const genMatch = out.match(/^@@KRCGEN (\d+)\n/);
                if (genMatch) {
                    // 被更新的歌顶掉的旧请求，直接丢弃
                    if (Number(genMatch[1]) !== root.fetchGeneration)
                        return;
                    lyrics = out.slice(genMatch[0].length).trim();
                } else {
                    lyrics = out.trim();
                }
                // 没取到词：保留「♪ 歌名 — 艺人」占位
                if (lyrics.length === 0) {
                    root.source = "none";
                    root.status = "not_found";
                    return;
                }
                root.lastRawLyrics = lyrics;
                root.lyricLines = root.parseLyrics(lyrics);
                const offsetMatch = lyrics.match(/\[offset:(-?\d+)\]/);
                root.rawLyricOffset = offsetMatch ? -Number(offsetMatch[1]) / 1000 : 0;
                root.source = root.lyricLines.length > 0 ? "kugou" : "none";
                root.status = root.lyricLines.length > 0 ? "ok" : "not_found";
                root.updateCurrentLine();
            }
        }
    }

    // ─── 歌词解析（KRC / LRC + 翻译 / 音译） ────────────────────────────
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

    // 音译（romaji）判定：Kugou 对日文歌会同时给「音译块」和「语义翻译块」。
    // 音译 token（wa ta ku shi 这类）能完全拆成日语音节，中英文句子不能。
    function isRomajiToken(raw) {
        let t = raw.replace(/^'+|'+$/g, "");
        if (t.length === 0)
            return true;
        t = t.replace(/^([kstcbgdpfhjz])\1/, "$1");
        const syl = /^(she|chi|tsu|[kgstnhmyrwgzdbpfcjv]y[auo]|[kgstnhmyrwgzdbpfcjv]h?[aiueo]|[aiueo]|n)/;
        let rest = t;
        while (rest.length > 0) {
            const m = rest.match(syl);
            if (!m)
                return false;
            rest = rest.slice(m[0].length);
        }
        return true;
    }

    function isRomajiText(s) {
        if (!s || /[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]/.test(s))
            return false;
        const tokens = s.toLowerCase().match(/[a-z]+(?:'[a-z]+)?/g);
        if (!tokens || tokens.length === 0)
            return false;
        let ok = 0;
        for (const t of tokens) {
            if (root.isRomajiToken(t))
                ok += 1;
        }
        return ok / tokens.length >= 0.85;
    }

    function parseTranslations(lrcText) {
        const result = [];
        const match = lrcText.match(/\[language:([A-Za-z0-9+/=]*)\]/);
        if (!match)
            return result;
        try {
            let b64 = match[1];
            while (b64.length % 4 !== 0) b64 += "=";
            const bytes = root.base64Decode(b64);
            const json = JSON.parse(root.utf8Decode(bytes));
            const contents = json?.content ?? [];
            for (const block of contents) {
                const lines = [];
                for (const line of (block?.lyricContent ?? []))
                    lines.push(Array.isArray(line) ? line.join("") : String(line));
                if (lines.length === 0)
                    continue;
                // 跳过音译块，只留第一个语义翻译块（与原文 1:1 对齐）
                const sample = lines.slice(0, 8).filter(l => l.trim().length > 0);
                if (sample.length > 0 && root.isRomajiText(sample.join(" ")))
                    continue;
                if (result.length === 0) {
                    for (const l of lines)
                        result.push(l);
                    break;
                }
            }
        } catch (e) {
            console.log("[LyricsService] translation parse failed:", e);
        }
        return result;
    }

    function parseLyrics(lrcText) {
        const lines = [];
        if (!lrcText || typeof lrcText !== "string")
            return lines;
        const translations = root.parseTranslations(lrcText);
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
                    // KRC 词偏移相对行首（首个字为 0），直接累加
                    const wordStart = start + Number(word[1]) / 1000;
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
            const looksRomaji = root.isRomajiText(trans);
            lines.push({
                start: start,
                text: text,
                trans: (trans !== text && !looksRomaji) ? trans.trim() : "",
                roman: (trans !== text && looksRomaji) ? trans.trim() : "",
                words: (words && words.length > 0) ? words : null
            });
        }
        lines.sort((a, b) => a.start - b.start);
        return lines;
    }

    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // 逐字高亮 HTML（桌面歌词浮层用）
    function buildLineHtml(line) {
        if (!line || !line.words)
            return root.escapeHtml(line?.text ?? "");
        const t = root.adjustedTime;
        let html = "";
        for (const w of line.words) {
            // 开始唱（含正在唱）即高亮 —— 唱完才亮会滞后整整一个字长
            const started = t >= w.start;
            const color = started ? Appearance.colors.colPrimary : Appearance.colors.colSecondary;
            html += `<font color="${color}">${root.escapeHtml(w.text)}</font>`;
        }
        return html;
    }

    // ─── 旧接口兼容 ─────────────────────────────────────────────────────
    function restartLyrics() {
        root.requestFetch(true);
    }

    // ─── 信号联动 ───────────────────────────────────────────────────────
    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() {
            root.currentTime = root.activePlayer?.position ?? 0;
            root.requestFetch();
        }
        function onTrackArtistChanged() {
            root.requestFetch();
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
            root.currentTime = activePlayer.position ?? 0;
            root.requestFetch();
        } else if (!root.splayerActive) {
            root.lyricLines = [];
            root.currentLineIndex = -1;
            root.source = "none";
            root.status = "no_info";
            root.slots = root.buildSlots(-1);
        }
    }

    Connections {
        target: MprisController
        function onPlayersChanged() { root.pickPlayer() }
        function onActivePlayerChanged() { root.pickPlayer() }
    }

    // 漏信号时的兜底轮询
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.pickPlayer()
    }

    // 指纹认出歌之后重新取一次词（限流在 LyricsIdentifier 里）
    Connections {
        target: LyricsIdentifier
        function onIdentified() {
            if (!root.splayerActive)
                root.doFetch(false);
        }
    }

    Timer {
        // 指纹身份过期（或一直没认出来）时重试
        interval: 15000
        running: root.usingFingerprint && AudioActivity.playing
        repeat: true
        onTriggered: {
            if (!LyricsIdentifier.hasIdentity)
                LyricsIdentifier.requestIdentify();
        }
    }

    // 1. 高精度 MPRIS 轮询：每 350ms 主动拉一次 D-Bus position
    Timer {
        id: mprisSyncTimer
        interval: 350
        repeat: true
        running: root.isPlaying && root.activePlayer !== null && !root.splayerActive
        onTriggered: {
            if (root.activePlayer) {
                root.activePlayer.positionChanged();
                const realPos = root.activePlayer.position ?? 0;
                if (realPos > 0) {
                    const diff = realPos - root.currentTime;
                    // 小幅漂移平滑拉近，大幅直接对齐
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

    // 2. 100ms 本地插值：让逐字填色平滑（不依赖 MPRIS 的 350ms 粒度）
    Timer {
        interval: 100
        running: root.isPlaying && root.hasLyrics
        repeat: true
        onTriggered: {
            if (root.lyricLines.length > 0)
                root.currentTime += 0.1;
        }
    }

    Component.onCompleted: {
        root.pickPlayer();
        if (root.activePlayer) {
            root.currentTime = root.activePlayer.position ?? 0;
            root.requestFetch();
        }
    }
}
