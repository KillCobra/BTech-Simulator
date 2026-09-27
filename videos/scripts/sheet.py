# Stack review stills into one sheet: python scripts/sheet.py out.png a.png b.png ...
import sys
from PIL import Image
out, files = sys.argv[1], sys.argv[2:]
cols = 3 if len(files) > 4 else 2
w, h = 640, 360
rows = (len(files) + cols - 1) // cols
s = Image.new("RGB", (cols * w, rows * h), (40, 40, 40))
for i, f in enumerate(files):
    s.paste(Image.open(f).convert("RGB").resize((w, h)), ((i % cols) * w, (i // cols) * h))
s.save(out)
