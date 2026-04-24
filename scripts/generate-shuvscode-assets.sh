#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source_png="${1:-assets/branding/shuvscode-devil-phone-source.png}"

if [[ ! -f "$source_png" ]]; then
  echo "Missing source image: $source_png" >&2
  exit 1
fi

for program in magick base64; do
  if ! command -v "$program" >/dev/null 2>&1; then
    echo "Missing required program: $program" >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

logo_1024="$tmpdir/shuvscode-devil-phone-1024.png"
mask_png="$tmpdir/shuvscode-devil-phone-mask.png"
flat_png="$tmpdir/shuvscode-devil-phone-flat.png"

# The generated source has a white background and some antialiasing artifacts.
# Build a clean mask from red-dominant pixels, then apply it to one flat brand
# color before deriving every checked-in asset from that normalized source.
magick "$source_png" \
  -alpha off \
  -colorspace sRGB \
  -fx '((r > 0.35) && (r > g * 1.18) && (r > b * 1.18)) ? 1 : 0' \
  -morphology close disk:1 \
  -blur 0x0.35 \
  -level 30%,100% \
  "$mask_png"

magick -size 1254x1254 xc:'#ff150f' "$mask_png" \
  -compose CopyOpacity \
  -composite \
  PNG32:"$flat_png"

magick "$flat_png" \
  -trim +repage \
  -resize 900x900 \
  -background none \
  -gravity center \
  -extent 1024x1024 \
  PNG32:"$logo_1024"

write_svg_image() {
  local png="$1"
  local output="$2"
  local width="$3"
  local height="$4"
  local image_width="${5:-$width}"
  local image_height="${6:-$height}"
  local x="${7:-0}"
  local y="${8:-0}"
  local opacity="${9:-1}"
  local data

  data="$(base64 -w 0 "$png")"

  cat > "$output" <<SVG
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">
  <image href="data:image/png;base64,$data" x="$x" y="$y" width="$image_width" height="$image_height" opacity="$opacity"/>
</svg>
SVG
}

write_letterpress() {
  local output="$1"
  local color="$2"
  local opacity="$3"
  local letter_png="$tmpdir/$(basename "$output" .svg).png"

  magick "$logo_1024" \
    -resize 32x32 \
    -fill "$color" \
    -colorize 100 \
    -channel A -evaluate multiply "$opacity" +channel \
    -background none \
    -gravity center \
    -extent 40x40 \
    PNG32:"$letter_png"

  write_svg_image "$letter_png" "$output" 40 40
}

mkdir -p \
  icons/stable \
  icons/insider \
  src/stable/resources/linux/rpm \
  src/stable/resources/server \
  src/stable/src/vs/workbench/browser/media \
  src/stable/src/vs/workbench/browser/parts/editor/media

cp "$logo_1024" src/stable/resources/linux/code.png
magick "$logo_1024" src/stable/resources/linux/rpm/code.xpm
magick "$logo_1024" -resize 192x192 PNG32:src/stable/resources/server/code-192.png
magick "$logo_1024" -resize 512x512 PNG32:src/stable/resources/server/code-512.png
magick "$logo_1024" -define icon:auto-resize=256,128,96,64,48,32,24,16 src/stable/resources/server/favicon.ico

write_svg_image "$logo_1024" src/stable/resources/linux/code.svg 1024 1024
write_svg_image "$logo_1024" src/stable/src/vs/workbench/browser/media/code-icon.svg 1024 1024

write_letterpress src/stable/src/vs/workbench/browser/parts/editor/media/letterpress-dark.svg '#B2B2B2' 0.3
write_letterpress src/stable/src/vs/workbench/browser/parts/editor/media/letterpress-light.svg '#B2B2B2' 0.1
write_letterpress src/stable/src/vs/workbench/browser/parts/editor/media/letterpress-hcDark.svg '#3C3C3C' 1
write_letterpress src/stable/src/vs/workbench/browser/parts/editor/media/letterpress-hcLight.svg '#B2B2B2' 1

for quality in stable insider; do
  write_svg_image "$logo_1024" "icons/$quality/codium_cnl.svg" 1024 1024
  write_svg_image "$logo_1024" "icons/$quality/codium_clt.svg" 1024 1024
  write_svg_image "$logo_1024" "icons/$quality/codium_cnl_w80_b8.svg" 1024 1024 820 820 102 102
done

magick identify \
  src/stable/resources/linux/code.png \
  src/stable/resources/server/code-192.png \
  src/stable/resources/server/code-512.png \
  src/stable/resources/server/favicon.ico
