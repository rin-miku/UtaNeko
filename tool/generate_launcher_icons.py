"""从 assets/icon/icon-utaneko-1024.png 只做缩放，生成 Android / Windows 图标。

不改写母本，不抠图，不把透明通道合成到纯色底上。
Android 不用自适应图标：那层遮罩会把透明区域画成黑色。
"""
import shutil
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[1]
src_path = root / "assets/icon/icon-utaneko-1024.png"
src_bytes = src_path.read_bytes()

with Image.open(src_path) as opened:
    src = opened.convert("RGBA")

if src.size != (1024, 1024):
    raise SystemExit(f"母本必须是 1024x1024，当前是 {src.size}")
if src.getchannel("A").getextrema()[0] != 0:
    raise SystemExit("母本没有透明通道，已停止，避免当成不透明图处理")

def content_radius(image: Image.Image) -> float:
    """不透明像素离中心的最远距离，耳朵尖在这里。"""
    alpha = image.getchannel("A")
    width, height = image.size
    pixels = alpha.load()
    cx = (width - 1) / 2
    cy = (height - 1) / 2
    farthest = 0.0
    for y in range(height):
        for x in range(width):
            if pixels[x, y] <= 16:
                continue
            farthest = max(farthest, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5)
    if farthest <= 0:
        raise SystemExit("母本没有可见像素")
    return farthest


def save_launcher(path: Path, size: int, radius: float) -> None:
    """在「耳朵离边缘 4%」的尺寸上再放大 1.2 倍。超出画布的部分裁掉。"""
    max_radius = (size / 2) * (1 - 0.04) * 1.2
    side = max(1, round(max_radius * src.width / radius))
    resized = src.resize((side, side), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - side) // 2
    canvas.paste(resized, (offset, offset), resized)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


ear_radius = content_radius(src)
for folder, size in [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]:
    save_launcher(
        root / "android/app/src/main/res" / folder / "ic_launcher.png",
        size,
        ear_radius,
    )

# 自适应图标会把透明底画成黑色，并额外裁一圈。桌面只用上面的透明 PNG。
res = root / "android/app/src/main/res"
for folder in (
    "mipmap-mdpi",
    "mipmap-hdpi",
    "mipmap-xhdpi",
    "mipmap-xxhdpi",
    "mipmap-xxxhdpi",
):
    foreground = res / folder / "ic_launcher_foreground.png"
    if foreground.exists():
        foreground.unlink()
anydpi = res / "mipmap-anydpi-v26"
if anydpi.exists():
    shutil.rmtree(anydpi)

# 旧流程写过浅粉底色，透明区域不应再被铺色
colors_xml = root / "android/app/src/main/res/values/colors.xml"
if colors_xml.exists():
    colors_xml.unlink()

ico_sizes = [16, 24, 32, 48, 64, 128, 256]
ico_images = [src.resize((s, s), Image.Resampling.LANCZOS) for s in ico_sizes]


def save_ico(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ico_images[-1].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=ico_images[:-1],
    )


save_ico(root / "windows/runner/resources/app_icon.ico")
save_ico(root / "assets/icon/app_icon.ico")

if src_path.read_bytes() != src_bytes:
    raise SystemExit("母本被改写，已中止")

print("icons generated from icon-utaneko-1024.png; master unchanged")
