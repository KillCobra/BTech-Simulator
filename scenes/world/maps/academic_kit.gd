extends "res://scenes/world/maps/grounds.gd"
## Builds big academic buildings out of "wings": a corridor with rooms on both
## sides, several storeys, switchback stairwells at both corridor ends and
## doors out at the ground-floor ends. Room interiors are laid out in the
## room's own frame (l = along the corridor, d = depth from the corridor wall,
## f = into the room), so a wing can run along x or z and rooms can sit on
## either side of the corridor.
##
## A map that uses this calls begin_campus(), then wing(...) for each block,
## court()/principal_car()/assembly_point() outside, then finish_campus().

const FH := 3.6        # storey height: 3.2 walls + 0.4 slab
const WH := 3.2
const WT := 0.24
const CORRIDOR := 3.2
const STAIR_W := 4.8

var style := {
	"wall": P.WALL, "trim": P.TRIM, "floor": [P.FLOOR_A, P.FLOOR_B], "hall": [P.VERANDAH_A, P.VERANDAH_B],
	"dado_in": P.DADO_INSIDE, "dado_hall": P.DADO_OUTSIDE, "dado_out": P.DADO_OUTSIDE,
	"frame": Color("3f86a8"), "roof": P.ROOF, "ceiling": Color("f7f3ea"),
}
var _wings: Array[Dictionary] = []
var _notices := 0
var _alarms := 0
var _subjects := ["Thermodynamics\nAttendance: 9:05", "Engineering Maths\nUnit test on Friday!",
	"Data Structures\nNo phones in class", "Chemistry Lab\nWear your lab coat"]
var _npc_subjects := ["Philosophy of Naps", "Advanced Doodling", "History of Chairs", "Applied Daydreaming",
	"Quantum Excuses", "Intro to Queueing", "Competitive Waiting", "Statistics\nMidterm moved (again)"]


func begin_campus() -> void:
	c.classes.clear()
	for i in 4:
		c.classes.append({})
	c.levels = 1
	c._oy = 0.0


func finish_campus() -> void:
	c._oy = 0.0
	# Waypoints just outside every wing, so exits, passages and yards all link up.
	for W: Dictionary in _wings:
		for v: float in [W.v0 - 2.2, W.v1 + 2.2]:
			var u: float = W.u0 - 2.2
			while u <= W.u1 + 2.3:
				var p: Vector3 = W.ua * u + W.va * v
				var inside := false
				for other: Dictionary in _wings:
					if (other.rect as Rect2).grow(0.6).has_point(Vector2(p.x, p.z)):
						inside = true
				if not inside:
					c.nav_points.append(p)
				u += 7.0
	c.wall_color = P.WALL
	c.frame_color = Color("3f86a8")
	for i in c.classes.size():
		assert(not (c.classes[i] as Dictionary).is_empty(), "classroom %d was never placed" % i)


# --- Room frames --------------------------------------------------------------------------------------

func frame(o: Vector3, f: Vector3, r: Vector3, w: float, d: float) -> Dictionary:
	return {"o": o, "f": f, "r": r, "w": w, "d": d}


## Point in a frame (local y; the storey offset is added by the builder).
func fp(F: Dictionary, l: float, y: float, d: float) -> Vector3:
	return (F.o as Vector3) + (F.r as Vector3) * l + Vector3(0, y, 0) + (F.f as Vector3) * d


func fs(F: Dictionary, sl: float, sy: float, sd: float) -> Vector3:
	var r: Vector3 = F.r
	var f: Vector3 = F.f
	return Vector3(absf(r.x) * sl + absf(f.x) * sd, sy, absf(r.z) * sl + absf(f.z) * sd)


func fb(F: Dictionary, l: float, y: float, d: float, sl: float, sy: float, sd: float, color: Color, jitter := 0.02, solid := false) -> void:
	box(fp(F, l, y, d), fs(F, sl, sy, sd), color, jitter, solid)


func frect(F: Dictionary, inset := 0.0) -> Rect2:
	var a := fp(F, -F.w / 2.0 + inset, 0, inset)
	var b := fp(F, F.w / 2.0 - inset, 0, F.d - inset)
	return Rect2(minf(a.x, b.x), minf(a.z, b.z), absf(a.x - b.x), absf(a.z - b.z))


## Yaw of someone facing into the room (towards its far wall).
func fyaw(F: Dictionary) -> float:
	return facing(Vector2(F.f.x, F.f.z))


func oy() -> Vector3:
	return Vector3(0, c._oy, 0)


func kglow(pos: Vector3, size: Vector3, color := P.GLOW) -> void:
	c._glow.box(pos + oy(), size, color)


var _light_budget := 90  # omni lights are the priciest thing indoors; tube glows do the rest


func klight(pos: Vector3, energy := 0.9, rng_m := 8.5) -> void:
	if _light_budget <= 0:
		return
	_light_budget -= 1
	var light := OmniLight3D.new()
	light.position = pos + oy()
	light.light_color = Color(1.0, 0.95, 0.86)
	light.light_energy = energy
	light.omni_range = rng_m
	c._root.add_child(light)


# --- Wings --------------------------------------------------------------------------------------------

## rooms_a / rooms_b: per storey, a list of [kind, width, data] from the wing's
## start. Side a (towards -v) also gets a stairwell at both ends. opts:
##   "ends": [true, true]   ground-floor doors at the start / end of the corridor
##   "title": String, "front": "a"/"b"   big name board on the roof edge
##   "cams": [storeys]      a corridor camera on these storeys
##   "no_stairs": true      single-storey wing
##   "join": [true, true]   no end wall at the start / end: the wing runs into the side of
##                          another wing, whose "link" room opens into this corridor
##   "blind_a"/"blind_b": [[u0, u1], ...]  no outside windows there (another wing is in the way)
## A "link" room is a short passage with a doorway through its outside wall on every storey,
## lined up with the corridor of a wing that joins there.
func wing(rect: Rect2, along_x: bool, floors: int, rooms_a: Array, rooms_b: Array, opts := {}) -> void:
	var W := {"rect": rect, "along_x": along_x, "floors": floors,
		"blind_a": opts.get("blind_a", []), "blind_b": opts.get("blind_b", [])}
	W.u0 = rect.position.x if along_x else rect.position.y
	W.u1 = rect.end.x if along_x else rect.end.y
	W.v0 = rect.position.y if along_x else rect.position.x
	W.v1 = rect.end.y if along_x else rect.end.x
	W.vm = (W.v0 + W.v1) / 2.0
	W.ca = W.vm - CORRIDOR / 2.0
	W.cb = W.vm + CORRIDOR / 2.0
	W.ua = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	W.va = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var stairs: bool = floors > 1 and not opts.get("no_stairs", false)
	_wings.append(W)
	c._map(rect, style.roof, "", -1, false, "building")  # roof footprint, under the floor plans
	c.levels = maxi(c.levels, floors)
	c.wall_color = style.wall
	c.frame_color = style.frame
	for k in floors:
		c._oy = k * FH
		var list_a: Array = rooms_a[mini(k, rooms_a.size() - 1)] if not rooms_a.is_empty() else []
		var list_b: Array = rooms_b[mini(k, rooms_b.size() - 1)] if not rooms_b.is_empty() else []
		# Corridor floor.
		c._tiles(_wrect(W, W.u0, W.u1, W.ca, W.cb), 1.2, style.hall[0], style.hall[1])
		c._map(_wrect(W, W.u0, W.u1, W.ca, W.cb), (style.hall[0] as Color).lightened(0.2), "", k, false, "hall")
		# Rooms, side a (stairwells at both ends) and side b.
		var u := float(W.u0)
		var end_a := float(W.u1)
		if stairs:
			_stair_room(W, k, u)
			u += STAIR_W
			end_a -= STAIR_W
		_place_rooms(W, k, list_a, u, end_a, "a")
		if stairs:
			_stair_room(W, k, end_a)
		_place_rooms(W, k, list_b, W.u0, W.u1, "b")
		_corridor(W, k, opts)
		_end_walls(W, k, opts)
		_slab(W, k, stairs)
	c._oy = 0.0
	_roof(W, opts)


