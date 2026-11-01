pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// 场景门控：决定瞬态活动（音量 / 通知）当前是否允许出现。
//
// 两级来源：
//   - 自动：场景由 ActivityManager 推导。录屏时不弹音量条，避免污染演示画面。
//   - 手动：Persistent.states.island.silentMode，用户在设置里开「专注」后静默全部瞬态。
Singleton {
    id: root

    readonly property string scene: ActivityManager.scene

    // 手动静默：持久化，默认关闭
    readonly property bool silentMode: Persistent.states.island.silentMode ?? false

    // 场景级静默：录屏中不打扰
    readonly property bool sceneSilent: scene === "recording"

    readonly property bool suppressTransient: silentMode || sceneSilent

    function allowTransient() {
        return !suppressTransient
    }

    function setSilentMode(on) {
        Persistent.states.island.silentMode = on
    }
}
