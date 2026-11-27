#!/usr/bin/env python3
# /// script
# dependencies = ["resvg-py", "pillow"]
# ///
"""Render the AppIcon PNGs from the brand's primary icon in a Wiffletree host checkout.

    uv run scripts/render-app-icon.py ~/dev/vyttle/wiffletree

The brand ships a rounded tile with transparent corners. iOS masks the corners
itself and tints its own variant, so each appearance is derived from that SVG.
"""
import io
import sys
from pathlib import Path

from PIL import Image
from resvg_py import svg_to_bytes

ICONS = Path(__file__).resolve().parent.parent / 'Wiffletree/Assets.xcassets/AppIcon.appiconset'

TILE = '<rect fill="#1A262D" x="0" y="0" width="1000" height="1000" rx="230"/>\n'
INK = 'fill="#F3F2ED"'
JOINT = 'fill="#D63C35"'


def replace_once(svg, old, new):
    if svg.count(old) != 1:
        sys.exit(f'error: the brand icon changed; expected one {old.strip()!r}')
    return svg.replace(old, new)


def render(svg):
    return Image.open(io.BytesIO(svg_to_bytes(svg_string=svg, width=1024, height=1024)))


def main():
    brand = (Path(sys.argv[1]) / 'design/brand/icon/icon-deep-teal.svg').read_text()
    square = replace_once(brand, TILE, TILE.replace(' rx="230"', ''))
    symbol = replace_once(brand, TILE, '')
    tinted = replace_once(replace_once(symbol, INK, 'fill="#F2F2F2"'), JOINT, 'fill="#A6A6A6"')

    # The App Store rejects an alpha channel on the default icon.
    render(square).convert('RGB').save(ICONS / 'AppIcon.png', optimize=True)
    render(symbol).save(ICONS / 'AppIcon-Dark.png', optimize=True)
    render(tinted).save(ICONS / 'AppIcon-Tinted.png', optimize=True)


if __name__ == '__main__':
    main()
