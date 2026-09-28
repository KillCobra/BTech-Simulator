#!/bin/sh
# Final render of the Launch trailer: 240 fps master -> 4-subframe motion blur at 60 fps -> deliverables.
#   sh scripts/launch-render.sh v1
set -e
V=${1:-v1}
OUT=out/launch/$V
mkdir -p "$OUT"
FF=$(uv run --quiet --with imageio-ffmpeg python3 -c "import imageio_ffmpeg as i; print(i.get_ffmpeg_exe())")
npx remotion render src/index.ts Launch "$OUT/master-240.mp4" --props '{"fps":240}' --codec h264 --crf 8 \
  --pixel-format yuv444p --image-format png --muted --concurrency 8 --gl=angle --log error
"$FF" -v error -y -i "$OUT/master-240.mp4" \
  -vf "tmix=frames=4:weights='1 1 1 1',select='not(mod(n+1\,4))',setpts=N/(60*TB),scale=in_range=tv:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709,format=yuv444p10le" \
  -r 60 -c:v prores_ks -profile:v 4444 -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv "$OUT/blurred-60.mov"
H264="-c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -x264-params colorprim=bt709:transfer=bt709:colormatrix=bt709 -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv -movflags +faststart"
"$FF" -v error -y -i "$OUT/blurred-60.mov" -i public/audio/launch/mix.wav $H264 -c:a aac -b:a 256k -shortest "$OUT/BunkMaster-teaser-1080p60.mp4"
"$FF" -v error -y -i "$OUT/blurred-60.mov" $H264 -an "$OUT/BunkMaster-teaser-1080p60-muted.mp4"
"$FF" -v error -y -ss 29.5 -i "$OUT/blurred-60.mov" -frames:v 1 -q:v 2 "$OUT/poster.jpg"
rm "$OUT/master-240.mp4" "$OUT/blurred-60.mov"
ls -la "$OUT"