func _wrect(W: Dictionary, u0: float, u1: float, v0: float, v1: float) -> Rect2:
	return Rect2(u0, v0, u1 - u0, v1 - v0) if W.along_x else Rect2(v0, u0, v1 - v0, u1 - u0)


func _place_rooms(W: Dictionary, k: int, list: Array, from: float, to: float, side: String) -> void:
	var u := from
	for i in list.size():
		var item: Array = list[i]
		var width: float = item[1]
		if i == list.size() - 1 or u + width > to:
			width = to - u  # the last room takes what's left
		if width < 2.0:
			break
		_room(W, k, side, u, u + width, str(item[0]), item[2] if item.size() > 2 else {})
		u += width
	if to - u >= 2.0:
		_room(W, k, side, u, to, "store", {})


## One room: walls on its corridor side, outside and start end, then its interior.
func _room(W: Dictionary, k: int, side: String, u0: float, u1: float, kind: String, data: Dictionary) -> void:
	var edge: float = W.ca if side == "a" else W.cb
	var outer: float = W.v0 if side == "a" else W.v1
	var f: Vector3 = -W.va if side == "a" else W.va
	var um := (u0 + u1) / 2.0
	var F := frame(W.ua * um + W.va * edge, f, W.ua, u1 - u0, absf(outer - edge))
	var along_x: bool = W.along_x
	var din: Color = style.dado_in
	var dhall: Color = style.dado_hall
	var dout: Color = style.dado_out
	# Corridor wall: a door near the far end, a wide opening for halls.
	var holes := []
	match kind:
		"lobby", "passage", "stairs", "link":
			holes = [[um - F.w / 2.0 + 0.6, um + F.w / 2.0 - 0.6, 0.0, 2.7]]
		"detention":
			holes = []
		_:
			holes = [[u1 - 2.2, u1 - 0.8, 0.0, 2.3]]
	if side == "a":
		c._wall(along_x, u0, u1, edge, holes, din, dhall)
	else:
		c._wall(along_x, u0, u1, edge, holes, dhall, din)
	if holes.size() == 1 and kind not in ["lobby", "passage", "stairs", "link"]:
		_door_leaf(F, kind)
	# Outside wall: windows (open ones on the ground floor are escape routes).
	var wins := []
	var blind := false
	for b: Array in W.get("blind_" + side, []):
		if u0 < float(b[1]) - 0.01 and u1 > float(b[0]) + 0.01:
			blind = true
	if kind == "link":
		wins = [[um - 1.3, um + 1.3, 0.0, 2.6]]
	elif blind:
		wins = []
	elif kind in ["lobby", "passage"] and k == 0:
		wins = [[um - 1.5, um + 1.5, 0.0, 2.7]]
	elif kind != "stairs":
		var n: int = maxi(1, int(F.w / 4.0))
		for j in n:
			var cu: float = u0 + (j + 0.5) * F.w / n
			if kind in ["class", "lab", "empty"] and absf(cu - um) < 2.3:
				continue  # blackboard
			wins.append([cu - 0.9, cu + 0.9, 1.0, 2.3])
	else:
		wins = [[um - 0.7, um + 0.7, 1.4, 2.3]]
	if side == "a":
		c._wall(along_x, u0, u1, outer, wins, dout, din)
	else:
		c._wall(along_x, u0, u1, outer, wins, din, dout)
	for w in wins:
		if w[2] > 0.5:
			c._window_frame(along_x, w[0], w[1], outer, w[2], w[3], kind == "detention" or k > 0)
	# Partition at the start of the room.
	var lo := minf(edge, outer)
	var hi := maxf(edge, outer)
	if absf(u0 - float(W.u0)) > 0.01:
		c._wall(not along_x, lo, hi, u0, [], din, din)
	c._map(frect(F), _room_color(kind, data), _room_label(kind, data), k, false, "stairs" if kind == "stairs" else "room")
	match kind:
		"class": _classroom(F, k, data)
		"lab": _classroom(F, k, data, true)
		"empty": _classroom(F, k, data)
		"staff": _staff_room(F)
		"library": _library(F)
		"canteen": _canteen(F)
		"washroom": _washroom(F)
		"detention": _detention(F)
		"lobby": _lobby(F, k, data)
		"computer": _computer_lab(F)
		"music": _music_room(F)
		"lecture": _lecture_hall(F)
		"office": _office(F, data)
		"art": _art_room(F)
		"passage": _passage(F)
		"link": _link(F)
		"stairs": pass
		_: _store_room(F)
	# Nav: both sides of the door.
	var door_l: float = F.w / 2.0 - 1.5 if kind not in ["lobby", "passage", "link"] else 0.0
	if kind not in ["detention", "stairs"]:
		c.nav_points.append(fp(F, door_l, 0, -0.9) + oy())
		c.nav_points.append(fp(F, door_l, 0, 1.0) + oy())
		if kind in ["class", "lab", "empty"]:
			for q: Vector2 in [Vector2(-0.75, 1.0), Vector2(-0.75, F.d - 2.2), Vector2(0, F.d - 0.8)]:
				c.nav_points.append(fp(F, q.x, 0, q.y) + oy())
		elif kind in ["lobby", "passage", "link"]:
			c.nav_points.append(fp(F, 0, 0, F.d / 2.0) + oy())


func _room_color(kind: String, data: Dictionary) -> Color:
	match kind:
		"class", "lab":
			return (P.CLASS_COLORS[int(data.get("idx", 0))] as Color).lerp(Color.WHITE, 0.35)
		"staff": return Color("c9d6e8")
		"library": return Color("e8d9bf")
		"canteen": return Color("ffd24a")
		"washroom": return Color("bfe3ea")
		"detention": return Color("c9a0a0")
		"lobby", "passage", "link": return Color("e7d2aa")
		"stairs": return P.STONE_DARK
	return Color("b9b0a4")


func _room_label(kind: String, data: Dictionary) -> String:
	match kind:
		"class", "lab":
			return ["Class A", "Class B", "Class C", "Lab"][int(data.get("idx", 0))]
		"staff": return "Staff room"
		"library": return "Library"
		"canteen": return "Canteen"
		"washroom": return "Washroom"
		"detention": return "Detention"
		"lobby": return str(data.get("name", "Entrance"))
		"lecture": return "Lecture hall"
		"computer": return "Computers"
		"office": return "Principal"
	return ""


