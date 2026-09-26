extends RefCounted
## Toolkit for the university grounds around the academic block. Each map
## extends this and overrides:
##   _plan()  sizes, roads, buildings and water: what the ground and its
##            collision need to know before anything is built;
##   _build() everything else (geometry, guards, patrols, exits).
## All positions are world metres; y = 0 is the ground.

const P := preload("res://scripts/palette.gd")

const STOREY := 3.4
const GLASS := Color("7fb8d6")
const DIRT := Color("b88a5a")
const DIRT_DARK := Color("a37a4e")
const SAND := Color("f0dca0")
const SAND_DARK := Color("e2c98a")
const IRON := Color("2f3440")

var c: RefCounted  # the CampusBuilder
var rng := RandomNumberGenerator.new()
var classic := false  # true: this map uses the original academic block (First Day)


func plan(campus: RefCounted) -> void:
	c = campus
	rng.seed = 7000 + int(campus.map_id)
	_plan()


func build(campus: RefCounted) -> void:
	c = campus
	_build()


func _plan() -> void:
	pass


func _build() -> void:
	pass


## Yaw that makes a staff member (or camera) look along dir (x, z).
static func facing(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


# --- Basics -------------------------------------------------------------------------------------

func box(center: Vector3, size: Vector3, color: Color, jitter := 0.02, solid := false) -> void:
	c._block(center, size, color, jitter, solid)


func collide(center: Vector3, size: Vector3) -> void:
	c._collide(center, size)


func glow(center: Vector3, size: Vector3) -> void:
	c._glow.box(center, size, P.GLOW)


func label(text: String, pos: Vector3, font_size: int, color: Color, yaw := 0.0, outline := 10) -> Label3D:
	return c._label(text, pos, font_size, color, yaw, outline)


func map_rect(rect: Rect2, color: Color, text := "", force := false, kind := "") -> void:
	c._map(rect, color, text, -1, force, kind)


func pave(rect: Rect2) -> void:
	c._paved.append(rect)


func reserve(rect: Rect2) -> void:
	c._blocked.append(rect)


## Grassy but no trees here (sports fields, mazes, yards).
func keep_clear(rect: Rect2) -> void:
	_clear_rects.append(rect)


var _clear_rects: Array[Rect2] = []


func free_at(x: float, z: float) -> bool:
	if c._is_paved(x, z) or c.academic_rect.has_point(Vector2(x, z)):
		return false
	for r in _clear_rects:
		if r.has_point(Vector2(x, z)):
			return false
	return true


## Flat slab, split into pieces so each mesh chunk culls on its own.
func slab(rect: Rect2, top: float, thick: float, color: Color, jitter := 0.0, alt := Color(0, 0, 0, 0)) -> void:
	var nx := maxi(1, ceili(rect.size.x / 12.0))
	var nz := maxi(1, ceili(rect.size.y / 12.0))
	var w := rect.size.x / nx
	var d := rect.size.y / nz
	for ix in nx:
		for iz in nz:
			var col := color if alt.a == 0.0 or (ix + iz) % 2 == 0 else alt
			c._vbox(Vector3(rect.position.x + (ix + 0.5) * w, top - thick / 2.0, rect.position.y + (iz + 0.5) * d),
				Vector3(w, thick, d), col, jitter, true)


# --- Ways ----------------------------------------------------------------------------------------

## Asphalt road with a dashed centre line. Call from _plan().
func road(rect: Rect2, along_x: bool, lines := true) -> void:
	pave(rect)
	map_rect(rect, P.ASPHALT, "", false, "road")
	_roads.append([rect, along_x, lines])


## Stone footpath / plaza. Call from _plan().
func walk(rect: Rect2, color := P.STONE, alt := P.STONE_DARK, label_text := "") -> void:
	pave(rect)
	map_rect(rect, color, label_text, false, "path")
	_walks.append([rect, color, alt])


## Dirt trail. Call from _plan().
func trail(rect: Rect2) -> void:
	walk(rect, DIRT, DIRT_DARK)


var _walks: Array = []
var _roads: Array = []


## Lays the slabs for every road and walk planned. Call at the start of _build().
func lay_paving() -> void:
	# Each slab sits a hair higher than the last, so crossings don't flicker (z-fighting).
	for i in _walks.size():
		var w: Array = _walks[i]
		slab(w[0], 0.03 + (i % 7) * 0.0015, 0.12, w[1], 0.02, w[2])
	for i in _roads.size():
		var r: Array = _roads[i]
		var rect: Rect2 = r[0]
		var along_x: bool = r[1]
		slab(rect, 0.045 + (i % 7) * 0.0015, 0.12, P.ASPHALT, 0.01)
		if not r[2]:
			continue
		var length := rect.size.x if along_x else rect.size.y
		var n := maxi(1, int(length / 6.0))
		var mid := rect.get_center()
		var start := rect.position.x if along_x else rect.position.y
		for k in n:
			var a := start + (k + 0.5) * length / n
			var p := Vector3(a, 0.065, mid.y) if along_x else Vector3(mid.x, 0.065, a)
			c._vbox(p, Vector3(2.4, 0.02, 0.16) if along_x else Vector3(0.16, 0.02, 2.4), P.LINE)


## Adds walkable nav points every `step` metres along a line (for staff pathing).
func nav_line(a: Vector2, b: Vector2, step := 10.0) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / step))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		c.nav_points.append(Vector3(p.x, 0, p.y))


