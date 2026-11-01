pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    readonly property var visualizerStyles: [
        { key: "bars",          icon: "bar_chart",             name: Translation.tr("Bars spectrum") },
        { key: "mirror",        icon: "align_vertical_center", name: Translation.tr("Mirror spectrum") },
        { key: "line",          icon: "show_chart",            name: Translation.tr("Line spectrum") },
        { key: "wave",          icon: "waves",                 name: Translation.tr("Wave curve") },
        { key: "dots",          icon: "scatter_plot",          name: Translation.tr("Dot matrix") },
        { key: "area",          icon: "area_chart",            name: Translation.tr("Filled wave") },
        { key: "circular",      icon: "donut_large",           name: Translation.tr("Circular radial") },
        { key: "particles",     icon: "bubble_chart",          name: Translation.tr("Particle burst") },
        { key: "spectrum",      icon: "equalizer",             name: Translation.tr("Centered spectrum") },
        { key: "waveSpectrum",  icon: "multiple_stop",         name: Translation.tr("Mirror waveform") },
    ]
    readonly property string currentVisualStyle: Config.options.background.widgets.visualizer.style ?? "bars"
    readonly property string currentStyleName: root.visualizerStyles.find(s => s.key === root.currentVisualStyle)?.name ?? ""

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol { text: "graphic_eq"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
            StyledText { Layout.fillWidth: true; text: Translation.tr("Visualizer style"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
            StyledText { text: root.currentStyleName; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer1; opacity: 0.6 }
        }

        Row {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 4
            Repeater {
                model: root.visualizerStyles
                delegate: RippleButton {
                    required property var modelData
                    implicitWidth: 40
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    readonly property bool active: root.currentVisualStyle === modelData.key
                    colBackground: active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer2
                    colRipple: Appearance.colors.colSecondary
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        opacity: active ? 1 : 0.7
                    }
                    StyledToolTip { text: modelData.name }
                    onClicked: Config.options.background.widgets.visualizer.style = modelData.key
                }
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            Layout.topMargin: 4
            buttonIcon: "graphic_eq"
            text: Translation.tr("Visualizer")
            checked: Config.options.background.widgets.visualizer.enable
            onCheckedChanged: Config.options.background.widgets.visualizer.enable = checked
        }
    }
}
