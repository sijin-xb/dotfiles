pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * 上游 `Players` → 本仓库 `MprisController` + `LyricsService`。
 *
 * active 指向 `LyricsService.activePlayer` 而不是 `MprisController.activePlayer`：
 * Media 页的歌词来自 LyricsService，两者各选各的播放器时会出现
 * 「封面是 A、歌词是 B」的错位。以歌词源为准，两端永远同一首歌。
 */
Singleton {
    id: root

    readonly property var active: LyricsService.activePlayer
    readonly property var list: MprisController.players

    /**
     * 上游写这个属性切换播放器（LyricsAndSelector 底部的下拉菜单）。
     * 必须同时写两处，否则只有一半生效：
     *   - MprisController.trackedPlayer：影响 Bar / 侧栏等所有媒体组件；
     *   - LyricsService.lyricPlayer：歌词源的 sticky 选择，不写的话歌词
     *     仍跟着旧播放器走。
     */
    property var manualActive: null
    onManualActiveChanged: {
        const p = root.manualActive;
        if (!p)
            return;
        MprisController.trackedPlayer = p;
        LyricsService.lyricPlayer = p;
    }

    /** 上游签名：getArtUrl(player, size) */
    function getArtUrl(player, size) {
        if (!player)
            return "";
        const url = player.trackArtUrl;
        return url ? url : "";
    }

    /**
     * 上游签名：getIdentity(player) —— LyricsAndSelector 下拉项的标题。
     * 原先缺失，每次渲染菜单都报
     * "TypeError: Property 'getIdentity' ... is not a function"。
     */
    function getIdentity(player) {
        if (!player)
            return "";
        return player.identity ?? player.desktopEntry ?? "";
    }
}