# --- Water ---------------------------------------------------------------------------------------

## A lake, river or sea: a 2 m deep pit. Fall in and you're washed back to `bank`.
## Call from _plan() (the ground collision is cut around it).
func water(rect: Rect2, bank: Vector3, text := "", side := Vector2.ZERO, banks := true) -> void:
	c.waters.append({"rect": rect, "bank": bank, "side": side, "banks": banks})
	reserve(rect)
	map_rect(rect, Color("5fb8dc"), text, false, "water")


## A deck over water that staff may also use. Call from _plan().
func bridge_area(rect: Rect2) -> void:
	c.bridges.append(rect)


## Water surface and banks for every planned water body. Call from _build().
func lay_water() -> void:
	for w in c.waters:
		var r: Rect2 = w.rect
		slab(r, -0.28, 0.1, P.WATER, 0.015, P.WATER.darkened(0.06))
		if not w.get("banks", true):
			continue
		# Muddy banks just under the lip, visible at the edges.
		var mid := r.get_center()
		for side: float in [-1.0, 1.0]:
			c._vbox(Vector3(mid.x, -0.15, mid.y + side * (r.size.y / 2.0 - 0.15)), Vector3(r.size.x, 0.3, 0.3), DIRT_DARK)
			c._vbox(Vector3(mid.x + side * (r.size.x / 2.0 - 0.15), -0.15, mid.y), Vector3(0.3, 0.3, r.size.y), DIRT_DARK)


## Plank bridge with rails. along_x: the deck runs along x.
func bridge(rect: Rect2, along_x: bool, rails := true, plank := P.WOOD) -> void:
	var mid := rect.get_center()
	var length := rect.size.x if along_x else rect.size.y
	var width := rect.size.y if along_x else rect.size.x
	var n := maxi(1, int(length / 0.6))
	for k in n:
		var a := (rect.position.x if along_x else rect.position.y) + (k + 0.5) * length / n
		var p := Vector3(a, -0.04, mid.y) if along_x else Vector3(mid.x, -0.04, a)
		var s := Vector3(length / n - 0.04, 0.12, width) if along_x else Vector3(width, 0.12, length / n - 0.04)
		c._vbox(p, s, plank.darkened(0.08 * (k % 2)), 0.03)
	collide(Vector3(mid.x, -0.1, mid.y), Vector3(rect.size.x, 0.2, rect.size.y))
	# Supports down into the water.
	var step := 6.0
	var m := maxi(1, int(length / step))
	for k in m + 1:
		var a := (rect.position.x if along_x else rect.position.y) + k * length / m
		for side: float in [-1.0, 1.0]:
			var off := side * (width / 2.0 - 0.2)
			var p := Vector3(a, -1.0, mid.y + off) if along_x else Vector3(mid.x + off, -1.0, a)
			c._vbox(p, Vector3(0.3, 2.0, 0.3), P.WOOD_DARK)
	if rails:
		for side: float in [-1.0, 1.0]:
			var off := side * (width / 2.0 - 0.06)
			var p := Vector3(mid.x, 0.95, mid.y + off) if along_x else Vector3(mid.x + off, 0.95, mid.y)
			var s := Vector3(length, 0.08, 0.1) if along_x else Vector3(0.1, 0.08, length)
			c._vbox(p, s, P.WOOD_DARK)
			collide(p - Vector3(0, 0.45, 0), Vector3(s.x, 1.0, s.z) if along_x else Vector3(s.x, 1.0, s.z))
			for k in int(length / 2.0) + 1:
				var a := (rect.position.x if along_x else rect.position.y) + k * length / int(length / 2.0 + 1)
				var q := Vector3(a, 0.5, mid.y + off) if along_x else Vector3(mid.x + off, 0.5, a)
				c._vbox(q, Vector3(0.1, 0.95, 0.1), P.WOOD_DARK)


