pragma Singleton

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
