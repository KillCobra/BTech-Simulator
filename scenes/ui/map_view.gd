extends Control
## Illustrated top-down map, drawn from the campus builder's shapes. Used for
## the round minimap (turns with you, compass ring) and the big map (M).
## A true top-down view: north (-z) is up and east (+x) is right.
##
## Shape kinds (see CampusBuilder._map): area, water, path, road, court,
## building, hall, room, stairs, wall. Drawn in that order, with building
## shadows, room walls, road markings and non-overlapping name tags.

const KIND_ORDER := ["area", "water", "path", "road", "court", "building", "hall", "room", "stairs", "wall"]
const OUTSIDE := Color("4a7f41")
const GRASS := Color("7cbf5a")
const INK := Color("2a2230")
const WALL_INK := Color("3a2d26")

var shapes: Array = []
var center := Vector2.ZERO  # world x/z at the middle
var zoom := 4.0             # pixels per metre
var level := 0
var markers: Array = []     # {"at", "kind", "color", "text", "yaw", "alert", "other_floor"}
var label_size := 11
var rot := 0.0              # minimap: turn so the player's view points up
var round_map := false      # minimap: circular with a compass ring
var bounds := Rect2()       # the university grounds (outside is darker)
var frame_color := Color(0.08, 0.08, 0.14, 0.92)
var show_names := true      # staff/friend names next to their markers
var outside := OUTSIDE      # colour beyond the playable area
var route: Array = []       # phone Navigate: [from: Vector2, to: Vector2, on this floor: bool] segments
const ROUTE := Color("b07cff")

var _sorted: Array = []
var _placed: Array[Rect2] = []


func set_shapes(list: Array) -> void:
	shapes = list
	_sorted = list.duplicate()
	_sorted.sort_custom(func(a, b): return KIND_ORDER.find(_kind(a)) < KIND_ORDER.find(_kind(b)))


static func _kind(s: Dictionary) -> String:
	var k: String = s.get("kind", "")
	return k if k != "" else "area"


func to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + ((p - center) * zoom).rotated(rot)


func _poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([to_screen(r.position), to_screen(Vector2(r.end.x, r.position.y)),
		to_screen(r.end), to_screen(Vector2(r.position.x, r.end.y))])


func _visible_radius() -> float:
	return size.length() / zoom * 0.55


func _draw() -> void:
	_placed.clear()
	var font := get_theme_default_font()
	var reach := _visible_radius()
	draw_rect(Rect2(Vector2.ZERO, size), outside)
	if bounds.has_area():
		draw_colored_polygon(_poly(bounds), GRASS)
	# Shapes, back to front.
	for s in _sorted:
		if s.level != -1 and s.level != level:
			continue
		var r: Rect2 = s.rect
		if r.get_center().distance_to(center) > reach + r.size.length() / 2.0:
			continue
		_draw_shape(s, r)
	# Your class right now: tinted and outlined.
	for m in markers:
		if m.kind == "room" and int(m.get("level", -1)) in [-1, level]:
			var poly := _poly(m.rect)
			draw_colored_polygon(poly, Color(1.0, 0.42, 0.36, 0.3))
			var ring := poly.duplicate()
			ring.append(poly[0])
			draw_polyline(ring, Color("ff5a4a"), 2.5)
	# Navigate route: solid on this floor, dashed where it's on another floor (stairs).
	for seg: Array in route:
		var a := to_screen(seg[0])
		var b := to_screen(seg[1])
		if seg[2]:
			draw_line(a, b, Color(1, 1, 1, 0.9), 6.0, true)
			draw_line(a, b, ROUTE, 3.5, true)
		else:
			draw_dashed_line(a, b, Color(ROUTE, 0.7), 2.5, 6.0)
	# Name tags, most important first, never on top of each other.
	var tags := []
	for s in _sorted:
		if s.label == "" or (s.level != -1 and s.level != level):
			continue
		var r: Rect2 = s.rect
		if r.get_center().distance_to(center) > reach:
			continue
		var pri := 0 if s.get("force", false) else (1 if _kind(s) == "building" else (2 if _kind(s) == "room" else 3))
		tags.append([pri, s])
	tags.sort_custom(func(a, b): return a[0] < b[0])
	for t in tags:
		var s: Dictionary = t[1]
		var r: Rect2 = s.rect
		var room := minf(r.size.x, r.size.y) * zoom
		if room < 14.0 and not s.get("force", false):
			continue
		_tag(font, to_screen(r.get_center()), s.label, label_size, Color.WHITE, Color(0.1, 0.08, 0.12, 0.72))
	# Markers: exits and quests under people, you on top.
	for m in markers:
		if m.kind in ["exit", "quest", "ping", "seat"]:
			_marker(font, m)
	for m in markers:
		if m.kind in ["staff", "friend"]:
			_marker(font, m)
	for m in markers:
		if m.kind == "me":
			_marker(font, m)
	if round_map:
		_round_frame(font)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), false, 3.0)