func _door_leaf(F: Dictionary, kind: String) -> void:
	var col: Color = style.trim
	var l: float = F.w / 2.0 - 1.5
	fb(F, l - 0.75, 1.15, 0, 0.1, 2.3, WT + 0.08, P.WOOD_DARK, 0.0)
	fb(F, l + 0.75, 1.15, 0, 0.1, 2.3, WT + 0.08, P.WOOD_DARK, 0.0)
	fb(F, l, 2.34, 0, 1.6, 0.1, WT + 0.08, P.WOOD_DARK, 0.0)
	# The leaf swung open into the room, against the hinge wall.
	fb(F, l + 0.66, 1.12, WT / 2.0 + 0.66, 0.06, 2.2, 1.26, col.lightened(0.25), 0.02, true)


## Corridor furniture: ceiling lights, lockers, a notice board and a fire alarm, a camera.
func _corridor(W: Dictionary, k: int, opts: Dictionary) -> void:
	var length: float = W.u1 - W.u0
	var n: int = int(length / 6.0)
	for j in n:
		var u: float = W.u0 + (j + 0.5) * length / n
		var p: Vector3 = W.ua * u + W.va * W.vm
		box(p + Vector3(0, WH - 0.03, 0), Vector3(0.6, 0.06, 0.6), P.SHIRT, 0.0)
		kglow(p + Vector3(0, WH - 0.065, 0), Vector3(0.44, 0.02, 0.44))
		c.nav_points.append(p + oy())
	for end_u in [W.u0 + 1.0, W.u1 - 1.0]:
		c.nav_points.append(W.ua * float(end_u) + W.va * W.vm + oy())
	if k == 0 and _notices < 2 and opts.get("notice", true):
		_notices += 1
		var nu: float = W.u0 + length * (0.35 if _notices == 1 else 0.65)
		var F := frame(W.ua * nu + W.va * W.cb, W.va, W.ua, 2.0, 1.0)  # on the side b wall, facing the corridor
		fb(F, 0, 1.65, -WT / 2.0 - 0.03, 1.9, 1.15, 0.06, P.WOOD_DARK, 0.0)
		fb(F, 0, 1.65, -WT / 2.0 - 0.065, 1.75, 1.0, 0.02, Color("c9975c"), 0.02)
		for q in 6:
			var paper: Color = [P.PAPER, Color("ffe8a3"), Color("bfe3ff"), Color("ffc9d6")][rng.randi() % 4]
			fb(F, -0.6 + (q % 3) * 0.6, 1.9 - (q / 3) * 0.48, -WT / 2.0 - 0.08, 0.36, 0.4, 0.01, paper, 0.0)
		label("NOTICE BOARD", fp(F, 0, 2.38, -WT / 2.0 - 0.04), 32, Color("ffd24a"), fyaw(F))
		c._interactable("notice", fp(F, 0, 0, -1.0), "Stick a meme on the notice board")
	if k == 0 and _alarms < 2 and opts.get("alarm", true):
		_alarms += 1
		var au: float = W.u0 + length * (0.35 if _alarms == 1 else 0.65) + 2.4  # beside the notice board
		var F := frame(W.ua * au + W.va * W.cb, W.va, W.ua, 1.0, 1.0)  # on the side b wall, facing the corridor
		fb(F, 0, 1.5, -WT / 2.0 - 0.05, 0.3, 0.4, 0.1, Color("e0524f"), 0.0)
		fb(F, 0, 1.45, -WT / 2.0 - 0.11, 0.14, 0.08, 0.04, Color.WHITE, 0.0)
		label("FIRE", fp(F, 0, 1.64, -WT / 2.0 - 0.105), 18, Color.WHITE, fyaw(F), 0)
		c._interactable("alarm", fp(F, 0, 0, -1.0), "Pull the fire alarm", {"wall": fp(F, 0, 0, -WT / 2.0) + oy()})
	if k in opts.get("cams", []):
		var at: Vector3 = W.ua * (W.u0 + 0.6) + W.va * W.vm + Vector3(0, c._oy + WH - 0.3, 0)
		c.add_cctv(at, facing(Vector2(W.ua.x, W.ua.z)), 0.4, 0.4)


func _end_walls(W: Dictionary, k: int, opts: Dictionary) -> void:
	var ends: Array = opts.get("ends", [true, true])
	var join: Array = opts.get("join", [false, false])
	for i in 2:
		if join[i]:
			continue  # runs into another wing: that wing's wall (and link doorway) closes this end
		var u: float = W.u0 if i == 0 else W.u1
		var holes := []
		if k == 0 and ends[i]:
			holes = [[W.ca + 0.4, W.cb - 0.4, 0.0, 2.6]]
			var out: Vector3 = W.ua * (u + (-1.4 if i == 0 else 1.4)) + W.va * W.vm
			c.nav_points.append(out)
			c.nav_points.append(W.ua * (u + (-4.0 if i == 0 else 4.0)) + W.va * W.vm)
		else:
			holes = [[W.ca + 0.5, W.cb - 0.5, 1.0, 2.3]]
		c._wall(not W.along_x, W.v0, W.v1, u, holes, style.dado_out, style.dado_out)
		if holes[0][2] > 0.5:
			c._window_frame(not W.along_x, holes[0][0], holes[0][1], u, 1.0, 2.3, true)


## Ceiling / next floor over this storey (or the roof), with holes over the stairwells.
func _slab(W: Dictionary, k: int, stairs: bool) -> void:
	var rect: Rect2 = W.rect
	var holes := []
	if stairs and k < W.floors - 1:
		var hole_v0: float = W.v0
		var hole_v1: float = W.ca - 1.4
		holes.append(_wrect(W, W.u0 + WT / 2.0, W.u0 + STAIR_W - WT / 2.0, hole_v0, hole_v1))
		holes.append(_wrect(W, W.u1 - STAIR_W + WT / 2.0, W.u1 - WT / 2.0, hole_v0, hole_v1))
	for piece in c._subtract(rect.grow(0.12), holes):
		var m: Vector2 = piece.get_center()
		box(Vector3(m.x, (WH + FH) / 2.0, m.y), Vector3(piece.size.x, FH - WH, piece.size.y), style.ceiling, 0.0, true)
	# Trim band round the outside at this floor line.
	var m: Vector2 = rect.get_center()
	for s: float in [-1.0, 1.0]:
		box(Vector3(m.x, FH - 0.2, m.y + s * (rect.size.y / 2.0 + 0.1)), Vector3(rect.size.x + 0.4, 0.44, 0.1), style.trim, 0.0)
		box(Vector3(m.x + s * (rect.size.x / 2.0 + 0.1), FH - 0.2, m.y), Vector3(0.1, 0.44, rect.size.y + 0.4), style.trim, 0.0)


func _roof(W: Dictionary, opts: Dictionary) -> void:
	var rect: Rect2 = W.rect
	var top: float = W.floors * FH
	var m: Vector2 = rect.get_center()
	box(Vector3(m.x, top + 0.01, m.y), Vector3(rect.size.x - 0.2, 0.02, rect.size.y - 0.2), style.roof, 0.0)
	for s: float in [-1.0, 1.0]:
		box(Vector3(m.x, top + 0.3, m.y + s * (rect.size.y / 2.0 - 0.1)), Vector3(rect.size.x, 0.6, 0.24), style.wall, 0.0)
		box(Vector3(m.x + s * (rect.size.x / 2.0 - 0.1), top + 0.3, m.y), Vector3(0.24, 0.6, rect.size.y), style.wall, 0.0)
	box(Vector3(m.x + rect.size.x * 0.3, top + 0.8, m.y), Vector3(1.8, 1.6, 1.8), Color("2c2e36"), 0.0)
	for k in 3:
		box(Vector3(m.x - rect.size.x * 0.3 + k * 1.3, top + 0.35, m.y), Vector3(1.0, 0.7, 0.6), P.PAPER, 0.03)
	var title: String = opts.get("title", "")
	if title != "":
		var side: String = opts.get("front", "a")
		var v: float = (W.v0 - 0.15) if side == "a" else (W.v1 + 0.15)
		var um: float = (W.u0 + W.u1) / 2.0
		var at: Vector3 = W.ua * um + W.va * v + Vector3(0, top + 1.2, 0)
		var out: Vector3 = -W.va if side == "a" else W.va
		box(at, (W.ua * minf(W.u1 - W.u0 - 2.0, title.length() * 0.8 + 2.0)).abs() + Vector3(0, 1.4, 0) + (W.va * 0.2).abs(), Color("24315e"), 0.0)
		label(title, at + out * 0.14, 110, Color("ffd24a"), facing(Vector2(-out.x, -out.z)), 16)


