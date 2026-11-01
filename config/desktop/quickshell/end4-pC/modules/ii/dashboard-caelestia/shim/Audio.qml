pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Services

/**
 * 上游 `qs.services.Audio` 里 dashboard 用到的两个成员：cava / beatTracker。
 *
 * ⚠ cava 用桩对象，不是真 CavaProvider：
 *   本机 libcava 在实例化 CavaProvider 且 bars>0 时会在
 *   `cava_init → fftw_plan_dft_r2c_1d → fftw_measure_execution_time` 处 SIGSEGV
 *   （见 quickshell 崩溃报告）。这是 FFTW 在本地 CPU + -march=native 下
 *   的 measure 模式问题，QML 层绕不开。
 *
 *   桩对象形状与真 CavaProvider 一致：`.values` 是长度 = bars 的全 0 数组，
 *   `.bars` 是 int —— 这样 CoverVisualiser 的绑定不会拿到 undefined/NaN，
 *   波形会画成最小幅度的一圈短线，不崩。
 *
 *   BeatTracker 走的是独立实现（beattracker.hpp，不是 CavaProcessor），
 *   崩溃栈里没有它，保留真实例。
 */
Singleton {
    id: root

    readonly property int _bars: 50

    readonly property QtObject cava: QtObject {
        readonly property int bars: root._bars

        readonly property var values: {
            const arr = new Array(root._bars);
            for (let i = 0; i < root._bars; i++)
                arr[i] = 0;
            return arr;
        }
    }

    readonly property alias beatTracker: beatTrackerInstance

    BeatTracker {
        id: beatTrackerInstance
    }
}
