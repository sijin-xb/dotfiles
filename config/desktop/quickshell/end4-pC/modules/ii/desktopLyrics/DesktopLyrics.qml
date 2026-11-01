import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.services

/**
 * 通用桌面歌词浮层（视图）。
 *
 * 数据全部来自 LyricsService —— 也就是那条唯一的「通用桌面歌词源」
 * （SPlayer WebSocket 桥接，退路是 MPRIS + kugou）。这个文件只负责画，
 * 不再自己维护取词、时间补偿、播放器选择等逻辑。
 *
 * 显示：当前行逐字高亮，下面依次是翻译、音译。
 *
 * IPC 命令：
 *   qs -c end4-pC ipc call desktoplyrics toggle
 *   qs -c end4-pC ipc call desktoplyrics refetch        (强制重新取词，跳过缓存)
 *   qs -c end4-pC ipc call desktoplyrics offset_faster  (歌词提前 0.1s)
 *   qs -c end4-pC ipc call desktoplyrics offset_slower  (歌词延后 0.1s)
 *   qs -c end4-pC ipc call desktoplyrics set_offset 0.3 (设置当前播放器偏移)
 *   qs -c end4-pC ipc call desktoplyrics offset_reset   (重置当前播放器偏移)
 *   qs -c end4-pC ipc call desktoplyrics get_offset     (打印当前偏移信息)
 *   qs -c end4-pC ipc call desktoplyrics list_offsets   (列出各播放器偏移)
 */
PanelWindow {
    id: root

    readonly property bool enabled: Config.options.desktopLyricsEnabled
    readonly property bool shouldShow: root.enabled && LyricsService.isPlaying
        && LyricsService.currentText.length > 0

    anchors {
        bottom: true
        left: true
        right: true
    }
    margins.bottom: 90
    implicitHeight: 180
    exclusiveZone: -1
    mask: Region {}

    color: "transparent"

    visible: root.shouldShow || fadeOutLinger.running
    Timer {
        id: fadeOutLinger
        interval: 400
        running: !root.shouldShow
    }

    Item {
        id: lyricWrap
        anchors.fill: parent

        opacity: root.shouldShow ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        ListView {
            id: lyricList
            anchors.fill: parent
            clip: true
            interactive: false
            model: LyricsService.lyricLines
            currentIndex: LyricsService.currentLineIndex
            spacing: 7
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: height / 2 - 20
            preferredHighlightEnd: height / 2 + 20
            highlightMoveDuration: Appearance.animation.elementMove.duration
            highlightMoveVelocity: -1
            snapMode: ListView.SnapToItem

            delegate: Column {
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === lyricList.currentIndex

                width: lyricList.width
                spacing: 3

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.isCurrent ? LyricsService.buildLineHtml(parent.modelData) : LyricsService.escapeHtml(parent.modelData.text)
                    textFormat: Text.RichText
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: parent.isCurrent ? 21 : 14
                    font.weight: parent.isCurrent ? Font.DemiBold : Font.Normal
                    color: parent.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    opacity: {
                        const d = Math.abs(index - lyricList.currentIndex);
                        return parent.isCurrent ? 1 : Math.max(0.14, 0.4 - d * 0.08);
                    }
                    horizontalAlignment: Text.AlignHCenter

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }

                // 当前行下方两行副标题：先翻译、再音译（原文 / 翻译 / 音译 三行）
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: parent.isCurrent && (parent.modelData.trans ?? "").length > 0
                    text: parent.modelData.trans ?? ""
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 13
                    color: Appearance.colors.colSecondary
                    opacity: 0.85
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: parent.isCurrent && (parent.modelData.roman ?? "").length > 0
                    text: parent.modelData.roman ?? ""
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 13
                    font.italic: true
                    color: Appearance.colors.colSecondary
                    opacity: 0.65
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    IpcHandler {
        target: "desktoplyrics"

        function toggle(): void {
            Config.options.desktopLyricsEnabled = !Config.options.desktopLyricsEnabled;
        }
        function show(): void {
            Config.options.desktopLyricsEnabled = true;
        }
        function hide(): void {
            Config.options.desktopLyricsEnabled = false;
        }
        function open(): void {
            Config.options.desktopLyricsEnabled = true;
        }
        function refetch(): string {
            LyricsService.restartLyrics();
            return "正在重新获取歌词（跳过缓存，仅缓存校验匹配的结果）…";
        }

        // 偏移微调：正数提前（快），负数延后（慢）。
        // 只作用于当前播放器，并立即持久化。
        function offset_faster(): string {
            const v = LyricsService.adjustManualOffset(0.1);
            return `歌词已提前 +100ms（仅当前播放器）| 播放器: ${LyricsService.activePlayer?.identity ?? "未知"} | 本播放器偏移: ${(v * 1000).toFixed(0)}ms | 总时间补偿: ${(LyricsService.effectiveOffset * 1000).toFixed(0)}ms`;
        }
        function offset_slower(): string {
            const v = LyricsService.adjustManualOffset(-0.1);
            return `歌词已延后 -100ms（仅当前播放器）| 播放器: ${LyricsService.activePlayer?.identity ?? "未知"} | 本播放器偏移: ${(v * 1000).toFixed(0)}ms | 总时间补偿: ${(LyricsService.effectiveOffset * 1000).toFixed(0)}ms`;
        }
        function set_offset(seconds: real): string {
            const v = LyricsService.setManualOffsetForCurrent(seconds);
            return `当前播放器偏移已设为: ${v}s | 播放器: ${LyricsService.activePlayer?.identity ?? "未知"} | 总时间补偿: ${(LyricsService.effectiveOffset * 1000).toFixed(0)}ms`;
        }
        function offset_reset(): string {
            LyricsService.setManualOffsetForCurrent(0.0);
            return `当前播放器偏移已重置为 0s | 播放器: ${LyricsService.activePlayer?.identity ?? "未知"} | 自动补偿: ${(LyricsService.playerOffset * 1000).toFixed(0)}ms | 总时间补偿: ${(LyricsService.effectiveOffset * 1000).toFixed(0)}ms`;
        }
        function get_offset(): string {
            const pName = LyricsService.activePlayer?.identity ?? (LyricsService.activePlayer?.dbusName ?? "无播放器");
            return `[歌词时间信息] 来源: ${LyricsService.source} | 播放器: ${pName} | 自动补偿: ${(LyricsService.playerOffset * 1000).toFixed(0)}ms | 本播放器手动偏移: ${(LyricsService.manualOffset * 1000).toFixed(0)}ms | 全局设置: ${((Config.options.desktopLyricsOffset ?? 0.0) * 1000).toFixed(0)}ms | 歌曲标签偏移: ${(LyricsService.rawLyricOffset * 1000).toFixed(0)}ms | 总提前量: ${(LyricsService.effectiveOffset * 1000).toFixed(0)}ms`;
        }
        function list_offsets(): string {
            const keys = Object.keys(LyricsService.perPlayerOffsets);
            if (keys.length === 0)
                return "尚无按播放器保存的偏移。";
            return "按播放器保存的偏移:\n" + keys.map(k => `  ${k}: ${(LyricsService.perPlayerOffsets[k] * 1000).toFixed(0)}ms`).join("\n");
        }
    }
}
