// Caelestia 锁屏移植的独立测试外壳。
//
// 为什么需要它：上游的 LockSurface 是 WlSessionLockSurface，只有真的锁会话时才能渲染 ——
// 每验一次都要锁一次屏，1:1 比对根本没法做。
// 这个外壳把锁屏的**可见部分**（upstream/Content.qml，就是那个三栏布局：
// 左 Weather/Fetch/Media、中 Center、右 Resources/NotifDock）渲染在一个全屏浮层里，
// 于是可以在不锁会话的前提下反复比对布局与交互。
//
// 由 scripts/lock/locktest.sh 启动（它负责搭好配置目录，让 qs.* 能正常解析）。
// 不要直接 `qs -p` 这个文件 —— 那样 shell 根会变成文件所在目录，
// 上游树与 shim 里的 qs.* import 全都解析不到。
//
// 说明：
// · LockSurface 里除 Content 之外的部分（方块展开动画、锁图标、解锁动画）依赖真实的
//   WlSessionLock，测不到；那部分只能在真锁屏上验。
// · lock / pam 是桩对象，只提供上游 QML 真正读到的成员（值抄自上游 Pam.qml 的对外接口）。
// · 布局尺寸（Tokens.*、Config.lock.*）来自插件，与原版完全一致。

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.ii.lock.caelestia.upstream as Upstream

ShellRoot {
    id: root

    // ── 桩：pam ────────────────────────────────────────────────────────
    QtObject {
        id: fakePam

        property int state: 0
        property string buffer: ""
        property string message: ""
        property string lockMessage: ""
        property bool active: false
        property var d: null
        property var config: null

        property QtObject passwd: QtObject {
            property bool available: true
            property bool enabled: true
            property bool active: false
            property int tries: 0
            property int maxTries: 3
            property bool canAttempt: true
        }
        property QtObject fprint: QtObject {
            property bool available: false
            property bool enabled: false
            property bool active: false
            property int tries: 0
            property int maxTries: 3
            property bool canAttempt: false
        }
        property QtObject howdy: QtObject {
            property bool available: false
            property bool enabled: false
            property bool active: false
            property int tries: 0
            property int maxTries: 3
            property bool canAttempt: false
        }

        function handleKey(key) {}
        function start() {}
        function abort() {}
    }

    // ── 桩：lock ──────────────────────────────────────────────────────
    QtObject {
        id: fakeLock

        property bool locked: true
        property bool unlocking: false
        property var screen: null
        property var pam: fakePam

        signal unlock()
    }

    // ── 渲染 ──────────────────────────────────────────────────────────
    PanelWindow {
        id: window

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "quickshell:locktest"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "#101014"

        Upstream.Content {
            anchors.fill: parent
            anchors.margins: 48
            lock: fakeLock
        }
    }
}
