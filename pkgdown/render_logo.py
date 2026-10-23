"""Render pkgdown/logo.svg into man/figures/logo.png and pkgdown/favicon/*.

Requires: playwright (with chromium installed) and Pillow.
Usage (from the package root): python pkgdown/render_logo.py
"""
import base64
import io
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "pkgdown" / "logo.svg"
LOGO_PNG = ROOT / "man" / "figures" / "logo.png"
FAVICON_DIR = ROOT / "pkgdown" / "favicon"

LOGO_HEIGHT = 1200  # render resolution; icons are downsampled from this
LOGO_PNG_HEIGHT = 278  # usethis::use_logo() convention; ships in the tarball
SQUARE_ICONS = {
    "apple-touch-icon.png": 180,
    "favicon-96x96.png": 96,
    "web-app-manifest-192x192.png": 192,
    "web-app-manifest-512x512.png": 512,
}
ICO_SIZES = [(16, 16), (32, 32), (48, 48)]


def render_svg(svg_text: str, height: int) -> Image.Image:
    scale = height / 600
    width = round(519.6 * scale)
    html = (
        "<html><body style='margin:0;background:transparent'>"
        f"<div style='width:{width}px;height:{height}px'>"
        + svg_text.replace(
            'width="519.6" height="600"', f'width="{width}" height="{height}"', 1
        )
        + "</div></body></html>"
    )
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height})
        page.set_content(html)
        png = page.locator("svg").screenshot(omit_background=True)
        browser.close()
    return Image.open(io.BytesIO(png)).convert("RGBA")


def square(img: Image.Image, size: int) -> Image.Image:
    """Center the hex on a transparent square canvas of the given size."""
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    logo = render_svg(SVG.read_text(encoding="utf-8"), LOGO_HEIGHT)
    small = logo.resize(
        (round(logo.width * LOGO_PNG_HEIGHT / logo.height), LOGO_PNG_HEIGHT),
        Image.LANCZOS,
    )
    small.save(LOGO_PNG, optimize=True)

    for name, size in SQUARE_ICONS.items():
        square(logo, size).save(FAVICON_DIR / name, optimize=True)
    square(logo, 48).save(FAVICON_DIR / "favicon.ico", sizes=ICO_SIZES)

    # favicon.svg embeds a raster so it renders identically without the fonts
    buf = io.BytesIO()
    square(logo, 256).save(buf, format="PNG", optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    (FAVICON_DIR / "favicon.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" '
        'viewBox="0 0 256 256"><image width="256" height="256" '
        f'href="data:image/png;base64,{b64}"/></svg>',
        encoding="utf-8",
    )
    print(f"wrote {LOGO_PNG} {small.size} and favicons in {FAVICON_DIR}")


if __name__ == "__main__":
    main()
