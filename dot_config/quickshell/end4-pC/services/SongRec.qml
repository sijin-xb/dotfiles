pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    enum MonitorSource { Monitor, Input }

    property var monitorSource: SongRec.MonitorSource.Monitor
    property int timeoutInterval: Config.options.musicRecognition.interval
    property int timeoutDuration: Config.options.musicRecognition.timeout
    readonly property bool running: recognizeMusicProc.running

    function toggleRunning(running) {
        const target = (running !== undefined) ? running : !root.running;
        // Suppress the "couldn't recognize" notification when the user stops
        // a listening session themselves
        root.manuallyStopped = root.running && !target;
        recognizeMusicProc.running = target;
        musicReconizedProc.running = false;
    }

    function toggleMonitorSource(source) {
        if (source !== undefined) {
            root.monitorSource = source
            return
        }
        root.monitorSource = (root.monitorSource === SongRec.MonitorSource.Monitor) ? SongRec.MonitorSource.Input : SongRec.MonitorSource.Monitor
    }
    function monitorSourceToString(source) {
        if (source === SongRec.MonitorSource.Monitor) {
            return "monitor"
        } else {
            return "input"
        }
    }
    readonly property string monitorSourceString: monitorSourceToString(monitorSource)
    property var recognizedTrack: ({ title:"", subtitle:"", url:"", image:"" })
    property bool manuallyStopped: false

    // Music diary: recently recognized tracks, persisted for the sidebar card
    readonly property string historyPath: `${Directories.state}/user/generated/songrec_history.json`
    readonly property int historyLimit: 30
    property var history: []

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadHistory()
        onLoadFailed: root.history = []
    }

    function loadHistory() {
        try {
            history = JSON.parse(historyFile.text())
        } catch (e) {
            history = []
        }
    }

    function recordHistory() {
        const t = root.recognizedTrack;
        if (!t.title) return;
        const list = Array.from(root.history ?? []);
        // Same song as the most recent entry: just refresh its timestamp
        if (list.length > 0 && list[0].title === t.title && list[0].subtitle === t.subtitle) {
            list[0].timestamp = Date.now();
        } else {
            list.unshift({ title: t.title, subtitle: t.subtitle, url: t.url, image: t.image, timestamp: Date.now() });
        }
        if (list.length > root.historyLimit) list.length = root.historyLimit;
        root.history = list;
        historyFile.setText(JSON.stringify(list, null, 2));
    }

    function handleRecognition(jsonText) {
        try {
            const obj = JSON.parse(jsonText)
            const track = obj?.track ?? {}
            root.recognizedTrack = {
                title: track.title ?? "",
                subtitle: track.subtitle ?? "",
                url: track.url ?? "",
                image: track.image ?? ""
            }
            root.recordHistory();
            musicReconizedProc.running = true
        } catch(e) {
            Quickshell.execDetached(["notify-send", Translation.tr("Couldn't recognize music"), Translation.tr("Perhaps what you're listening to is too niche"), "-a", "Shell"])
        }
    }

    Process {
        id: recognizeMusicProc
        running: false
        command: [`${Directories.scriptPath}/musicRecognition/recognize-music.sh`, "-i", `${root.timeoutInterval}`, "-t", `${root.timeoutDuration}`, "-s", root.monitorSourceString]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.manuallyStopped) {
                    root.manuallyStopped = false
                    return
                }
                handleRecognition(this.text)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                Quickshell.execDetached(["notify-send", Translation.tr("Couldn't recognize music"), Translation.tr("Make sure you have songrec installed"), "-a", "Shell"])
            } else if (exitCode === 2) {
                Quickshell.execDetached(["notify-send", Translation.tr("Couldn't capture audio"), Translation.tr("Check the selected audio output or input device"), "-a", "Shell"])
            }
        }
    }

    // Result notification with album art (downloaded from Shazam when
    // available) and named actions; prints the clicked action name
    Process {
        id: musicReconizedProc
        running: false
        command: {
            const t = root.recognizedTrack;
            return ["bash", "-c",
                `art=""
if [ -n "$1" ]; then
    curl -sL --max-time 6 "$1" -o /tmp/songrec_art.jpg 2>/dev/null
    [ -s /tmp/songrec_art.jpg ] && art="-i /tmp/songrec_art.jpg"
fi
notify-send -a Shell $art "Music Recognized" "$2 - $3" -A "open=Apple Music" -A "youtube=YouTube"
`, "_", t.image, t.title, t.subtitle]
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const choice = this.text.trim()
                if (choice === "open" && root.recognizedTrack.url.length > 0) {
                    Qt.openUrlExternally(root.recognizedTrack.url);
                } else if (choice === "youtube") {
                    Qt.openUrlExternally("https://www.youtube.com/results?search_query=" + encodeURIComponent(`${root.recognizedTrack.title} ${root.recognizedTrack.subtitle}`));
                }
            }
        }
    }
}
