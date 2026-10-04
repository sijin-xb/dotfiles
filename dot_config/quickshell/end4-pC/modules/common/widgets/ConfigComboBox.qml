import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RowLayout {
    id: root

    property string text: ""
    property string description: ""
    property string buttonIcon: ""
    property var model: []
    property string textRole: "displayName"
    property var currentValue: undefined
    // 上游 10-02 新增：可搜索下拉（GeneralConfig 等设置页在用）。
    // true 时用 StyledComboBoxSearch 替代普通下拉；两个分支共用同一套
    // measuredTextWidth 宽度公式，避免搜索框比邻居宽一截的视觉割裂。
    property bool searchable: false
    // 上游 10-02 新增：true 时定宽 fieldWidth，不做内容自适应。
    property bool fixedWidth: false

    // 下拉框的最小宽度。实际宽度会按模型里最长的文案自动撑开——
    // 否则长文案（尤其是其他语言）会被整段吞掉：StyledComboBox 里
    // popup.width = root.width，按钮多窄弹窗就多窄。
    property real fieldWidth: 220

    property alias comboBox: comboBox

    signal selected(var newValue)

    // 量一次模型里最长的文案宽度（TextMetrics 不会创建可见元素）
    //
    // ⚠ 这里**绝不能写成属性绑定**：绑定体内要给 textMeasurer.text 赋值，而
    // 返回值又读 textMeasurer.advanceWidth —— 赋值当场把自己标脏，Qt 下一帧
    // 重新求值、再赋值、再标脏……形成 Binding loop。设置页面一出现这类下拉框，
    // 日志里就是几百上千条 "Binding loop detected for property
    // measuredTextWidth"，最后直接把 qs 拖到内存爆掉、SIGSEGV 退出。
    //
    // 改成命令式重算：模型 / textRole / 字体变化时算一次并写回普通属性。
    property real measuredTextWidth: 0

    // 字体是值类型，没有 per-field 的信号可用。用一个只读表达式当触发源
    // （只读不写，因此不会成环），字体一变就重新量一次。
    readonly property real fontToken: comboBox.font.pixelSize + comboBox.font.family.length

    function measureTextWidth() {
        let widest = 0;
        const model = root.model ?? [];
        for (let i = 0; i < model.length; ++i) {
            const item = model[i];
            const label = (item && typeof item === "object")
                ? String(item[root.textRole] ?? "")
                : String(item ?? "");
            textMeasurer.text = label;
            widest = Math.max(widest, textMeasurer.advanceWidth);
        }
        root.measuredTextWidth = widest;
    }

    onModelChanged: Qt.callLater(root.measureTextWidth)
    onTextRoleChanged: Qt.callLater(root.measureTextWidth)
    onFontTokenChanged: Qt.callLater(root.measureTextWidth)
    Component.onCompleted: Qt.callLater(root.measureTextWidth)
    // 图标 + 左右内边距 + 右侧展开箭头
    readonly property real comboChromeWidth: 64

    TextMetrics {
        id: textMeasurer
        font: comboBox.font
    }

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
        opacity: root.enabled ? 1 : 0.4
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            opacity: root.enabled ? 1 : 0.4
        }
    }

    StyledComboBox {
        id: comboBox
        visible: !root.searchable
        Layout.preferredWidth: root.fixedWidth
            ? root.fieldWidth
            : Math.max(root.fieldWidth, root.measuredTextWidth + root.comboChromeWidth)
        Layout.alignment: Qt.AlignVCenter
        enabled: root.enabled
        textRole: root.textRole
        model: root.model

        currentIndex: {
            const index = root.model.findIndex(item => item.value === root.currentValue);
            return index !== -1 ? index : 0;
        }

        onActivated: index => {
            root.selected(comboBox.model[index].value);
        }
    }

    // 可搜索分支：与普通下拉同参同宽（fixedWidth / measuredTextWidth 公式），
    // 只多一个过滤输入。API 与 StyledComboBox 同源（两者都是 ComboBox 派生），
    // currentIndex/onActivated 的绑定逻辑保持逐行一致。
    StyledComboBoxSearch {
        id: searchComboBox
        visible: root.searchable
        Layout.preferredWidth: root.fixedWidth
            ? root.fieldWidth
            : Math.max(root.fieldWidth, root.measuredTextWidth + root.comboChromeWidth)
        Layout.alignment: Qt.AlignVCenter
        enabled: root.enabled
        textRole: root.textRole
        model: root.model

        currentIndex: {
            const index = root.model.findIndex(item => item.value === root.currentValue);
            return index !== -1 ? index : 0;
        }

        onActivated: index => {
            root.selected(searchComboBox.model[index].value);
        }
    }
}