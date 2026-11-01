"""Generates every logo size OpenLucid uses from branding/logo-source.jpg.

    pip install pillow
    python branding/make_assets.py

Run from the repository root. Then, for the app icons:

    cd frontend/desktop
    dart run flutter_launcher_icons
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "branding"
STATIC = ROOT / "website" / "static"
WEB_PUBLIC = ROOT / "frontend" / "web" / "public"
APP_ASSETS = ROOT / "frontend" / "desktop" / "assets"

BACKGROUND = (12, 17, 36)  # the logo's night blue, #0C1124
LAVENDER = (140, 152, 255)
MOONLIGHT = (240, 196, 104)


def distance(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def clean_square(source: Image.Image) -> Image.Image:
    """Opaque square: JPEG noise in the background flattened to one exact colour."""
    img = source.convert("RGB")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if distance(px[x, y], BACKGROUND) < 45:
                px[x, y] = BACKGROUND
    return img


def transparent(square: Image.Image) -> Image.Image:
    """Same picture with the background made see-through (soft edges kept)."""
    rgba = square.convert("RGBA")
    px = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = px[x, y]
            d = distance((r, g, b), BACKGROUND)
            alpha = max(0, min(255, int((d - 20) * 255 / 120)))
            px[x, y] = (r, g, b, alpha)
    return rgba


def mark(clear: Image.Image, size: int) -> Image.Image:
    """Just the moon and zigzag, cropped close, on transparent."""
    box = clear.getbbox()
    cropped = clear.crop(box)
    side = max(cropped.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def font(names, size):
    for name in names:
        for folder in (Path("C:/Windows/Fonts"), Path("/usr/share/fonts/truetype/dejavu"), Path("/Library/Fonts")):
            path = folder / name
            if path.exists():
                return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def social_card(clear: Image.Image) -> Image.Image:
    """1200x630 preview shown when someone shares a link to the website."""
    card = Image.new("RGB", (1200, 630), BACKGROUND)
    logo = mark(clear, 360)
    card.paste(logo, (110, 135), logo)
    draw = ImageDraw.Draw(card)
    title = font(["segoeuib.ttf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf"], 96)
    body = font(["segoeui.ttf", "DejaVuSans.ttf", "Arial.ttf"], 36)
    draw.text((540, 200), "Open", font=title, fill=(230, 232, 242))
    open_width = draw.textlength("Open", font=title)
    draw.text((540 + open_width, 200), "Lucid", font=title, fill=LAVENDER)
    draw.text((544, 330), "An open-source dream machine", font=body, fill=(200, 204, 230))
    draw.text((544, 380), "you can build yourself", font=body, fill=(200, 204, 230))
    draw.text((544, 470), "openlucid.nl", font=body, fill=MOONLIGHT)
    return card


def main():
    for folder in (STATIC, WEB_PUBLIC, APP_ASSETS):
        folder.mkdir(parents=True, exist_ok=True)

    square = clean_square(Image.open(BRANDING / "logo-source.jpg")).resize((1024, 1024), Image.LANCZOS)
    clear = transparent(square)

    # Masters
    square.save(BRANDING / "icon-1024.png")
    clear.save(BRANDING / "icon-transparent-1024.png")
    mark(clear, 512).save(BRANDING / "logo-mark-512.png")
    social_card(clear).save(BRANDING / "og-image.png")

    # Website
    square.resize((180, 180), Image.LANCZOS).save(STATIC / "apple-touch-icon.png")
    square.resize((192, 192), Image.LANCZOS).save(STATIC / "icon-192.png")
    square.resize((512, 512), Image.LANCZOS).save(STATIC / "icon-512.png")
    square.resize((32, 32), Image.LANCZOS).save(STATIC / "favicon-32.png")
    square.save(STATIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    mark(clear, 96).save(STATIC / "logo-mark-96.png")
    social_card(clear).save(STATIC / "og-image.png")

    # Vue web app
    square.save(WEB_PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

    # Flutter app (shown inside the app; launcher icons come from flutter_launcher_icons)
    mark(clear, 256).save(APP_ASSETS / "logo-mark-256.png")

    print("Done.")


if __name__ == "__main__":
    main()
