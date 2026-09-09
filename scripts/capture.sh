#!/bin/sh
# Screenshots docs/media/*.html with Chrome at 2x: the hero and the desktop,
# the notification, the accounts close-up, and three animations (the item's
# moods, a session asking and being allowed from the bar, Talk).
set -e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd "$(dirname "$0")/.."
node scripts/showcase.mjs
M=docs/media
F=$M/frames
GROUND="#141416"
shot() { "$CHROME" --headless=new --hide-scrollbars --disable-gpu --force-device-scale-factor=2 --window-size="$3" --screenshot="$PWD/$2" "file://$PWD/$1" >/dev/null 2>&1; }
# Flat-ground pages: cut to content, then pad every frame to one size so a GIF holds still.
trim() { magick "$1" -fuzz 1% -trim +repage -bordercolor "$GROUND" -border 24 "$1"; }
same_size() { # same_size out.gif delay frame...
  out=$1; delay=$2; shift 2
  w=0; h=0
  for f in "$@"; do
    set -- $(magick identify -format "%w %h" "$f") "$@"; fw=$1; fh=$2; shift 2
    [ "$fw" -gt "$w" ] && w=$fw; [ "$fh" -gt "$h" ] && h=$fh
  done
  for f in "$@"; do magick "$f" -background "$GROUND" -gravity north -extent "${w}x${h}" "$f"; done
  magick -delay "$delay" -loop 0 "$@" -layers Optimize "$out"
}

shot $M/hero.html $M/hero@2x.png 1920,1080
magick $M/hero@2x.png -crop 1120x1080+2440+0 +repage $M/hero.png
magick $M/hero@2x.png -resize 1920x1080 $M/desktop.png
rm -f $M/hero@2x.png

shot $M/notification.html $M/notification@2x.png 1920,1080
magick $M/notification@2x.png -crop 1600x400+2240+0 +repage -resize 1200x300 $M/notification.png
rm -f $M/notification@2x.png

shot $F/accounts.html $M/accounts.png 420,400
trim $M/accounts.png

for i in 0 1 2 3 4 5; do shot $F/story-$i.html $F/story-$i.png 420,900; trim $F/story-$i.png; done
same_size $M/story.gif 140 $F/story-0.png $F/story-1.png $F/story-2.png $F/story-3.png $F/story-4.png $F/story-5.png
cp $F/story-1.png $M/popover.png

for i in 0 1 2 3; do shot $F/talk-$i.html $F/talk-$i.png 420,400; trim $F/talk-$i.png; done
same_size $M/talk.gif 110 $F/talk-0.png $F/talk-1.png $F/talk-2.png $F/talk-3.png

# Chrome clamps tiny windows, so the item is drawn big and shrunk here.
for i in 0 1 2 3 4 5 6; do shot $F/bar-$i.html $F/bar-$i.png 600,300; magick $F/bar-$i.png -resize 50% $F/bar-$i.png; done
magick -delay 70 -loop 0 $F/bar-*.png -layers Optimize $M/menubar.gif

rm -rf $F $M/hero.html $M/notification.html
ls -la $M
