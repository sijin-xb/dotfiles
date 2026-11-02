pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft
    property real fontScale: 1.0
    property bool animateTransitions: false
    property real lineSpacing: 6
    property bool showTranslation: true
    property bool showProgress: true

    implicitWidth: 200
    implicitHeight: 200

    readonly property int radius: 3
    readonly property int slotCount: root.radius * 2 + 1
    readonly property var lines: LyricsService.lyricLines ?? []
    readonly property int activeIndex: LyricsService.currentLineIndex
    readonly property bool ready: LyricsService.status === "ok" && root.activeIndex >= 0
    readonly property real baseFontSize: Appearance.font.pixelSize.normal * root.fontScale

    function lineIndexFor(slot) {
        const index = root.activeIndex + (slot - root.radius);
        return index >= 0 && index < root.lines.length ? index : -1;
    }

    function lineAt(slot) {
        const index = root.lineIndexFor(slot);
        return index >= 0 ? root.lines[index] : null;
    }

    function distanceFor(slot) {
        return Math.abs(slot - root.radius);
    }

    function fontSizeFor(slot) {
        const d = root.distanceFor(slot);
        if (d === 0)
            return root.baseFontSize * 1.35;
        if (d === 1)
            return root.baseFontSize;
        if (d === 2)
            return root.baseFontSize * 0.9;
        return root.baseFontSize * 0.82;
    }

    function opacityFor(slot) {
        const d = root.distanceFor(slot);
        if (d === 0)
            return 1;
        if (d === 1)
            return 0.6;
        if (d === 2)
            return 0.35;
        return 0.15;
    }

    // Word-level sweep. Sung words take the active colour, unsung stay in the
    // body colour, and the word under the playhead is a linear blend of the
    // two so the highlight advances with the audio instead of snapping.
    readonly property string richLine: {
        if (!root.ready)
            return "";
        const line = root.lines[root.activeIndex];
        if (!line || !line.words || line.words.length === 0)
            return "";

        const sungHex = String(root.activeColor);
        const baseHex = String(root.textColor);
        const t = LyricsService.currentTime + LyricsService.effectiveOffset;
        let html = "";
        for (let i = 0; i < line.words.length; i++) {
            const word = line.words[i];
            const text = String(word.text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            const start = Number(word.start) || 0;
            const dur = Number(word.dur) || 0;
            let progress;
            if (dur <= 0)
                progress = t >= start ? 1 : 0;
            else if (t >= start + dur)
                progress = 1;
            else if (t <= start)
                progress = 0;
            else
                progress = (t - start) / dur;

            if (progress >= 1)
                html += '<font color="' + sungHex + '">' + text + "</font>";
            else if (progress <= 0)
                html += text;
            else
                html += '<font color="' + mixHex(baseHex, sungHex, progress) + '">' + text + "</font>";
        }
        return html;
    }

    readonly property real lineProgress: {
        if (!root.ready)
            return 0;
        const line = root.lines[root.activeIndex];
        if (!line)
            return 0;
        const next = root.lines[root.activeIndex + 1];
        const start = Number(line.start) || 0;
        const end = next ? Number(next.start) || start : start + 5;
        const span = end - start;
        if (span <= 0)
            return 0;
        const t = LyricsService.currentTime + LyricsService.effectiveOffset;
        return Math.max(0, Math.min(1, (t - start) / span));
    }

    function parseHex(value) {
        const m = /^#?([0-9a-f]{6})$/i.exec(String(value || "").trim());
        if (!m)
            return null;
        const n = parseInt(m[1], 16);
        return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    }

    function mixHex(from, to, k) {
        const t = Math.max(0, Math.min(1, k));
        const a = root.parseHex(from);
        const b = root.parseHex(to);
        if (a === null || b === null)
            return String(to || from || "");
        const ch = (lo, hi) => Math.round(lo + (hi - lo) * t);
        const hex = v => {
            const s = Math.max(0, Math.min(255, v)).toString(16);
            return s.length < 2 ? "0" + s : s;
        };
        return "#" + hex(ch(a[0], b[0])) + hex(ch(a[1], b[1])) + hex(ch(a[2], b[2]));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status !== "ok"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 48
                    implicitHeight: 48

                    MaterialLoadingIndicator {
                        anchors.fill: parent
                        loading: LyricsService.status === "loading"
                        colBg: root.indicatorColor
                        colShape: root.indicatorShapeColor
                        implicitSize: 48
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LyricsService.restartLyrics()
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok"
            spacing: root.lineSpacing

            Repeater {
                model: root.slotCount

                delegate: Item {
                    id: slotRoot

                    required property int index

                    readonly property var line: root.lineAt(slotRoot.index)
                    readonly property bool active: root.distanceFor(slotRoot.index) === 0

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 2

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.fill: parent
                                visible: slotRoot.active && root.richLine !== ""
                                textFormat: Text.RichText
                                text: slotRoot.active ? root.richLine : ""
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                horizontalAlignment: root.textAlignment
                                verticalAlignment: Text.AlignVCenter
                                font.family: Appearance.font.family.main
                                font.pixelSize: root.fontSizeFor(slotRoot.index)
                                font.weight: Font.Bold
                                color: root.textColor
                                opacity: root.opacityFor(slotRoot.index)
                            }

                            StyledText {
                                anchors.fill: parent
                                visible: !(slotRoot.active && root.richLine !== "")
                                text: slotRoot.line ? (slotRoot.line.text ?? "") : ""
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                horizontalAlignment: root.textAlignment
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: root.fontSizeFor(slotRoot.index)
                                font.weight: slotRoot.active ? Font.Bold : Font.Medium
                                color: slotRoot.active ? root.activeColor : root.textColor
                                opacity: root.opacityFor(slotRoot.index)

                                Behavior on font.pixelSize {
                                    enabled: root.animateTransitions
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 250
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Translation under the active line only — translated
                        // neighbours would compete with the lyric for attention.
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.showTranslation && slotRoot.active && slotRoot.line
                                     && (slotRoot.line.trans ?? "") !== ""
                            text: slotRoot.line ? (slotRoot.line.trans ?? "") : ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            horizontalAlignment: root.textAlignment
                            font.pixelSize: Math.max(10, root.baseFontSize * 0.7)
                            font.weight: Font.Medium
                            color: root.dimColor
                            opacity: 0.85
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        visible: root.showProgress && root.ready
        color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.18)

        Rectangle {
            width: parent.width * root.lineProgress
            height: parent.height
            radius: 1
            color: root.activeColor

            Behavior on width {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.Linear
                }
            }
        }
    }
}
