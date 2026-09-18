import QtQuick
import Quickshell
import Quickshell.Io
// 头像取 Config.options.profile.*（见下方说明）
import qs.modules.common

// ─────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 的 src/services/home/DashHome.qml 移植。
//
// 改动：
//   1. 删除 import "../" 与 import "../../components"（扁平化后同目录靠隐式导入）；
//   2. 其余内容逐字保留 —— 三栏布局、列宽、间距、卡片高度一字未改。
//
// 依赖（全部为同目录文件）：ProfileCard / CalendarCard / ClockCard / PlayerCard /
// QuickSettings；WallpaperService 是并行工作提供的同名 shim 单例，原样引用。
// ─────────────────────────────────────────────────────────────────────────

// Dashboard Home tab — layout only.
//
//  ┌──────────────┬───────────────────────────┬──────────────┐
//  │ ProfileCard  │  ClockCard                │              │
//  ├──────────────┤                           │ QuickSettings│
//  │ CalendarCard │  PlayerCard               │ (brightness  │
//  │              │                           │  + toggles)  │
//  └──────────────┴───────────────────────────┴──────────────┘

Item {
    id: root

    readonly property int colW:    210
    readonly property int gap:       8
    readonly property int profileH: 160
    readonly property int clockH:   220

    // ── Avatar path ───────────────────────────────────────────────────────────
    // ⚠ 与上游的差异（必要修复）：
    // Brain_Shell 的头像取 $HOME/.curr_wall_static.jpg —— 那是它自己的
    // WallpaperService 在应用壁纸时生成的静态帧。end4-pC 不生成这个文件，
    // 所以照搬的结果是头像路径恒为空、ProfileCard 一直显示占位图。
    // 改用 end4-pC 自己的头像约定，与下面两个既有插件完全一致：
    //   modules/ii/sidebarRight/SidebarRightContent.qml
    //   modules/ii/background/widgets/usercard/UserCardWidget.qml
    //   1. 设置了 profile.avatarPath 时用 profile.avatarPicture；
    //   2. 否则退回 ~/.face。
    property string _avatarPath: ""
    readonly property string avatarSource: Config.options.profile.avatarPath !== ""
        ? Config.options.profile.avatarPicture
        : "/home/" + (Quickshell.env("USER") ?? "user") + "/.face"

    // 路径不变时 Qt 会命中图片缓存里的旧贴图，
    // 所以换壁纸后先清空一帧再恢复，强制 Image 重新读盘
    onAvatarSourceChanged: {
        root._avatarPath = ""
        reloadTimer.restart()
    }

    Timer {
        id: reloadTimer
        interval: 0
        repeat:   false
        onTriggered: root._avatarPath = root.avatarSource
    }

    Component.onCompleted: root._avatarPath = root.avatarSource

    // ── Left column ───────────────────────────────────────────────────────────
    Item {
        id: leftCol
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: root.gap }
        width: root.colW

        ProfileCard {
            id: profileCard
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.profileH
            avatarPath: root._avatarPath
        }

        CalendarCard {
            anchors {
                left: parent.left; right: parent.right
                top: profileCard.bottom; topMargin: root.gap
                bottom: parent.bottom
            }
        }
    }

    // ── Right column — QuickSettings fills full height ────────────────────────
    QuickSettings {
        id: rightCard
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: root.gap }
        width: root.colW
    }

    // ── Center column ─────────────────────────────────────────────────────────
    Item {
        id: centerCol
        anchors {
            left:  leftCol.right;  leftMargin:  root.gap
            right: rightCard.left; rightMargin: root.gap
            top:   parent.top;     bottom:      parent.bottom
            topMargin: root.gap
        }

        ClockCard {
            id: clockCard
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.clockH
        }

        PlayerCard {
            anchors {
                left:   parent.left;  right:  parent.right
                top:    clockCard.bottom; topMargin: root.gap
                bottom: parent.bottom
            }
        }
    }
}
