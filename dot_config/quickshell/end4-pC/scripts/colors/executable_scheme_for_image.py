#!/usr/bin/env python3
"""按图片的「彩色度」挑一个合适的 Material You 配色方案。

设置里 palette.type = auto 时走这里，避免给灰调壁纸硬套高饱和方案。

彩色度用 Hasler & Süsstrunk 的指标：

    rg = |R - G|
    yb = |0.5(R + G) - B|
    colorfulness = sqrt(σ_rg² + σ_yb²) + 0.3 * sqrt(μ_rg² + μ_yb²)

原实现用 OpenCV（cv2）拆通道再上 numpy。venv 里并没有装 cv2，
所以这个脚本一直抛 ModuleNotFoundError、被调用方当成「识别失败」，
auto 类型实际上从来没生效过。这里改成只用 Pillow：
通道差用 ImageChops 算，均值/标准差交给 ImageStat（都是 C 实现），
既没有额外依赖，也比 numpy 版本省内存。

输出：一个 scheme-* 字符串；识别不了就退回 scheme-tonal-spot。
"""

from __future__ import annotations

import sys

from PIL import Image, ImageChops, ImageStat

# 与 Hasler & Süsstrunk 论文一致的判定阈值
COLORFULNESS_THRESHOLD = 40.0


def image_colorfulness(image: Image.Image) -> float:
    red, green, blue = (image.getchannel(channel) for channel in ("R", "G", "B"))

    # |R - G|
    rg = ImageChops.difference(red, green)
    # |0.5 * (R + G) - B|；ImageChops.add 的 scale 参数就是除数
    yb = ImageChops.difference(ImageChops.add(red, green, scale=2.0), blue)

    rg_stat, yb_stat = ImageStat.Stat(rg), ImageStat.Stat(yb)
    std_rg, mean_rg = rg_stat.stddev[0], rg_stat.mean[0]
    std_yb, mean_yb = yb_stat.stddev[0], yb_stat.mean[0]

    return (std_rg**2 + std_yb**2) ** 0.5 + 0.3 * (mean_rg**2 + mean_yb**2) ** 0.5


def pick_scheme(colorfulness: float) -> str:
    """低彩色度（灰调、低饱和）用 scheme-neutral，保持原本的灰调；
    其余交给 scheme-tonal-spot —— 它最接近 Material You 的默认观感。"""
    return "scheme-neutral" if colorfulness < COLORFULNESS_THRESHOLD else "scheme-tonal-spot"


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

    if not args:
        print("scheme-tonal-spot")
        return 1

    image = load_and_resize(args[0])
    if image is None:
        print("scheme-tonal-spot")
        return 1

    colorfulness = image_colorfulness(image)
    print(f"{colorfulness:.2f}" if colorfulness_mode else pick_scheme(colorfulness))
    return 0


if __name__ == "__main__":
    sys.exit(main())
