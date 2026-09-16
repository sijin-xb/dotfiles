pragma Singleton

import QtQuick
import qs.modules.common
import qs.modules.common.functions

/** 上游 `qs.utils.Paths` 里锁屏用到的那几个成员。 */
Singleton {
    id: root

    readonly property string home: Directories.home

    function toLocalFile(path) {
        return String(path).replace(/^file:\/\//, "");
    }

    function absolutePath(path) {
        return FileUtils.trimFileProtocol(String(path));
    }
}