## Stepping stones across water: jump from one to the next.
func stones(points: Array, size := 1.3) -> void:
	for p: Vector2 in points:
		var s := size * rng.randf_range(0.85, 1.1)
		box(Vector3(p.x, -1.0, p.y), Vector3(s, 2.0, s), P.STONE_DARK.darkened(0.1), 0.04, true)
		box(Vector3(p.x, 0.02, p.y), Vector3(s * 0.8, 0.08, s * 0.8), P.STONE_DARK, 0.04)


# --- Walls, fences, gates ------------------------------------------------------------------------

## Tall brick perimeter wall with gaps [[a0, a1], ...] left open.
func wall(along_x: bool, a0: float, a1: float, fixed: float, gaps := [], height := 3.4) -> void:
	var cur := a0
	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort_custom(func(x, y): return x[0] < y[0])
	for g in sorted_gaps + [[a1, a1]]:
		if g[0] > cur:
			c._brick_wall(along_x, cur, g[0], fixed, height)
			var r := Rect2(cur, fixed - 0.4, g[0] - cur, 0.8) if along_x else Rect2(fixed - 0.4, cur, 0.8, g[0] - cur)
			map_rect(r, P.BRICK, "", false, "wall")
		cur = maxf(cur, g[1])


## See-through iron fence. Crawl gaps [[a0, a1], ...] have a torn bottom: crouch through.
func fence(along_x: bool, a0: float, a1: float, fixed: float, crawl := [], gaps := [], height := 3.0) -> void:
	var length := a1 - a0
	var map_r := Rect2(a0, fixed - 0.3, length, 0.6) if along_x else Rect2(fixed - 0.3, a0, 0.6, length)
	map_rect(map_r, IRON.lightened(0.2), "", false, "wall")
	var in_any := func(list: Array, a: float) -> bool:
		for g in list:
			if a >= g[0] and a <= g[1]:
				return true
		return false
	# Posts and rails.
	var posts := maxi(1, int(length / 3.0))
	for k in posts + 1:
		var a := a0 + k * length / posts
		if in_any.call(gaps, a):
			continue
		c._vbox(_axis(along_x, a, height / 2.0, fixed), _size(along_x, 0.14, height, 0.14), IRON)
	for y: float in [0.15, height * 0.5, height - 0.05]:
		_fence_rail(along_x, a0, a1, fixed, y, gaps + (crawl if y < 1.3 else []))
	# Pickets.
	var n := int(length / 0.5)
	for k in n:
		var a := a0 + (k + 0.5) * length / n
		if in_any.call(gaps, a):
			continue
		var torn: bool = in_any.call(crawl, a)
		var y0 := 1.3 if torn else 0.0
		c._vbox(_axis(along_x, a, (y0 + height) / 2.0 + 0.1, fixed), _size(along_x, 0.04, height - y0 + 0.2, 0.04), IRON)
		c._vbox(_axis(along_x, a, height + 0.3, fixed), _size(along_x, 0.06, 0.18, 0.06), IRON.lightened(0.2))
	# Collision: solid, except gaps (open) and crawl holes (only the top half).
	var cur := a0
	var holes := gaps + crawl
	holes.sort_custom(func(x, y): return x[0] < y[0])
	for g in holes + [[a1, a1]]:
		if g[0] > cur:
			collide(_axis(along_x, (cur + g[0]) / 2.0, height / 2.0 + 0.3, fixed), _size(along_x, g[0] - cur, height + 0.6, 0.3))
		cur = maxf(cur, g[1])
	for g in crawl:
		collide(_axis(along_x, (g[0] + g[1]) / 2.0, (1.3 + height) / 2.0 + 0.3, fixed), _size(along_x, g[1] - g[0], height - 1.3 + 0.6, 0.3))
		# Bent pickets lying in the grass.
		for k in 3:
			c._vbox(_axis(along_x, g[0] + 0.3 + k * 0.4, 0.04, fixed + (0.4 + k * 0.2)), _size(along_x, 0.05, 0.05, 1.1), IRON)


