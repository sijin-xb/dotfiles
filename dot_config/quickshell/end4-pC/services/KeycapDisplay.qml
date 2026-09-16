pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * 按键显示的数据源。
 *
 * 起 scripts/keyboard/keycap-reader.py 读 /dev/input/event*（只读，不 grab，
 * 不会影响按键进到应用里），逐行读它输出的 {"keys": ["Ctrl","A"]}。
 *
 * 状态分两层，因为「按住」和「显示」不是一回事：
 *   heldKeys  —— 守护上报的真实状态，手指松开就空了
 *   shownKeys —— 界面要画的东西。按下时立刻跟上，全部松开后还留 timeout 毫秒
 *                再淡出，否则快速点一下根本来不及看见
 *
 * 需要能读 /dev/input/event*：把用户加进 input 组即可。读不到时守护会往
 * stderr 说明原因，这里收进 error 供设置界面提示。
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/keyboard/keycap-reader.py")

    // 不用可选链（?. / ??）：qmllint 的 JS 解析器还不认，会整片报 Syntax error
    property bool enabled: Config.options.keycapDisplay.enable
    property int timeout: Config.options.keycapDisplay.timeout
    /** 守护上报的当前按住集合 */
    property list<string> heldKeys: []
    /** 界面要显示的集合（松开后还会留一会儿） */
    property list<string> shownKeys: []
    /** 是否有内容要画 */
    property bool showing: false

    /**
     * 守护上报的错误码（形如 NO_INPUT_DEVICES），空串表示没出错。
     * 守护只报稳定的错误码、不报人话 —— 人话在这里按当前语言翻译，
     * 否则界面会把守护的中文原样显示给用其它语言的用户。
     */
    property string errorCode: ""

    /** 供界面直接显示的错误文案（已按当前语言翻译） */
    readonly property string errorText: {
        switch (root.errorCode) {
        case "NO_INPUT_DEVICES":
            return Translation.tr("Cannot read input devices — add your user to the input group and log back in");
        case "":
            return "";
        default:
            return root.errorCode;
        }
    }

    function applyLine(line) {
        const text = String(line).trim()
        if (text === "")
            return
        let payload
        try {
            payload = JSON.parse(text)
        } catch (e) {
            return // 半行 JSON，等下一次
        }
        const keys = payload ? payload.keys : null
        if (!Array.isArray(keys))
            return

        root.heldKeys = keys
        if (keys.length > 0) {
            // 按着的时候就一直显示，不要开始倒计时
            root.shownKeys = keys
            root.showing = true
            hideTimer.stop()
        } else if (root.shownKeys.length > 0) {
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: root.timeout
        repeat: false
        onTriggered: {
            root.showing = false
            root.shownKeys = []
        }
    }

    Process {
        id: reader
        running: root.enabled
        command: ["python3", root.scriptPath]

        stdout: SplitParser {
            onRead: (line) => root.applyLine(line)
        }

        stderr: SplitParser {
            onRead: (line) => {
                const text = String(line).trim()
                if (text === "")
                    return
                if (text.startsWith("ERROR:")) {
                    root.errorCode = text.slice(6)
                } else if (text.startsWith("#")) {
                    // 以 # 开头的是给人手工运行脚本时看的说明，界面不需要
                    console.log("[keycap-reader]", text.slice(1).trim())
                }
            }
        }

        onRunningChanged: {
            if (!running)
                root.reset()
        }
    }

    function reset() {
        hideTimer.stop()
        root.heldKeys = []
        root.shownKeys = []
        root.showing = false
        root.errorCode = ""
    }
}