## Switchback stairwell at side a, from corridor position u (its start).
func _stair_room(W: Dictionary, k: int, u: float) -> void:
	var F := frame(W.ua * (u + STAIR_W / 2.0) + W.va * W.ca, -W.va, W.ua, STAIR_W, W.ca - W.v0)
	_room(W, k, "a", u, u + STAIR_W, "stairs", {})
	var d_near := 1.4
	var d_far: float = F.d - 1.6
	var ll := -1.2
	var lr := 1.2
	var stone := P.STONE
	if k == 0:
		c._tiles(frect(F, WT / 2.0), 1.0, stone, P.STONE_DARK)
		fb(F, lr, 0.8, (d_near + F.d) / 2.0, 2.0, 1.6, F.d - d_near, P.WOOD_DARK, 0.02, true)  # cupboard under the flight
	else:
		var strip := frame(F.o, F.f, F.r, F.w, d_near)
		c._tiles(frect(strip, WT / 2.0), 1.0, stone, P.STONE_DARK)
	# Divider between the two flights, full storey height.
	fb(F, 0, WH / 2.0, (d_near + d_far) / 2.0, 0.14, WH, d_far - d_near, style.wall, 0.0, true)
	if k < W.floors - 1:
		var steps := 9
		for s in steps:
			var t: float = (s + 0.5) / steps
			var d1 := lerpf(d_near, d_far, t)
			var d2 := lerpf(d_far, d_near, t)
			var rise := FH / 2.0 / steps
			fb(F, ll, t * FH / 2.0 - 0.05 - rise / 2.0, d1, 2.0, 0.12 + rise, (d_far - d_near) / steps + 0.02, stone if s % 2 == 0 else P.STONE_DARK, 0.0)
			fb(F, lr, FH / 2.0 + t * FH / 2.0 - 0.05 - rise / 2.0, d2, 2.0, 0.12 + rise, (d_far - d_near) / steps + 0.02, stone if s % 2 == 0 else P.STONE_DARK, 0.0)
		c._ramp(fp(F, ll, 0, d_near) + oy(), fp(F, ll, FH / 2.0, d_far) + oy(), 2.0)
		c._ramp(fp(F, lr, FH / 2.0, d_far) + oy(), fp(F, lr, FH, d_near) + oy(), 2.0)
		fb(F, 0, FH / 2.0 - 0.1, (d_far + F.d) / 2.0, F.w - WT, 0.2, F.d - d_far, stone, 0.0, true)  # half landing
		# Handrails on the divider, following each flight.
		c._bar(fp(F, -0.15, 0.9, d_near), fp(F, -0.15, FH / 2.0 + 0.9, d_far), 0.07, P.METAL_DARK)
		c._bar(fp(F, 0.15, FH / 2.0 + 0.9, d_far), fp(F, 0.15, FH + 0.9, d_near), 0.07, P.METAL_DARK)
		c.nav_points.append(fp(F, ll, FH / 4.0, (d_near + d_far) / 2.0) + oy())
		c.nav_points.append(fp(F, ll, FH / 2.0, (d_far + F.d) / 2.0) + oy())
		c.nav_points.append(fp(F, lr, FH / 2.0, (d_far + F.d) / 2.0) + oy())
		c.nav_points.append(fp(F, lr, FH * 0.75, (d_near + d_far) / 2.0) + oy())
	else:
		# Top floor: a railing across the stairwell opening (nothing goes further up).
		fb(F, ll, 1.0, d_near, 2.0, 0.08, 0.08, P.METAL_DARK, 0.0)
		fb(F, ll, 0.5, d_near, 2.0, 0.05, 0.05, P.METAL_DARK, 0.0)
		for q in 5:
			fb(F, ll - 0.96 + q * 0.48, 0.5, d_near, 0.05, 1.0, 0.05, P.METAL_DARK, 0.0)
		c._collide(fp(F, ll, 0.5, d_near), fs(F, 2.0, 1.0, 0.1))
	c.nav_points.append(fp(F, ll, 0, 0.7) + oy())
	c.nav_points.append(fp(F, lr, 0, 0.7) + oy())


# --- Room interiors -------------------------------------------------------------------------------------

func _floor(F: Dictionary, a := Color(0, 0, 0, 0), b := Color(0, 0, 0, 0)) -> void:
	var ca: Color = style.floor[0] if a.a == 0.0 else a
	var cb: Color = style.floor[1] if b.a == 0.0 else b
	c._tiles(frect(F, WT / 2.0), 1.0, ca, cb)


