"""Makes fonts/Jersey10-Large.ttf: Jersey 10 (SIL OFL 1.1, see OFL.txt) drawn 1.33x
bigger at every point size, by shrinking its units-per-em. Jersey 10 is a compact
pixel face; the game's font sizes were picked for an ordinary UI font, so this
lets them stay as they are. Run from the project root: python fonts/make_font.py
(needs fonttools).
"""
from fontTools.ttLib import TTFont

SCALE = 1.33
f = TTFont("fonts/Jersey10-Regular.ttf")
f["head"].unitsPerEm = round(f["head"].unitsPerEm / SCALE)
# A modified font gets its own family name (the licence has no reserved name,
# but this keeps it clear it isn't the original).
for rec in f["name"].names:
    if rec.nameID in (1, 3, 4, 6, 16):
        new = "Jersey10Large" if rec.nameID == 6 else "Jersey 10 Large"
        rec.string = rec.toUnicode().replace("Jersey10", new).replace("Jersey 10", new)
f.save("fonts/Jersey10-Large.ttf")
print("wrote fonts/Jersey10-Large.ttf, unitsPerEm", f["head"].unitsPerEm)
