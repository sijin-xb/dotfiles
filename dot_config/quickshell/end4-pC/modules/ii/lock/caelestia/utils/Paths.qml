pragma Singleton

import QtQuick
import Quickshell

// 移植自 caelestia-dots/shell（GPL-3.0），去掉 caelestia 专有目录。
Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || `${home}/Pictures`
    readonly property string videos: Quickshell.env("XDG_VIDEOS_DIR") || `${home}/Videos`

    function shortenHome(path: string): string {
        return path.replace(home, "~");
    }
}