func _classroom(F: Dictionary, k: int, data: Dictionary, lab := false) -> void:
	var W: float = F.w
	var D: float = F.d
	var idx: int = int(data.get("idx", -1))
	var accent: Color = P.CLASS_COLORS[idx] if idx >= 0 else Color("8a8f9c")
	_floor(F)
	var back := D - WT / 2.0
	fb(F, 0, 0.045, D - 0.85, W - 0.5, 0.07, 1.5, P.WOOD_DARK, 0.0)
	fb(F, 0, 1.75, back - 0.03, 3.9, 1.5, 0.06, P.WOOD_DARK, 0.0)
	fb(F, 0, 1.75, back - 0.07, 3.7, 1.3, 0.03, P.BOARD, 0.0)
	fb(F, 0, 1.02, back - 0.1, 3.7, 0.05, 0.12, P.WOOD_DARK, 0.0)
	var subject: String = _subjects[idx] if idx >= 0 else _npc_subjects[rng.randi() % _npc_subjects.size()]
	var chalk := label(subject, fp(F, 0, 1.85, back - 0.09), 30, P.CHALK, fyaw(F), 0)
	chalk.modulate.a = 0.9
	fb(F, 0, 2.78, back - 0.03, 0.46, 0.46, 0.05, Color("2a2a30"), 0.0)
	fb(F, 0, 2.78, back - 0.06, 0.38, 0.38, 0.02, Color.WHITE, 0.0)
	# Teacher's table with the register.
	fb(F, 1.6, 0.84, D - 1.1, 1.7, 0.06, 0.8, P.WOOD, 0.02)
	fb(F, 1.6, 0.53, D - 1.48, 1.7, 0.6, 0.04, P.WOOD_DARK, 0.0)
	c._collide(fp(F, 1.6, 0.48, D - 1.1), fs(F, 1.7, 0.8, 0.8))
	for sx: float in [-0.8, 0.8]:
		fb(F, 1.6 + sx, 0.41, D - 1.1, 0.06, 0.82, 0.76, P.WOOD_DARK, 0.0)
	fb(F, 1.6, 0.88, D - 1.05, 0.34, 0.04, 0.44, Color("2f5fb0"), 0.0)
	fb(F, 1.6, 0.54, D - 0.45, 0.5, 0.06, 0.5, P.WOOD, 0.0)
	for cl: float in [-0.21, 0.21]:
		for cd: float in [-0.21, 0.21]:
			fb(F, 1.6 + cl, 0.26, D - 0.45 + cd, 0.05, 0.52, 0.05, P.WOOD_DARK, 0.0)
	fb(F, 1.6, 0.84, D - 0.22, 0.5, 0.56, 0.05, P.WOOD, 0.0)
	# Benches: 2 columns x 3 rows, two per bench.
	for row in 3:
		for bl: float in [-2.4, 0.9]:
			var dd: float = 1.9 + row * 1.5
			_bench(F, bl, dd, lab)
			var s1 := fp(F, bl - 0.45, 0.02, dd - 0.62) + oy()
			var s2 := fp(F, bl + 0.45, 0.02, dd - 0.62) + oy()
			if idx >= 0:
				c.seats[idx].append(s1)
				c.seats[idx].append(s2)
			elif data.get("kids", false) and rng.randf() < 0.4:
				c.extra_seats.append(s1)
				c.extra_yaws.append(fyaw(F))
			if rng.randf() < 0.6:
				fb(F, bl + rng.randf_range(-0.6, 0.6), 0.815, dd, 0.22, 0.04, 0.3, P.BAGS[rng.randi() % P.BAGS.size()], 0.03)
			if lab:
				fb(F, bl - 0.5, 0.86, dd + 0.1, 0.07, 0.14, 0.07, Color("7fe0a0"), 0.0)
	# Side tube lights and fans.
	for s: float in [-1.0, 1.0]:
		var wl := s * (W / 2.0 - WT / 2.0 - 0.04)
		fb(F, wl, 2.6, D / 2.0, 0.06, 0.08, 1.3, P.SHIRT, 0.0)
		kglow(fp(F, wl - s * 0.05, 2.6, D / 2.0), fs(F, 0.05, 0.05, 1.18))
		c._fan(fp(F, s * 2.2, WH - 0.35, D / 2.0))
	klight(fp(F, 0, 2.7, D / 2.0), 1.1 if idx >= 0 else 0.7)
	# Sign above the door and lockers outside it.
	fb(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.03, 1.5, 0.4, 0.05, accent, 0.0)
	var name_txt: String = ["CLASS A", "CLASS B", "CLASS C", "LAB"][idx] if idx >= 0 else "ROOM %d%02d" % [k, rng.randi_range(1, 30)]
	label(name_txt, fp(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.06), 44, Color.WHITE, fyaw(F), 10)
	if idx >= 0:
		for q in 3:
			_locker(F, -1.6 + q * 0.8, accent)
		c._interactable("register", fp(F, 1.6, 0, D - 1.9), "Sign the attendance register", {"room": idx})
		var y: float = c._oy
		c.classes[idx] = {"rect": frect(F), "y": y, "yaw": fyaw(F), "side": F.r,
			"board": fp(F, 0, 0, D - 0.8) + oy(), "table": fp(F, 1.6, 0, D - 0.35) + oy(),
			"aisle": [fp(F, -0.75, 0, D - 2.2) + oy(), fp(F, -0.75, 0, 1.1) + oy()]}
	if lab:
		fb(F, -W / 2.0 + 1.2, 0.45, D - 0.7, 1.6, 0.9, 0.7, P.METAL, 0.0, true)
		var sk := fp(F, -W / 2.0 + 0.6, 0, D - 2.2)
		box(sk + Vector3(0, 0.6, 0), Vector3(0.05, 1.1, 0.05), P.METAL, 0.0)
		box(sk + Vector3(0, 1.35, 0), Vector3(0.36, 0.5, 0.12), Color("f1ecdc"), 0.0)
		box(sk + Vector3(0, 1.73, 0), Vector3(0.24, 0.26, 0.24), Color("f1ecdc"), 0.0)


func _bench(F: Dictionary, l: float, d: float, lab: bool) -> void:
	var top_col := Color("3a3d45") if lab else P.WOOD
	var frame_col := P.METAL if lab else P.WOOD_DARK
	fb(F, l, 0.76, d, 1.8, 0.06, 0.52, top_col, 0.03)
	fb(F, l, 0.5, d + 0.24, 1.8, 0.46, 0.04, frame_col, 0.0)
	for sx: float in [-0.87, 0.87]:
		fb(F, l + sx, 0.37, d, 0.06, 0.74, 0.5, frame_col, 0.0)
		fb(F, l + sx, 0.22, d - 0.62, 0.06, 0.44, 0.3, frame_col, 0.0)
	fb(F, l, 0.46, d - 0.62, 1.8, 0.05, 0.32, top_col, 0.03)
	fb(F, l, 0.78, d - 0.8, 1.8, 0.26, 0.04, top_col, 0.0)
	for sx: float in [-0.87, 0.87]:
		fb(F, l + sx, 0.62, d - 0.8, 0.06, 0.34, 0.04, frame_col, 0.0)
	c._collide(fp(F, l, 0.4, d), fs(F, 1.8, 0.8, 0.52))


## Locker against the corridor wall, facing the corridor: a hiding spot.
func _locker(F: Dictionary, l: float, accent: Color) -> void:
	var d: float = -WT / 2.0 - 0.3
	for part: Array in c.locker_parts(accent):
		var at: Vector3 = part[0]
		var size: Vector3 = part[1]
		fb(F, l + at.x, at.y, d + at.z, size.x, size.y, size.z, part[2], 0.0)
	c._collide(fp(F, l, 0.95, d), fs(F, 0.74, 1.9, 0.56))
	var eye: Vector3 = c.LOCKER_EYE
	c._add_hide(fp(F, l + eye.x, eye.y, d + eye.z), fp(F, l, 0.05, d - 0.85), fyaw(F) + PI, "Hide in locker")


func _staff_room(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F)
	fb(F, -0.5, 0.76, D / 2.0, 3.2, 0.06, 1.2, P.WOOD, 0.02)
	fb(F, -0.5, 0.38, D / 2.0, 3.0, 0.7, 1.0, P.WOOD_DARK, 0.0)
	c._collide(fp(F, -0.5, 0.4, D / 2.0), fs(F, 3.2, 0.8, 1.2))
	for cl: float in [-1.5, -0.5, 0.5]:
		for cd: float in [-0.95, 0.95]:
			fb(F, cl, 0.45, D / 2.0 + cd, 0.45, 0.06, 0.45, P.WOOD, 0.02)
			fb(F, cl, 0.22, D / 2.0 + cd, 0.38, 0.44, 0.38, P.WOOD_DARK, 0.0)
	fb(F, 0.6, 0.86, D / 2.0 - 0.2, 0.36, 0.14, 0.46, P.PAPER, 0.0)
	fb(F, 0.6, 0.94, D / 2.0 - 0.2, 0.3, 0.02, 0.4, Color("e0524f"), 0.0)
	c._interactable("pickup", fp(F, 0.6, 0, D / 2.0 - 1.2), "Steal the exam paper", {"item": "exam_paper"})
	fb(F, -W / 2.0 + 0.8, 0.95, D - 0.45, 0.9, 1.9, 0.55, P.WOOD_DARK, 0.02, true)
	c._interactable("pickup", fp(F, -W / 2.0 + 0.8, 0, D - 1.4), "Forge a medical note", {"item": "medical_note"})
	klight(fp(F, 0, 2.7, D / 2.0))
	# The office bell outside the door, in the corridor.
	fb(F, W / 2.0 - 3.0, 1.55, -WT / 2.0 - 0.03, 0.3, 0.3, 0.06, P.METAL_DARK, 0.0)
	fb(F, W / 2.0 - 3.0, 1.55, -WT / 2.0 - 0.09, 0.2, 0.2, 0.08, Color("ffd24a"), 0.0)
	c._interactable("bell", fp(F, W / 2.0 - 3.0, 0, -0.8), "Ring the staff room bell")
	fb(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.03, 1.8, 0.4, 0.05, Color("24315e"), 0.0)
	label("STAFF ROOM", fp(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.06), 40, Color("ffd24a"), fyaw(F), 8)
	var seat := fp(F, -1.5, 0, D / 2.0 - 0.95) + oy()
	c.staff_sit = {"pos": seat, "yaw": fyaw(F), "away": fyaw(F) + PI, "zone": frect(F)}


