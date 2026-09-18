// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/services/system/ThermalService.qml
//
// 改动（仅硬件相关的两处，结构 / 公开 API 与上游完全一致）：
//   1. CPU 温度解析加了 AMD 回退。原版只认 Intel 的 "Package id 0:"，
//      本机是 AMD（k10temp），sensors 输出的是 "Tctl:"，不加回退的话
//      cpuTemp 永远是 "—"。现在先试 Intel 行，找不到再试 Tctl。
//   2. GPU 温度来源从 nvidia-smi 换成 amdgpu hwmon。
//      本机只有 AMD 独显 RX 7600M XT，nvidia-smi 不存在，
//      改为匹配 name=amdgpu 的 hwmon 后读 temp1_input（毫摄氏度）。
//      进程名同步改为 _gpuProc，其余属性名不变。
//
// 公开 API 不变：cpuTemp / gpuTemp / fan1Rpm / fan2Rpm / fanCount /
//                cpuTempStr / gpuTempStr / fan1Str / fan2Str
// ─────────────────────────────────────────────────────────────────────────────

import QtQuick
import Quickshell.Io

// Runs `sensors` every 3s and parses CPU package temp + fan speeds.
// GPU temp is read from the amdgpu hwmon node (AMD-only machine, see header).
//
// Exposes:
//   real   cpuTemp      — CPU package temp °C, 0 if unread
//   real   gpuTemp      — GPU temp °C, 0 if unread/off
//   int    fan1Rpm      — fan1 speed RPM, 0 if not present
//   int    fan2Rpm      — fan2 speed RPM, 0 if not present
//   int    fanCount     — number of fans detected (0, 1, or 2)
//   string cpuTempStr   — e.g. "52°C"
//   string gpuTempStr   — e.g. "65°C" or "—"
//   string fan1Str      — e.g. "2400 RPM" or "—"
//   string fan2Str      — e.g. "0 RPM"    or "—"

QtObject {
    id: root

    property bool   active:     true
    property real   cpuTemp:    0
    property real   gpuTemp:    0
    property int    fan1Rpm:    0
    property int    fan2Rpm:    0
    property int    fanCount:   0
    property string cpuTempStr: "—"
    property string gpuTempStr: "—"
    property string fan1Str:    "—"
    property string fan2Str:    "—"

    // ── sensors process ───────────────────────────────────────────────────────
    property var _proc: Process {
        command: ["sh", "-c", "sensors 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
    }

    // ── amdgpu GPU temp ───────────────────────────────────────────────────────
    // 匹配 name 文件内容为 amdgpu 的 hwmon，读 temp1_input（毫摄氏度）。
    property var _gpuProc: Process {
        command: ["sh", "-c",
            "for h in /sys/class/hwmon/hwmon*; do " +
            "[ \"$(cat $h/name 2>/dev/null)\" = \"amdgpu\" ] || continue; " +
            "cat \"$h/temp1_input\"; break; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var milli = parseFloat(text.trim())
                if (!isNaN(milli) && milli > 0) {
                    root.gpuTemp    = milli / 1000
                    root.gpuTempStr = root.gpuTemp.toFixed(0) + "°C"
                }
            }
        }
    }

    // ── Poll timer ────────────────────────────────────────────────────────────
    property var _timer: Timer {
        interval: 2000
        running:  root.active
        repeat:   true
        onTriggered: root._run()
    }

    function _run() {
        _proc.running    = false
        _proc.running    = true
        _gpuProc.running = false
        _gpuProc.running = true
    }

    function _parse(text) {
        var lines = text.split("\n")
        var pkg   = -1
        var fans  = []

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]

            // CPU package temp — "Package id 0:  +52.0°C"
            if (/Package id 0:/i.test(line)) {
                var m = line.match(/\+([0-9.]+)°C/)
                if (m) pkg = parseFloat(m[1])
                continue
            }

            // AMD fallback — k10temp exposes "Tctl:  +64.1°C" instead
            if (pkg < 0 && /^\s*Tctl:/i.test(line)) {
                var mt = line.match(/\+([0-9.]+)°C/)
                if (mt) pkg = parseFloat(mt[1])
                continue
            }

            // Fan lines — "fan1:   2400 RPM" or "Fan Speed:  2400 RPM"
            var fm = line.match(/fan\d\s*:\s+([0-9]+)\s+RPM/i)
            if (fm) {
                fans.push(parseInt(fm[1]))
                continue
            }
        }

        if (pkg >= 0) {
            root.cpuTemp    = pkg
            root.cpuTempStr = pkg.toFixed(0) + "°C"
        }

        root.fanCount = fans.length
        root.fan1Rpm  = fans.length > 0 ? fans[0] : 0
        root.fan2Rpm  = fans.length > 1 ? fans[1] : 0
        root.fan1Str  = fans.length > 0 ? fans[0] + " RPM" : "—"
        root.fan2Str  = fans.length > 1 ? fans[1] + " RPM" : "—"
    }

    Component.onCompleted: _run()
}
