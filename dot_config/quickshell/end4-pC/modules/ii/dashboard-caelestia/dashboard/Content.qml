pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import "../components"
import "../components/filedialog"
import "../shim"

Item {
    id: root

    required property FileDialog facePicker

    // 岛屿面板是否展开，由 IslandHost 注入。进程页用它决定要不要开采样 ——
    // 面板收起时不该有后台轮询。
    property bool panelOpen: true

    // 页签内容的**实际可用高度**（= 中间那个 Flickable 的高度）。
    // 页签组件不要自己写死 implicitHeight —— 写死容易比这个值大几像素，
    // 底部就会被 ClippingRectangle 切掉半行（实测：进程页的底栏被切了一半）。
    readonly property real paneHeight: view.height


    readonly property var dashboardTabs: {
        const allTabs = [
            {
                component: dashComponent,
                iconName: "dashboard",
                text: Tr.tr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                component: mediaComponent,
                iconName: "queue_music",
                text: Tr.tr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                component: performanceComponent,
                iconName: "speed",
                text: Tr.tr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                component: processComponent,
                iconName: "list_alt",
                text: Tr.tr("Processes"),
                // 不挂 Config.dashboard.showXxx：那是 Caelestia 的 C++ 配置，
                // 没有对应属性，读出来是 undefined 会让页签永远被过滤掉。
                enabled: true
            },
            {
                component: weatherComponent,
                iconName: "cloud",
                text: Tr.tr("Weather"),
                enabled: Config.dashboard.showWeather
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real nonAnimWidth: view.implicitWidth + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + view.implicitHeight + viewWrapper.anchors.margins * 2

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        nonAnimWidth: root.nonAnimWidth - anchors.margins * 2
        tabs: root.dashboardTabs
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: Dashboard.dashboardTab
            readonly property Item currentItem: {
                repeater.count; // Trigger update on count change
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick

            implicitWidth: currentItem?.implicitWidth ?? 0
            implicitHeight: currentItem?.implicitHeight ?? 0

            contentX: currentItem?.x ?? 0
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            onContentXChanged: {
                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    Dashboard.dashboardTab = Math.min(Dashboard.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    Dashboard.dashboardTab = Math.max(Dashboard.dashboardTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    Dashboard.dashboardTab = Math.min(Dashboard.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    Dashboard.dashboardTab = Math.max(Dashboard.dashboardTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            RowLayout {
                id: row

                Repeater {
                    id: repeater

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        Layout.alignment: Qt.AlignTop

                        sourceComponent: modelData.component

                        // ⚠ 上游是「Loader 默认 active=true，先把 4 个页签全建出来，
                        // 再用 visibleArea 把不显示的关掉」。实测加载时 4/4 全建
                        // （约 30ms），其中 3 个立刻销毁，Weather 还被建了又拆。
                        // 那套几何判断本身也不可靠：未激活的 Loader 宽度是 0，会跟
                        // 下一个页签叠在同一个 x 上，「可见区右边缘 == 下一页的 x」
                        // 恒成立 → 四个页签被级联激活。而且它读自身 x / implicitWidth，
                        // 上游原版在日志里就一直报
                        // "Binding loop detected for property active"。
                        //
                        // 现在只建当前页，且保持**零自引用**（不读 item、不读自身几何、
                        // 不在 Component.onCompleted 里用 Qt.binding() 回写）。
                        // 代价是切页签要重建，但上游本来也会销毁离屏页签，没有变差。
                        active: index === view.currentIndex
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {}
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: processComponent

                Process {
                    panelOpen: root.panelOpen
                    availableHeight: root.paneHeight
                }
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    // ⚠ 故意不挂 Behavior on implicitWidth / implicitHeight：
    // 本仓库的面板宽度由 IslandHost.surface.width 单独做 400ms OutQuint
    // 动画；如果这里也挂 Anim，会变成双层动画叠加 —— 切 tab 时先等
    // Content 花 ~500ms 慢慢算完 implicitWidth，surface.width 再花
    // 400ms 动画，加起来近 900ms，观感就是「慢半拍」。
    //
    // 上游 Caelestia 的 Wrapper 里是另一套结构（面板宽度 = implicitWidth
    // 直接改，没有外层 Behavior），所以那边留着这两个 Behavior 是对的。
}
