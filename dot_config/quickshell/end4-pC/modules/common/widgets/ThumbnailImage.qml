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
    // 视频帧抽取引擎：在脚本内由 sourcePath 派生 md5 + 缓存路径，再 ffmpeg 抽帧。
    // 这样 ffmpeg 的 -i 与最后的 mv 落到同一份输入算出来的目标，
    // 杜绝 GridView 复用 delegate 时"-i 仍是旧文件、目标已是新文件"的串写。
    readonly property string videoThumbScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/thumbnails/generate-video-thumbnail.sh`
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

    // 关键：sourcePath 变化时，先把 source 清掉再重新绑定。
    // 否则 StyledImage 的 retainWhileLoading: true 会在异步加载新帧期间
    // 一直保留上一个 delegate 留下的 pixmap，看上去就是"视频格显示成
    // 别张静态壁纸"。
    function clearStaleThumbnail() {
        root.source = "";
        root.source = Qt.binding(() => root.thumbnailPath);
    }

    // Regenerate when the target thumbnail path changes: this covers both
    // size changes and sourcePath changes (GridView delegate recycling),
    // so newly added files get their missing thumbnail on first display.
    onThumbnailPathChanged: {
        root.clearStaleThumbnail();
        root.ensureThumbnail();
    }
    Component.onCompleted: root.ensureThumbnail()

    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const isVideo = Images.isValidVideoByName(root.sourcePath);
            const out = FileUtils.trimFileProtocol(root.thumbnailPath);
            const dir = out.replace(/\/[^/]+$/, "");
            // 视频走专用脚本：目标路径在脚本里按 sourcePath 现算，
            // 避免绑定求值顺序引发的串写。脚本内部 mktemp + 原子 mv，
            // 文件已存在且不要求 force 时直接 exit 0（on-demand 模式不重抽）。
            if (isVideo) {
                return ["bash", root.videoThumbScriptPath, root.sourcePath, root.thumbnailSizeName];
            }
            // 图片保持原本的 magick 分支（图片没观察到串写问题，逻辑不动）。
            const filter = `scale=${maxSize}:${maxSize}:force_original_aspect_ratio=decrease`;
            const head = `mkdir -p '${dir}'; out='${out}'; tmp="$out.tmp.$$"; ` +
                `[ -s "$out" ] && exit 0; `;
            const tail = `[ -s "$tmp" ] || { rm -f "$tmp"; exit 2; }; mv -f "$tmp" "$out"; exit 1;`;
            return ["bash", "-c", head +
                `magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} "$tmp" 2>/dev/null ` +
                `|| convert '${root.sourcePath}' -resize ${maxSize}x${maxSize} "$tmp" 2>/dev/null; ` +
                tail];
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingThumbnailPath = "";
            if (exitCode === 0) {
                root.reloadThumbnail(); // 0：新生成或本来就存在，统一刷一下保险
            } else if (exitCode === 2) {
                console.log("[ThumbnailImage] thumbnail generation failed:", root.sourcePath);
            }
        }
    }
}