func _library(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F, Color("e8d9bf"), Color("c9b48f"))
	var rows: int = int((D - 3.0) / 1.8)
	for r in rows:
		var dd: float = 2.6 + r * 1.8
		var sw: float = W - 4.0
		fb(F, -0.8, 1.0, dd, sw, 2.0, 0.5, P.WOOD_DARK, 0.0, true)
		for shelf in 4:
			var x: float = -0.8 - sw / 2.0 + 0.1
			while x < -0.8 + sw / 2.0 - 0.2:
				var bw: float = rng.randf_range(0.08, 0.16)
				var bh: float = rng.randf_range(0.28, 0.4)
				var book: Color = P.BAGS[rng.randi() % P.BAGS.size()]
				for s: float in [-1.0, 1.0]:
					fb(F, x + bw / 2.0, 0.3 + shelf * 0.46 + bh / 2.0, dd + s * 0.26, bw - 0.01, bh, 0.04, book, 0.0)
				x += bw
	fb(F, W / 2.0 - 1.4, 0.4, 1.6, 1.4, 0.8, 0.6, P.WOOD, 0.02, true)
	fb(F, W / 2.0 - 1.4, 0.86, 1.6, 0.4, 0.1, 0.3, Color("4f86e0"), 0.0)
	c._interactable("return_book", fp(F, W / 2.0 - 1.4, 0, 0.8), "Return the overdue library book")
	label("SILENCE\nPLEASE", fp(F, 0, 2.1, D - WT / 2.0 - 0.04), 34, Color("e0524f"), fyaw(F), 0)
	fb(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.03, 1.6, 0.4, 0.05, Color("24315e"), 0.0)
	label("LIBRARY", fp(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.06), 40, Color("ffd24a"), fyaw(F), 8)
	klight(fp(F, 0, 2.7, D / 2.0))
	c.librarian_sit = {"pos": fp(F, W / 2.0 - 1.4, 0, 2.3) + oy(), "yaw": fyaw(F) + PI, "away": fyaw(F) + PI / 2.0, "zone": frect(F)}


func _canteen(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F, P.STONE, P.STONE_DARK)
	var counter_d := D - 2.4
	fb(F, -1.0, 0.5, counter_d, W - 3.0, 1.0, 0.6, P.WOOD, 0.02, true)
	fb(F, -1.0, 1.03, counter_d, W - 2.8, 0.06, 0.7, P.WOOD_DARK, 0.0)
	for q in 6:
		fb(F, -W / 2.0 + 2.0 + (q % 3) * 0.22, 1.12 + (q / 3) * 0.1, counter_d, 0.18, 0.1, 0.18, Color("e0a050"), 0.05)
	for q in 5:
		fb(F, -W / 2.0 + 3.5 + q * 0.18, 1.12, counter_d, 0.08, 0.12, 0.08, Color("c68a5c"), 0.0)
	fb(F, 0.5, 1.25, counter_d, 0.4, 0.4, 0.4, P.METAL, 0.0)
	fb(F, W / 2.0 - 0.8, 0.95, D - 0.6, 0.9, 1.9, 0.8, Color("e0524f"), 0.0, true)
	fb(F, -1.0, 1.9, D - WT / 2.0 - 0.05, 1.6, 1.0, 0.04, P.BOARD, 0.0)
	label("SAMOSA   15\nCHAI     10\nMAGGI    30", fp(F, -1.0, 1.9, D - WT / 2.0 - 0.08), 28, P.CHALK, fyaw(F), 0)
	fb(F, -1.0, 2.9, counter_d - 0.4, W - 2.0, 0.08, 1.6, Color("e0524f"), 0.0)
	label("PAPPU'S CANTEEN", fp(F, -1.0, 2.6, counter_d - 1.2), 60, Color("e0524f"), fyaw(F), 10)
	c._interactable("counter", fp(F, -1.0, 0, counter_d - 0.9), "Buy a samosa")
	c._interactable("pickup", fp(F, W / 2.0 - 1.6, 0, D - 1.2), "Grab the service door key", {"item": "canteen_key"})
	fb(F, W / 2.0 - 1.6, 1.07, D - WT / 2.0 - 0.02, 0.12, 0.08, 0.04, Color("ffd24a"), 0.0)  # key hook on the rail
	var zone_f := frame(fp(F, 0, 0, counter_d + 0.3), F.f, F.r, W, D - counter_d - 0.3)
	c.uncle_spot = {"pos": fp(F, -1.0, 0, counter_d + 0.9) + oy(), "yaw": fyaw(F) + PI, "away": fyaw(F), "zone": frect(zone_f)}
	# Tables and plastic chairs.
	var tables_d := counter_d - 2.6
	var t: float = 0
	while tables_d > 1.4:
		for tl in range(int(-W / 2.0) + 2, int(W / 2.0) - 1, 4):
			fb(F, tl, 0.74, tables_d, 1.4, 0.06, 0.9, P.SHIRT, 0.02)
			fb(F, tl, 0.36, tables_d, 0.12, 0.72, 0.12, P.METAL, 0.0)
			c._collide(fp(F, tl, 0.38, tables_d), fs(F, 1.4, 0.76, 0.9))
			for sd: float in [-0.72, 0.72]:
				var chair: Color = [Color("e0524f"), Color("3f86a8"), Color("48b06a")][rng.randi() % 3]
				fb(F, tl, 0.42, tables_d + sd, 0.4, 0.06, 0.4, chair, 0.02)
				fb(F, tl, 0.2, tables_d + sd, 0.34, 0.4, 0.34, chair.darkened(0.2), 0.0)
			c.extra_seats.append(fp(F, tl, 0, tables_d - 0.72) + oy())
			c.extra_yaws.append(fyaw(F))
			t += 1
		tables_d -= 2.6
	klight(fp(F, 0, 2.7, D / 2.0), 1.0, 10.0)
	fb(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.03, 1.6, 0.4, 0.05, Color("e0524f"), 0.0)
	label("CANTEEN", fp(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.06), 40, Color.WHITE, fyaw(F), 8)


