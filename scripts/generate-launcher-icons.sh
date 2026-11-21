#!/usr/bin/env bash
# Requires ImageMagick. Derive launcher sizes from the approved transparent artwork.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
source_image="$root/assets/branding/bandaged-mount.png"
res="$root/android/app/src/main/res"
mkdir -p "$res/drawable-nodpi"
# Content stays inside the adaptive icon safe circle, including tripod corners.
magick "$source_image" -resize 620x620 -gravity center -background none -extent 1080x1080 "$res/drawable-nodpi/toolkit_mark.png"
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    density=${spec%:*}
    size=${spec#*:}
    content=$((size * 84 / 100))
    magick "$source_image" -resize "${content}x${content}" -gravity center -background '#301044' -extent "${size}x${size}" "$res/mipmap-$density/ic_launcher.png"
done
