// ─────────────────────────────────────────────────────────────────────────────
// 频谱数据源：改用 Caelestia 的 C++ cava 插件
//
// 以前这份数据来自 `cava` 子进程（MediaControls.qml 里的 Process），走的是
// 「raw ascii → stdout → SplitParser → 字符串 split → parseFloat」这条路：
// 一个常驻子进程，外加每帧一次的全文本解析，而且解析就发生在 qs 主线程上。
//
// Caelestia 的 QML 插件里有个 CavaProvider（plugin/src/Caelestia/Services/
// cavaprovider.cpp）：音频从 PipeWire 抓（AudioCollector，进程内共享单例），
// libcava 直接算 FFT，跑在自己的 QThread 上，算完只把 QVector<double> 交给 QML。
// 没有子进程，也没有文本解析。
//
// 接进本仓库前有两个差异必须先对齐，否则波形会不对：
//
//   1. **值域**。下游是按 0~1000 归一化的 —— 见 modules/ii/bar/Visualizer.qml 的
//      `maxVisualizerValue: 1000`、modules/ii/background/widgets/visualizer/
//      VisualizerWidget.qml 的 `effectiveMaxV = 1000 / sensitivity`（因为 cava
//      的 ascii 输出上限由 ascii_max_range 决定，默认就是 1000）。而 CavaProvider
//      给的是**归一化后的 0~1**（caelestia 自己的 VisualiserBars 里是
//      clamp(…, 0, 1)）。
//
//      valueScale 取 600 是实测出来的，不是拍脑袋。同一段音频同时喂两个源，
//      跳过 autosens 收敛期后统计：
//          原 cava   逐帧峰值 p50 = 616、p90 = 819；所有值 p50/p90/p99 = 16/166/631
//          C++ 源    逐帧峰值 p50 = 1.0（autosens 打满）；所有值 = 0.1/0.3/1.0
//      乘 600 之后 C++ 的 p90/p99 落在 186/620，与原 cava 的 166/631 基本重合，
//      量级与视觉高度都对得上。两个源的 FFT 配置本来就不同（原配置是
//      `mode = waves` + noise_reduction = 20，插件走 libcava 默认 mode +
//      noise_reduction = 0.85，外加一道 monstercat 滤波），形状不可能完全一致，
//      这里只对齐量级。
//
//   2. **推送频率**。CavaProvider 的 timer 间隔是
//      k_chunkSize * 1000 / k_sampleRate = 512 * 1000 / 44100 ≈ 11ms，也就是
//      ~90Hz，比原来 cava 配置里的 framerate = 60 还密。而下游有好几个消费者会
//      跟着数据重采样（VisualizerWidget 每次要跑 160 点 + 64 点两趟 JS 循环），
//      所以这里做 30Hz 节流，且只在「值确实变过」时才更新 points。
//
// 本文件**不是单例**（所以没有 pragma Singleton）：它由调用方用 Loader 或
// Qt.createComponent 动态加载，这样插件缺失（没编译 / QML2_IMPORT_PATH 没指对）
// 时只会让加载方拿到一个 Error，据此回退到 cava 子进程，而不是让整个 shell 挂掉。
//
// 用法：
//     Loader { id: bridge; source: "…/services/CaelestiaCava.qml" }
//     Binding { target: 某处; property: "points"; value: bridge.item?.points ?? [] }
// ─────────────────────────────────────────────────────────────────────────────

import QtQuick
import Caelestia.Services

// 根类型用 QtObject：它不参与渲染，所以挂到 Loader 下不会出现
// 「Created graphical object was not placed in the graphics scene」那条警告。
// 代价是 QtObject 没有默认属性，子对象得写成属性绑定（见下面几个 readonly property）。
QtObject {
    id: root

    /** 是否让 C++ 侧开始采集。置 false 会 unref，插件内部随之 stop()。 */
    property bool active: false

    /** 输出柱数。默认与原来的 cava 配置（scripts/cava/raw_output_config.txt 的 bars = 50）一致。 */
    property int bars: 50

    /** 值域缩放：CavaProvider 是 0~1，乘这个数对齐下游的 0~1000 语义。取值依据见文件头。 */
    property real valueScale: 600

    /** 缩放后的频谱数据，长度 = bars */
    readonly property list<real> points: _points

    property list<real> _points: []

    readonly property CavaProvider cava: CavaProvider {
        bars: root.bars
    }

    // ServiceRef 的 service 是可写的，而 Service::ref/unref 是引用计数 ——
    // 置 null 就会 unref，计数归零时插件内部 stop()（停 timer、断开 PipeWire）。
    // 于是「到底有没有人在看波形」这件事就完全由 QML 侧的绑定来表达。
    readonly property ServiceRef svcRef: ServiceRef {
        service: root.active ? root.cava : null
    }

    // 高频的 valuesChanged 只置个脏标记，真正写回由下面 30Hz 的 Timer 做
    property bool _dirty: false

    // 只打印一次，便于排查「为什么没有波形」（数据源到底起没起来）
    property bool _loggedFirstFrame: false

    readonly property Connections conn: Connections {
        target: root.cava

        function onValuesChanged(): void {
            root._dirty = true
        }
    }

    readonly property Timer ticker: Timer {
        interval: 33
        repeat: true
        running: root.active

        onTriggered: {
            if (!root._dirty)
                return
            root._dirty = false

            const values = root.cava.values
            const out = new Array(values.length)
            for (let i = 0; i < values.length; i++)
                out[i] = Math.min(1, Math.max(0, values[i])) * root.valueScale
            root._points = out

            if (!root._loggedFirstFrame) {
                root._loggedFirstFrame = true
                console.info("[CaelestiaCava] 频谱数据源就绪：bars=" + out.length
                             + " scale=" + root.valueScale
                             + " 首帧前 5 点=" + out.slice(0, 5).map(v => v.toFixed(1)).join(","))
            }
        }
    }

    // 停用时立刻清空，让下游回到「没有数据」的状态（和以前 cavaProc 停掉时一致）
    onActiveChanged: {
        if (!root.active) {
            root._dirty = false
            root._points = []
        }
    }
}
