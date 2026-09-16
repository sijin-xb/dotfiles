#!/usr/bin/env python3
"""生成本地 shim 模块，让上游 Caelestia 锁屏可以「零业务改动」跑在本仓库上。

上游文件里 `import qs.services` / `import qs.utils` 指向的是 Caelestia 自己的
shell 根；vendored 过来之后这些 import 被改写成 `import "shim"`，于是所有
`Colours.*` / `Players.*` / `Weather.*` / `Time.*` / `Notifs.*` / `Hypr.*` /
`Paths.*` / `Strings.*` 都由这里提供，业务代码一行不用动。

引用次数（决定优先级）：
    Colours 264 · Players 15 · Hypr 14 · Config 13 · Weather 11
    Notifs 5 · Time 4 · Strings 4 · Paths 4 · Wallpapers 1

映射目标：
    Colours → Appearance.m3colors / colors      （跟随壁纸取色）
    Players → MprisController
    Hypr    → HyprlandXkb / HyprlandData
    Time    → DateTime
    Notifs  → Notifications
    Paths / Strings → 本地实现（纯字符串处理）
    Weather / Config → 本仓库同名服务，成员名不一致处做适配

用法：gen-lock-shim.py <shim 目录>
"""

from __future__ import annotations

import pathlib
import sys

FILES: dict[str, str] = {}

FILES["qmldir"] = """module shim
singleton Colours 1.0 Colours.qml
singleton Players 1.0 Players.qml
singleton Weather 1.0 Weather.qml
singleton Time 1.0 Time.qml
singleton Notifs 1.0 Notifs.qml
singleton Hypr 1.0 Hypr.qml
singleton Paths 1.0 Paths.qml
singleton Strings 1.0 Strings.qml
singleton Config 1.0 Config.qml
"""

# ── Colours：上游引用最多（264 次），全部映射到本仓库的 M3 调色板 ────────
FILES["Colours.qml"] = '''pragma Singleton

import QtQuick
import qs.modules.common

/**
 * 上游 Caelestia 锁屏的配色入口。
 *
 * 上游用的是 `Caelestia.Config` 里的 `Colours`；本仓库整套配色由 matugen 生成、
 * 落在 `Appearance.m3colors`。这里做一层同名映射，于是上游文件里的
 * `Colours.palette.m3primary` 这类写法一个字都不用改，就能跟随壁纸取色。
 *
 * `tPalette` 是终端调色板（上游拿它做锁屏的次级容器底色），
 * 本仓库没有对应物，用 M3 的 surface container 系列顶上。
 * `layer` 是上游的层叠底色数组，映射到 M3 的 surface container 阶梯。
 */
Singleton {
    id: root

    readonly property bool light: !Appearance.m3colors.darkmode

    readonly property QtObject palette: QtObject {
        property color m3background: Appearance.m3colors.m3background
        property color m3onBackground: Appearance.m3colors.m3onBackground
        property color m3surface: Appearance.m3colors.m3surface
        property color m3surfaceDim: Appearance.m3colors.m3surfaceDim
        property color m3surfaceBright: Appearance.m3colors.m3surfaceBright
        property color m3surfaceContainerLowest: Appearance.m3colors.m3surfaceContainerLowest
        property color m3surfaceContainerLow: Appearance.m3colors.m3surfaceContainerLow
        property color m3surfaceContainer: Appearance.m3colors.m3surfaceContainer
        property color m3surfaceContainerHigh: Appearance.m3colors.m3surfaceContainerHigh
        property color m3surfaceContainerHighest: Appearance.m3colors.m3surfaceContainerHighest
        property color m3onSurface: Appearance.m3colors.m3onSurface
        property color m3surfaceVariant: Appearance.m3colors.m3surfaceVariant
        property color m3onSurfaceVariant: Appearance.m3colors.m3onSurfaceVariant
        property color m3inverseSurface: Appearance.m3colors.m3inverseSurface
        property color m3inverseOnSurface: Appearance.m3colors.m3inverseOnSurface
        property color m3outline: Appearance.m3colors.m3outline
        property color m3outlineVariant: Appearance.m3colors.m3outlineVariant
        property color m3shadow: Appearance.m3colors.m3shadow
        property color m3scrim: Appearance.m3colors.m3scrim
        property color m3surfaceTint: Appearance.m3colors.m3surfaceTint
        property color m3primary: Appearance.m3colors.m3primary
        property color m3onPrimary: Appearance.m3colors.m3onPrimary
        property color m3primaryContainer: Appearance.m3colors.m3primaryContainer
        property color m3onPrimaryContainer: Appearance.m3colors.m3onPrimaryContainer
        property color m3inversePrimary: Appearance.m3colors.m3inversePrimary
        property color m3secondary: Appearance.m3colors.m3secondary
        property color m3onSecondary: Appearance.m3colors.m3onSecondary
        property color m3secondaryContainer: Appearance.m3colors.m3secondaryContainer
        property color m3onSecondaryContainer: Appearance.m3colors.m3onSecondaryContainer
        property color m3tertiary: Appearance.m3colors.m3tertiary
        property color m3onTertiary: Appearance.m3colors.m3onTertiary
        property color m3tertiaryContainer: Appearance.m3colors.m3tertiaryContainer
        property color m3onTertiaryContainer: Appearance.m3colors.m3onTertiaryContainer
        property color m3error: Appearance.m3colors.m3error
        property color m3onError: Appearance.m3colors.m3onError
        property color m3errorContainer: Appearance.m3colors.m3errorContainer
        property color m3onErrorContainer: Appearance.m3colors.m3onErrorContainer
    }

    // 上游拿 tPalette 做「比 surface 稍深一档」的容器底色
    readonly property QtObject tPalette: QtObject {
        property color m3surfaceContainer: Appearance.m3colors.m3surfaceContainerLow
        property color m3surfaceContainerHigh: Appearance.m3colors.m3surfaceContainer
        property color m3surfaceContainerHighest: Appearance.m3colors.m3surfaceContainerHigh
    }

    // 上游的层叠底色：layer0 最外层，数字越大越靠上层
    readonly property var layer: [
        Appearance.colors.colLayer0,
        Appearance.colors.colLayer1,
        Appearance.colors.colLayer2,
        Appearance.colors.colLayer3,
        Appearance.colors.colLayer4
    ]
}
'''

