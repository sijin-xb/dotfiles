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

    /**
     * 是否 12 小时制。等价于上游的 `Units.twelveHourClock`。
     * caelestia 插件 v2.5 起把 `Config.services.useTwelveHourClock`（bool）
     * 换成了 `Config.services.clockFormat`（枚举），所以这里改从 end4-pC
     * 自己的 `DateTime.use12HourFormat` 取，不再依赖上游那个被移除的属性。
     */
    readonly property bool twelveHour: DateTime.use12HourFormat

    function format(fmt) {
        return Qt.locale().toString(DateTime.clock.date, fmt);
    }
}
