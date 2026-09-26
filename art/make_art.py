"""Draws the game's icon and boot splash as little isometric voxel dioramas in the
game's palette (scripts/palette.gd): a student in uniform standing on the
campus wall, halfway to freedom.

Run from the project root:  python art/make_art.py
Writes art/icon.png (1024), art/icon.ico (16-256) and art/splash.png (1280x720).
Needs Pillow.
"""
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent

# Palette (same values as scripts/palette.gd).
GRASS = "#8cc45c"
GRASS_DARK = "#74b04e"
DIRT = "#8a5a3a"
DIRT_DARK = "#6e4630"
LEAVES = ["#5fae4a", "#4e9a3e", "#86c95a"]
TRUNK = "#8a5a3a"
BRICK = "#b95c43"
BRICK_ALT = "#a9533e"
BRICK_CAP = "#e2c9a6"
STONE = "#d9d0bf"
SHIRT = "#f4f4f0"
TROUSERS = "#2b3a67"
SHOES = "#26262e"
BELT = "#3a2d26"
SKIN = "#e0ac7e"
HAIR = "#1f1a17"
EYES = "#1c1c24"
BAG = "#e0524f"
STRAP = "#2f6fd6"
FLOWERS = ["#ff6b8a", "#ffd24a", "#ffffff", "#b07cff"]
CLOUD = "#ffffff"
GOLD = "#ffc93c"
INK = "#2a1a0e"
SKY = "#8fd3f0"


def rgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


