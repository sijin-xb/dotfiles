// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/state/ClockState.qml
//
// 改动：无实质改动 —— 原文件是纯逻辑、没有任何外部依赖（连 import 都只有
//       QtQuick），这里只把根类型 QtObject → Singleton（对齐本目录单例写法），
//       正文逐字保留。
// 用途：ClockCard 的计时器 / 秒表状态。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell

// ClockState — exposes active clock module state for the dynamic island.
// Written by ClockCard, read by CenterNotch / dynamic island.

Singleton {
    // Timer
    property bool   timerRunning: false
    property bool   timerStarted:   false
    property int    timerLeft:    0
    property int    timerTotal:   0
    property string timerDisplay: "00:00"

    // Stopwatch
    property bool   swRunning: false
    property bool   swStarted:   false
    property string swDisplay: "00:00"

    signal requestStopwatchReset()
    signal requestTimerReset()

    // Alarms — list of { id, hour, minute, label, enabled }
    property var alarms: []

    // Nearest upcoming enabled alarm: { hour, minute, label, minsUntil } or null
    property var nextAlarm: null

    // True when something is actively running
    readonly property bool hasActiveEvent:
        timerRunning || swRunning || nextAlarm !== null
}
