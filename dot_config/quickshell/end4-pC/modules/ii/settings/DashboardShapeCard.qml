import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

DashboardCard {
    id: root

    property string controlKey: ""
    property string title: ""
    property string icon: "shapes"
    property var tileShape: MaterialShape.Shape.Flower
    property var override: null

    readonly property var control: override ?? SettingsQuickControls.controls[controlKey] ?? null
    readonly property var currentValue: control ? control.get() : null

    tint: Appearance.colors.colPrimaryContainer

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                shape: root.tileShape
                text: root.icon
                iconSize: 24
                fill: 1
                padding: 10
                color: Appearance.colors.colPrimary
                colSymbol: Appearance.colors.colOnPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimaryContainer
                elide: Text.ElideRight
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: grid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: grid
                width: flick.width
                y: Math.max(0, flick.height - height)
                spacing: 6

                Repeater {
                    model: root.control?.options ?? []

                    delegate: Rectangle {
                        id: tile
                        required property var modelData

                        readonly property bool selected: root.currentValue === modelData

                        width: 42
                        height: 42
                        radius: 14
                        color: selected ? Appearance.colors.colPrimary : Qt.rgba(1, 1, 1, 0.1)

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }

                        MaterialShape {
                            anchors.centerIn: parent
                            implicitSize: 26
                            shape: ShapeUtils.getShape(tile.modelData)
                            color: tile.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const value = tile.modelData;
                                Qt.callLater(() => root.control.set(value));
                            }
                        }
                    }
                }
            }
        }
    }
}