func _draw_shape(s: Dictionary, r: Rect2) -> void:
	var c: Color = s.color
	var pts := _poly(r)
	match _kind(s):
		"water":
			draw_colored_polygon(pts, Color("5cb6e0"))
			if zoom > 1.2 and r.size.x * zoom > 40.0:
				# A few wave marks.
				var n := int(r.size.x * r.size.y / 900.0) + 1
				for k in mini(n, 12):
					var wp := r.position + r.size * Vector2(fposmod(k * 0.618, 1.0), fposmod(k * 0.382 + 0.2, 1.0))
					var sp := to_screen(wp)
					draw_arc(sp, 4.0, PI * 1.15, PI * 1.85, 6, Color(1, 1, 1, 0.45), 1.5)
		"road":
			draw_colored_polygon(pts, Color("5a5d68"))
			draw_polyline(_closed(pts), Color("3e4049"), 1.0)
			if minf(r.size.x, r.size.y) * zoom > 5.0:
				var a: Vector2
				var b: Vector2
				if r.size.x >= r.size.y:
					a = Vector2(r.position.x, r.get_center().y)
					b = Vector2(r.end.x, r.get_center().y)
				else:
					a = Vector2(r.get_center().x, r.position.y)
					b = Vector2(r.get_center().x, r.end.y)
				draw_dashed_line(to_screen(a), to_screen(b), Color("f4f1e6", 0.8), maxf(1.0, zoom * 0.18), maxf(4.0, zoom * 2.4))
		"path":
			draw_colored_polygon(pts, c.lightened(0.1))
			draw_polyline(_closed(pts), c.darkened(0.25), 1.0)
		"court":
			draw_colored_polygon(pts, c)
			draw_polyline(_closed(_poly(r.grow(-0.8))), Color(1, 1, 1, 0.8), 1.2)
			draw_line(to_screen(Vector2(r.position.x + 0.8, r.get_center().y)), to_screen(Vector2(r.end.x - 0.8, r.get_center().y)), Color(1, 1, 1, 0.8), 1.2)
		"building":
			var shadow := PackedVector2Array()
			var off := Vector2(3, 4) if not round_map else Vector2(2, 3).rotated(rot)
			for p in pts:
				shadow.append(p + off)
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.28))
			draw_colored_polygon(pts, c)
			draw_polyline(_closed(pts), c.darkened(0.45), 1.5)
			draw_polyline(_closed(_poly(r.grow(-maxf(0.4, 1.5 / zoom)))), c.lightened(0.18), 1.0)
		"hall":
			draw_colored_polygon(pts, c)
		"room":
			draw_colored_polygon(pts, c)
			draw_polyline(_closed(pts), WALL_INK, maxf(1.0, zoom * 0.12))
		"stairs":
			draw_colored_polygon(pts, Color("9a9486"))
			var steps := int(maxf(r.size.x, r.size.y) * zoom / 5.0)
			for k in range(1, steps):
				var t := float(k) / steps
				if r.size.y >= r.size.x:
					draw_line(to_screen(Vector2(r.position.x, r.position.y + r.size.y * t)), to_screen(Vector2(r.end.x, r.position.y + r.size.y * t)), Color("6a6456"), 1.0)
				else:
					draw_line(to_screen(Vector2(r.position.x + r.size.x * t, r.position.y)), to_screen(Vector2(r.position.x + r.size.x * t, r.end.y)), Color("6a6456"), 1.0)
			draw_polyline(_closed(pts), WALL_INK, 1.0)
		"wall":
			draw_colored_polygon(pts, c.darkened(0.1))
			if minf(r.size.x, r.size.y) * zoom < 2.0:
				# Thin walls still show up as a line.
				var a2: Vector2
				var b2: Vector2
				if r.size.x >= r.size.y:
					a2 = Vector2(r.position.x, r.get_center().y)
					b2 = Vector2(r.end.x, r.get_center().y)
				else:
					a2 = Vector2(r.get_center().x, r.position.y)
					b2 = Vector2(r.get_center().x, r.end.y)
				draw_line(to_screen(a2), to_screen(b2), c.darkened(0.2), 2.0)
		_:
			draw_colored_polygon(pts, c)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


