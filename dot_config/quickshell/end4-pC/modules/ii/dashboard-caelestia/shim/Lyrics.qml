pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * Caelestia `Caelestia.Services.Lyrics` 的本地代理。
 *
 * 上游 Lyrics 是 C++ 单例（QStringList 形式，只有纯文本行），通过自有后端
 * 拉词。本地另有一套更完整的 `LyricsService`：带翻译 / 音译 / 逐字时间戳，
 * 而且已经在桌面歌词 / 锁屏等场景跑通。
 *
 * 这里把 LyricsService 的结构适配成上游那套窄接口，让 vendor 过来的
 * LyricList / LyricsInfo 不用改一行业务代码就能跑。
 *
 * 覆盖的上游成员（dashboard 里实际用到的）：
 *   lyrics, hasLyrics, loading, offset, selectedCandidate,
 *   setTrack(), clearTrack(), indexForTime(), timeForIndex()
 */
Singleton {
    id: root

    // ── 歌词文本行 ────────────────────────────────────────────────────
    // 上游是 QStringList；本地 lyricLines 是对象数组，取 .text 摊平。
    readonly property list<string> lyrics: LyricsService.lyricLines.map(l => l.text ?? "")

    readonly property bool hasLyrics: LyricsService.lyricLines.length > 0
    readonly property bool loading: LyricsService.status === "loading"

    // ── 副标题（翻译 / 音译）─────────────────────────────────────────
    // 上游 `lyrics` 是 QStringList，塞不下第二行，所以单独给一组按行对齐的
    // 副标题，让岛屿也能显示翻译 —— 与桌面歌词浮层（原文 / 翻译 / 音译）接轨。
    // 取舍：优先语义翻译 trans，没有翻译时退回音译 roman。这与
    // custom-island/PlayerCard.qml 的取舍一致（那边的歌词窗只给 trans）。
    //
    // 用 function 而不是整表 map：delegate 只在**当前行**上调它，
    // 避免为几百行歌词各建一个字符串绑定。
    function subtitleFor(i) {
        const lines = LyricsService.lyricLines;
        if (i < 0 || i >= lines.length)
            return "";
        const l = lines[i];
        return (l.trans ?? "") || (l.roman ?? "");
    }

    // ── 当前供词的播放器 ────────────────────────────────────────────
    // shim/Players.active 也指向这里，保证 Media 页的封面/标题与歌词
    // 永远来自同一个播放器（不会出现「封面是 A、歌词是 B」）。
    readonly property var activePlayer: LyricsService.activePlayer

    // ── 偏移（秒，可写）───────────────────────────────────────────────
    // 上游 offset 单位是秒；本地 LyricsService 对应的是 manualOffset。
    //
    // manualOffset 在 LyricsService 里是**只读计算属性**（由 perPlayerOffsets
    // 推导），直接赋值会被丢掉。写入必须走 setManualOffsetForCurrent()。
    // 加阈值判断避免「绑定读回 → 触发 onOffsetChanged → 再写一次」的回流。
    property real offset: LyricsService.manualOffset
    onOffsetChanged: {
        if (Math.abs(root.offset - LyricsService.manualOffset) > 0.0005)
            LyricsService.setManualOffsetForCurrent(root.offset);
    }

    // ── 后端名（供 LyricsInfo 显示）───────────────────────────────────
    // 上游用 CUtils.enumToString(Lyrics, "backend") 把 C++ 枚举转成字符串。
    // 但那个 C++ 方法带默认参数（即两个重载），而这里的 Lyrics 是 QML 单例，
    // 传进去会让 Qt 在重载解析里踩空 → 段错误（实测：创建媒体页就崩）。
    // 所以改成直接给一个字符串，不再走 C++ 枚举转换。
    readonly property string sourceName: LyricsService.source === "splayer"
        ? "SPlayer"
        : (LyricsService.source === "kugou" ? "Kugou" : "—")

    // ── 后端 / 候选（桩）─────────────────────────────────────────────
    // 本地 LyricsService 没有「后端选择 / 候选列表」概念，LyricsInfo 里对应
    // 的 UI 会被这两个桩隐藏或显示为空。
    readonly property int backend: 0
    property int preferredBackend: 0

    readonly property QtObject selectedCandidate: QtObject {
        readonly property string title: LyricsService.songTitle
        readonly property string artist: LyricsService.songArtist
        readonly property string album: ""
    }

    readonly property var lyricCandidates: []

    // ── 上游接口里的两个「跟踪」方法（本地不需要）──────────────────
    // 上游靠 setTrack 显式喂曲目信息，本地 LyricsService 自己订阅 MPRIS /
    // SPlayer，会自己发现曲目变化，所以这两个方法退化为无操作。
    function setTrack(artist, title, album, length) {
        // no-op: LyricsService 自动跟踪当前播放曲目
    }

    function clearTrack() {
        // no-op: 同上
    }

    // ── 时间 ↔ 行号（供 LyricList 高亮和点击跳转用）──────────────────
    //
    // 上游 LyricList 传入的是 MPRIS 裸 position，但桌面歌词浮层用的时间是
    // LyricsService.currentTime + effectiveOffset（播放器自动补偿 + 手动偏移
    // + 全局偏移 + 歌词标签偏移）。两边各算一次必然错行 —— 浏览器源要补
    // 300ms、通用源 150ms，肉眼可见。
    //
    // 所以这里不再自己二分，直接返回服务已经算好的 currentLineIndex，
    // 让岛屿高亮行与桌面歌词浮层严格同一行。入参 t 只为兼容上游签名保留。
    function indexForTime(t) {
        return LyricsService.currentLineIndex;
    }

    function timeForIndex(i) {
        const lines = LyricsService.lyricLines;
        if (i < 0 || i >= lines.length)
            return 0;
        return lines[i].start ?? 0;
    }
}
