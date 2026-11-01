import QtQuick
import Quickshell

// 移植自 caelestia-dots/shell（GPL-3.0）。
// 移除 Caelestia.Images 的 IUtils.urlForPath 依赖，改用 Qt.resolvedUrl。
Image {
    id: root

    property string path

    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    source: root.path.length > 0 ? Qt.resolvedUrl(root.path) : ""
    sourceSize: {
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        return Qt.size(width * dpr, height * dpr);
    }
}