func _washroom(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F, Color("dfeef2"), Color("bcd8e0"))
	var n: int = mini(4, int((W - 1.0) / 1.4))
	for q in n + 1:
		fb(F, -W / 2.0 + 0.6 + q * 1.4, 1.0, D - 0.9, 0.06, 2.0, 1.55, Color("8fc9d6"), 0.0, true)
	for q in n:
		var l: float = -W / 2.0 + 1.3 + q * 1.4
		fb(F, l, 0.25, D - 0.5, 0.4, 0.5, 0.45, Color.WHITE, 0.0)
		fb(F, l - 0.35, 1.0, D - 1.7, 0.6, 1.8, 0.05, Color("5f8fb8"), 0.0)
		c._add_hide(fp(F, l, 0.05, D - 0.9), fp(F, l, 0.05, D - 2.4), fyaw(F) + PI, "Hide in the stall")
		c._interactable("toilet", fp(F, l - 0.4, 0, D - 1.3), "Use the toilet")
		c._interactable("cistern", fp(F, l + 0.45, 0, D - 0.8), "Hide an item in the cistern")
		fb(F, l, 0.75, D - 0.3, 0.45, 0.4, 0.2, Color.WHITE, 0.0)  # cistern
	for q in 2:
		fb(F, W / 2.0 - 1.0 - q * 1.2, 0.8, WT / 2.0 + 0.22, 0.6, 0.12, 0.45, Color.WHITE, 0.0)
		fb(F, W / 2.0 - 1.0 - q * 1.2, 0.38, WT / 2.0 + 0.15, 0.16, 0.76, 0.16, Color.WHITE, 0.0)
	klight(fp(F, 0, 2.7, D / 2.0), 0.7, 6.0)
	fb(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.03, 1.8, 0.4, 0.05, Color("3f86a8"), 0.0)
	label("WASHROOM", fp(F, W / 2.0 - 1.5, 2.72, -WT / 2.0 - 0.06), 40, Color.WHITE, fyaw(F), 8)


func _detention(F: Dictionary) -> void:
	var D: float = F.d
	_floor(F)
	fb(F, 0, 0.23, D - 1.0, 2.4, 0.46, 0.45, P.WOOD, 0.02, true)
	fb(F, -F.w / 2.0 + 1.2, 0.4, D / 2.0, 0.9, 0.8, 1.6, P.WOOD_DARK, 0.02, true)
	fb(F, 0, 1.8, D - WT / 2.0 - 0.02, 1.6, 0.8, 0.02, P.PAPER, 0.0)
	label("DISCIPLINE IS\nTHE KEY TO SUCCESS", fp(F, 0, 1.8, D - WT / 2.0 - 0.04), 26, Color("e0524f"), fyaw(F), 0)
	klight(fp(F, 0, 2.7, D / 2.0), 0.8, 6.0)
	fb(F, 0, 2.72, -WT / 2.0 - 0.03, 3.2, 0.5, 0.05, Color("24315e"), 0.0)
	label("PRINCIPAL  ·  DETENTION", fp(F, 0, 2.72, -WT / 2.0 - 0.06), 40, Color("ffd24a"), fyaw(F), 8)
	c.detention_spot = fp(F, 0.8, 0.05, D / 2.0) + oy()
	c.detention_exit = fp(F, F.w / 2.0 - 1.5, 0.05, -1.0) + oy()
	fb(F, -F.w / 2.0 + 1.2, 0.82, D / 2.0 + 0.2, 0.5, 0.02, 0.7, P.PAPER, 0.0)
	c._interactable("essay", fp(F, -F.w / 2.0 + 2.2, 0, D / 2.0), "Write lines (get out sooner)")


func _lobby(F: Dictionary, k: int, data: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F, P.STONE, P.STONE_DARK)
	fb(F, -W / 2.0 + 1.6, 0.5, D / 2.0, 2.4, 1.0, 0.8, P.WOOD, 0.02, true)  # reception desk
	fb(F, -W / 2.0 + 1.6, 1.03, D / 2.0, 2.5, 0.06, 0.9, P.WOOD_DARK, 0.0)
	for s: float in [-1.0, 1.0]:
		c._planter(fp(F, s * (W / 2.0 - 0.9) + 0.63, 0, D - 0.9), 0.7)
	klight(fp(F, 0, 2.7, D / 2.0), 1.0)
	if data.get("gate", false) and k == 0:
		var yaw := fyaw(F) + PI  # the guard watches people coming from the corridor
		c.gate_post = fp(F, W / 2.0 - 1.2, 0, D - 1.6)
		c.gate_yaw = yaw
		c.gate_zones.append(frect(F).grow(1.5))
		c.nav_points.append(fp(F, 0, 0, D + 1.5))
		c.nav_points.append(fp(F, 0, 0, D + 5.0))
	var title: String = data.get("name", "")
	if title != "":
		label(title.to_upper(), fp(F, 0, 2.95, D + 0.2), 56, Color("ffd24a"), fyaw(F) + PI, 12)


## Link between wings: stone floor, a sill across the doorway into the other wing.
func _link(F: Dictionary) -> void:
	_floor(F, P.STONE, P.STONE_DARK)
	fb(F, 0, 0.0125, F.d, 2.6, 0.025, WT + 0.4, P.STONE_DARK, 0.0)
	c.nav_points.append(fp(F, 0, 0, F.d + 1.2) + oy())


func _passage(F: Dictionary) -> void:
	_floor(F, P.STONE, P.STONE_DARK)
	if c._oy < 0.1:
		c.nav_points.append(fp(F, 0, 0, F.d + 1.5))


func _computer_lab(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F)
	var rows: int = int((D - 1.5) / 1.8)
	for r in rows:
		var dd: float = 2.0 + r * 1.8
		fb(F, -0.8, 0.38, dd, W - 3.0, 0.76, 0.7, Color("dcdfe6"), 0.02, true)
		var n: int = int((W - 3.0) / 1.2)
		for q in n:
			var l: float = -0.8 - (W - 3.0) / 2.0 + 0.6 + q * 1.2
			fb(F, l, 0.99, dd + 0.1, 0.6, 0.45, 0.06, Color("26262e"), 0.0)
			kglow(fp(F, l, 0.99, dd + 0.065), fs(F, 0.52, 0.37, 0.01), Color("7fd0ea"))
	klight(fp(F, 0, 2.7, D / 2.0), 0.8)


func _music_room(F: Dictionary) -> void:
	var D: float = F.d
	_floor(F)
	c._piano(fp(F, -2.5, 0, D - 1.35), F.f)
	fb(F, 2.0, 0.3, D - 2.0, 0.6, 0.6, 0.6, Color("e0524f"), 0.0, true)
	fb(F, 2.9, 0.25, D - 1.7, 0.45, 0.5, 0.45, Color("ffd24a"), 0.0, true)
	fb(F, 2.45, 1.1, D - 1.7, 0.5, 0.04, 0.5, Color("ffd24a"), 0.0)
	fb(F, 2.45, 0.55, D - 1.7, 0.04, 1.1, 0.04, P.METAL, 0.0)
	c._interactable("piano", fp(F, -2.5, 0, D - 2.5), "Play the piano")
	c._interactable("drums", fp(F, 2.4, 0, D - 2.9), "Play the drums")
	klight(fp(F, 0, 2.7, D / 2.0), 0.7)


