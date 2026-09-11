pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls

/**
 * Floating capsule filter bar for the wallpaper selector.
 *
 * All / History / Video buttons, a row of colour chips (only buckets that
 * actually exist in the current directory are shown), and a search field that
 * expands inline on demand.
 */
Item {
    id: root

    property string currentFilter: "All"
    property var availableBuckets: []
    property bool searchOpen: false
    property string searchQuery: ""

    signal filterSelected(string filter)
    signal searchTriggered(string query)

    readonly property var colourOptions: [
        { name: "Red",        hex: "#E0483E" },
        { name: "Orange",     hex: "#E08A3E" },
        { name: "Yellow",     hex: "#E0C93E" },
        { name: "Green",      hex: "#6CBF5C" },
        { name: "Blue",       hex: "#4C7FE0" },
        { name: "Purple",     hex: "#8A5CE0" },
        { name: "Pink",       hex: "#E05C9E" },
        { name: "Monochrome", hex: "#A9A9A9" },
    ]

    function isBucketShown(name) {
        return root.availableBuckets.indexOf(name) !== -1;
    }

    implicitHeight: 34
    implicitWidth: capsule.width

    Rectangle {
        id: capsule
        anchors.centerIn: parent
        height: root.implicitHeight
        width: contentRow.width + 16
        radius: Appearance.rounding.full
        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.06)
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 6

            RippleButton {
                id: allButton
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                toggled: root.currentFilter === "All"
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.filterSelected("All")
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "grid_view"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: allButton.toggled ? 1 : 0
                    color: allButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("All wallpapers") }
            }

            RippleButton {
                id: historyButton
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                toggled: root.currentFilter === "History"
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.filterSelected("History")
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "history"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: historyButton.toggled ? 1 : 0
                    color: historyButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Recently used") }
            }

            RippleButton {
                id: videoButton
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                toggled: root.currentFilter === "Video"
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.filterSelected("Video")
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_circle"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: videoButton.toggled ? 1 : 0
                    color: videoButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Video wallpapers") }
            }

            Repeater {
                model: root.colourOptions

                delegate: Item {
                    id: chip
                    required property var modelData
                    visible: root.isBucketShown(chip.modelData.name)
                    width: visible ? 26 : 0
                    height: 34

                    Rectangle {
                        id: colourDot
                        property bool hovered: chipMouse.containsMouse
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        radius: width / 2
                        color: chip.modelData.hex
                        border.width: root.currentFilter === chip.modelData.name ? 3 : 1
                        border.color: root.currentFilter === chip.modelData.name
                            ? Appearance.colors.colOnLayer1
                            : Appearance.colors.colLayer0Border
                        scale: root.currentFilter === chip.modelData.name ? 1.15
                             : (chipMouse.containsMouse ? 1.08 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.width { NumberAnimation { duration: 200 } }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.filterSelected(chip.modelData.name)
                        }

                        StyledToolTip { text: chip.modelData.name }
                    }
                }
            }

            RippleButton {
                id: searchToggle
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                toggled: root.searchOpen
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.searchOpen = !root.searchOpen
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "search"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: searchToggle.toggled ? 1 : 0
                    color: searchToggle.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Search online") }
            }

            TextField {
                id: searchField
                width: root.searchOpen ? 200 : 0
                opacity: root.searchOpen ? 1 : 0
                implicitHeight: 34
                height: 34
                clip: true
                placeholderText: Translation.tr("Search wallpapers…")
                placeholderTextColor: Appearance.colors.colSubtext
                color: Appearance.colors.colOnLayer1
                selectedTextColor: Appearance.colors.colOnSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                font {
                    family: Appearance.font.family.main
                    pixelSize: Appearance.font.pixelSize.small
                    hintingPreference: Font.PreferFullHinting
                    variableAxes: Appearance.font.variableAxes.main
                }
                background: Rectangle {
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                }
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
                onAccepted: root.searchTriggered(searchField.text.trim())
                onActiveFocusChanged: {
                    if (!activeFocus) searchField.text = root.searchQuery;
                }
                Connections {
                    target: root
                    function onSearchQueryChanged() {
                        if (!searchField.activeFocus) searchField.text = root.searchQuery;
                    }
                }
            }
        }
    }
}
