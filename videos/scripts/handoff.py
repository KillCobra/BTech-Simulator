# Handoff sheet: rows of frames around each cut.  uv run --with imageio-ffmpeg --with pillow python scripts/handoff.py video out.png t1 t2 ...
import subprocess, sys, io
import imageio_ffmpeg
from PIL import Image
video, out, *cuts = sys.argv[1:]
ff = imageio_ffmpeg.get_ffmpeg_exe()
offs = [-0.2, -0.1, -0.03, 0.03, 0.1, 0.2, 0.35]
w, h = 320, 180
sheet = Image.new("RGB", (w * len(offs), h * len(cuts)), (40, 40, 40))
for r, c in enumerate(cuts):
    for i, o in enumerate(offs):
        t = max(0, float(c) + o)
        png = subprocess.run([ff, "-v", "error", "-ss", f"{t:.3f}", "-i", video, "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"], capture_output=True).stdout
        sheet.paste(Image.open(io.BytesIO(png)).convert("RGB").resize((w, h)), (i * w, r * h))
sheet.save(out)
