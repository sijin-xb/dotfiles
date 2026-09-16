pragma Singleton

import QtQuick
import Quickshell
import qs.services

/** 上游 `Time` → 本仓库 `DateTime`。上游锁屏的大时钟用这四个成员。 */
Singleton {
    id: root

    readonly property string hourStr: String(DateTime.hour12).padStart(2, "0")
    readonly property string minuteStr: String(DateTime.clock.date.getMinutes()).padStart(2, "0")
    readonly property string amPmStr: DateTime.hour24 < 12 ? "AM" : "PM"

    function format(fmt) {
        return Qt.locale().toString(DateTime.clock.date, fmt);
    }
}
