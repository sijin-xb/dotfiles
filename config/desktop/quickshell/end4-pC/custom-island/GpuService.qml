// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植并改造：src/services/system/GpuService.qml
//
// 为什么要改：原版是按「Intel 核显 + NVIDIA 独显」写死的，读的是
//   /sys/class/drm/card1/gt/gt0/rps_act_freq_mhz  （Intel 专属）
//   nvidia-smi                                     （NVIDIA 专属）
// 本机只有一张 AMD 独显 Radeon RX 7600M XT (Navi 33, PCI 1002:7480)，
// 上面这些节点和命令都不存在，所以改成读 amdgpu 驱动暴露的节点：
//   使用率   /sys/class/drm/card*/device/gpu_busy_percent
//   VRAM     /sys/class/drm/card*/device/mem_info_vram_{used,total}
//   频率     /sys/class/hwmon/hwmon*/freq1_input  (name=amdgpu, 单位 Hz, 当前 sclk)
//   最高频率 /sys/class/drm/card*/device/pp_dpm_sclk (取最大 DPM 档位)
//   温度     /sys/class/hwmon/hwmon*/temp1_input  (毫摄氏度)
//   功耗     /sys/class/hwmon/hwmon*/power1_average (微瓦)
// 以上节点已在本机逐条确认可读。
//
// 公开 API 形状保持不变（DashStats / TempPanel / PowerPanel 直接引用）：
//   bool   active
//   string envyMode
//   igpu { real freqPercent; string curMhz; string maxMhz }
//   dgpu { bool active; real usagePercent; string usedVram; string totalVram }
//
// 新增（AMD 拿得到、原版没有的指标，纯增量，不影响既有引用）：
//   dgpu.curMhz / dgpu.maxMhz / dgpu.freqPercent
//   dgpu.tempC / dgpu.tempStr / dgpu.powerW / dgpu.powerStr
//
// 诚实降级：
//   - 本机没有核显，igpu.* 恒为 0 / "— MHz"（属性保留，不删）。
//   - dgpu.active 的语义从「envycontrol 独显开关」变成「检测到 amdgpu 显卡」。
//   - envyMode 默认 "hybrid"：本机没有 envycontrol，没有任何东西会去改它。
// ─────────────────────────────────────────────────────────────────────────────

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool   active:   true
    property string envyMode: "hybrid"

    property QtObject igpu: QtObject {
        // 本机无核显：保持 0 / "— MHz"，不伪造数据
        // active=false 让上层（DashStats）直接把 iGPU 表盘藏掉，
        // 否则会留一个永远 0% 的死表盘
        property bool   active:     false
        property real   freqPercent: 0.0
        property string curMhz:     "— MHz"
        property string maxMhz:     "— MHz"
    }

    property QtObject dgpu: QtObject {
        property bool   active:       false
        property real   usagePercent: 0.0
        property string usedVram:     "— MB"
        property string totalVram:    "— MB"

        // ── AMD 新增指标 ─────────────────────────────────────────────────────
        property string curMhz:       "— MHz"
        property string maxMhz:       "— MHz"
        property real   freqPercent:  0.0
        property real   tempC:        0
        property string tempStr:      "—"
        property real   powerW:       0
        property string powerStr:     "—"
    }

    // 内部缓存：算 freqPercent 需要同时拿到当前频率与最高频率
    property real _curMhz: 0
    property real _maxMhz: 0

    // ── AMD: 使用率 + VRAM ────────────────────────────────────────────────────
    // 输出三行：gpu_busy_percent / vram_used(字节) / vram_total(字节)
    // 找不到带 gpu_busy_percent 的卡（非 amdgpu）时无输出，视为不可用。
    property var _busyProc: Process {
        command: ["sh", "-c",
            "for d in /sys/class/drm/card*/device; do " +
            "[ -r \"$d/gpu_busy_percent\" ] || continue; " +
            "cat \"$d/gpu_busy_percent\"; " +
            "cat \"$d/mem_info_vram_used\" 2>/dev/null; " +
            "cat \"$d/mem_info_vram_total\" 2>/dev/null; " +
            "break; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parseBusy(text)
        }
    }

    // ── AMD: 当前频率 + 最高频率 ──────────────────────────────────────────────
    // 固定输出两行：freq1_input(Hz) / pp_dpm_sclk 里的最大档位(MHz)
    property var _freqProc: Process {
        command: ["sh", "-c",
            "cur=0; max=0; " +
            "for h in /sys/class/hwmon/hwmon*; do " +
            "[ \"$(cat $h/name 2>/dev/null)\" = \"amdgpu\" ] || continue; " +
            "cur=$(cat \"$h/freq1_input\" 2>/dev/null || echo 0); break; done; " +
            "for f in /sys/class/drm/card*/device/pp_dpm_sclk; do " +
            "[ -r \"$f\" ] || continue; " +
            "max=$(grep -o \"[0-9]*Mhz\" \"$f\" | tr -d \"Mhz\" | sort -n | tail -1); " +
            "break; done; " +
            "printf '%s\\n%s\\n' \"${cur:-0}\" \"${max:-0}\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parseFreq(text)
        }
    }

    // ── AMD: 温度 + 功耗 ──────────────────────────────────────────────────────
    // 固定输出两行：temp1_input(毫摄氏度) / power1_average(微瓦)
    property var _powerProc: Process {
        command: ["sh", "-c",
            "t=0; p=0; " +
            "for h in /sys/class/hwmon/hwmon*; do " +
            "[ \"$(cat $h/name 2>/dev/null)\" = \"amdgpu\" ] || continue; " +
            "t=$(cat \"$h/temp1_input\" 2>/dev/null || echo 0); " +
            "p=$(cat \"$h/power1_average\" 2>/dev/null || echo 0); " +
            "break; done; " +
            "printf '%s\\n%s\\n' \"${t:-0}\" \"${p:-0}\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parsePower(text)
        }
    }

    function _lines(text) {
        return text.trim().split("\n").filter(function(l) { return l.trim() !== "" })
    }

    function _parseBusy(text) {
        var lines = root._lines(text)
        if (lines.length < 1) {
            // 没有 amdgpu 卡：如实标记不可用，而不是留着上一次的旧值
            root.dgpu.active       = false
            root.dgpu.usagePercent = 0
            root.dgpu.usedVram     = "— MB"
            root.dgpu.totalVram    = "— MB"
            return
        }

        root.dgpu.active       = true
        root.dgpu.usagePercent = parseFloat(lines[0]) || 0

        if (lines.length >= 3) {
            var used  = parseFloat(lines[1])
            var total = parseFloat(lines[2])
            if (!isNaN(used))  root.dgpu.usedVram  = Math.round(used  / 1024 / 1024) + " MB"
            if (!isNaN(total)) root.dgpu.totalVram = Math.round(total / 1024 / 1024) + " MB"
        }
    }

    function _parseFreq(text) {
        var lines = root._lines(text)

        if (lines.length >= 1) {
            var hz = parseFloat(lines[0])
            if (!isNaN(hz) && hz > 0) {
                root._curMhz     = hz / 1e6
                root.dgpu.curMhz = Math.round(root._curMhz) + " MHz"
            }
        }

        if (lines.length >= 2) {
            var m = parseFloat(lines[1])
            if (!isNaN(m) && m > 0) {
                root._maxMhz     = m
                root.dgpu.maxMhz = Math.round(m) + " MHz"
            }
        }

        if (root._curMhz > 0 && root._maxMhz > 0) {
            // 睿频时当前频率可能超过 DPM 最高档，夹到 0–100 防止仪表盘溢出
            root.dgpu.freqPercent = Math.max(0, Math.min(100,
                Math.round((root._curMhz / root._maxMhz) * 100)))
        }
    }

    function _parsePower(text) {
        var lines = root._lines(text)

        if (lines.length >= 1) {
            var milli = parseFloat(lines[0])
            if (!isNaN(milli) && milli > 0) {
                root.dgpu.tempC    = milli / 1000
                root.dgpu.tempStr  = root.dgpu.tempC.toFixed(0) + "°C"
            }
        }

        if (lines.length >= 2) {
            var micro = parseFloat(lines[1])
            if (!isNaN(micro) && micro > 0) {
                root.dgpu.powerW    = micro / 1e6
                root.dgpu.powerStr  = root.dgpu.powerW.toFixed(1) + " W"
            }
        }
    }

    // ── Poll timer ────────────────────────────────────────────────────────────
    property var _pollTimer: Timer {
        interval: 1000
        running:  root.active
        repeat:   true
        onTriggered: root._run()
    }

    function _run() {
        _busyProc.running   = false
        _busyProc.running   = true
        _freqProc.running   = false
        _freqProc.running   = true
        _powerProc.running  = false
        _powerProc.running  = true
    }

    // ── dGPU active state follows envyMode ────────────────────────────────────
    // 保留上游语义：envyMode 为 "integrated" 时视为独显被关掉。
    // 本机没有 envycontrol，正常不会被触发。
    onEnvyModeChanged: {
        if (envyMode === "integrated") {
            dgpu.active       = false
            dgpu.usagePercent = 0
            dgpu.usedVram     = "— MB"
            dgpu.totalVram    = "— MB"
        }
    }

    Component.onCompleted: _run()
}