func _lecture_hall(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F, Color("8a2a3a").lightened(0.4), Color("8a2a3a").lightened(0.3))
	fb(F, 0, 0.15, D - 1.0, W - 1.0, 0.3, 1.8, P.WOOD_DARK, 0.0, true)
	fb(F, 0, 1.9, D - WT / 2.0 - 0.03, minf(W - 2.0, 6.0), 2.0, 0.04, Color.WHITE, 0.0)
	var cols: int = int((W - 2.0) / 1.2)
	for row in int((D - 3.0) / 1.2):
		for q in cols:
			var p := fp(F, -(cols - 1) * 0.6 + q * 1.2, 0, 1.3 + row * 1.2)
			box(p + Vector3(0, 0.44, 0), fs(F, 0.5, 0.06, 0.45), Color("e0524f"), 0.02)
			box(p + fs(F, 0, 0.72, 0) + (F.f as Vector3) * -0.2, fs(F, 0.5, 0.5, 0.06), Color("e0524f"), 0.02)
			box(p + Vector3(0, 0.22, 0), fs(F, 0.4, 0.44, 0.4), P.METAL_DARK, 0.0)
	klight(fp(F, 0, 2.7, D / 2.0), 1.0, 11.0)


func _office(F: Dictionary, data: Dictionary) -> void:
	var D: float = F.d
	_floor(F, Color("c9a0a0"), Color("b98a8a"))
	fb(F, 0, 0.4, D - 1.8, 2.4, 0.8, 1.0, P.WOOD_DARK, 0.02, true)
	fb(F, 0, 0.55, D - 0.9, 0.6, 1.1, 0.6, Color("26262e"), 0.0)
	fb(F, -F.w / 2.0 + 0.6, 1.53, D - 0.6, 0.06, 3.0, 0.06, P.METAL, 0.0)
	fb(F, -F.w / 2.0 + 1.0, 2.7, D - 0.6, 0.8, 0.5, 0.02, Color("24315e"), 0.0)
	klight(fp(F, 0, 2.7, D / 2.0), 0.8)


func _art_room(F: Dictionary) -> void:
	var D: float = F.d
	_floor(F)
	for q in 4:
		var l: float = -F.w / 2.0 + 1.5 + q * 2.2
		fb(F, l, 0.8, D / 2.0, 0.08, 1.6, 0.08, P.WOOD_DARK, 0.0)
		fb(F, l, 1.5, D / 2.0 - 0.06, 0.9, 0.7, 0.04, [Color("ff8ab0"), Color("7fd0ea"), Color("ffd24a"), Color("7fe0a0")][q], 0.0)
	klight(fp(F, 0, 2.7, D / 2.0), 0.7)


func _store_room(F: Dictionary) -> void:
	var D: float = F.d
	var W: float = F.w
	_floor(F)
	for q in int(W * D / 8.0):
		var l: float = rng.randf_range(-W / 2.0 + 0.8, W / 2.0 - 0.8)
		var d: float = rng.randf_range(1.8, D - 0.7)
		var s: float = rng.randf_range(0.6, 1.0)
		fb(F, l, s / 2.0, d, s, s, s, P.WOOD.darkened(rng.randf_range(0.0, 0.3)), 0.04, true)


# --- Outdoors ---------------------------------------------------------------------------------------------

## Basketball court (length along z) with two hoops and two balls.
func court(at: Vector2) -> void:
	var p := Vector3(at.x, 0, at.y)
	slab(Rect2(at.x - 7, at.y - 8, 14, 16), 0.03, 0.08, P.COURT)
	for z: float in [-7.2, 7.2]:
		box(p + Vector3(0, 0.045, z), Vector3(12.4, 0.01, 0.08), P.LINE, 0.0)
	box(p + Vector3(0, 0.045, 0), Vector3(12.4, 0.01, 0.08), P.LINE, 0.0)
	for x: float in [-6.2, 6.2]:
		box(p + Vector3(x, 0.045, 0), Vector3(0.08, 0.01, 14.4), P.LINE, 0.0)
	c.rims.clear()
	c.ball_spawns.clear()
	for end: Array in [[-7.6, 1.0], [7.6, -1.0]]:
		var z: float = end[0]
		var dir: float = end[1]
		box(p + Vector3(0, 1.6, z), Vector3(0.16, 3.2, 0.16), P.METAL_DARK, 0.0, true)
		box(p + Vector3(0, 3.1, z + dir * 0.35), Vector3(0.1, 0.1, 0.7), P.METAL_DARK, 0.0)
		box(p + Vector3(0, 3.2, z + dir * 0.7), Vector3(1.6, 1.0, 0.06), P.SHIRT, 0.0, true)
		box(p + Vector3(0, 3.05, z + dir * 0.74), Vector3(0.5, 0.4, 0.02), Color("e0524f"), 0.0)
		var ring := z + dir * 1.0
		var rim := Color("ff7a2a")
		box(p + Vector3(0, 2.8, ring - 0.24), Vector3(0.52, 0.035, 0.035), rim, 0.0, true)
		box(p + Vector3(0, 2.8, ring + 0.24), Vector3(0.52, 0.035, 0.035), rim, 0.0, true)
		box(p + Vector3(-0.24, 2.8, ring), Vector3(0.035, 0.035, 0.52), rim, 0.0, true)
		box(p + Vector3(0.24, 2.8, ring), Vector3(0.035, 0.035, 0.52), rim, 0.0, true)
		c.rims.append(p + Vector3(0, 2.8, ring))
	c.ball_spawns.append(p + Vector3(0, 0.6, -2.0))
	c.ball_spawns.append(p + Vector3(1.0, 0.6, 2.0))
	map_rect(Rect2(at.x - 7, at.y - 8, 14, 16), P.COURT, "Court", false, "court")
	nav_line(at + Vector2(-8, -9), at + Vector2(-8, 9), 6.0)


## The principal's shiny car (selfie quest), nose along x.
func principal_car(at: Vector2) -> void:
	car(at, true, Color.WHITE)
	label("PRINCIPAL", Vector3(at.x + 1.93, 0.45, at.y), 22, Color("24315e"), PI / 2, 0)
	c._interactable("car", Vector3(at.x, 0, at.y - 1.6), "Take a selfie with the principal's car")


## Locked grille across a doorway; the canteen key opens it for a while.
func service_door(at: Vector3, across_x: bool, width := 2.4) -> void:
	var gate := StaticBody3D.new()
	gate.name = "ServiceGate"
	gate.position = at
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 2.6, 0.3) if across_x else Vector3(0.3, 2.6, width)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.3
	gate.add_child(col)
	var v := preload("res://scripts/voxel.gd").new(5)
	for rail_y: float in [0.2, 1.2, 2.2]:
		v.box(Vector3(0, rail_y, 0), Vector3(width, 0.08, 0.08) if across_x else Vector3(0.08, 0.08, width), Color("2f6a4a"))
	for b in int(width / 0.2):
		var o := -width / 2.0 + 0.1 + b * 0.2
		v.box(Vector3(o, 1.2, 0) if across_x else Vector3(0, 1.2, o), Vector3(0.05, 2.2, 0.05), Color("2f6a4a"))
	v.box(Vector3(0, 1.2, 0), Vector3(0.14, 0.18, 0.14), Color("ffd24a"))
	gate.add_child(v.to_instance())
	c._root.add_child(gate)
	c.service_gate = gate
	c.service_gate_pos = at
	c._interactable("service_gate", at, "Unlock the staff door")


func assembly_point(at: Vector2) -> void:
	c.assembly = Vector3(at.x, 0, at.y)
	signpost(at + Vector2(3, 0), "ASSEMBLY POINT", 0.0, Color("48b06a"))
