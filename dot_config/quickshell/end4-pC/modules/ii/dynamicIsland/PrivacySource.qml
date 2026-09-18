import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.services

// 隐私指示：麦克风 / 摄像头被占用时常驻提示。
//
// 不直接复用 Privacy 服务：它把数组赋给了 bool 属性，空数组在 JS 里是 truthy，
// 判断会恒为真。这里用 .some() 自己算真正的布尔值。
//
// 录屏期间不重复提示——recording 活动已经表达了状态。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // publish() 会写 ActivityManager，进而触发 revision 变化；
    // 而 revision 变化又回调 publish()。这个守卫切断那条环。
    property bool publishing: false

    // ──「麦克风状态不会消失」的根源 ────────────────────────────────────────
    // 之前的实现只看 linkGroup 是否存在（pwlg.source/target.type 匹配），
    // 但 Pipewire 拆掉 app → 销毁目标节点 → 销毁链接之后，Quickshell 的
    // linkGroups 聚合常常滞后：旧的条目连同里头的 source/target PwNodeIface
    // 一并被当成僵尸保留下来，`.some()` 继续返回 true → 灵动岛一直显示。
    //
    // Quickshell 的 pw API 没暴露节点的 Pipewire `state`（running/idle/
    // suspended），只有 `ready` 与链接的 `state`（PwLinkState::Enum），
    // 所以这里双层过滤：
    //   1) pwlg.state === 6 (PwLinkState::Active) —— 排除 Paused/Unlinked/
    //      Error 等残态（pw 拆链接会经过这些中间态；聚合滞后时它们会留住）
    //   2) pwlg.target.ready === true —— app 端的输入流节点还活着
    //
    // 注释里的数字 6 对应 PwLinkState 枚举里的 Active 位置
    // （Error Unlinked Init Negotiating Allocating Paused Active）。
    // 若日后 Quickshell 改枚举顺序要相应调整。
    readonly property bool micActive: Pipewire.linkGroups.values.some(pwlg => {
        if (!pwlg || !pwlg.source || !pwlg.target)
            return false;
        if (pwlg.source.type !== PwNodeType.AudioSource)
            return false;
        if (pwlg.target.type !== PwNodeType.AudioInStream)
            return false;
        return pwlg.state === 6 && pwlg.target.ready === true;
    })

    readonly property bool cameraActive: Pipewire.linkGroups.values.some(pwlg => {
        if (!pwlg || !pwlg.source || !pwlg.target)
            return false;
        if (pwlg.source.type !== PwNodeType.VideoSource)
            return false;
        return pwlg.target.ready === true;
    })

    readonly property bool inUse: micActive || cameraActive

    function publish() {
        if (publishing)
            return
        publishing = true
        // 录屏进行中：状态已由 recording 活动表达，避免冗余
        const coveredByRecording = ActivityManager.entries["recording"] !== undefined
        if (inUse && !coveredByRecording) {
            ActivityManager.set("privacy", {
                mic: micActive,
                camera: cameraActive
            }, 4)
        } else {
            ActivityManager.clear("privacy")
        }
        publishing = false
    }

    onMicActiveChanged: publish()
    onCameraActiveChanged: publish()

    // recording 活动出现 / 消失时重算：录屏开始要收起隐私提示，结束要恢复
    Connections {
        target: ActivityManager
        function onRevisionChanged() {
            root.publish()
        }
    }
}
