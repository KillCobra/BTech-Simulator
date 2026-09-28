#!/usr/bin/env bash
# Final render: 240 fps master -> 4-subframe motion blur -> 60 fps H.264 with the score.
set -e
cd "$(dirname "$0")/.."
V=${1:-v1}
OUT=out/trailer/$V
mkdir -p "$OUT"
FF=$(uv run -q --with imageio-ffmpeg python -c "import imageio_ffmpeg as i; print(i.get_ffmpeg_exe())")
npx remotion render src/index.ts Trailer "$OUT/master-240.mp4" --props '{"fps":240}' --codec h264 --crf 10 --pixel-format yuv444p --image-format jpeg --jpeg-quality 95 --muted --concurrency 10 --log error
"$FF" -v error -y -i "$OUT/master-240.mp4" -i public/audio/trailer.wav \
  -filter_complex "[0:v]tmix=frames=4:weights='1 1 1 1',select='not(mod(n+1\,4))',setpts=N/(60*TB),scale=in_range=tv:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709,format=yuv420p[v]" \
  -map "[v]" -map 1:a -r 60 -c:v libx264 -preset slow -crf 16 -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv \
  -c:a aac -b:a 256k -movflags +faststart -shortest "$OUT/BunkMaster-trailer.mp4"
"$FF" -v error -y -ss 29.5 -i "$OUT/BunkMaster-trailer.mp4" -frames:v 1 -q:v 2 "$OUT/poster.jpg"
rm "$OUT/master-240.mp4"
ls -la "$OUT"
