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

    // 下拉框的最小宽度。实际宽度会按模型里最长的文案自动撑开——
    // 否则长文案（尤其是其他语言）会被整段吞掉：StyledComboBox 里
    // popup.width = root.width，按钮多窄弹窗就多窄。
    property real fieldWidth: 220

    property alias comboBox: comboBox

    signal selected(var newValue)

    // 量一次模型里最长的文案宽度（TextMetrics 不会创建可见元素）
    readonly property real measuredTextWidth: {
        let widest = 0;
        for (let i = 0; i < root.model.length; ++i) {
            const item = root.model[i];
            const label = (item && typeof item === "object")
                ? String(item[root.textRole] ?? "")
                : String(item ?? "");
            textMeasurer.text = label;
            widest = Math.max(widest, textMeasurer.advanceWidth);
        }
        return widest;
    }
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
        Layout.preferredWidth: Math.max(root.fieldWidth, root.measuredTextWidth + root.comboChromeWidth)
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
}