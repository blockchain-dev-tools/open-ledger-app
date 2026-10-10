"""Generate native launcher icons from the D8 OpenLedger geometry.

Requires Pillow. Run from the repository root with
`python3 scripts/generate_brand_icons.py`. Generated files are committed so
building the app does not need Pillow.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/mobile-flutter"
LIGHT = (0, 0, 0, 255)
DARK = (161, 244, 78, 255)
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)
OUTER = [(320, 120), (680, 120), (880, 320), (880, 680),
         (680, 880), (320, 880), (120, 680), (120, 320)]
INNER = [(350, 235), (650, 235), (765, 350), (765, 650),
         (650, 765), (350, 765), (235, 650), (235, 350)]
LETTER = [(375, 330), (490, 330), (490, 585),
          (620, 585), (685, 650), (375, 650)]


def render(size, dark=False, transparent=False, scale=0.9):
    supersample = 4
    dimension = size * supersample
    foreground = DARK if dark else LIGHT
    background = CLEAR if transparent else (BLACK if dark else WHITE)
    image = Image.new("RGBA", (dimension, dimension), background)
    draw = ImageDraw.Draw(image)

    def transform(points):
        return [((x - 500) * scale * dimension / 1000 + dimension / 2,
                 (y - 500) * scale * dimension / 1000 + dimension / 2)
                for x, y in points]

    draw.polygon(transform(OUTER), fill=foreground)
    draw.polygon(transform(INNER), fill=background)
    draw.polygon(transform(LETTER), fill=foreground)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save(relative, size, dark=False, transparent=False, scale=0.9):
    destination = APP / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    image = render(size, dark=dark, transparent=transparent, scale=scale)
    if relative.startswith("ios/"):
        image = image.convert("RGB")  # App Store icons may not carry alpha.
    image.save(destination)


save("assets/icon/icon-light.png", 1024)
save("assets/icon/icon-dark.png", 1024, dark=True)
save("assets/icon/adaptive-fg-light.png", 1024, transparent=True, scale=0.72)
save("assets/icon/adaptive-fg-dark.png", 1024, dark=True, transparent=True, scale=0.72)

for density, legacy_size, adaptive_size in [
    ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
]:
    save(f"android/app/src/main/res/mipmap-{density}/ic_launcher.png", legacy_size)
    save(f"android/app/src/main/res/mipmap-night-{density}/ic_launcher.png",
         legacy_size, dark=True)
    save(f"android/app/src/main/res/drawable-{density}/ic_launcher_foreground.png",
         adaptive_size, transparent=True, scale=0.72)
    save(f"android/app/src/main/res/drawable-night-{density}/ic_launcher_foreground.png",
         adaptive_size, dark=True, transparent=True, scale=0.72)

icon_set = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")
contents = json.loads((APP / icon_set / "Contents.json").read_text())
for entry in contents["images"]:
    filename = entry.get("filename")
    if filename:
        points = float(entry["size"].split("x")[0])
        factor = int(entry["scale"].removesuffix("x"))
        save(str(icon_set / filename), round(points * factor))

save("web/favicon.png", 32)
save("web/favicon-dark.png", 32, dark=True)
for size in [192, 512]:
    save(f"web/icons/Icon-{size}.png", size)
    save(f"web/icons/Icon-{size}-dark.png", size, dark=True)
    save(f"web/icons/Icon-maskable-{size}.png", size, scale=0.72)

print("Generated D8 app icons in", APP)