class Voxels:
    def __init__(self, seed=7):
        self.v = {}  # (x, y, z) -> {"top", "front", "side"} colours
        self.rng = random.Random(seed)

    def put(self, x, y, z, color, front=None, jitter=0.03):
        k = 1.0 + self.rng.uniform(-jitter, jitter)
        c = shade(rgb(color), k)
        self.v[(x, y, z)] = {"top": c, "side": c, "front": shade(rgb(front), k) if front else c}

    def fill(self, x0, x1, y0, y1, z0, z1, color, jitter=0.03):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    self.put(x, y, z, color if isinstance(color, str) else self.rng.choice(color), jitter=jitter)

    def render(self, a, origin, img):
        """Isometric view from +x +y +z: x runs right-down, y left-down."""
        d = ImageDraw.Draw(img)
        ox, oy = origin
        for (x, y, z) in sorted(self.v, key=lambda p: (p[0] + p[1] + p[2], p[2])):
            f = self.v[(x, y, z)]
            cx = ox + (x - y) * a
            cy = oy + (x + y) * a / 2 - z * a
            top = [(cx, cy - a / 2), (cx + a, cy), (cx, cy + a / 2), (cx - a, cy)]
            # Soft ambient occlusion: darken tops that have a neighbour stacked beside them above.
            occ = sum((x + dx, y + dy, z + 1) in self.v for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if (x, y, z + 1) not in self.v:
                d.polygon(top, fill=shade(f["top"], 1.0 - 0.06 * occ))
            if (x, y + 1, z) not in self.v:  # +y face, lower left
                d.polygon([(cx - a, cy), (cx, cy + a / 2), (cx, cy + a * 1.5), (cx - a, cy + a)], fill=shade(f["front"], 0.86))
            if (x + 1, y, z) not in self.v:  # +x face, lower right
                d.polygon([(cx, cy + a / 2), (cx + a, cy), (cx + a, cy + a), (cx, cy + a * 1.5)], fill=shade(f["side"], 0.7))

    def bounds(self, a):
        xs, ys = [], []
        for (x, y, z) in self.v:
            cx = (x - y) * a
            cy = (x + y) * a / 2 - z * a
            xs += [cx - a, cx + a]
            ys += [cy - a / 2, cy + a * 1.5]
        return min(xs), min(ys), max(xs), max(ys)


def diorama(size=9, tree=False, flowers=True):
    """Grass chunk, brick compound wall across it, a student on top of the wall."""
    s = Voxels()
    n = size - 1
    s.fill(0, n, 0, n, -2, -1, [DIRT, DIRT_DARK])
    s.fill(0, n, 0, n, 0, 0, [GRASS, GRASS_DARK])
    # Wall along x at y = 3..4; bricks in alternating courses, stone cap.
    for x in range(0, n + 1):
        for z in range(1, 5):
            for y in (3, 4):
                s.put(x, y, z, BRICK if (x + z) % 2 else BRICK_ALT)
        for y in (3, 4):
            s.put(x, y, 5, BRICK_CAP)
    # Student standing on the cap, facing us (+y), arm up: made it!
    sx = n // 2 - 1  # left leg column; body is 3 wide
    s.fill(sx, sx, 4, 4, 6, 6, SHOES)
    s.fill(sx + 2, sx + 2, 4, 4, 6, 6, SHOES)
    s.fill(sx, sx, 4, 4, 7, 8, TROUSERS)
    s.fill(sx + 2, sx + 2, 4, 4, 7, 8, TROUSERS)
    s.fill(sx, sx + 2, 4, 4, 9, 9, BELT)
    s.fill(sx, sx + 2, 4, 4, 10, 12, SHIRT)
    s.put(sx + 1, 4, 11, SHIRT, front=STRAP)  # ID card on its strap
    s.put(sx + 1, 4, 10, SHIRT, front="#ffffff")
    s.fill(sx, sx + 2, 3, 3, 9, 12, BAG)  # backpack
    s.fill(sx - 1, sx - 1, 4, 4, 10, 11, SHIRT)  # left arm down
    s.put(sx - 1, 4, 9, SKIN)
    s.fill(sx + 3, sx + 3, 4, 4, 12, 12, SHIRT)  # right arm punching the air
    s.fill(sx + 4, sx + 4, 4, 4, 12, 15, SHIRT)
    s.put(sx + 4, 4, 16, SKIN)
    s.fill(sx, sx + 2, 3, 4, 13, 15, SKIN)  # head
    s.put(sx, 4, 14, SKIN, front=EYES)
    s.put(sx + 2, 4, 14, SKIN, front=EYES)
    s.fill(sx, sx + 2, 3, 4, 16, 16, HAIR)
    s.fill(sx, sx + 2, 3, 3, 13, 15, HAIR)
    if tree:  # a tree inside the campus, behind the wall
        s.fill(n - 1, n - 1, 1, 1, 1, 6, TRUNK)
        s.fill(n - 2, n, 0, 2, 6, 8, LEAVES)
        s.fill(n - 1, n - 1, 1, 1, 9, 9, LEAVES)
    if flowers:  # outside: freedom, and flowers
        for (x, y) in ((1, 7), (6, 6), (7, 8), (3, 8)):
            if x <= n and y <= n:
                s.put(x, y, 1, s.rng.choice(FLOWERS))
    return s


def draw_scene(s, a, canvas, center, shadow=True):
    """Renders `s` with cube half-width `a` so that its bounds are centred at `center`."""
    x0, y0, x1, y1 = s.bounds(a)
    ox = center[0] - (x0 + x1) / 2
    oy = center[1] - (y0 + y1) / 2
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        m = Voxels()
        m.v = {k: {"top": (0, 0, 0), "front": (0, 0, 0), "side": (0, 0, 0)} for k in s.v}
        m.render(a, (ox + a * 0.25, oy + a * 0.6), sh)
        alpha = sh.split()[3].point(lambda v: int(v * 0.35)).filter(ImageFilter.GaussianBlur(a * 0.6))
        dark = Image.new("RGBA", canvas.size, (20, 20, 40, 255))
        dark.putalpha(alpha)
        canvas.alpha_composite(dark)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    s.render(a, (ox, oy), layer)
    canvas.alpha_composite(layer)


def make_icon():
    ss = 4  # supersample, then downscale for smooth edges
    size = 1024 * ss
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = diorama()
    x0, y0, x1, y1 = s.bounds(1.0)
    a = 0.9 * size / max(x1 - x0, y1 - y0)
    draw_scene(s, a, img, (size / 2, size / 2))
    icon = img.resize((1024, 1024), Image.LANCZOS)
    icon.save(HERE / "icon.png")
    icon.save(HERE / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def cloud(s, x, y, z, w):
    s.fill(x, x + w, y, y + 1, z, z, CLOUD, jitter=0.0)
    s.fill(x + 1, x + w - 1, y, y + 1, z + 1, z + 1, CLOUD, jitter=0.0)


def make_splash():
    ss = 2
    W, H = 1280 * ss, 720 * ss
    img = Image.new("RGBA", (W, H), rgb(SKY) + (255,))
    # Voxel clouds drifting across the sky.
    clouds = Voxels(3)
    cloud(clouds, 0, 0, 0, 5)
    cloud(clouds, 3, -12, 1, 4)
    draw_scene(clouds, 18 * ss, img, (W * 0.2, H * 0.13), shadow=False)
    far = Voxels(5)
    cloud(far, 0, 0, 0, 4)
    draw_scene(far, 14 * ss, img, (W * 0.9, H * 0.1), shadow=False)
    s = diorama(size=11, tree=True)
    draw_scene(s, 22 * ss, img, (W * 0.28, H * 0.52))
    # Logo like the main menu's: gold, thick ink outline, drop shadow.
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype("C:/Windows/Fonts/ariblk.ttf", 118 * ss)
    tx, ty = W * 0.52, H * 0.26
    for i, line in enumerate(("BUNK", "MASTER")):
        pos = (tx, ty + i * 128 * ss)
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).text((pos[0], pos[1] + 10 * ss), line, font=font, fill=(0, 0, 0, 110),
                                    stroke_width=12 * ss, stroke_fill=(0, 0, 0, 110))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(4 * ss)))
        d.text(pos, line, font=font, fill=rgb(GOLD), stroke_width=12 * ss, stroke_fill=rgb(INK))
    small = ImageFont.truetype("C:/Windows/Fonts/ariblk.ttf", 30 * ss)
    d.text((tx + 6 * ss, ty + 280 * ss), "sneak out. don't get caught.", font=small, fill=rgb(INK))
    img.resize((1280, 720), Image.LANCZOS).convert("RGB").save(HERE / "splash.png")


if __name__ == "__main__":
    make_icon()
    make_splash()
    print("wrote", HERE / "icon.png", HERE / "icon.ico", HERE / "splash.png")
