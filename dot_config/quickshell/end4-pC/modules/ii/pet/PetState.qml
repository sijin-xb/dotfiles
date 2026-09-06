pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Feeds the desktop pet with system vitals and derives its mood.
 *
 * petMetrics.sh emits raw counters; this component diffs consecutive samples
 * to get CPU % and download rate, then applies a priority chain:
 *   offline > low battery > compiling > high CPU > downloading > music > sleep
 *
 * Moods: sleep | busy | carry | typing | music | anxious | lost
 */
Item {
    id: root

    property bool active: true
    property string moodOverride: "" // set via `ipc call pet mood <mood>`, "auto" releases

    // ——— readings ———
    property real cpuPercent: 0
    property real rxBytesPerSec: 0
    property bool netOnline: true
    property bool batteryExists: false
    property int batteryPercent: 100
    property bool charging: false
    property bool compiling: false
    property int hour: new Date().getHours()
    readonly property bool night: hour >= 23 || hour < 7
    property string nowPlaying: ""

    // ——— thresholds ———
    readonly property real busyThreshold: 60
    readonly property real calmThreshold: 35
    readonly property real downloadThreshold: 2 * 1024 * 1024
    readonly property real downloadCalmThreshold: 512 * 1024
    readonly property int lowBatteryPercent: 20

    // ——— hysteresis latches (need 2 consecutive samples to trip) ———
    property bool _busyLatched: false
    property int _busyHits: 0
    property bool _downloading: false
    property int _downloadHits: 0
    property var _prevSample: null

    readonly property string mood: {
        if (moodOverride.length > 0 && moodOverride !== "auto")
            return moodOverride;
        if (!netOnline)
            return "lost";
        if (batteryExists && !charging && batteryPercent <= lowBatteryPercent)
            return "anxious";
        if (compiling)
            return "typing";
        if (_busyLatched)
            return "busy";
        if (_downloading)
            return "carry";
        if (nowPlaying.length > 0)
            return "music";
        return "sleep";
    }

    readonly property string moodLabel: {
        if (mood === "sleep")
            return night ? "夜深了，晚安…" : "打盹中";
        if (mood === "busy")
            return "好忙！";
        if (mood === "carry")
            return "搬货中";
        if (mood === "typing")
            return "敲键盘编译…";
        if (mood === "music")
            return "听歌中 ♪";
        if (mood === "anxious")
            return "电量焦虑…";
        if (mood === "lost")
            return "网络丢了？";
        return "";
    }

    readonly property string moodDetail: {
        if (mood === "sleep")
            return night ? "别熬太晚哦" : `CPU ${Math.round(cpuPercent)}%`;
        if (mood === "busy")
            return `CPU ${Math.round(cpuPercent)}%`;
        if (mood === "carry")
            return formatRate(rxBytesPerSec);
        if (mood === "typing")
            return "呃啊…";
        if (mood === "music")
            return nowPlaying.length > 0 ? nowPlaying : "♪";
        if (mood === "anxious")
            return `电量只剩 ${batteryPercent}%`;
        if (mood === "lost")
            return "正在找网络…";
        return "";
    }

    function formatRate(bps) {
        if (bps >= 1024 * 1024)
            return (bps / 1024 / 1024).toFixed(1) + " MB/s";
        if (bps >= 1024)
            return Math.round(bps / 1024) + " KB/s";
        return Math.round(bps) + " B/s";
    }

    Timer {
        interval: 3000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!metricsProc.running)
                metricsProc.running = true;
        }
    }

    Process {
        id: metricsProc
        command: [`${Directories.scriptPath}/pet/petMetrics.sh`]
        stdout: StdioCollector {
            onStreamFinished: root.handleSample(text)
        }
    }

    function handleSample(raw) {
        let s;
        try {
            s = JSON.parse(raw);
        } catch (e) {
            return;
        }
        const prev = _prevSample;
        hour = s.hour ?? hour;
        netOnline = s.netOnline ?? netOnline;
        batteryExists = s.batteryExists ?? batteryExists;
        batteryPercent = s.batteryPercent ?? batteryPercent;
        charging = s.charging ?? charging;
        compiling = (s.compileCount ?? 0) > 0;

        let playing = "";
        const players = MprisController.players;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying) {
                playing = players[i].trackTitle ?? "";
                break;
            }
        }
        nowPlaying = playing;

        if (prev && s.ts > prev.ts) {
            const dt = (s.ts - prev.ts) / 1000;
            // Skip stale diffs (pet was hidden / machine suspended)
            if (dt >= 1 && dt <= 60) {
                const dTotal = s.cpuJiffies - prev.cpuJiffies;
                const dIdle = s.idleJiffies - prev.idleJiffies;
                if (dTotal > 0) {
                    const instant = Math.max(0, Math.min(100, (dTotal - dIdle) / dTotal * 100));
                    cpuPercent = cpuPercent * 0.35 + instant * 0.65;
                }
                const drx = Math.max(0, s.rxBytes - prev.rxBytes);
                rxBytesPerSec = rxBytesPerSec * 0.35 + (drx / dt) * 0.65;
            }
        }

        if (cpuPercent >= busyThreshold) {
            _busyHits++;
            if (_busyHits >= 2)
                _busyLatched = true;
        } else if (cpuPercent <= calmThreshold) {
            _busyHits = 0;
            _busyLatched = false;
        }
        if (rxBytesPerSec >= downloadThreshold) {
            _downloadHits++;
            if (_downloadHits >= 2)
                _downloading = true;
        } else if (rxBytesPerSec <= downloadCalmThreshold) {
            _downloadHits = 0;
            _downloading = false;
        }

        _prevSample = s;
    }
}