func _fence_rail(along_x: bool, a0: float, a1: float, fixed: float, y: float, skip: Array) -> void:
	var cur := a0
	var sorted_skip := skip.duplicate()
	sorted_skip.sort_custom(func(x, z): return x[0] < z[0])
	for g in sorted_skip + [[a1, a1]]:
		if g[0] > cur:
			c._vbox(_axis(along_x, (cur + g[0]) / 2.0, y, fixed), _size(along_x, g[0] - cur, 0.07, 0.07), IRON)
		cur = maxf(cur, g[1])


func _axis(along_x: bool, a: float, y: float, fixed: float) -> Vector3:
	return Vector3(a, y, fixed) if along_x else Vector3(fixed, y, a)


func _size(along_x: bool, length: float, height: float, depth: float) -> Vector3:
	return Vector3(length, height, depth) if along_x else Vector3(depth, height, length)


## Grand gate: two pillars, a name arch and gate leaves swung open.
## `out` points outside the grounds (x, z).
func gate(at: Vector2, along_x: bool, width: float, out: Vector2, title: String, sub := "") -> void:
	var half := width / 2.0
	for side: float in [-1.0, 1.0]:
		var p := _axis(along_x, (at.x if along_x else at.y) + side * (half + 0.7), 2.4, at.y if along_x else at.x)
		box(p, Vector3(1.4, 4.8, 1.4), P.STONE, 0.02, true)
		box(p + Vector3(0, 2.5, 0), Vector3(1.7, 0.25, 1.7), P.TRIM, 0.0)
		box(p + Vector3(0, 2.85, 0), Vector3(0.5, 0.45, 0.5), P.METAL_DARK, 0.0)
		glow(p + Vector3(0, 3.25, 0), Vector3(0.44, 0.36, 0.44))
		# Leaf swung open against the inside of the wall.
		var leaf_a := (at.x if along_x else at.y) + side * (half - 0.1)
		var inner := -out * 1.6
		var q := Vector3(at.x, 1.2, at.y) + Vector3(inner.x, 0, inner.y)
		if along_x:
			q.x = leaf_a
		else:
			q.z = leaf_a
		var ls := _size(along_x, 0.08, 2.4, 0.08)
		for rail_y: float in [0.3, 2.3]:
			c._vbox(Vector3(q.x, rail_y, q.z), Vector3(0.08, 0.08, 2.8) if along_x else Vector3(2.8, 0.08, 0.08), IRON)
		collide(q, Vector3(0.14, 2.4, 2.8) if along_x else Vector3(2.8, 2.4, 0.14))
		for b in 10:
			var o := -1.25 + b * 0.28
			c._vbox(q + (Vector3(0, 0, o) if along_x else Vector3(o, 0, 0)), ls, IRON)
	var arch_c := Vector3(at.x, 5.3, at.y)
	box(arch_c, _size(along_x, width + 2.8, 1.3, 0.6), Color("24315e"), 0.0)
	box(arch_c + Vector3(0, 0.75, 0), _size(along_x, width + 3.0, 0.2, 0.7), P.TRIM, 0.0)
	var yaw_out := facing(-out)  # label readable from outside
	var yaw_in := facing(out)
	var off_out := Vector3(out.x, 0, out.y) * 0.32
	label(title, arch_c + off_out, 72, Color("ffd24a"), yaw_out, 14)
	label(sub if sub != "" else "Come back soon!", arch_c - off_out, 60, Color("ffd24a"), yaw_in, 12)


