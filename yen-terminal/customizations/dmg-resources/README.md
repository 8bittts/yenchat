# DMG Resources

Background art for the `YEN.dmg` installer window.
The frozen window layout and packaging rules are in `_docs/05-infrastructure.md` → DMG; change both in the same commit.

| File | Size | Role |
|------|------|------|
| `background.png` | 600x600 | 1x background |
| `background@2x.png` | 1200x1200 | 2x background |

Both must be opaque RGB: with an alpha channel, Finder's `set background picture` silently stores a background color instead of the image.
The art carries no baked label text.
It has a mid-gray pill under each Finder label and three chevrons with a subtle drop shadow between the `YEN.app` and `Applications` icons.
The pill rectangles match Finder's label boxes at icon size `108` and text size `12`; move them if the layout changes.

## Regenerating

The source frame is `public/dmg-frame.png`.
The art is drawn at 2x and then downscaled for 1x.

```bash
P="stroke-linecap round stroke-linejoin round"
C1="$P polyline 576,666 600,690 624,666"
C2="$P polyline 576,690 600,714 624,690"
C3="$P polyline 576,714 600,738 624,714"
OUT=yen-terminal/customizations/dmg-resources
magick public/dmg-frame.png -resize 1200x1200 \
  -fill '#8e8e8e' -stroke none \
  -draw "roundrectangle 536,604 664,644 20,20" \
  -draw "roundrectangle 514,961 686,1001 20,20" \
  \( -size 1200x1200 xc:none -fill none -stroke 'rgba(0,0,0,0.6)' -strokewidth 6 \
     -draw "$C1" -draw "$C2" -draw "$C3" -blur 0x3 -roll +0+3 \) -compose over -composite \
  -fill none -strokewidth 6 \
  -stroke 'rgba(157,253,202,0.30)' -draw "$C1" \
  -stroke 'rgba(157,253,202,0.60)' -draw "$C2" \
  -stroke 'rgba(157,253,202,0.95)' -draw "$C3" \
  -alpha off -strip "$OUT/background@2x.png"
magick "$OUT/background@2x.png" -resize 600x600 -alpha off -strip "$OUT/background.png"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT/background.png" "$OUT/background@2x.png"
```

Then run `scripts/manual/14-verify-dmg-layout.sh` against a fresh packaging build.
