#!/usr/bin/env python3
"""按图片的「彩色像素占比」挑一个合适的 Material You 配色方案。

设置里 palette.type = auto 时走这里，避免给灰调壁纸硬套高饱和方案。

为什么不用 Hasler & Süsstrunk 彩色度：
    该指标是整幅图的全局统计量（对偶通道的均值 + 标准差），
    会被「大面积近黑背景 / 近白高光」严重拉低。实测本机壁纸里
    粉发黑底的人像（yeqi.mp4 首帧）彩色度只有 33.9，落在旧阈值
    40 以下 → 被误判成灰调壁纸 → scheme-neutral 把彩度压到 0.31，
    粉色直接消失。但同图色相明明是 352°，只是彩度被抹掉了。

改用的判据：彩色像素占比（chroma coverage）
    在 HSV 里同时满足「饱和度 ≥ SAT_FLOOR」且「明度 ≥ VAL_FLOOR」
    的像素比例 —— 先把近黑背景和近白高光排除掉，再看图里到底有
    多少像素是「真的带颜色」。只要占比超过 CHROMA_COVERAGE_THRESHOLD
    就认为这张图有明确的色彩身份，交给 scheme-tonal-spot。

实测（24 张壁纸）：真·灰调壁纸占比 0.00%~0.07%，其余 ≥ 10.9%，
用 5% 作阈值两边都有充足余量。全程 Pillow C 实现（point +
logical_and + ImageStat），没有 Python 逐像素循环。

输出：一个 scheme-* 字符串；识别不了就退回 scheme-tonal-spot。
"""

from __future__ import annotations

import sys

from PIL import Image, ImageChops, ImageStat

# 彩色像素占比阈值：低于此值才认为是真·灰调壁纸
CHROMA_COVERAGE_THRESHOLD = 0.05
# HSV 分量下限（0-255）：滤掉近黑背景 / 近白高光 / 纯灰
SAT_FLOOR = 64
VAL_FLOOR = 38

# 保留旧指标仅供 --colorfulness 调试输出，不再参与方案判定
COLORFULNESS_THRESHOLD = 40.0


def image_colorfulness(image: Image.Image) -> float:
    """Hasler & Süsstrunk 彩色度。仅用于诊断，不再用于选方案。"""
    red, green, blue = (image.getchannel(channel) for channel in ("R", "G", "B"))

    # |R - G|
    rg = ImageChops.difference(red, green)
    # |0.5 * (R + G) - B|；ImageChops.add 的 scale 参数就是除数
    yb = ImageChops.difference(ImageChops.add(red, green, scale=2.0), blue)

    rg_stat, yb_stat = ImageStat.Stat(rg), ImageStat.Stat(yb)
    std_rg, mean_rg = rg_stat.stddev[0], rg_stat.mean[0]
    std_yb, mean_yb = yb_stat.stddev[0], yb_stat.mean[0]

    return (std_rg**2 + std_yb**2) ** 0.5 + 0.3 * (mean_rg**2 + mean_yb**2) ** 0.5


def chroma_coverage(image: Image.Image) -> float:
    """彩色像素占比：HSV 中 S 与 V 同时高于下限的像素比例（0~1）。

    用 point 做阈值、logical_and 求交集、ImageStat 求均值，
    全部是 Pillow 的 C 实现，128px 图上耗时 < 1ms。
    """
    hsv = image.convert("HSV")
    saturated = hsv.getchannel("S").point(lambda value: 255 if value >= SAT_FLOOR else 0)
    bright = hsv.getchannel("V").point(lambda value: 255 if value >= VAL_FLOOR else 0)
    both = ImageChops.logical_and(saturated.convert("1"), bright.convert("1")).convert("L")
    return ImageStat.Stat(both).mean[0] / 255.0


def pick_scheme(coverage: float) -> str:
    """只有「几乎没有彩色像素」的壁纸才用 scheme-neutral 保住灰调；
    其余交给 scheme-tonal-spot —— 它最接近 Material You 的默认观感，
    也能保住人像/动画壁纸的主色相（如粉发、红黑主题）。"""
    return "scheme-neutral" if coverage < CHROMA_COVERAGE_THRESHOLD else "scheme-tonal-spot"


def load_and_resize(path: str, max_dim: int = 128) -> Image.Image | None:
    """缩到 128px 以内再统计：彩色度是全局特征，不需要原图分辨率，
    大图整幅读进内存只会白白吃内存。"""
    try:
        image = Image.open(path)
        image.load()
    except (OSError, ValueError):
        return None
    image = image.convert("RGB")
    width, height = image.size
    if max(width, height) > max_dim:
        scale = max_dim / max(width, height)
        image = image.resize((max(1, int(width * scale)), max(1, int(height * scale))))
    return image


def main() -> int:
    args = sys.argv[1:]
    colorfulness_mode = "--colorfulness" in args
    if colorfulness_mode:
        args.remove("--colorfulness")
    coverage_mode = "--coverage" in args
    if coverage_mode:
        args.remove("--coverage")

    if not args:
        print("scheme-tonal-spot")
        return 1

    image = load_and_resize(args[0])
    if image is None:
        print("scheme-tonal-spot")
        return 1

    coverage = chroma_coverage(image)
    if coverage_mode:
        print(f"{coverage:.4f}")
    elif colorfulness_mode:
        print(f"{image_colorfulness(image):.2f}")
    else:
        print(pick_scheme(coverage))
    return 0


if __name__ == "__main__":
    sys.exit(main())
