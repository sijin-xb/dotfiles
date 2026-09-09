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

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "motion_photos_on"
            text: Translation.tr("Enable")
            checked: Config.options.background.parallax.enable
            onCheckedChanged: Config.options.background.parallax.enable = checked
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "drag_pan"
            text: Translation.tr("Move on workspace switch")
            checked: Config.options.background.parallax.enableWorkspace
            enabled: Config.options.background.parallax.enable
            onCheckedChanged: Config.options.background.parallax.enableWorkspace = checked
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "side_navigation"
            text: Translation.tr("Move on sidebar toggle")
            checked: Config.options.background.parallax.enableSidebar
            enabled: Config.options.background.parallax.enable
            onCheckedChanged: Config.options.background.parallax.enableSidebar = checked
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "mouse"
            text: Translation.tr("Cursor follow")
            checked: Config.options.background.parallax.enableCursor
            enabled: Config.options.background.parallax.enable
            onCheckedChanged: Config.options.background.parallax.enableCursor = checked
        }
    }
}
