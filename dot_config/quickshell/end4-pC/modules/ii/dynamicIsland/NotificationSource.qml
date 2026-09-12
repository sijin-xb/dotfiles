import QtQuick
import qs.services

// 通知活动源：来通知时短暂注册 "notification" 活动，
// 灵动岛会在主岛右侧挂一个小胶囊轻轻顶一下，几秒后自动消失。
//
// 不做常驻、不抢主岛：仅当已有其它活动（音乐 / 录屏 / 包管理）时才显示为副岛，
// 避免打断正在看的内容。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // 同时到达的多条通知只显示最新一条
    property string summary: ""
    property string appName: ""
    property string body: ""

    readonly property int visibleDuration: 4000

    // 展开通知时置 true：暂停自动清除，否则正文还没读完就消失了。
    property bool holdOpen: false

    onHoldOpenChanged: {
        if (holdOpen)
            ActivityManager.hold("notification")
        else if (ActivityManager.entries["notification"] !== undefined)
            ActivityManager.release("notification", visibleDuration)
    }

    function show(notif) {
        // 场景静默（录屏 / 专注模式）时不打扰
        if (!IslandContext.allowTransient())
            return
        summary = notif?.summary ?? ""
        appName = notif?.appName ?? ""
        body = notif?.body ?? ""
        ActivityManager.pulse("notification", {
            summary: summary,
            appName: appName,
            body: body
        }, 6, visibleDuration, { transient: true })
    }

    function dismiss() {
        ActivityManager.clear("notification")
    }

    Connections {
        target: Notifications
        ignoreUnknownSignals: true
        function onNotify(notification) {
            root.show(notification)
        }
    }

}
