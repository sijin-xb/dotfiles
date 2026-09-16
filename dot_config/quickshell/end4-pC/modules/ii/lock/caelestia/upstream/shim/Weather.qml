pragma Singleton

import QtQuick
import qs.services

/**
 * 上游 `Weather` → 本仓库 `Weather`。
 *
 * 两边成员名不完全一致：上游是 temp / icon / description / forecast /
 * hourlyForecast / formatTemp / reload，本仓库的字段结构不同。
 * 这里逐个适配；本仓库确实没有的字段返回空值，让天气卡显示占位而不是崩掉。
 */
Singleton {
    id: root

    readonly property var current: Weather.weather ? Weather.weather.current : null

    readonly property real temp: current ? (current.temp ?? 0) : 0
    readonly property string description: current ? (current.description ?? "") : ""
    readonly property string icon: current ? (current.icon ?? "") : ""
    readonly property var forecast: Weather.weather ? Weather.weather.daily : []
    readonly property var hourlyForecast: Weather.weather ? Weather.weather.hourly : []

    function formatTemp(value) {
        return Math.round(Number(value)) + "°";
    }

    function reload() {
        Weather.reload();
    }
}
