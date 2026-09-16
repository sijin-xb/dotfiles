pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * 按键显示的数据源。
 *
 * 起 scripts/keyboard/keycap-reader.py 读 /dev/input/event*（只读，不 grab，
 * 不会影响按键进到应用里），逐行读它输出的
 *     {"keys": ["Ctrl","Shift"], "text": "hello wor"}
 *
 * 两个字段对应两种显示需求，分开满足：
 *   keys —— 需要以键帽展示的键：修饰键、以及按住 Ctrl/Alt/Super 时的组合键、
 *           方向键 / F 键这类不可打印键。适合看快捷键。
 *   text —— 已经打出来的可见文本。可打印字符走这里而不是键帽，否则一个单词会被
 *           拆成一堆单独闪过的键帽，根本读不出你打了什么。
 *
 * 键帽和文本的存活时间都交给守护（--text-idle），界面只负责画：
 * 守护自己会在闲置后清空文本并推送新快照，界面不做第二套超时逻辑，
 * 否则两边时间对不上会出现「界面清空了、下次按键又冒出旧文本」。
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/keyboard/keycap-reader.py")

    // 不用可选链（?. / ??）：qmllint 的 JS 解析器还不认，会整片报 Syntax error
    property bool enabled: Config.options.keycapDisplay.enable
    property bool showTypedText: Config.options.keycapDisplay.showTypedText
    property int timeout: Config.options.keycapDisplay.timeout
    property int textTimeout: Config.options.keycapDisplay.textTimeout
    property int maxTextLength: Config.options.keycapDisplay.maxTextLength

    /** 守护上报的、需要以键帽展示的键 */
    property list<string> heldKeys: []
    /** 守护上报的、已经打出来的文本 */
    property string typedText: ""

    /** 界面实际要画的键帽：松开后还留一会儿，否则快速点按会一闪而过 */
    property list<string> shownKeys: []
    /** 是否有内容要画 */
    property bool showing: false

    Timer {
        id: keycapLinger
        interval: root.timeout
        repeat: false
        onTriggered: {
            root.shownKeys = []
            root.refreshShowing()
        }
    }

    function refreshShowing() {
        root.showing = root.shownKeys.length > 0 || root.typedText.length > 0
    }

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

    readonly property var command: {
        const args = ["python3", root.scriptPath,
                      "--text-idle", String(Math.max(0.5, root.textTimeout / 1000)),
                      "--max-text", String(root.maxTextLength)];
        if (!root.showTypedText)
            args.push("--no-text");
        return args;
    }

    function applyLine(line) {
        const raw = String(line).trim()
        if (raw === "")
            return
        let payload
        try {
            payload = JSON.parse(raw)
        } catch (e) {
            return // 半行 JSON，等下一次
        }

        const keys = Array.isArray(payload.keys) ? payload.keys : []
        const text = (typeof payload.text === "string") ? payload.text : ""

        root.heldKeys = keys
        root.typedText = text

        // 键帽：按住期间实时跟随；全部松开后不立刻清空，交给 keycapLinger 停留一会儿。
        // 否则快速点一下 Ctrl+A 只闪一帧，等于没显示。
        if (keys.length > 0) {
            root.shownKeys = keys
            keycapLinger.stop()
        } else if (root.shownKeys.length > 0) {
            keycapLinger.restart()
        }
        root.refreshShowing()
    }

    Process {
        id: reader
        running: root.enabled
        command: root.command

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
        keycapLinger.stop()
        root.heldKeys = []
        root.typedText = ""
        root.shownKeys = []
        root.showing = false
        root.errorCode = ""
    }
}
