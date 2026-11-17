# DMG Resources

Background art for the `YEN.dmg` installer window.
The frozen window layout and packaging rules are in `_docs/05-infrastructure.md` → DMG; change both in the same commit.

| File | Size | Role |
|------|------|------|
| `background.png` | 800x800 | 1x background |
| `background@2x.png` | 1600x1600 | 2x background |

Both must be opaque RGB: with an alpha channel, Finder's `set background picture` silently stores a background color instead of the image.
The art is icon-only, with no baked labels; the three chevrons sit between the `YEN.app` and `Applications` icons.

## Regenerating

The source frame is `public/dmg-frame-2.png`.

```bash
magick public/dmg-frame-2.png \
  \( -size 800x800 xc:none -fill none -stroke 'rgba(171,245,224,0.13)' -strokewidth 10 \
     -draw "line 382,448 400,464 line 400,464 418,448" -blur 0x8 \) \
  -compose screen -composite \
  \( -size 800x800 xc:none -fill none -stroke 'rgba(155,248,215,0.30)' -strokewidth 10 \
     -draw "line 382,464 400,480 line 400,480 418,464" -blur 0x9 \) \
  -compose screen -composite \
  \( -size 800x800 xc:none -fill none -stroke 'rgba(146,253,207,0.55)' -strokewidth 10 \
     -draw "line 382,480 400,496 line 400,496 418,480" -blur 0x10 \) \
  -compose screen -composite \
  -fill none -stroke 'rgba(213,244,235,0.20)' -strokewidth 4 \
  -draw "line 384,448 400,464 line 400,464 416,448" \
  -stroke 'rgba(178,250,222,0.52)' \
  -draw "line 384,464 400,480 line 400,480 416,464" \
  -stroke 'rgba(157,253,202,0.98)' \
  -draw "line 384,480 400,496 line 400,496 416,480" \
  -alpha off -strip \
  yen-terminal/customizations/dmg-resources/background.png
magick yen-terminal/customizations/dmg-resources/background.png \
  -resize 200% -alpha off -strip \
  yen-terminal/customizations/dmg-resources/background@2x.png
sips -g pixelWidth -g pixelHeight \
  yen-terminal/customizations/dmg-resources/background.png \
  yen-terminal/customizations/dmg-resources/background@2x.png
```

Then run `scripts/manual/14-verify-dmg-layout.sh` against a fresh packaging build.
