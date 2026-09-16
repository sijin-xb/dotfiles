pragma Singleton

import QtQuick
import Quickshell
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
