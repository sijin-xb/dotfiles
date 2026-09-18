/**
 * 从 Brain_Shell 的 src/modules/Center/DashStats.qml 移植（仪表盘「System」系统页）。
 *
 * 改动：
 *   1) 删掉 `import "../../"`、`import "../../components"`、`import "../../services/"`。
 *      扁平化后 Theme 单例和各组件都靠同目录隐式导入，不再需要相对路径。
 *   2) 删掉 `FanControl { id: fan }` 和 `EnvyControlService { id: envy }` 两处实例化
 *      —— 这两个服务不在本次移植范围（用户 AMD 独显，无 NVIDIA/envycontrol，
 *      也不做风扇调速）。
 *   3) `GpuService` 去掉了 `envyMode: envy.currentMode` 绑定：envy 没了，没东西可喂。
 *      属性本身由 GpuService 保留（并行移植保持 Brain_Shell 形状），这里走默认值。
 *   4) 下面 `FanPanel` 不再传 `service`（FanPanel 自己读 sysfs，见 FanPanel.qml
 *      文件头的降级说明），`PowerPanel` 不再传 `envyService`。
 *   5) 外层 Column 改成 Row，右侧塞入一张通高的进程卡（ProcessPanel）。
 *   6) 左侧因此变窄，原「温度 | 风扇」两卡一行改成「温度 | 风扇 | 网络」三卡一行，
 *      原来「网络 | 磁盘 | 电源」那一行只留「磁盘 | 电源」。
 *      原因：网络卡里的 StatRow 是 label/value 两端对齐，实测内容宽约 126px，
 *      卡宽低于 ~175px 就会开始 elide（"↑ Upload" 和 "4.3 MB/s" 撞在一起）。
 *      三卡平分 536px 时每张 173px，刚好够；继续挤在四卡行里必然放不下。
 */
import QtQuick

