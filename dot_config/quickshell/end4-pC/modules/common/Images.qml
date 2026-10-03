pragma Singleton

import Quickshell

Singleton {
    // Formats
    readonly property list<string> validImageTypes: ["jpeg", "png", "webp", "tiff", "svg"]
    // 扩展名清单与 null 安全取上游（10-02：avif/bmp + name 空值兜底）
    readonly property list<string> validImageExtensions: ["jpg", "jpeg", "png", "webp", "avif", "bmp", "tif", "tiff", "svg"]
    // 视频扩展与检测为本地定制（视频缩略图专用脚本链路依赖它）
    readonly property list<string> validVideoExtensions: ["mp4", "webm", "mkv", "avi", "mov"]

    function isValidImageByName(name: string): bool {
        const lower = (name || "").toLowerCase();
        return validImageExtensions.some(t => lower.endsWith(`.${t}`));
    }

    function isValidVideoByName(name: string): bool {
        return validVideoExtensions.some(t => name.toLowerCase().endsWith(`.${t}`));
    }

    // Thumbnails
    // https://specifications.freedesktop.org/thumbnail-spec/latest/directory.html
    readonly property var thumbnailSizes: ({
        "normal": 128,
        "large": 256,
        "x-large": 512,
        "xx-large": 1024
    })
    function thumbnailSizeNameForDimensions(width: int, height: int): string {
        const sizeNames = Object.keys(thumbnailSizes);
        for(let i = 0; i < sizeNames.length; i++) {
            const sizeName = sizeNames[i];
            const maxSize = thumbnailSizes[sizeName];
            if (width <= maxSize && height <= maxSize) return sizeName;
        }
        return "xx-large";
    }
}
