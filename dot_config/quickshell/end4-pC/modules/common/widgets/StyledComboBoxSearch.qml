pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ComboBox {
    id: root

    property string buttonIcon: ""
    property real buttonRadius: height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    property string searchText: ""

    readonly property var filteredItems: {
        const query = root.searchText.toLowerCase()
        const source = root.model ?? []
        const result = []
        for (let i = 0; i < source.length; i++) {
            const item = source[i]
            const isObject = typeof item === "object"
            const label = isObject ? (item[root.textRole] ?? "") : String(item)
            if (query.length === 0 || label.toLowerCase().includes(query))
                result.push({ realIndex: i, label: label, icon: isObject ? (item.icon ?? "") : "" })
        }
        return result
    }
    readonly property int visibleCount: root.filteredItems.length

    function pick(realIndex) {
        root.activated(realIndex)
        root.popup.close()
    }

    implicitHeight: 40
    Layout.fillWidth: true

    background: Rectangle {
        radius: root.buttonRadius
        color: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: MaterialSymbol {
        x: root.width - width - 16
        y: root.height / 2 - height / 2
        text: "keyboard_arrow_down"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSecondaryContainer

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitWidth: buttonLayout.implicitWidth
        implicitHeight: buttonLayout.implicitHeight

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: 8
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.buttonIcon.length > 0 || !!(root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: {
                        if (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon) {
                            return root.model[root.currentIndex].icon;
                        }
                        return root.buttonIcon;
                    }
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Component {
        id: entryDelegate

        ItemDelegate {
            id: itemDelegate
            required property var modelData
            required property int index
            readonly property bool selected: root.currentIndex === itemDelegate.modelData.realIndex

            width: ListView.view ? ListView.view.width : root.width
            implicitHeight: 42
            onClicked: root.pick(itemDelegate.modelData.realIndex)

            property color color: {
                if (itemDelegate.selected) {
                    if (itemDelegate.down) return Appearance.colors.colSecondaryContainerActive;
                    if (itemDelegate.hovered) return Appearance.colors.colSecondaryContainerHover;
                    return Appearance.colors.colSecondaryContainer;
                } else {
                    if (itemDelegate.down) return Appearance.colors.colLayer3Active;
                    if (itemDelegate.hovered) return Appearance.colors.colLayer3Hover;
                    return ColorUtils.transparentize(Appearance.colors.colLayer3);
                }
            }
            property color colText: itemDelegate.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

            background: Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: 2
                radius: Appearance.rounding.small
                color: itemDelegate.color
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                }
            }

            contentItem: RowLayout {
                spacing: 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: Appearance.font.pixelSize.larger
                    active: itemDelegate.modelData.icon.length > 0
                    visible: active
                    sourceComponent: Item {
                        implicitWidth: icon.implicitWidth
                        implicitHeight: Appearance.font.pixelSize.larger
                        MaterialSymbol {
                            id: icon
                            anchors.centerIn: parent
                            text: itemDelegate.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: itemDelegate.colText
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.larger
                    color: itemDelegate.colText
                    text: itemDelegate.modelData.label
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        clip: true
        height: Math.min(
            searchField.implicitHeight + 12 + (root.visibleCount * 42) + topPadding + bottomPadding,
            320
        )
        padding: 8

        onVisibleChanged: {
            if (visible) {
                searchField.forceActiveFocus()
                Qt.callLater(() => {
                    const position = root.filteredItems.findIndex(entry => entry.realIndex === root.currentIndex)
                    if (position >= 0) listView.positionViewAtIndex(position, ListView.Center)
                })
            } else {
                root.searchText = ""
                searchField.text = ""
            }
        }

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        exit: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow { target: popupBackground }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchField.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6

                    MaterialSymbol {
                        Layout.leftMargin: 6
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search..."
                        color: Appearance.colors.colOnLayer1
                        background: null
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        onTextChanged: root.searchText = text
                        Keys.onDownPressed: listView.incrementCurrentIndex()
                        Keys.onUpPressed: listView.decrementCurrentIndex()
                        Keys.onReturnPressed: {
                            const entry = root.filteredItems[Math.max(listView.currentIndex, 0)]
                            if (entry) root.pick(entry.realIndex)
                        }
                    }

                    MaterialSymbol {
                        visible: searchField.text.length > 0
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        Layout.rightMargin: 6
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            StyledListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 320 - root.popup.topPadding - root.popup.bottomPadding - searchField.implicitHeight - 12)
                clip: true
                spacing: 0
                popin: false
                animateAppearance: false
                model: root.popup.visible ? root.filteredItems : null
                delegate: entryDelegate
            }
        }
    }
}