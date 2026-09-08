#!/bin/sh
# Screenshots docs/media/*.html with Chrome at 2x and animates the menu bar states.
set -e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd "$(dirname "$0")/.."
node scripts/showcase.mjs
shot() { "$CHROME" --headless=new --hide-scrollbars --disable-gpu --force-device-scale-factor=2 --window-size=1920,1080 --screenshot="$PWD/$2" "file://$PWD/$1" >/dev/null 2>&1; }
shot docs/media/hero.html docs/media/hero@2x.png
magick docs/media/hero@2x.png -resize 1920x1080 docs/media/hero.png
shot docs/media/notification.html docs/media/notification@2x.png
magick docs/media/notification@2x.png -crop 1600x400+2240+0 +repage -resize 1200x300 docs/media/notification.png
rm -f docs/media/notification@2x.png
for i in 0 1 2 3 4 5; do
  shot docs/media/frames/bar-$i.html docs/media/frames/bar-$i.png
  magick docs/media/frames/bar-$i.png -crop 1400x300+2440+0 +repage -resize 1120x240 docs/media/frames/bar-$i.png
done
magick -delay 90 -loop 0 docs/media/frames/bar-*.png -layers Optimize docs/media/menubar.gif
rm -rf docs/media/frames docs/media/hero@2x.png
echo "docs/media: hero.png notification.png menubar.gif"