# ── Players → MprisController ─────────────────────────────────────────────
FILES["Players.qml"] = '''pragma Singleton

import QtQuick
import qs.services

/** 上游 `Players` → 本仓库 `MprisController`。上游只用到 active 与 getArtUrl。 */
Singleton {
    id: root

    readonly property var active: MprisController.activePlayer
    readonly property var list: MprisController.players

    /** 上游签名：getArtUrl(player, size) */
    function getArtUrl(player, size) {
        if (!player)
            return "";
        const url = player.trackArtUrl;
        return url ? url : "";
    }
}
'''

# ── Time → DateTime ──────────────────────────────────────────────────────
FILES["Time.qml"] = '''pragma Singleton

import QtQuick
import qs.services

/** 上游 `Time` → 本仓库 `DateTime`。上游锁屏的大时钟用这四个成员。 */
Singleton {
    id: root

    readonly property string hourStr: String(DateTime.hour12).padStart(2, "0")
    readonly property string minuteStr: String(DateTime.clock.date.getMinutes()).padStart(2, "0")
    readonly property string amPmStr: DateTime.hour24 < 12 ? "AM" : "PM"

    function format(fmt) {
        return Qt.locale().toString(DateTime.clock.date, fmt);
    }
}
'''

# ── Notifs → Notifications ───────────────────────────────────────────────
FILES["Notifs.qml"] = '''pragma Singleton

import QtQuick
import qs.services

/** 上游 `Notifs` → 本仓库 `Notifications`。通知坞用 list / notClosed。 */
Singleton {
    id: root

    readonly property var list: Notifications.list
    /** 上游语义：还没被手动关掉的通知。本仓库没有该字段，等价于全部未关闭的通知。 */
    readonly property var notClosed: Notifications.list
}
'''

# ── Hypr → HyprlandXkb（锁屏的 Caps Lock / 布局指示） ────────────────────
FILES["Hypr.qml"] = '''pragma Singleton

import QtQuick
import qs.services

/**
 * 上游 `Hypr` → 本仓库 `HyprlandXkb`。
 * 上游锁屏只用到键盘状态：当前布局 + 大小写锁定（在密码框旁提示 Caps Lock）。
 *
 * 布局用本仓库真实的 `currentLayoutName`。
 *
 * capsLock 目前恒为 false：本仓库没有任何服务跟踪大小写锁定状态
 * （Hyprland 也不通过 IPC 广播它，只有 `hyprctl devices -j` 里能查到，轮询不值当）。
 * 待办：接一个事件驱动的来源（例如监听键盘设备，或在按键守护里顺带跟踪）后，
 * 这里的 Caps 提示才会真正出现。其余布局相关的行为不受影响。
 */
Singleton {
    id: root

    readonly property bool capsLock: false
    readonly property string kbLayout: HyprlandXkb.currentLayoutName
    readonly property string kbLayoutFull: HyprlandXkb.currentLayoutName
    readonly property string defaultKbLayout: HyprlandXkb.currentLayoutName
    readonly property bool numLock: false
}
'''

# ── Paths / Strings：纯工具，本地实现 ────────────────────────────────────
FILES["Paths.qml"] = '''pragma Singleton

import QtQuick
import qs.modules.common
import qs.modules.common.functions

/** 上游 `qs.utils.Paths` 里锁屏用到的那几个成员。 */
Singleton {
    id: root

    readonly property string home: Directories.home

    function toLocalFile(path) {
        return String(path).replace(/^file:\\/\\//, "");
    }

    function absolutePath(path) {
        return FileUtils.trimFileProtocol(String(path));
    }
}
'''

FILES["Strings.qml"] = '''pragma Singleton

import QtQuick

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
'''

# ── Weather / Config：本仓库同名服务，成员名做适配 ───────────────────────
FILES["Weather.qml"] = '''pragma Singleton

import QtQuick
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

    readonly property real temp: current ? (current.temp ?? 0) : 0
    readonly property string description: current ? (current.description ?? "") : ""
    readonly property string icon: current ? (current.icon ?? "") : ""
    readonly property var forecast: Weather.weather ? Weather.weather.daily : []
    readonly property var hourlyForecast: Weather.weather ? Weather.weather.hourly : []

    function formatTemp(value) {
        return Math.round(Number(value)) + "°";
    }

    function reload() {
        Weather.reload();
    }
}
'''

FILES["Config.qml"] = '''pragma Singleton

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
'''


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 1
    target = pathlib.Path(sys.argv[1]).expanduser()
    target.mkdir(parents=True, exist_ok=True)
    for name, content in FILES.items():
        (target / name).write_text(content, encoding="utf-8")
    print(f"写出 {len(FILES)} 个 shim 文件到 {target}")
    for name in sorted(FILES):
        print(f"  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
