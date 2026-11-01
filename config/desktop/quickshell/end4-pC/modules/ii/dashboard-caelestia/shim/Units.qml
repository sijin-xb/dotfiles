pragma Singleton

import QtQuick
import Quickshell

/**
 * 上游 `Caelestia.I18n.Units` 里 dashboard 用到的三个函数：
 *   - formatBytes(bytes, compact)   字节 → "KiB / MiB / GiB…"
 *   - formatKibUsage(used, total)   KiB → "used / total"（内存 / 磁盘）
 *   - formatSensorTemp(celsius)     摄氏度 → "NN°C"
 *
 * 上游 Units 还有温度单位换算（C/F/K）、字节大小写偏好等一大套配置，
 * end4-pC 的 dashboard 只用到上面三个，这里做最简实现。
 */
Singleton {
    id: root

    function _fmtBytes(bytes) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let v = Number(bytes);
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i += 1;
        }
        const decimals = i === 0 ? 0 : (v >= 100 ? 0 : (v >= 10 ? 1 : 2));
        return v.toFixed(decimals) + " " + units[i];
    }

    function formatBytes(bytes, compact) {
        return root._fmtBytes(bytes);
    }

    function formatKibUsage(used, total) {
        return root._fmtBytes(used * 1024) + " / " + root._fmtBytes(total * 1024);
    }

    function formatSensorTemp(celsius) {
        return Math.round(Number(celsius)) + "°C";
    }
}
