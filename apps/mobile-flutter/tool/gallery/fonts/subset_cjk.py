#!/usr/bin/env python3
"""Subset Noto Sans CJK (SC face) for the Flutter app / gallery (ADR-005).

Why this exists
---------------
Flutter web has no platform CJK fallback: headless Chrome renders Chinese with
whatever fontconfig provides, which differs from the Noto Sans CJK shapes a
real Android device uses. Visual review against web screenshots would
therefore measure font-rendering noise instead of design quality. Bundling a
*subsetted* Noto Sans CJK as `fontFamilyFallback` keeps Latin on Roboto
(engine-bundled, identical to Android) while CJK uses the same Noto shapes as
the device — at a fraction of the ~19 MB full font.

Coverage: every character appearing in the localized `.arb` string tables
(en/zh/ja/ko) plus printable ASCII. The app's only other CJK surface is the
mnemonic wordlist, which is English-only (lib/data/bip39_wordlist.dart).

Regenerate after adding/editing localized strings:

    python3 tool/gallery/fonts/subset_cjk.py                 # uses defaults
    python3 tool/gallery/fonts/subset_cjk.py /path/to/NotoSansCJK-Regular.ttc

Requires: `pip install fonttools` (a Debian `fonttools` package works too).
The committed .ttf outputs are build inputs — commit them after regenerating.
"""

import json
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.subset import Subsetter, Options

APP_ROOT = Path(__file__).resolve().parents[3]
ARB_DIR = APP_ROOT / "lib" / "ui" / "i18n"
OUT_DIR = APP_ROOT / "assets" / "fonts"

# TTC face order in NotoSansCJK-*.ttc:
# 0 JP, 1 KR, 2 SC, 3 TC, 4 HK, 5..9 mono variants.
SC_FACE_INDEX = 2

# One output per weight the app asks for: the theme is built on w500, and
# w600 has no Noto Sans CJK face (only Thin..Black in steps of 100/200).
SOURCES = [
    (
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "NotoSansCJK-Subset-Regular.ttf",
    ),
    (
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc",
        "NotoSansCJK-Subset-Medium.ttf",
    ),
    (
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
        "NotoSansCJK-Subset-Bold.ttf",
    ),
]


def collect_characters() -> str:
    chars = set(chr(c) for c in range(0x20, 0x7F))  # ASCII
    for arb in sorted(ARB_DIR.glob("app_*.arb")):
        data = json.loads(arb.read_text(encoding="utf-8"))
        for key, value in data.items():
            if key.startswith("@"):
                continue  # metadata entries, not user-visible text
            if isinstance(value, str):
                chars.update(value)
    return "".join(sorted(chars))


def subset(ttc_path: Path, out_path: Path, chars: str) -> None:
    font = TTFont(str(ttc_path), fontNumber=SC_FACE_INDEX)
    options = Options()
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.recommended_glyphs = True
    options.layout_features = ["kern"]
    options.drop_tables += ["DSIG"]
    ss = Subsetter(options=options)
    ss.populate(text=chars)
    ss.subset(font)
    font.save(str(out_path))


def main() -> int:
    override = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    chars = collect_characters()
    arb_count = len(list(ARB_DIR.glob("app_*.arb")))
    print(f"Subsetting {len(chars)} unique characters from {arb_count} ARB files")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for default_src, out_name in SOURCES:
        src = override if override is not None else Path(default_src)
        if override is not None:
            weight = Path(out_name).stem.split("-")[-1]  # Regular / Medium / Bold
            candidate = Path(str(src).replace("Regular", weight))
            src = candidate if candidate.exists() else src
        if not src.exists():
            print(f"SKIP {out_name}: source font not found: {src}", file=sys.stderr)
            continue
        out_path = OUT_DIR / out_name
        subset(src, out_path, chars)
        size_kb = out_path.stat().st_size // 1024
        print(f"  wrote {out_path.relative_to(APP_ROOT)} ({size_kb} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
