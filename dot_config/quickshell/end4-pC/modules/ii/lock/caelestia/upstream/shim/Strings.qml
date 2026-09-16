pragma Singleton

import QtQuick
import Quickshell

/** 上游 `qs.utils.Strings` 里锁屏用到的那两个格式化函数。 */
Singleton {
    id: root

    /** 0.35 → "35%" */
    function percent(value) {
        return Math.round(Number(value) * 100) + "%";
    }

    /** 0.35 → "35%"（上游的 percentOne 是保留一位小数的版本） */
    function percentOne(value) {
        return (Math.round(Number(value) * 1000) / 10) + "%";
    }
}