## Security booth (square, windows on every side).
func booth(at: Vector2, text := "SECURITY") -> void:
	var p := Vector3(at.x, 0, at.y)
	box(p + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 2.4), P.SHIRT, 0.02, true)
	box(p + Vector3(0, 0.3, 0), Vector3(2.45, 0.6, 2.45), Color("3f86a8"), 0.0)
	box(p + Vector3(0, 2.5, 0), Vector3(3.0, 0.18, 3.0), P.TRIM, 0.0)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var f := Vector3(d.x, 0, d.y) * 1.21
		c._glass.box(p + f + Vector3(0, 1.5, 0), Vector3(0.02 + absf(d.y) * 1.4, 0.8, 0.02 + absf(d.x) * 1.4), Color.WHITE)
		c._vbox(p + f * 1.004 + Vector3(0, 1.5, 0), Vector3(0.03 + absf(d.y) * 1.5, 0.9, 0.03 + absf(d.x) * 1.5), Color("2c5e78"))
	label(text, p + Vector3(0, 2.75, -1.25), 34, Color("24315e"), PI, 0)
	label(text, p + Vector3(0, 2.75, 1.25), 34, Color("24315e"), 0.0, 0)


## Raised red-and-white boom barrier on a post.
func barrier(at: Vector2) -> void:
	box(Vector3(at.x, 0.5, at.y), Vector3(0.3, 1.0, 0.3), P.METAL_DARK, 0.0, true)
	for k in 7:
		box(Vector3(at.x, 1.2 + k * 0.4, at.y), Vector3(0.12, 0.4, 0.12), Color("e0524f") if k % 2 == 0 else Color.WHITE, 0.0)


## Camera on a pole (or wall) at height h, looking along yaw.
func camera(at: Vector2, h: float, yaw: float, sweep := 0.7, speed := 0.4, pole := true) -> void:
	if pole:
		box(Vector3(at.x, h / 2.0, at.y), Vector3(0.14, h, 0.14), P.METAL_DARK, 0.0, true)
	c.add_cctv(Vector3(at.x, h, at.y), yaw, sweep, speed)


# --- Staff and students -------------------------------------------------------------------------------

## A guard who stands at a gate. zone: where they check passes (hall passes don't work there).
func post(id: String, display: String, at: Vector2, look_dir: Vector2, zone: Rect2, look_seed := 0) -> void:
	c.posts.append({"id": id, "name": display, "pos": Vector3(at.x, 0, at.y), "yaw": facing(look_dir), "zone": zone, "seed": look_seed})
	c.gate_zones.append(zone)


func patrol(id: String, display: String, loop: Array, walk_speed := 1.7, chase := 4.8, view := 14.0, look := "guard") -> void:
	var pts := []
	for p: Vector2 in loop:
		pts.append(Vector3(p.x, 0, p.y))
	c.patrols.append({"id": id, "name": display, "loop": pts, "walk": walk_speed, "chase": chase, "view": view, "look": look})


func stroll(loop: Array) -> void:
	var pts := []
	for p: Vector2 in loop:
		pts.append(Vector3(p.x, 0, p.y))
	c.walkers.append(pts)


func exit_marker(at: Vector2, text: String) -> void:
	c.exits.append({"at": at, "name": text})


# --- Buildings ----------------------------------------------------------------------------------------

