import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Music diary: recently recognized tracks (fed by SongRec), most recent
// first. Click a row to open the track's page when it has a URL.
Item {
    id: root

    readonly property var entries: SongRec.history ?? []

    // Stats over the last 7 days: total recognitions + most recognized artist
    readonly property var weeklyStats: {
        const weekAgo = Date.now() - 7 * 24 * 3600 * 1000;
        const recent = root.entries.filter(e => (e.timestamp ?? 0) >= weekAgo);
        const counts = {};
        let top = "";
        let topCount = 0;
        for (const e of recent) {
            const artist = e.subtitle ?? "";
            counts[artist] = (counts[artist] ?? 0) + 1;
            if (counts[artist] > topCount) {
                topCount = counts[artist];
                top = artist;
            }
        }
        return { count: recent.length, top: top, topCount: topCount };
    }
    readonly property string weeklyText: {
        const stats = weeklyStats;
        if (stats.count === 0) return "";
        let text = `${stats.count} this week`;
        if (stats.top) text += ` · ${stats.top} ×${stats.topCount}`;
        return text;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol {
                text: "library_music"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: Translation.tr("Music Diary")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            Item {
                Layout.fillWidth: true
            }
        }

        // Weekly report strip: recognition count over the last 7 days
        Rectangle {
            visible: root.weeklyText.length > 0
            Layout.fillWidth: true
            implicitWidth: weeklyRow.implicitWidth + 20
            implicitHeight: weeklyRow.implicitHeight + 10
            radius: height / 2
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                id: weeklyRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "insights"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: root.weeklyText
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }

        StyledText {
            visible: root.entries.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Songs recognized with music recognition will show up here")
            color: Appearance.colors.colSubtext
        }

        ListView {
            id: entryList
            visible: root.entries.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.entries.length

            delegate: RowLayout {
                id: entryRow
                required property int index
                readonly property var entry: root.entries[index]
                spacing: 10
                width: entryList.width

                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSecondaryContainer
                    clip: true

                    Image {
                        id: coverImage
                        anchors.fill: parent
                        source: entryRow.entry.image ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 20
                        color: Appearance.colors.colOnSecondaryContainer
                        visible: coverImage.status !== Image.Ready
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    StyledText {
                        text: entryRow.entry.title ?? ""
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: `${entryRow.entry.subtitle ?? ""} · ${root.ago(entryRow.entry.timestamp ?? 0)}`
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                MaterialSymbol {
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    visible: (entryRow.entry.url ?? "").length > 0
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if ((entryRow.entry.url ?? "").length > 0)
                            Qt.openUrlExternally(entryRow.entry.url)
                    }
                }
            }
        }
    }

    function ago(timestamp) {
        const minutes = Math.floor((Date.now() - timestamp) / 60000);
        if (minutes < 1) return Translation.tr("just now");
        if (minutes < 60) return `${minutes}m`;
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return `${hours}h`;
        return new Date(timestamp).toLocaleDateString();
    }
}
