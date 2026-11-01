# Branding

<img src="logo-mark-512.png" alt="OpenLucid logo" width="120">

**The logo:** a crescent moon (sleep) with a yellow zigzag inside: the left-right-left-right eye signal that a lucid dreamer can send from inside a dream.

| Colour | Hex | Used for |
|---|---|---|
| Night blue | `#0C1124` | backgrounds |
| Lavender | `#8C98FF` | the moon, accents |
| Moonlight | `#F0C468` | the zigzag, highlights |

## Files

| File | What it is |
|---|---|
| `logo-source.jpg` | The original, made with Google Gemini. Every other file is generated from it. |
| `icon-1024.png` | Square app icon on night blue |
| `icon-transparent-1024.png` | Same, transparent background (Android adaptive icon) |
| `logo-mark-512.png` | Just the moon and zigzag, transparent, cropped close |
| `og-image.png` | 1200×630 preview for links shared on social media |
| `make_assets.py` | Makes all of the above, plus the website's favicons and the in-app logo |

## Changing the logo

1. Replace `logo-source.jpg` (a square image on the night-blue background).
2. From the repository root: `pip install pillow` and `python branding/make_assets.py`
3. App icons: `cd frontend/desktop` and `dart run flutter_launcher_icons`
4. Website: rebuild and deploy (see `website/README.md`).