## Blocky building: storeys of windows, a trim band per floor, a roof with
## clutter and a named entrance on the `front` side. Solid (you can't go in).
## Call from _plan() via reserve()/map, and build it in _build().
func building(rect: Rect2, floors: int, wall_c: Color, trim: Color, title := "", front := Vector2(0, -1), lit := 0.15) -> void:
	var h := floors * STOREY
	var mid := rect.get_center()
	box(Vector3(mid.x, h / 2.0, mid.y), Vector3(rect.size.x, h, rect.size.y), wall_c, 0.0, true)
	box(Vector3(mid.x, 0.45, mid.y), Vector3(rect.size.x + 0.14, 0.9, rect.size.y + 0.14), trim.darkened(0.2), 0.0)
	for f in range(1, floors + 1):
		box(Vector3(mid.x, f * STOREY - 0.12, mid.y), Vector3(rect.size.x + 0.18, 0.24, rect.size.y + 0.18), trim, 0.0)
	# Windows on all four faces.
	for face: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var along_x: bool = face.y != 0
		var length: float = rect.size.x if along_x else rect.size.y
		var n := maxi(1, int(length / 3.2))
		var fixed: float = (rect.position.y if face.y < 0 else rect.end.y) if along_x else (rect.position.x if face.x < 0 else rect.end.x)
		var start: float = rect.position.x if along_x else rect.position.y
		for f in floors:
			for k in n:
				var a := start + (k + 0.5) * length / n
				if f == 0 and face == front and absf(a - (mid.x if along_x else mid.y)) < 2.4:
					continue  # entrance
				var p := _axis(along_x, a, f * STOREY + 1.75, fixed + (face.y if along_x else face.x) * 0.04)
				var s := _size(along_x, 1.5, 1.5, 0.08)
				if rng.randf() < lit:
					c._glow.box(p, s, P.GLOW)
				else:
					c._vbox(p, s, GLASS.darkened(rng.randf_range(0.0, 0.15)))
				c._vbox(_axis(along_x, a, f * STOREY + 0.95, fixed + (face.y if along_x else face.x) * 0.08), _size(along_x, 1.7, 0.1, 0.16), trim.lightened(0.1))
	# Roof: parapet, water tank, AC units.
	box(Vector3(mid.x, h + 0.25, rect.position.y + 0.15), Vector3(rect.size.x, 0.5, 0.3), trim, 0.0)
	box(Vector3(mid.x, h + 0.25, rect.end.y - 0.15), Vector3(rect.size.x, 0.5, 0.3), trim, 0.0)
	box(Vector3(rect.position.x + 0.15, h + 0.25, mid.y), Vector3(0.3, 0.5, rect.size.y), trim, 0.0)
	box(Vector3(rect.end.x - 0.15, h + 0.25, mid.y), Vector3(0.3, 0.5, rect.size.y), trim, 0.0)
	box(Vector3(mid.x, h + 0.01, mid.y), Vector3(rect.size.x - 0.6, 0.04, rect.size.y - 0.6), P.ROOF, 0.0)
	box(Vector3(mid.x + rect.size.x * 0.25, h + 0.8, mid.y), Vector3(1.8, 1.6, 1.8), Color("2c2e36"), 0.0)
	for k in 3:
		box(Vector3(mid.x - rect.size.x * 0.25 + k * 1.3, h + 0.35, mid.y + rect.size.y * 0.2), Vector3(1.0, 0.7, 0.6), P.PAPER, 0.03)
	# Entrance: door, canopy, name board.
	var fx: bool = front.y != 0
	var fixed_f: float = (rect.position.y if front.y < 0 else rect.end.y) if fx else (rect.position.x if front.x < 0 else rect.end.x)
	var centre: float = mid.x if fx else mid.y
	var out3 := Vector3(front.x, 0, front.y)
	var door := _axis(fx, centre, 1.3, fixed_f) + out3 * 0.05
	box(door, _size(fx, 2.4, 2.6, 0.1), Color("2c3e5a"), 0.0)
	c._glass.box(door + out3 * 0.04, _size(fx, 2.0, 2.3, 0.02), Color.WHITE)
	box(_axis(fx, centre, 3.0, fixed_f) + out3 * 0.9, _size(fx, 4.0, 0.16, 1.8), trim, 0.0)
	if title != "":
		var board := _axis(fx, centre, h - 1.2 if floors > 1 else 2.9, fixed_f) + out3 * 0.12
		if floors > 1:
			box(board, _size(fx, minf(length_of(rect, fx) - 1.0, title.length() * 0.75 + 1.5), 1.1, 0.1), Color("24315e"), 0.0)
		label(title, board + out3 * 0.08, 90 if floors > 1 else 50, Color("ffd24a"), facing(-front), 12)


func length_of(rect: Rect2, along_x: bool) -> float:
	return rect.size.x if along_x else rect.size.y


# --- Nature and props ---------------------------------------------------------------------------------

func tree(at: Vector2, kind := -1) -> void:
	c._tree(Vector3(at.x, 0, at.y), rng.randi() % 3 if kind < 0 else kind)


