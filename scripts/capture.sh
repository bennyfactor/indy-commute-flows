#!/usr/bin/env bash
# scripts/capture.sh — run the headless tour, then encode mp4 + gif.
set -euo pipefail
node scripts/03-capture-video.mjs
FR=output/frames
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  output/indy-commute-flows.mp4
# Compact preview GIF via palette. The moving-camera tour compresses poorly as
# GIF (900px/10fps -> ~90MB), so the GIF is a small shareable preview at
# 480px/8fps/96 colors (~17MB); the MP4 above is the full-quality deliverable.
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" \
  -vf "fps=8,scale=480:-1:flags=lanczos,palettegen=max_colors=96" /tmp/indy-pal.png
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" -i /tmp/indy-pal.png \
  -lavfi "fps=8,scale=480:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4" \
  output/indy-commute-flows.gif
echo "ENCODE OK"