Item {
    id: root

    // 本机（AMD 独显）没有核显，iGPU 表盘只会显示 0% / — MHz，
    // 是个死表盘。检测不到核显时不画它，让剩下 3 个表盘平分整行宽度。
    readonly property bool hasIgpu:    gpu.igpu.active
    readonly property int  gaugeCount: root.hasIgpu ? 4 : 3

    // 右侧进程卡宽度。340 是实测下限：再窄进程名那一列就只剩两三个字符。
    readonly property int procCardW: 340
    readonly property int gap: 8

    CpuService         { id: cpu;     active: root.visible }
    MemService         { id: mem;     active: root.visible }
    NetService         { id: net;     active: root.visible }
    ThermalService     { id: thermal; active: root.visible }
    DiskService        { id: disk;    active: root.visible }
    CpuFreqService     { id: cpuFreq }
    GpuService {
        id:       gpu
        active:   root.visible
    }

    Row {
        anchors {
            fill:          parent
            bottomMargin:  8
            topMargin:     8
        }
        spacing: root.gap

        // ── 左列：原来的三行统计 ───────────────────────────────────────────
        Column {
            id: leftCol
            width:  parent.width - procCard.width - root.gap
            height: parent.height
            spacing: root.gap

            // Speedometers
            Row {
                id:      speedoRow
                width:   parent.width
                anchors.topMargin: 4
                height:  160
                spacing: 8

                StatCard {
                    width:  (parent.width - parent.spacing * (root.gaugeCount - 1)) / root.gaugeCount
                    height: parent.height
                    Speedometer {
                        anchors.centerIn: parent
                        label:       "CPU"
                        percent:     cpu.usagePercent
                        centerText:  cpu.usagePercent + "%"
                        bottomText:  cpuFreq.curFreqStr
                        active:      true
                        accentColor: Theme.active
                    }
                }

                StatCard {
                    width:  (parent.width - parent.spacing * (root.gaugeCount - 1)) / root.gaugeCount
                    height: parent.height
                    Speedometer {
                        anchors.centerIn: parent
                        label:       "RAM"
                        percent:     mem.usagePercent
                        centerText:  mem.usagePercent + "%"
                        bottomText:  mem.usedStr + " / " + mem.totalStr
                        active:      true
                        accentColor: "#cba6f7"
                    }
                }

                StatCard {
                    width:  (parent.width - parent.spacing * (root.gaugeCount - 1)) / root.gaugeCount
                    height: parent.height
                    // 没有核显就不画这张卡（见 root.hasIgpu 的说明）
                    visible: root.hasIgpu
                    Speedometer {
                        anchors.centerIn: parent
                        label:       "iGPU"
                        percent:     gpu.igpu.freqPercent
                        centerText:  gpu.igpu.freqPercent + "%"
                        bottomText:  gpu.igpu.curMhz
                        active:      true
                        accentColor: "#89dceb"
                    }
                }

                StatCard {
                    width:  (parent.width - parent.spacing * (root.gaugeCount - 1)) / root.gaugeCount
                    height: parent.height
                    Speedometer {
                        anchors.centerIn: parent
                        label:       "dGPU"
                        percent:     gpu.dgpu.active ? gpu.dgpu.usagePercent : 0
                        centerText:  gpu.dgpu.active ? (gpu.dgpu.usagePercent + "%") : "0%"
                        bottomText:  gpu.dgpu.active ? (gpu.dgpu.usedVram + " / " + gpu.dgpu.totalVram) : ""
                        active:      gpu.dgpu.active
                        accentColor: "#a6e3a1"
                    }
                }
            }

            // Thermal | Fan | Network
            Row {
                id:      midRow
                width:   parent.width
                height:  100
                spacing: 8

                // Thermal strip
                // 宽度按实测分配：温度卡里的 Row 用 horizontalCenter 居中，
                // 只画 CPU/GPU 两颗表盘时需要 152px 内容宽（见 TempPanel.showFans），
                // 所以卡宽给到 0.36 才有余量；再窄就会溢出压到邻居卡上。
                StatCard {
                    width:   Math.round((parent.width - parent.spacing * 2) * 0.36)
                    height:  parent.height
                    padding: 6

                    TempPanel {
                        anchors.fill: parent
                        service:      thermal
                        dgpuActive:   gpu.dgpu.active
                        // 风扇转速由右边那张 FanPanel 专卡负责，这里不再重复画
                        showFans:     false
                    }
                }

                // Fan strip
                StatCard {
                    width:   Math.round((parent.width - parent.spacing * 2) * 0.20)
                    height:  parent.height
                    padding: 6

                    FanPanel {
                        anchors.fill: parent
                    }
                }

                // Network
                StatCard {
                    width:   parent.width - Math.round((parent.width - parent.spacing * 2) * 0.36)
                                           - Math.round((parent.width - parent.spacing * 2) * 0.20)
                                           - parent.spacing * 2
                    height:  parent.height
                    padding: 6

                    NetStatsPanel {
                        anchors.fill: parent
                        service:      net
                    }
                }
            }

            // Disks | Power
            Row {
                width:   parent.width
                height:  parent.height - speedoRow.height - midRow.height - parent.spacing * 2
                spacing: 8

                // Disks — horizontal bars stack vertically
                StatCard {
                    width:  Math.round(parent.width * 0.55)
                    height: parent.height
                    DiskPanel {
                        anchors.fill: parent
                        service:      disk
                    }
                }

                // Power — two button rows need space
                StatCard {
                    width:  parent.width - Math.round(parent.width * 0.55) - parent.spacing
                    height: parent.height
                    PowerPanel {
                        anchors.fill:   parent
                        cpuFreqService: cpuFreq
                    }
                }
            }
        }

        // ── 右列：通高进程列表 ─────────────────────────────────────────────
        StatCard {
            id: procCard
            width:  root.procCardW
            height: parent.height

            ProcessPanel {
                anchors.fill: parent
                active:       root.visible
            }
        }
    }
}
