pragma Singleton

import QtQuick
import Quickshell
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

    // 有没有真实天气数据。取不到时（例如定位失败，日志报
    // "[WeatherService] API error: Nothing to geocode"）temp 会落到 0，
    // 直接显示就是一张只有一个「0」的卡 —— 所以调用方要先看 hasData，
    // 决定显示占位符还是真实温度。
    readonly property bool hasData: current !== null && current !== undefined

    // ⚠ 上游的 Weather.temp 是**已格式化好的字符串**（形如 "23°"），不是数字。
    // 本 shim 原先直接透传数字，于是没数据时卡片上只剩一个光秃秃的「0」
    // ——连度符号都没有，看着像坏了。这里改成与上游一致的字符串语义，
    // 顺带修掉锁屏 BriefInfo / WeatherTab 里同样显示裸数字的问题。
    readonly property string temp: root.hasData ? root.formatTemp(current.temp ?? 0) : "--°"

    readonly property string description: current ? (current.description ?? "") : ""
    readonly property string icon: current ? (current.icon ?? "") : ""
    readonly property var forecast: Weather.weather ? Weather.weather.daily : []
    readonly property var hourlyForecast: Weather.weather ? Weather.weather.hourly : []

    function formatTemp(value) {
        return Math.round(Number(value)) + "°";
    }

    function reload() {
        Weather.getData();
    }
}