func palm(at: Vector2) -> void:
	var p := Vector3(at.x, 0, at.y)
	var h := rng.randf_range(4.0, 6.0)
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	var segs := 7
	for k in segs:
		var t := float(k) / segs
		c._vbox(p + lean * t * t + Vector3(0, (k + 0.5) * h / segs, 0), Vector3(0.34, h / segs + 0.02, 0.34), P.TRUNK.lightened(0.08 * (k % 2)), 0.02)
	collide(p + Vector3(0, 1.25, 0), Vector3(0.4, 2.5, 0.4))
	var top := p + lean + Vector3(0, h, 0)
	var leaf: Color = P.LEAVES[rng.randi() % P.LEAVES.size()]
	c._vbox(top, Vector3(0.6, 0.4, 0.6), leaf.darkened(0.1), 0.03)
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		c._vbox(top + d * 1.1 + Vector3(0, -0.15, 0), Vector3(0.5, 0.12, 0.5) + d.abs() * 1.4, leaf, 0.04)
		c._vbox(top + d * 2.0 + Vector3(0, -0.28, 0), Vector3(0.4, 0.12, 0.4) + d.abs() * 0.5, leaf.lightened(0.06), 0.04)
	c._vbox(top + Vector3(0.2, -0.35, 0.2), Vector3(0.25, 0.25, 0.25), Color("7a5a2a"))


## Scatters `count` trees over rect, avoiding roads, buildings and water.
func forest(rect: Rect2, count: int, kinds := [0, 1, 2], palms := false) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 6:
		tries += 1
		var x := rng.randf_range(rect.position.x, rect.end.x)
		var z := rng.randf_range(rect.position.y, rect.end.y)
		if not free_at(x, z) or not free_at(x + 1.5, z + 1.5) or not free_at(x - 1.5, z - 1.5):
			continue
		if palms:
			palm(Vector2(x, z))
		else:
			tree(Vector2(x, z), kinds[rng.randi() % kinds.size()])
		placed += 1


func bushes(rect: Rect2, count: int) -> void:
	for k in count:
		var x := rng.randf_range(rect.position.x, rect.end.x)
		var z := rng.randf_range(rect.position.y, rect.end.y)
		if free_at(x, z) and free_at(x + 1, z + 1):
			c._bush(Vector3(x, 0, z), rng.randf_range(0.8, 1.4))


func flowers(rect: Rect2, count: int) -> void:
	for k in count:
		var x := rng.randf_range(rect.position.x, rect.end.x)
		var z := rng.randf_range(rect.position.y, rect.end.y)
		if not free_at(x, z):
			continue
		c._vbox(Vector3(x, 0.07, z), Vector3(0.03, 0.16, 0.03), P.GRASS_DARK)
		c._vbox(Vector3(x, 0.17, z), Vector3(0.12, 0.08, 0.12), P.FLOWERS[rng.randi() % P.FLOWERS.size()])


## Boulder you can hide behind.
func rock(at: Vector2, s := 1.2) -> void:
	var p := Vector3(at.x, 0, at.y)
	box(p + Vector3(0, s * 0.4, 0), Vector3(s * 1.3, s * 0.8, s), P.STONE_DARK.darkened(0.15), 0.05, true)
	box(p + Vector3(s * 0.15, s * 0.95, -s * 0.1), Vector3(s * 0.8, s * 0.4, s * 0.7), P.STONE_DARK, 0.05, true)


func lamp(at: Vector2) -> void:
	box(Vector3(at.x, 1.8, at.y), Vector3(0.14, 3.6, 0.14), P.METAL_DARK, 0.0, true)
	box(Vector3(at.x, 0.15, at.y), Vector3(0.32, 0.3, 0.32), P.METAL_DARK, 0.0)
	box(Vector3(at.x, 3.7, at.y), Vector3(0.4, 0.2, 0.4), P.METAL_DARK, 0.0)
	glow(Vector3(at.x, 3.55, at.y), Vector3(0.32, 0.1, 0.32))


func bench(at: Vector2) -> void:
	c._park_bench(Vector3(at.x, 0, at.y))


