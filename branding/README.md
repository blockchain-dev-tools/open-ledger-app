# OpenLedger visual assets

`openledger-community-light.svg` and `openledger-community-dark.svg` are the
community wordmarks. The app-only D8 mark lives in
`apps/mobile-flutter/assets/icons/brand/` as theme-specific SVGs.

All three use the same flat-bottom octagon and L geometry. For raster launcher
icons, run `python3 scripts/generate_brand_icons.py` from the repository root
with Pillow installed. The generated PNGs are tracked; normal Flutter builds
do not run the generator.

Flutter selects the mark from the app theme. Android launcher resources select
light or dark icons from the system theme. The experimental iOS target currently
uses the light launcher icon.
