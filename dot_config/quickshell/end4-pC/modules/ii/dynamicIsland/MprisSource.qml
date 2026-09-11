import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// MPRIS 数据源：有曲目的播放器即注册为 music 活动。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // 优先选正在播放的；否则选第一个有曲目的
    readonly property var player: {
        const ps = Mpris.players.values
        for (let i = 0; i < ps.length; i++)
            if (ps[i].isPlaying) return ps[i]
        for (let i = 0; i < ps.length; i++)
            if (ps[i].trackTitle) return ps[i]
        return null
    }

    // 有曲目即视为活动：暂停后仍保留岛，用户才能点击恢复播放。
    // 真正“无活动”= 没有播放器或没有曲目，此时隐藏。
    readonly property bool hasTrack: player !== null
        && (player.trackTitle ?? "").length > 0

    function publish() {
        // 缓存到局部变量并显式判空：player 可能在 hasTrack 求值与本次调用之间
        // 变为 null（播放器退出），直接读属性会抛 "trackTitle of null"。
        const p = player
        if (p === null || (p.trackTitle ?? "").length === 0) {
            ActivityManager.clear("music")
            return
        }
        ActivityManager.set("music", {
            title: p.trackTitle ?? "",
            artist: p.trackArtist ?? "",
            artUrl: p.trackArtUrl ?? "",
            isPlaying: p.isPlaying ?? false,
            progress: p.position ?? 0,
            durationSec: p.length ?? 0
        }, 10)
    }

    // ---- 播放控制（供 UI 调用）----
    function togglePlay() {
        if (player && player.canTogglePlaying) player.togglePlaying()
    }
    function next() {
        if (player && player.canGoNext) player.next()
    }
    function previous() {
        if (player && player.canGoPrevious) player.previous()
    }

    onHasTrackChanged: publish()
    onPlayerChanged: publish()
    Component.onCompleted: publish()

    // 曲目元数据变化
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root.publish() }
        function onTrackArtistChanged() { root.publish() }
        function onPlaybackStateChanged() { root.publish() }
    }

    // 播放进度：每 500ms 刷新一次 payload
    Timer {
        interval: 500
        running: root.hasTrack && (root.player?.isPlaying ?? false)
        repeat: true
        onTriggered: root.publish()
    }

    // 播放器列表变化
    Connections {
        target: Mpris.players
        ignoreUnknownSignals: true
        function onValuesChanged() { root.publish() }
    }
}