## Blocky car (along_x: nose along x).
func car(at: Vector2, along_x: bool, color: Color) -> void:
	var p := Vector3(at.x, 0, at.y)
	box(p + Vector3(0, 0.55, 0), _size(along_x, 3.8, 0.6, 1.7), color, 0.02, true)
	box(p + Vector3(0, 1.1, 0), _size(along_x, 2.1, 0.55, 1.55), Color("2c3e5a"), 0.0)
	box(p + Vector3(0, 1.4, 0), _size(along_x, 2.0, 0.07, 1.5), color, 0.0)
	for wa: float in [-1.25, 1.25]:
		for wb: float in [-0.82, 0.82]:
			box(p + (Vector3(wa, 0.3, wb) if along_x else Vector3(wb, 0.3, wa)), _size(along_x, 0.62, 0.62, 0.16), Color("26262e"), 0.0)


## Bus (along_x: nose along x).
func bus(at: Vector2, along_x: bool, color: Color, text := "") -> void:
	var p := Vector3(at.x, 0, at.y)
	box(p + Vector3(0, 1.6, 0), _size(along_x, 10.0, 2.6, 2.5), color, 0.02, true)
	box(p + Vector3(0, 2.2, 0), _size(along_x, 9.4, 0.9, 2.56), GLASS, 0.0)
	box(p + Vector3(0, 3.0, 0), _size(along_x, 10.0, 0.1, 2.5), color.lightened(0.2), 0.0)
	for wa: float in [-3.4, 3.4]:
		for wb: float in [-1.2, 1.2]:
			box(p + (Vector3(wa, 0.45, wb) if along_x else Vector3(wb, 0.45, wa)), _size(along_x, 0.9, 0.9, 0.2), Color("26262e"), 0.0)
	if text != "":
		var side := Vector3(0, 0, -1.3) if along_x else Vector3(-1.3, 0, 0)
		label(text, p + Vector3(0, 1.1, 0) + side, 60, Color.WHITE, PI if along_x else -PI / 2, 10)


## Sign on a post, readable from both sides.
func signpost(at: Vector2, text: String, yaw: float, board := Color("2f6a4a"), ink := Color.WHITE, h := 2.4) -> void:
	box(Vector3(at.x, h / 2.0, at.y), Vector3(0.12, h, 0.12), P.METAL_DARK, 0.0, true)
	var lines := text.split("\n")
	var widest := 0
	for l in lines:
		widest = maxi(widest, l.length())
	var w := widest * 0.13 + 0.5
	var bh := lines.size() * 0.24 + 0.24
	var along := Vector3(cos(yaw), 0, -sin(yaw))
	var bsize := Vector3(absf(along.x) * w + absf(along.z) * 0.08, bh, absf(along.z) * w + absf(along.x) * 0.08)
	box(Vector3(at.x, h + bh / 2.0, at.y), bsize, board, 0.0)
	var n := Vector3(sin(yaw), 0, cos(yaw)) * 0.06
	label(text, Vector3(at.x, h + bh / 2.0, at.y) + n, 40, ink, yaw, 8)
	label(text, Vector3(at.x, h + bh / 2.0, at.y) - n, 40, ink, yaw + PI, 8)


## Low wooden shack with a striped awning (stalls, snack shops).
func stall(at: Vector2, color: Color, text: String, front := Vector2(0, -1)) -> void:
	var p := Vector3(at.x, 0, at.y)
	box(p + Vector3(0, 1.1, 0), Vector3(3.4, 2.2, 2.4), color, 0.02, true)
	var f := Vector3(front.x, 0, front.y)
	box(p + f * 1.35 + Vector3(0, 0.55, 0), Vector3(3.4 if front.y != 0 else 0.4, 1.1, 0.4 if front.y != 0 else 3.4), P.WOOD, 0.02, true)
	box(p + Vector3(0, 2.3, 0) + f * 0.3, Vector3(4.0, 0.14, 3.2), Color("e0524f"), 0.0)
	for k in 5:
		var o := -1.6 + k * 0.8
		var q := p + f * 1.85 + Vector3(0, 2.22, 0) + (Vector3(o, 0, 0) if front.y != 0 else Vector3(0, 0, o))
		box(q, Vector3(0.8, 0.14, 0.3) if front.y != 0 else Vector3(0.3, 0.14, 0.8), Color("e0524f") if k % 2 == 0 else Color.WHITE, 0.0)
	label(text, p + Vector3(0, 2.75, 0) + f * 1.3, 44, Color.WHITE, facing(-front), 12)
