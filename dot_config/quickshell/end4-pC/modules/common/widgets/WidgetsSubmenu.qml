pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    // 音频可视化可选样式（桌面右键菜单 > Widgets 二级菜单中使用）
    readonly property var visualizerStyles: [
        { key: "bars",   icon: "bar_chart",             name: Translation.tr("Bars spectrum") },
        { key: "mirror", icon: "align_vertical_center", name: Translation.tr("Mirror spectrum") },
        { key: "line",   icon: "show_chart",            name: Translation.tr("Line spectrum") },
        { key: "wave",   icon: "waves",                 name: Translation.tr("Wave curve") },
        { key: "dots",   icon: "scatter_plot",          name: Translation.tr("Dot matrix") },
        { key: "area",   icon: "area_chart",            name: Translation.tr("Filled wave") },
    ]
    readonly property string currentVisualStyle: Config.options.background.widgets.visualizer.style ?? "bars"
    readonly property string currentStyleName: root.visualizerStyles.find(s => s.key === root.currentVisualStyle)?.name ?? ""

    readonly property var widgetList: [
        { key: "visualizer",  icon: "graphic_eq",         name: Translation.tr("Visualizer") },
        { key: "customImage", icon: "image",              name: Translation.tr("Custom Image") },
        { key: "weather",     icon: "partly_cloudy_day",  name: Translation.tr("Weather") },
        { key: "clock",       icon: "schedule",           name: Translation.tr("Clock") },
        { key: "media",       icon: "music_note",         name: Translation.tr("Media") },
        { key: "images",      icon: "photo_library",      name: Translation.tr("Image Converter") },
        { key: "resources",   icon: "monitor_heart",      name: Translation.tr("Resources") },
        { key: "calendar",    icon: "calendar_month",     name: Translation.tr("Calendar") },
        { key: "worldClock",  icon: "public",             name: Translation.tr("World Clock") },
        { key: "userCard",    icon: "person",             name: Translation.tr("User Card") },
        { key: "notes",       icon: "note_stack_add",     name: Translation.tr("Notes") },
        { key: "timers",      icon: "timer",              name: Translation.tr("Timers") },
        { key: "todo",        icon: "add_task",           name: Translation.tr("To-Do") },
    ]

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "lock"
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        Repeater {
            model: root.widgetList
            delegate: ConfigSwitch {
                required property var modelData
                Layout.fillWidth: true
                buttonIcon: modelData.icon
                text: modelData.name
                checked: Config.options.background.widgets[modelData.key].enable
                onCheckedChanged: Config.options.background.widgets[modelData.key].enable = checked
            }
        }

        // 可视化音频样式选择器：点击立即应用并持久化
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            MaterialSymbol { text: "graphic_eq"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
            StyledText { Layout.fillWidth: true; text: Translation.tr("Visualizer style"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
            StyledText { text: root.currentStyleName; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer1; opacity: 0.6 }
        }

        Row {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 4
            Repeater {
                model: root.visualizerStyles
                delegate: RippleButton {
                    required property var modelData
                    implicitWidth: 40
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    readonly property bool active: root.currentVisualStyle === modelData.key
                    colBackground: active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer2
                    colRipple: Appearance.colors.colSecondary
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        opacity: active ? 1 : 0.7
                    }
                    StyledToolTip { text: modelData.name }
                    onClicked: Config.options.background.widgets.visualizer.style = modelData.key
                }
            }
        }
    }
}