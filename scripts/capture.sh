#!/usr/bin/env bash
# scripts/capture.sh — run the headless tour, then encode mp4 + gif.
set -euo pipefail
node scripts/03-capture-video.mjs
FR=output/frames
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  output/indy-commute-flows.mp4
# GIF via palette for quality
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" \
  -vf "fps=10,scale=900:-1:flags=lanczos,palettegen" /tmp/indy-pal.png
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" -i /tmp/indy-pal.png \
  -lavfi "fps=10,scale=900:-1:flags=lanczos[x];[x][1:v]paletteuse" \
  output/indy-commute-flows.gif
echo "ENCODE OK"
