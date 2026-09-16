pragma Singleton

import QtQuick
import qs.modules.common

/**
 * 上游 `qs.services.Config` → 本仓库 `Config`。
 *
 * 上游锁屏只用到 `Config.options.*` 里的少量字段（时间格式、锁屏相关开关）。
 * 本仓库的 Config 结构不同，这里把用到的字段做适配；
 * 上游文件里 `Config.options.x` 的写法因此可以保持不变。
 */
Singleton {
    id: root

    readonly property QtObject options: QtObject {
        readonly property QtObject time: QtObject {
            property string format: Config.options.time.format
        }
        readonly property QtObject lock: QtObject {
            // 上游的锁屏行为开关，本仓库没有对应项，给保守默认值
            property bool enableFingerprint: true
            property bool enableWeather: true
            property bool enableMedia: true
            property bool enableNotifications: true
        }
        readonly property QtObject appearance: QtObject {
            // 上游叫 font，本仓库的主字体字段叫 main
            property string font: Config.options.appearance.main
        }
    }
}
