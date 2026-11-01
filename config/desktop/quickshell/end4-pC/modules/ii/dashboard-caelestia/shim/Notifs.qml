pragma Singleton

import QtQuick
import Quickshell
import qs.services

/** 上游 `Notifs` → 本仓库 `Notifications`。通知坞用 list / notClosed。 */
Singleton {
    id: root

    readonly property var list: Notifications.list
    /** 上游语义：还没被手动关掉的通知。本仓库没有该字段，等价于全部未关闭的通知。 */
    readonly property var notClosed: Notifications.list
}
