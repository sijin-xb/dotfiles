pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.modules.common
import "../../components"

// 移植自 caelestia-dots/shell（GPL-3.0）modules/lock/center/Clock.qml。
// 时针 m3primary、分针 m3secondary，分色排版。
Item {
    id: root

    required property real centerScale

    property date now: new Date()

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    function calcTopOff(metrics: TextMetrics): real {
        return metrics.tightBoundingRect.y - metrics.boundingRect.y;
    }

    implicitWidth: hours.implicitWidth + minutes.implicitWidth + Tokens.spacing.small
    implicitHeight: hourMetrics.tightBoundingRect.height

    StyledText {
        id: hours

        y: -root.calcTopOff(hourMetrics)
        text: Qt.formatDateTime(root.now, "hh")
        color: Appearance.m3colors.m3primary
        font: Tokens.font.headline.builders.large.scale(7 * root.centerScale).width(30).build()

        TextMetrics {
            id: hourMetrics
            text: hours.text
            font: hours.font
        }
    }

    StyledText {
        id: minutes

        anchors.right: parent.right
        y: -root.calcTopOff(minuteMetrics)
        text: Qt.formatDateTime(root.now, "mm")
        color: Appearance.m3colors.m3secondary
        font: Tokens.font.headline.builders.large.scale(7 * root.centerScale).width(30).build()

        TextMetrics {
            id: minuteMetrics
            text: minutes.text
            font: minutes.font
        }
    }
}
