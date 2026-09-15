import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // 正在生成的缩略图路径：同一目标不重复重启进程，
    // 否则 GridView/Carousel 复用 delegate 时会反复打断正在跑的 ffmpeg。
    property string pendingThumbnailPath: ""

    /**
     * 重新加载 source。不能直接 `source = thumbnailPath`：
     * 那会破坏 `source: thumbnailPath` 的绑定，之后 delegate 被复用时
     * 会一直显示上一个文件的缩略图（视频格尤其明显）。
     */
    function reloadThumbnail() {
        root.source = "";
        root.source = Qt.binding(() => root.thumbnailPath);
    }

    function ensureThumbnail() {
        if (!root.generateThumbnail || !root.sourcePath || !root.thumbnailPath) return;
        if (root.pendingThumbnailPath === root.thumbnailPath) return;
        root.pendingThumbnailPath = root.thumbnailPath;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }

    // Regenerate when the target thumbnail path changes: this covers both
    // size changes and sourcePath changes (GridView delegate recycling),
    // so newly added files get their missing thumbnail on first display.
    onThumbnailPathChanged: root.ensureThumbnail()
    Component.onCompleted: root.ensureThumbnail()

    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const isVideo = Images.isValidVideoByName(root.sourcePath);
            const out = FileUtils.trimFileProtocol(root.thumbnailPath);
            const dir = out.replace(/\/[^/]+$/, "");
            const filter = `scale=${maxSize}:${maxSize}:force_original_aspect_ratio=decrease`;
            // 先写临时文件再原子改名：进程被中断时不会在目标路径留下半截 PNG，
            // 否则后续的“文件已存在”判断会把它当成有效缩略图，格子永远空白。
            const head = `mkdir -p '${dir}'; out='${out}'; tmp="$out.tmp.$$"; ` +
                `[ -s "$out" ] && exit 0; `;
            const tail = `[ -s "$tmp" ] || { rm -f "$tmp"; exit 2; }; mv -f "$tmp" "$out"; exit 1;`;
            if (isVideo) {
                // 取第 1 秒的一帧；个别短视频 / 异常时间轴取不到时回退到第 0 帧
                return ["bash", "-c", head +
                    `ffmpeg -loglevel error -y -ss 1 -i '${root.sourcePath}' -frames:v 1 -an -sn -threads 1 -vf "${filter}" "$tmp" ` +
                    `|| ffmpeg -loglevel error -y -ss 0 -i '${root.sourcePath}' -frames:v 1 -an -sn -threads 1 -vf "${filter}" "$tmp"; ` +
                    tail];
            }
            return ["bash", "-c", head +
                `magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} "$tmp" 2>/dev/null ` +
                `|| convert '${root.sourcePath}' -resize ${maxSize}x${maxSize} "$tmp" 2>/dev/null; ` +
                tail];
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingThumbnailPath = "";
            if (exitCode === 1) {
                root.reloadThumbnail(); // 新生成
            } else if (exitCode === 0 && root.status === Image.Error) {
                root.reloadThumbnail(); // 文件本来就在，但加载失败过一次
            } else if (exitCode === 2) {
                console.log("[ThumbnailImage] thumbnail generation failed:", root.sourcePath);
            }
        }
    }
}