## Parent for the round minimap: draws a disc and clips its children to it.
class RoundMask extends Control:
	func _ready() -> void:
		clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	func _draw() -> void:
		draw_circle(size / 2.0, minf(size.x, size.y) / 2.0 - 1.0, Color(0.08, 0.08, 0.14, 0.9))


## A readable name tag; skipped if it would cover one already drawn.
func _tag(font: Font, at: Vector2, text: String, fsize: int, ink: Color, bg: Color, force := false) -> bool:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var box := Rect2(at - Vector2(w / 2.0 + 5, fsize * 0.5 + 3), Vector2(w + 10, fsize + 6))
	if not Rect2(Vector2.ZERO, size).grow(-2).encloses(box) and not force:
		return false
	for p in _placed:
		if p.intersects(box):
			return false
	_placed.append(box)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(box.size.y / 2.0))
	draw_style_box(sb, box)
	draw_string(font, Vector2(box.position.x + 5, box.position.y + fsize + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, ink)
	return true


func _marker(font: Font, m: Dictionary) -> void:
	var at := to_screen(m.at)
	if not Rect2(Vector2.ZERO, size).grow(10).has_point(at):
		return
	var c: Color = m.get("color", Color.WHITE)
	var t := Time.get_ticks_msec() / 1000.0
	match str(m.kind):
		"me":
			var dir := Vector2(-sin(m.yaw), -cos(m.yaw)).rotated(rot)
			# View cone.
			var cone := PackedVector2Array([at])
			for k in 9:
				cone.append(at + dir.rotated(-0.55 + k * 1.1 / 8.0) * 34.0)
			draw_colored_polygon(cone, Color(1, 0.85, 0.3, 0.18))
			draw_icon_arrow(self, at, dir, 1.0)
		"friend":
			draw_circle(at, 7.5, INK)
			draw_circle(at, 6.0, c)
			var initial: String = str(m.get("text", "?")).left(1).to_upper()
			draw_string(font, at + Vector2(-4, 4.5), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
			if show_names and str(m.get("text", "")) != "":
				_tag(font, at + Vector2(0, -16), str(m.text), label_size, Color.WHITE, Color(0.1, 0.3, 0.45, 0.8))
		"staff":
			draw_icon_staff(self, at, int(m.get("alert", 0)), bool(m.get("other_floor", false)), t)
			if show_names and str(m.get("text", "")) != "":
				_tag(font, at + Vector2(0, -17), str(m.text), label_size - 1, Color.WHITE, Color(0.45, 0.08, 0.08, 0.8))
		"quest":
			draw_icon_star(self, at, 1.0, Color("ffd24a"))
		"seat":
			draw_icon_seat(self, at, 1.0)
			if str(m.get("text", "")) != "":
				_tag(font, at + Vector2(0, -18), str(m.text), label_size, Color.WHITE, Color(0.1, 0.3, 0.45, 0.85))
		"exit":
			draw_icon_exit(self, at, 1.0)
			if not round_map and str(m.get("text", "")) != "":
				_tag(font, at + Vector2(0, 18), str(m.text), label_size, Color.WHITE, Color(0.1, 0.35, 0.18, 0.88), true)
		"ping":
			var pulse := fposmod(t * 1.5, 1.0)
			draw_arc(at, 5.0 + pulse * 10.0, 0, TAU, 20, Color(1, 0.82, 0.3, 1.0 - pulse), 2.0)
			draw_circle(at, 3.0, Color("ffd24a"))


func _round_frame(font: Font) -> void:
	var mid := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	# (The parent clips us to a circle.) A ring with a compass.
	draw_arc(mid, r + 1.0, 0, TAU, 72, INK, 5.0)
	draw_arc(mid, r - 1.0, 0, TAU, 72, Color(1, 1, 1, 0.35), 1.5)
	# North (-z) and the other points on the ring.
	var labels := {"N": 0.0, "E": PI / 2.0, "S": PI, "W": -PI / 2.0}
	for name in labels:
		var dir := Vector2(0, -1).rotated(rot + float(labels[name]))
		var p := mid + dir * (r - 2.0)
		var col := Color("ff5a4a") if name == "N" else Color.WHITE
		draw_circle(p, 8.0, INK)
		draw_string(font, p + Vector2(-4.5, 4.5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


# --- Icons (shared with the legend) ------------------------------------------------------------------

static func draw_icon_arrow(ci: CanvasItem, at: Vector2, dir: Vector2, s: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([at + dir * 12 * s, at - dir * 7 * s + perp * 8 * s, at - dir * 3 * s, at - dir * 7 * s - perp * 8 * s])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(at + (p - at) * 1.3)
	ci.draw_colored_polygon(outline, INK)
	ci.draw_colored_polygon(pts, Color("ffc93c"))


static func draw_icon_staff(ci: CanvasItem, at: Vector2, alert: int, other_floor: bool, t: float) -> void:
	var c := Color("ff3b3b") if alert == 2 else (Color("ff9a4a") if alert == 1 else Color("d94a4a"))
	if other_floor:
		ci.draw_arc(at, 6.5, 0, TAU, 16, c, 2.5)
		return
	if alert == 2:
		ci.draw_arc(at, 10.0 + sin(t * 10.0) * 2.0, 0, TAU, 18, Color(1, 0.2, 0.2, 0.7), 2.0)
	ci.draw_circle(at, 7.5, INK)
	ci.draw_circle(at, 6.0, c)
	ci.draw_rect(Rect2(at + Vector2(-1.2, -4), Vector2(2.4, 5)), Color.WHITE)
	ci.draw_rect(Rect2(at + Vector2(-1.2, 2.2), Vector2(2.4, 2)), Color.WHITE)


## Blue map pin: your seat.
static func draw_icon_seat(ci: CanvasItem, at: Vector2, s: float) -> void:
	var tip := at + Vector2(0, 7) * s
	ci.draw_colored_polygon(PackedVector2Array([tip, at + Vector2(-7, -3) * s, at + Vector2(7, -3) * s]), INK)
	ci.draw_circle(at + Vector2(0, -4) * s, 8.0 * s, INK)
	ci.draw_circle(at + Vector2(0, -4) * s, 6.5 * s, Color("3fa8e0"))
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, 5) * s, at + Vector2(-5, -2) * s, at + Vector2(5, -2) * s]), Color("3fa8e0"))
	ci.draw_circle(at + Vector2(0, -4) * s, 2.5 * s, Color.WHITE)


static func draw_icon_star(ci: CanvasItem, at: Vector2, s: float, c: Color) -> void:
	var pts := PackedVector2Array()
	var big := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		var rad := (8.0 if k % 2 == 0 else 3.6) * s
		pts.append(at + Vector2(cos(a), sin(a)) * rad)
		big.append(at + Vector2(cos(a), sin(a)) * (rad + 2.0))
	ci.draw_colored_polygon(big, INK)
	ci.draw_colored_polygon(pts, c)


static func draw_icon_exit(ci: CanvasItem, at: Vector2, s: float) -> void:
	ci.draw_circle(at, 11.0 * s, INK)
	ci.draw_circle(at, 9.5 * s, Color("2fa85a"))
	ci.draw_line(at + Vector2(-3, 6) * s, at + Vector2(-3, -6) * s, Color.WHITE, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -6) * s, at + Vector2(5, -3) * s, at + Vector2(-3, 0) * s]), Color.WHITE)
