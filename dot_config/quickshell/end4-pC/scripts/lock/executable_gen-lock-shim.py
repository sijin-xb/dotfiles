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
import re
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
NotifData 1.0 NotifData.qml
"""

# ── Colours：上游引用最多（264 次），全部映射到本仓库的 M3 调色板 ────────
FILES["Colours.qml"] = '''pragma Singleton

import QtQuick
import qs.modules.common
import qs.modules.common.functions

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

    // 上游的层叠底色不是数组，而是两个函数：
    //   layer(c, layer)  按层级把颜色调暗/加透明度（layer=0 用 base，其余按 layers 递进）
    //   on(c)            取「落在该颜色之上的内容色」
    // 上游 12 处调用的是函数形式，写成数组会报 “Property 'layer' is not a function”。
    // 这里映射到本仓库的透明度体系：开着透明度时逐层加一点，关着就原样返回。
    readonly property QtObject transparency: QtObject {
        readonly property bool enabled: Config.options.appearance.transparency.enable
        readonly property real base: Config.options.appearance.transparency.backgroundTransparency
        readonly property real layers: Config.options.appearance.transparency.contentTransparency
    }

    function layer(c, layerIndex) {
        if (!root.transparency.enabled)
            return c;
        const depth = (layerIndex === undefined || layerIndex === null) ? 1 : layerIndex;
        if (depth === 0)
            return Qt.alpha(c, root.transparency.base);
        // 逐层往 surface 方向混一点，层级越深越不透明
        const mixAmount = Math.min(0.9, root.transparency.layers + depth * 0.08);
        return ColorUtils.mix(c, Appearance.m3colors.m3surface, mixAmount);
    }

    function on(c) {
        // 上游用它取「叠在该色之上的前景色」，本仓库没有对应概念，原样返回
        return c;
    }
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
import Caelestia.Services

/**
 * 上游 `qs.services.Hypr` → 插件自带的 `Caelestia.Services.HyprDevices`。
 *
 * 上游锁屏只用键盘状态：当前布局 + 大小写锁定（在密码框旁提示 Caps Lock）。
 * 这两个都由插件的 `HyprKeyboard` 提供（capsLock / activeKeymap），
 * 所以这里不需要自己造状态源 —— 事件驱动、且与原版行为一致。
 *
 * 注意：`HyprDevices.keyboards` 是列表，取第一个（主键盘）。
 */
Singleton {
    id: root

    readonly property var primaryKeyboard: {
        const keyboards = HyprDevices.keyboards;
        return (keyboards && keyboards.length > 0) ? keyboards[0] : null;
    }

    readonly property bool capsLock: root.primaryKeyboard ? root.primaryKeyboard.capsLock : false
    readonly property string kbLayout: root.primaryKeyboard ? root.primaryKeyboard.activeKeymap : ""
    readonly property string kbLayoutFull: root.kbLayout
    readonly property string defaultKbLayout: root.kbLayout
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

# ── Config：**不提供** ────────────────────────────────────────────────────
# 插件的 `Caelestia.Config` 已经导出了 `Config`（与 `Tokens`、`GlobalConfig` 一起），
# 上游文件里的 `Config.lock.*` / `Config.appearance.*` 直接就能用。
# 如果 shim 再提供一个 `Config`，会和插件的同名单例撞车（两个 import 都提供同名类型），
# 所以这里刻意不生成它。


# ── 从上游 services/ 直接 vendor 的类型（纯数据类，不需要适配） ──────────
# NotifData 是通知的数据对象（NotifGroup 用它构造条目），上游放在 services/ 下，
# 插件也没导出它。它只依赖 Qt / Caelestia.*，所以原样搬过来、
# 把指向 Caelestia shell 根的 import 换成本地即可。
VENDOR_FROM_SERVICES = ["NotifData.qml"]


def vendor_from_services(upstream: pathlib.Path, target: pathlib.Path) -> int:
    src = upstream / "services"
    count = 0
    for name in VENDOR_FROM_SERVICES:
        path = src / name
        if not path.is_file():
            print(f"  ! 上游没有 {path}，跳过")
            continue
        text = path.read_text(encoding="utf-8")
        # 同一个 shim 目录里互相引用
        text = re.sub(r"^import qs\.services$", 'import "."', text, flags=re.M)
        text = re.sub(r"^import qs\.utils$", 'import "."', text, flags=re.M)
        (target / name).write_text(text, encoding="utf-8")
        count += 1
    return count


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        print("用法：gen-lock-shim.py <shim 目录> <上游仓库根>", file=sys.stderr)
        return 1
    target = pathlib.Path(sys.argv[1]).expanduser()
    upstream = pathlib.Path(sys.argv[2]).expanduser()
    target.mkdir(parents=True, exist_ok=True)
    for name, content in FILES.items():
        # `Singleton { }` 是 Quickshell 提供的根类型（不是 QML 内置的），
        # 少了 `import Quickshell` 会在加载时报 “Singleton is not a type”，
        # 而且报错链条会一路往上抛（Colours → StyledText → … → Content），
        # 看起来像别处坏了。这里统一补上。
        if name.endswith(".qml") and "Singleton {" in content and "import Quickshell" not in content:
            content = content.replace("import QtQuick\n", "import QtQuick\nimport Quickshell\n", 1)
        (target / name).write_text(content, encoding="utf-8")

    vendored = vendor_from_services(upstream, target)

    print(f"写出 {len(FILES)} 个 shim 文件 + 从上游 vendor {vendored} 个到 {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
