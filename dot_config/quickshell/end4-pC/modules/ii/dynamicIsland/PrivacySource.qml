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

    readonly property bool micActive: Pipewire.linkGroups.values.some(pwlg =>
        pwlg.source.type === PwNodeType.AudioSource
        && pwlg.target.type === PwNodeType.AudioInStream)

    readonly property bool cameraActive: Pipewire.linkGroups.values.some(pwlg =>
        pwlg.source.type === PwNodeType.VideoSource)

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
