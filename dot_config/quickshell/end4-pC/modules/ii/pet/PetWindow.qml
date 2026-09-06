pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * 桌宠窗口：全屏透明覆盖层，只有猫猫本体占的矩形接收输入（mask），其余全部穿透。
 * 猫猫可以被抓住拖走、甩出去（惯性 + 屏幕边缘反弹 + 落地压扁扬尘），
 * 落点持久化在 ~/.local/state/quickshell/pet-position.json。
 *
 * IPC:
 *   qs -c end4-pC ipc call pet toggle|show|hide|status
 *   qs -c end4-pC ipc call pet mood busy     (强制心情；"auto" 释放)
 *   qs -c end4-pC ipc call pet home          (回老家)
 *   qs -c end4-pC ipc call pet toss -800 -400 (扔猫；无参数 = 随机方向)
 */
PanelWindow {
    id: root

    property bool petEnabled: true
    // 桌面歌词实例（shell.qml 传入）：给猫猫提供逐字卡拉OK数据
    property var lyricsProvider: null

    WlrLayershell.namespace: "quickshell:pet"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: -1
    color: "transparent"
    visible: root.petEnabled

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // 只有猫猫占的矩形接收输入
    mask: Region {
        item: petContent.interactionRoot
    }

    PetState {
        id: petState
        active: root.petEnabled
    }

    Pet {
        id: petContent
        anchors.fill: parent
        active: root.petEnabled
        vitals: petState
        lyricsProvider: root.lyricsProvider
    }

    IpcHandler {
        target: "pet"

        function toggle(): void {
            root.petEnabled = !root.petEnabled;
        }
        function show(): void {
            root.petEnabled = true;
        }
        function hide(): void {
            root.petEnabled = false;
        }
        function mood(mood: string): void {
            petState.moodOverride = mood;
        }
        function status(): string {
            return petState.mood;
        }
        function home(): void {
            petContent.goHome();
        }
        function toss(dx: int, dy: int): void {
            petContent.toss(dx, dy);
        }
    }
}
