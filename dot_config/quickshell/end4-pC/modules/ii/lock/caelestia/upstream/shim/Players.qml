pragma Singleton

import QtQuick
import qs.services

/** 上游 `Players` → 本仓库 `MprisController`。上游只用到 active 与 getArtUrl。 */
Singleton {
    id: root

    readonly property var active: MprisController.activePlayer
    readonly property var list: MprisController.players

    /** 上游签名：getArtUrl(player, size) */
    function getArtUrl(player, size) {
        if (!player)
            return "";
        const url = player.trackArtUrl;
        return url ? url : "";
    }
}
