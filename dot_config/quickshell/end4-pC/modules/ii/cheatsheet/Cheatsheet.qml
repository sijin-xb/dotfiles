import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

/**
 * 快捷键管理器（速查表）。
 *
 * 数据来自 HyprlandKeybinds 单例 —— 它用 scripts/hyprland/get_keybinds.py
 * 解析 ~/.config/hypr/hyprland/keybinds.lua 与 custom/keybinds.lua，
 * 所以这里显示的就是**配置里真实存在的绑定**，不是手写的一份清单。
 *
 * 触发：SUPER + /  →  hl.dsp.global("quickshell:cheatsheetToggle")
 *   （该全局快捷键定义在 ~/.config/hypr/hyprland/keybinds.lua）
 * IPC：qs -c end4-pC ipc call cheatsheet toggle|open|close
 *
 * 说明：Hyprland 侧只认 `quickshell:cheatsheet` 这个 namespace 来做
 * 「底部滑入」动画，rules.lua 里另有 `cheatsheet[0-9]*` 的模糊规则，
 * 那是给旧版 per-screen 命名留的，这里统一用前者。
 */
Scope {
    id: root

    // 把「节 + 其绑定」摊平成列表，供页签与搜索使用。
    // 递归是因为配置里允许嵌套小节（children）。
    readonly property var sections: {
        const out = [];
        const walk = node => {
            if (!node)
                return;
            const binds = node.keybinds ?? [];
            if (binds.length > 0) {
                // 小节名来自 keybinds.lua 的注释（Utilities / Screen / …），
                // 要过一遍 tr —— zh_CN.json 里这些词都有译文，否则页签会是英文。
                const raw = node.name ?? "";
                out.push({
                    name: Translation.tr(raw.length > 0 ? raw : "General"),
                    keybinds: binds
                });
            }
            for (const child of (node.children ?? []))
                walk(child);
        };
        walk(HyprlandKeybinds.keybinds);
        return out;
    }

    property string searchQuery: ""

    // ⚠ 改键相关的**状态与函数都定义在面板组件内部**（见下面的 PanelWindow）。
    // 原因：它们要访问 searchField / card / rebindProc 这些 id，而这些 id 声明在
    // Loader 内部的 PanelWindow 里 —— QML 的 id 作用域是单向的，外层组件看不到
    // 内层组件的 id。之前把它们放在这个根 Scope 上，一调用就抛
    // ReferenceError，表现为「点了行、按了键，什么都没发生」。

    // Qt 按键 → Hyprland 键名。返回空串表示「这次按下不算一个键」
    // （单独的修饰键、或我们不认识的键），此时继续等下一个按键。
    function keyName(event) {
        const k = event.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z)
            return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9)
            return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12)
            return "F" + (k - Qt.Key_F1 + 1);
        // Shift 组合产生的符号（!@#$…）在 Qt 里是独立的 key code，
        // 但 Hyprland 只认基础键，所以映射回基础键。
        const shifted = {
            [Qt.Key_Exclam]: "1",
            [Qt.Key_At]: "2",
            [Qt.Key_NumberSign]: "3",
            [Qt.Key_Dollar]: "4",
            [Qt.Key_Percent]: "5",
            [Qt.Key_AsciiCircum]: "6",
            [Qt.Key_Ampersand]: "7",
            [Qt.Key_Asterisk]: "8",
            [Qt.Key_ParenLeft]: "9",
            [Qt.Key_ParenRight]: "0",
            [Qt.Key_Underscore]: "Minus",
            [Qt.Key_Plus]: "Equal",
            [Qt.Key_BraceLeft]: "BracketLeft",
            [Qt.Key_BraceRight]: "BracketRight",
            [Qt.Key_Bar]: "Backslash",
            [Qt.Key_Colon]: "Semicolon",
            [Qt.Key_QuoteDbl]: "Apostrophe",
            [Qt.Key_Less]: "Comma",
            [Qt.Key_Greater]: "Period",
            [Qt.Key_Question]: "Slash",
            [Qt.Key_AsciiTilde]: "Grave"
        };
        if (shifted[k] !== undefined)
            return shifted[k];

        const map = {
            [Qt.Key_Slash]: "Slash",
            [Qt.Key_Backslash]: "Backslash",
            [Qt.Key_Period]: "Period",
            [Qt.Key_Comma]: "Comma",
            [Qt.Key_Minus]: "Minus",
            [Qt.Key_Equal]: "Equal",
            [Qt.Key_Semicolon]: "Semicolon",
            [Qt.Key_Apostrophe]: "Apostrophe",
            [Qt.Key_BracketLeft]: "BracketLeft",
            [Qt.Key_BracketRight]: "BracketRight",
            [Qt.Key_QuoteLeft]: "Grave",
            [Qt.Key_Space]: "Space",
            [Qt.Key_Tab]: "Tab",
            [Qt.Key_Return]: "Return",
            [Qt.Key_Enter]: "KP_Enter",
            [Qt.Key_Backspace]: "Backspace",
            [Qt.Key_Delete]: "Delete",
            [Qt.Key_Insert]: "Insert",
            [Qt.Key_Home]: "Home",
            [Qt.Key_End]: "End",
            [Qt.Key_PageUp]: "Page_Up",
            [Qt.Key_PageDown]: "Page_Down",
            [Qt.Key_Up]: "Up",
            [Qt.Key_Down]: "Down",
            [Qt.Key_Left]: "Left",
            [Qt.Key_Right]: "Right",
            [Qt.Key_Escape]: "Escape",
            [Qt.Key_Menu]: "Menu",
            // 这三个之前漏了 —— 用户报的「PrtSc / Scroll / Pause 改不了」就是这个原因：
            // keyName 返回空串 → 被当成「未识别的键」直接忽略
            [Qt.Key_Print]: "Print",
            [Qt.Key_ScrollLock]: "Scroll_Lock",
            [Qt.Key_Pause]: "Pause",
            [Qt.Key_CapsLock]: "Caps_Lock"
            // 注：Qt6 没有独立的小键盘键码（用 Qt.KeypadModifier 区分），
            // 所以这里不做 KP_* 映射，小键盘按下会落到对应的基础键上。
        };
        return map[k] ?? "";
    }

    function modsFromEvent(event) {
        const m = [];
        if (event.modifiers & Qt.MetaModifier) m.push("SUPER");
        if (event.modifiers & Qt.ControlModifier) m.push("CTRL");
        if (event.modifiers & Qt.AltModifier) m.push("ALT");
        if (event.modifiers & Qt.ShiftModifier) m.push("SHIFT");
        return m;
    }

    // 组合键里的鼠标键（Hyprland 语法）
    readonly property var _mouseCombo: {
        "272": "mouse:272",
        "273": "mouse:273",
        "274": "mouse:274",
        "275": "mouse:275",
        "276": "mouse:276"
    }

    readonly property var allKeybinds: {
        const all = [];
        for (const s of root.sections)
            for (const b of s.keybinds)
                all.push(b);
        return all;
    }

    // 搜索时跨全部小节；否则只看当前页签
    readonly property var shownKeybinds: {
        const q = root.searchQuery.trim().toLowerCase();
        if (q.length > 0)
            return root.allKeybinds.filter(b => root._matches(b, q));
        const idx = Math.min(Persistent.states.cheatsheet.tabIndex, Math.max(0, root.sections.length - 1));
        return root.sections.length > 0 ? root.sections[idx].keybinds : [];
    }

    // 一行绑定的可搜索文本：修饰键 / 按键 / 说明 / 参数
    function _matches(bind, q) {
        const hay = [
            (bind.mods ?? []).join(" "),
            bind.key ?? "",
            bind.comment ?? "",
            bind.params ?? ""
        ].join(" ").toLowerCase();
        return hay.indexOf(q) !== -1;
    }

    // 鼠标键在 Hyprland 里用的是 X11 按钮码，直接显示 "mouse:273" 没人看得懂：
    //   272 = 左键   273 = 右键   274 = 中键   275 = 后退侧键   276 = 前进侧键
    function keyLabel(key) {
        const k = key ?? "";
        if (k.indexOf("mouse:") === 0) {
            const names = {
                "272": "Mouse Left",
                "273": "Mouse Right",
                "274": "Mouse Middle",
                "275": "Mouse Back",
                "276": "Mouse Forward"
            };
            return Translation.tr(names[k.slice(6)] ?? k);
        }
        if (k === "mouse_up")
            return Translation.tr("Scroll Up");
        if (k === "mouse_down")
            return Translation.tr("Scroll Down");
        return k;
    }

    function comboText(bind) {
        const parts = (bind.mods ?? []).filter(m => m.length > 0)
            .map(m => m === "SUPER" ? "Super" : m.charAt(0) + m.slice(1).toLowerCase());
        const key = root.keyLabel(bind.key);
        if (key.length > 0)
            parts.push(key);
        return parts.join(" + ");
    }

    // 说明里常见 "Section: 描述" 的前缀，展示时去掉，避免和页签名重复。
    // 去掉前缀后再过一遍 tr —— 这些说明是 keybinds.lua 里的英文注释，
    // 词条在 translations/*.json 里。查不到时 tr 会原样返回，不会显示成空。
    function commentText(bind) {
        const c = bind.comment ?? "";
        const i = c.indexOf(": ");
        const stripped = i > 0 && i < 24 ? c.slice(i + 2) : c;
        return Translation.tr(stripped);
    }

    Loader {
        id: cheatsheetLoader

        active: GlobalStates.cheatsheetOpen

        sourceComponent: PanelWindow {
            id: panel

            screen: Quickshell.screens.find(s => s.name === (Hyprland.focusedMonitor?.name ?? ""))
                ?? Quickshell.screens[0]

            anchors {
                bottom: true
                left: true
                right: true
            }

            implicitHeight: Math.min(contentColumn.implicitHeight + Appearance.sizes.elevationMargin * 2,
                                     (screen?.height ?? 1080) * 0.7)
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            // 拿独占键盘焦点，Esc 与输入框才收得到
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            function close() {
                GlobalStates.cheatsheetOpen = false;
            }

            // ── 改键（状态与逻辑都放在面板组件里，才能访问 searchField / card）──
            property var editingBind: null   // 正在等待新组合的那条绑定
            property string editStatus: ""   // 结果提示（成功/失败/冲突）
            property string pendingCombo: "" // 已捕获、待确认的新组合（按 Enter 才写盘）

            // 只有带源码位置的条目才能改：注释型（合成）条目 file 为空
            function editable(bind) {
                return !!bind && (bind.file ?? "").length > 0 && (bind.line ?? 0) > 0;
            }

            function beginEdit(bind) {
                if (!panel.editable(bind)) {
                    panel.editStatus = Translation.tr("This entry cannot be edited");
                    return;
                }
                panel.editingBind = bind;
                panel.editStatus = "";
                panel.pendingCombo = "";
                searchField.text = "";
                root.searchQuery = "";
                card.forceActiveFocus();
            }

            function cancelEdit() {
                panel.editingBind = null;
                panel.pendingCombo = "";
                panel.editStatus = "";
                searchField.forceActiveFocus();
            }

            function applyRebind(combo) {
                const b = panel.editingBind;
                if (!b || combo.length === 0)
                    return;

                // 冲突检测：比较前先归一化 —— comboText 产出的是 "Super + V"
                // 这种展示形式，而 combo 是 "SUPER + V"，直接比永远不相等。
                const norm = s => s.toUpperCase().replace(/\s+/g, "");
                const clash = root.allKeybinds.find(
                    x => x !== b && norm(root.comboText(x)) === norm(combo));

                rebindProc.targetFile = b.file;
                rebindProc.targetLine = b.line;
                rebindProc.combo = combo;
                rebindProc.expect = b.raw ?? "";
                rebindProc.clashLabel = clash ? root.commentText(clash) : "";
                panel.editStatus = Translation.tr("Rebinding…");
                rebindProc.running = true;
            }

        // ── 改键：原地改源码那一行，再让 Hyprland 重载 ──────────────────────
        Process {
            id: rebindProc

            property string targetFile: ""
            property int targetLine: 0
            property string combo: ""
            property string expect: ""
            property string clashLabel: ""

            running: false
            command: ["python3", `${Directories.scriptPath}/hyprland/rebind_keybind.py`,
                "--file", targetFile,
                "--line", String(targetLine),
                "--combo", combo,
                "--expect", expect]

            stdout: StdioCollector {
                id: rebindOut

                onStreamFinished: {
                    let r = {};
                    try {
                        r = JSON.parse(rebindOut.text.trim());
                    } catch (e) {
                        r = { ok: false, error: Translation.tr("Cannot parse script output") };
                    }
                    panel.editingBind = null;

                    if (!r.ok) {
                        panel.editStatus = r.error ?? Translation.tr("Rebind failed");
                    } else if (!r.changed) {
                        panel.editStatus = Translation.tr("Key unchanged");
                    } else {
                        let msg = Translation.tr("Rebound: %1 → %2").arg(r.old).arg(r.new);
                        if (rebindProc.clashLabel.length > 0)
                            msg += "  ·  " + Translation.tr("conflicts with: %1").arg(rebindProc.clashLabel);
                        panel.editStatus = msg;
                        // 让 Hyprland 重读配置。它会发 configreloaded 事件，
                        // HyprlandKeybinds 服务据此自动重解析 → 列表自动刷新
                        reloadProc.running = true;
                    }
                    searchField.forceActiveFocus();
                }
            }
        }

        Process {
            id: reloadProc
            running: false
            command: ["hyprctl", "reload"]
        }

            // ⚠ PanelWindow 创建时 visible 已经是 true，onVisibleChanged 不会触发。
            // 所以「打开时聚焦搜索框」必须放在 Component.onCompleted 里。
            Component.onCompleted: {
                Qt.callLater(() => searchField.forceActiveFocus());
            }

            // 点面板外关闭
            MouseArea {
                anchors.fill: parent
                onClicked: panel.close()
            }

            Rectangle {
                id: card

                anchors.fill: parent
                anchors.margins: Appearance.sizes.elevationMargin
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // 吞掉卡片内的点击，避免穿透到上面的关闭区
                MouseArea {
                    anchors.fill: parent
                    onClicked: {}
                }

                Keys.onPressed: event => {
                    // 改键捕获优先：这期间所有按键都归捕获逻辑，Esc = 取消
                    if (panel.editingBind !== null) {
                        if (event.key === Qt.Key_Escape) {
                            panel.cancelEdit();
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // ⚠ 必须显式确认才写盘。原先设计是「按下即写」，
                            // 只要误触发一次改键态，下一个杂散按键就直接改了用户的
                            // 配置文件（实测踩过两次），所以改成两步：先预览、再确认。
                            if (panel.pendingCombo.length > 0)
                                panel.applyRebind(panel.pendingCombo);
                        } else {
                            const name = root.keyName(event);
                            // name 为空 = 只按下了修饰键（或未识别的键），继续等
                            if (name.length > 0)
                                panel.pendingCombo = root.modsFromEvent(event).concat([name]).join(" + ");
                        }
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        panel.close();
                        event.accepted = true;
                    }
                }

                ColumnLayout {
                    id: contentColumn

                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    spacing: 10

                    // ── 标题行 ──────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("Keybind cheatsheet")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            text: Translation.tr("%1 keybinds").arg(root.shownKeybinds.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        // 改键结果 / 操作提示
                        StyledText {
                            Layout.maximumWidth: 380
                            visible: panel.editStatus.length > 0
                            text: panel.editStatus
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                            elide: Text.ElideRight
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        MaterialTextField {
                            id: searchField

                            Layout.preferredWidth: 260
                            placeholderText: Translation.tr("Search keybinds")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            placeholderTextColor: Appearance.colors.colSubtext

                            onTextChanged: root.searchQuery = text
                        }

                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            downAction: () => panel.close()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    // ── 小节页签（搜索时隐藏，因为搜索是跨小节的）──────
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: tabRow.implicitHeight
                        contentWidth: tabRow.implicitWidth
                        contentHeight: tabRow.implicitHeight
                        flickableDirection: Flickable.HorizontalFlick
                        clip: true
                        visible: root.searchQuery.trim().length === 0 && root.sections.length > 1

                        RowLayout {
                            id: tabRow
                            spacing: 6

                            Repeater {
                                model: root.sections

                                delegate: RippleButton {
                                    required property var modelData
                                    required property int index

                                    implicitHeight: 30
                                    implicitWidth: tabLabel.implicitWidth + 22
                                    buttonRadius: Appearance.rounding.full
                                    readonly property bool isCurrent: Persistent.states.cheatsheet.tabIndex === index
                                    colBackground: isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                                    colBackgroundHover: isCurrent ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
                                    downAction: () => Persistent.states.cheatsheet.tabIndex = index

                                    contentItem: StyledText {
                                        id: tabLabel
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: parent.isCurrent
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }

                    // ── 绑定列表（两列，密度高）────────────────────────
                    ClippingRectangle {
                        Layout.fillWidth: true
                        // ⚠ 必须给 preferredHeight：面板高度是按
                        // contentColumn.implicitHeight 算的，而只写 fillHeight
                        // 的项隐式高度为 0 —— 面板会被压成只剩标题和页签，
                        // 列表拿到 0 高度、什么都不显示。preferred 供隐式高度用，
                        // fillHeight 负责在真实高度里分配。
                        Layout.fillHeight: true
                        Layout.preferredHeight: 380
                        Layout.minimumHeight: 160
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.normal

                        GridView {
                            id: grid

                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            model: root.shownKeybinds
                            cellWidth: width / 2
                            cellHeight: 38
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.vertical: ScrollBar {}

                            delegate: Item {
                                id: bindRow

                                required property var modelData

                                readonly property bool isEditing: panel.editingBind === modelData
                                readonly property bool isEditable: panel.editable(modelData)

                                width: grid.cellWidth
                                height: grid.cellHeight

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    anchors.rightMargin: 8
                                    radius: Appearance.rounding.small
                                    color: bindRow.isEditing
                                        ? Appearance.colors.colPrimaryContainer
                                        : (rowHover.hovered && bindRow.isEditable
                                            ? Appearance.colors.colLayer2
                                            : "transparent")

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    // 按键胶囊：等宽字体，宽度自适应
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: Math.max(comboLabel.implicitWidth + 16, 60)
                                        implicitHeight: 26
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colLayer2

                                        StyledText {
                                            id: comboLabel
                                            anchors.centerIn: parent
                                            text: !bindRow.isEditing
                                                ? root.comboText(bindRow.modelData)
                                                : (panel.pendingCombo.length > 0
                                                    ? panel.pendingCombo
                                                    : Translation.tr("Press a key…"))
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colPrimary
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: bindRow.isEditing
                                            ? Translation.tr("Enter to apply · Esc to cancel")
                                            : root.commentText(bindRow.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: bindRow.isEditing
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }
                                }

                                HoverHandler {
                                    id: rowHover
                                    cursorShape: bindRow.isEditable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }

                                // 点一行即进入改键捕获
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: panel.beginEdit(bindRow.modelData)
                                }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.shownKeybinds.length === 0
                            text: Translation.tr("No matching keybinds")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // 打开时把焦点给搜索框，直接就能输入
            onVisibleChanged: {
                if (visible) {
                    searchField.forceActiveFocus();
                } else {
                    searchField.text = "";
                    root.searchQuery = "";
                }
            }
        }
    }

    // ── 全局快捷键 ──────────────────────────────────────────────────────
    // ⚠ 这三个必须注册在 Scope 根上（常驻），不能放进面板内部 —— 面板是按需
    // 创建的，若把注册写在里面，收起时注册就没了，Hyprland 那条
    // SUPER + / 绑定会指向一个不存在的处理器、按下去毫无反应。
    // 这也正是这个速查表此前一直打不开的原因：
    // hyprland/keybinds.lua 里早就绑了 quickshell:cheatsheetToggle，
    // 但 qs 侧从来没注册过这个名字（`hyprctl globalshortcuts` 里查不到）。
    CompositorGlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles keybind cheatsheet on press"

        onPressed: {
            GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens keybind cheatsheet on press"

        onPressed: {
            GlobalStates.cheatsheetOpen = true;
        }
    }

    CompositorGlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes keybind cheatsheet on press"

        onPressed: {
            GlobalStates.cheatsheetOpen = false;
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
        }

        function open(): void {
            GlobalStates.cheatsheetOpen = true;
        }

        function close(): void {
            GlobalStates.cheatsheetOpen = false;
        }
    }
}
