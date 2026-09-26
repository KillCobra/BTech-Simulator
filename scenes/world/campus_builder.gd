extends RefCounted
## Builds the whole campus as a voxel diorama. Opaque geometry is merged into
## one mesh per 48 m chunk (so the camera culls what it can't see), plus glowing
## lamps, glass and clouds; collision lives in one StaticBody3D. Deterministic,
## so every peer builds the same map.
##
## The academic block (below) is the same on every map. Its compound wall and
## gates lead out into the wider university grounds, which the chosen map
## builds (scenes/world/maps/). Escaping means getting outside those grounds.
##
## Top view of the academic block (x right, z towards the blackboards):
##   z=24    back compound wall (broken section at x 10..13)
##   z=0..8  Class A | Class B | Class C | Lab     (doors on z=0)
##   z=-4..0 open verandah with pillars
##   z=-12   plaza, founder statue, flagpole        canteen (x 24..34)
##   z=-33   main gate + guard booth                parking (x -34..-22)

const Voxel := preload("res://scripts/voxel.gd")
const P := preload("res://scripts/palette.gd")
const Maps := preload("res://scenes/world/maps/maps.gd")

const UNI_NAME := "ROYAL ACADEMY OF UNNECESSARY SCIENCES"
const UNI_MOTTO := "EST. 1987  ·  KNOWLEDGE, EVENTUALLY"
const CHUNK := 48.0  # metres per mesh chunk

const ROOM_CENTERS := [-15.0, -5.0, 5.0, 15.0]  # classroom x centres (index = classroom id)
const ROOM_LEVELS := [0, 0, 1, 1]              # Class A, B downstairs; Class C, Lab upstairs
const FLOOR_H := 3.6                           # storey height (wall + slab)
# Non-class rooms: [x centre, level, kind, sign]
const OTHER_ROOMS := [
	[5.0, 0, "computer", "COMPUTER ROOM"], [15.0, 0, "seminar", "SEMINAR HALL"],
	[-15.0, 1, "music", "MUSIC ROOM"], [-5.0, 1, "store", "STORE ROOM"],
]
const STAIR_X := [-22.2, 22.2]
const ROOM_SUBJECTS := [
	"Thermodynamics\nAttendance: 9:05",
	"Engineering Maths\nUnit test on Friday!",
	"Data Structures\nNo phones in class",
	"Chemistry Lab\nWear your lab coat",
]
const H := 3.2    # wall height
const T := 0.24   # wall thickness
const DADO := 1.0 # painted band at the bottom of walls
const WALL_Z_FRONT := 0.0
const WALL_Z_BACK := 8.0

var seats := [[], [], [], []]  # per classroom, spawn positions
var fans: Array[Node3D] = []
var clouds: Node3D
var lockers: Array[Dictionary] = []  # hiding spots: {"pos", "out", "yaw", "label"}
var nav_points := PackedVector3Array()
var interactables: Array[Dictionary] = []  # {"kind", "pos", "label", ...}
var cctv: Array[Dictionary] = []  # {"node", "pos", "base_yaw", "sweep", "speed"}
var service_gate: Node3D
var extra_seats: Array[Vector3] = []  # canteen/court seats for NPC students
var map_shapes: Array[Dictionary] = []  # for the minimap: {"rect", "color", "label", "level"}

# Filled in by the map (scenes/world/maps/).
var map_id := 0
var bounds := Rect2(-40, -33, 80, 57)  # the university grounds: leaving them = escaped
var world_rect := Rect2(-80, -80, 160, 160)  # playable area (invisible walls beyond)
var exits: Array[Dictionary] = []  # {"at": Vector2, "name": String} shown on the maps
var gate_zones: Array[Rect2] = []  # guarded gates: hall passes don't cover these
var posts: Array[Dictionary] = []  # extra gate guards: {"id", "name", "pos", "yaw", "zone"}
var patrols: Array[Dictionary] = []  # {"id", "name", "loop", "walk", "chase", "view"}
var walkers: Array = []  # loops for strolling NPC students
var escape_rects: Array[Rect2] = []  # also count as out (e.g. a ferry deck inside the bounds)
var waters: Array[Dictionary] = []  # {"rect", "bank", "side"}: fall in and you're washed back to the bank
var bridges: Array[Rect2] = []  # decks over water (staff may walk here)
var goal_text := ""  # HUD objective
var map_outside := Color("4a7f41")  # map colour beyond the playable area
var win_text := ""  # banner line when you get out

const NPC_WALL_LAYER := 8  # only staff collide with this: keeps them out of the water

const DETENTION_SPOT := Vector3(-32.0, 0.05, 11.0)
const GATE_POST := Vector3(4.6, 0, -29.3)
const GATE_ZONE := Rect2(-6, -36, 12, 10)  # near the main gate: passes don't cover this
const ASSEMBLY := Vector3(0, 0, -12)       # fire-alarm assembly point
const STAFFROOM_RECT := Rect2(25, -3, 6, 10)
const LIBRARY_RECT := Rect2(31, -3, 6, 10)
const CANTEEN_INSIDE := Rect2(24.1, -19.4, 9.8, 5.4)
const STAFF_SIT := Vector3(26.3, 0, 3.0)
const LIBRARIAN_SIT := Vector3(36.2, 0, 0.5)
const UNCLE_SPOT := Vector3(28.5, 0, -18.9)
const SERVICE_GATE_POS := Vector3(40, 0, -16.2)
const RIMS := [Vector3(-31, 2.8, -12.6), Vector3(-31, 2.8, 0.6)]  # basket centres
const BALL_SPAWNS := [Vector3(-31, 0.6, -8.0), Vector3(-30, 0.6, -4.0)]
const PATROL_LOOP := [
	Vector3(-18, 0, -2), Vector3(18, 0, -2), Vector3(24.3, 0, 4), Vector3(15, 0, 11),
	Vector3(-15, 0, 11), Vector3(-24.3, 0, 4), Vector3(-13, 0, -8), Vector3(0, 0, -14), Vector3(13, 0, -8),
]
const PROCTOR_LOOP := [
	Vector3(-18, 3.6, -2), Vector3(-6, 3.6, -2), Vector3(6, 3.6, -2), Vector3(18, 3.6, -2),
]
const PREFECT_LOOP := [
	Vector3(-13, 0, -8), Vector3(-22, 0, -6), Vector3(-31, 0, -6), Vector3(-28, 0, -21),
	Vector3(-12, 0, -20), Vector3(0, 0, -19), Vector3(-2, 0, -11),
]
const VP_LOOP := [
	Vector3(16, 0, -6), Vector3(23, 0, -6), Vector3(24.3, 0, 4), Vector3(23, 0, 11), Vector3(5, 0, 11),
	Vector3(11.5, 0, 20), Vector3(15, 0, 11), Vector3(23, 0, 11), Vector3(24, 0, -12), Vector3(21, 0, -10),
]


# --- The academic layout: what the rules need to know about the buildings -------------------------
# Filled by the classic block (_classic_layout) or by the map's own complex.

var levels := 2  # storeys the minimap can show
var classes: Array[Dictionary] = []  # per classroom: {"rect", "y", "yaw", "side", "board", "table", "aisle"}
var academic_rect := Rect2(-42, -35, 84, 61)  # no trees or clutter here
var detention_spot := Vector3.ZERO
var detention_exit := Vector3.ZERO  # where you're let out (walk back to class from here)
var gate_post := Vector3.ZERO
var gate_yaw := PI
var assembly := Vector3.ZERO
var staff_sit := {}     # {"pos", "yaw", "away", "zone"}
var librarian_sit := {}
var uncle_spot := {}
var service_gate_pos := Vector3.ZERO
var rims: Array = []
var ball_spawns: Array = []
var staff_loops := {}   # "peon", "prefect", "proctor", "vp" -> Array of Vector3
var core_walks: Array = []  # strolling students inside the academic area
var extra_yaws: Array = []  # facing for each of extra_seats


func level_of(pos: Vector3) -> int:
	return clampi(floori((pos.y + 1.0) / FLOOR_H), 0, levels - 1)


## Which player classroom a position is in, or -1.
func room_of(pos: Vector3) -> int:
	for i in classes.size():
		var c: Dictionary = classes[i]
		if (c.rect as Rect2).has_point(Vector2(pos.x, pos.z)) and absf(pos.y - float(c.y)) < 1.8:
			return i
	return -1


## Rules data for the classic academic block (the First Day map).
func _classic_layout() -> void:
	levels = 2
	for i in ROOM_CENTERS.size():
		var cx: float = ROOM_CENTERS[i]
		var y: float = ROOM_LEVELS[i] * FLOOR_H
		classes.append({"rect": Rect2(cx - 5.0, 0.0, 10.0, 8.0), "y": y, "yaw": PI, "side": Vector3(1, 0, 0),
			"board": Vector3(cx, y, 7.2), "table": Vector3(cx + 1.6, y, 7.65),
			"aisle": [Vector3(cx - 0.75, y, 5.8), Vector3(cx - 0.75, y, 1.1)]})
	detention_spot = DETENTION_SPOT
	detention_exit = Vector3(-30.2, 0.05, 7.2)
	gate_post = GATE_POST
	gate_yaw = PI
	gate_zones.append(GATE_ZONE)
	assembly = ASSEMBLY
	staff_sit = {"pos": STAFF_SIT, "yaw": PI / 2, "away": -PI / 2, "zone": STAFFROOM_RECT}
	librarian_sit = {"pos": LIBRARIAN_SIT, "yaw": PI / 2, "away": 0.0, "zone": LIBRARY_RECT}
	uncle_spot = {"pos": UNCLE_SPOT, "yaw": 0.0, "away": PI, "zone": CANTEEN_INSIDE}
	service_gate_pos = SERVICE_GATE_POS
	rims = RIMS.duplicate()
	ball_spawns = BALL_SPAWNS.duplicate()
	staff_loops = {"peon": PATROL_LOOP, "prefect": PREFECT_LOOP, "proctor": PROCTOR_LOOP, "vp": VP_LOOP}
	core_walks = [
		[Vector3(-18, 0, -2), Vector3(18, 0, -2)],
		[Vector3(-13, 0, -8), Vector3(13, 0, -8), Vector3(0, 0, -19)],
		[Vector3(14, 0, -10), Vector3(27, 0, -21.5)],
		[Vector3(-34, 0, -10), Vector3(-28, 0, -3), Vector3(-33, 0, -1), Vector3(-29, 0, -11)],  # court
		[Vector3(-6, 3.6, -2), Vector3(14, 3.6, -2)],  # first-floor balcony
	]
	for k in extra_seats.size():
		extra_yaws.append(PI)


var _root: Node3D
var _chunks := {}  # Vector2i -> Voxel
var _glow: Voxel
var _glass: Voxel
var _body: StaticBody3D
var _rng := RandomNumberGenerator.new()
var _paved: Array[Rect2] = []
var _blocked: Array[Rect2] = []  # buildings, water: no trees or grass here
var _oy := 0.0  # height offset of the storey being built
var wall_color := P.WALL  # buildings can restyle walls and window frames
var frame_color := Color("3f86a8")


func build(root: Node3D, which := 0) -> void:
	_root = root
	_rng.seed = 20260924
	_glow = Voxel.new(12)
	_glass = Voxel.new(13)
	_glow.world_space = true
	_glass.world_space = true
	_body = StaticBody3D.new()
	_body.name = "CampusCollision"
	root.add_child(_body)
	map_id = clampi(which, 0, Maps.LIST.size() - 1)
	var grounds: RefCounted = Maps.builder(map_id)
	grounds.plan(self)  # sets bounds/world_rect, reserves roads, buildings and water
	_ground_collision()
	_world_edges()
	if grounds.classic:
		_build_classic()
	grounds.build(self)  # the map's own academic complex (if any) and grounds
	_seat_interactables()
	_outer_ground(grounds.classic)
	_clouds()
	_commit()


## Players' seats (0-7 in each classroom) are chairs: [E] Sit down.
func _seat_interactables() -> void:
	for room in mini(seats.size(), classes.size()):
		var list: Array = seats[room]
		for k in mini(8, list.size()):
			interactables.append({"kind": "seat", "pos": list[k], "label": "Sit down", "room": room, "seat": k,
				"yaw": float(classes[room].yaw)})


## The original academic block: two storeys, four classrooms, canteen, court.
func _build_classic() -> void:
	_paved.append_array([
		Rect2(-20.4, -4.4, 40.8, 12.8),  # building
		Rect2(-12, -12, 24, 7.6),         # plaza
		Rect2(-2, -33, 4, 21),            # gate path
		Rect2(12, -11, 10, 2),            # path to canteen
		Rect2(22, -27, 14, 14),           # canteen patio
		Rect2(-34, -31, 12, 8),           # parking
		Rect2(-38, -14, 14, 16),          # basketball court
		Rect2(-36, 8, 8, 6),              # detention office
		Rect2(24.8, -3.2, 12.4, 10.4),    # staff block
		Rect2(23.8, 11.8, 6.4, 5.4),      # washrooms
		Rect2(-23.4, -4.6, 3.2, 13.4),    # west stairs
		Rect2(20.2, -4.6, 3.2, 13.4),     # east stairs
	])

	_map_outdoors()
	_ground()
	_main_building()
	_boundary_and_gate()
	_canteen()
	_parking()
	_court()
	_plaza()
	_detention_block()
	_staff_block()
	_washrooms()
	_service_gate()
	_cctv_and_alarms()
	_nav_outdoors()
	_trees_and_bushes()
	_grass_details()
	_classic_layout()


# --- Output ------------------------------------------------------------------------

func _commit() -> void:
	var keys := _chunks.keys()
	keys.sort()
	for key in keys:
		var solid: MeshInstance3D = (_chunks[key] as Voxel).to_instance()
		solid.name = "Blocks_%d_%d" % [key.x, key.y]
		_root.add_child(solid)

	var glow_mat := StandardMaterial3D.new()
	glow_mat.vertex_color_use_as_albedo = true
	glow_mat.vertex_color_is_srgb = true
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.95, 0.82)
	glow_mat.emission_energy_multiplier = 2.2
	var glow := _glow.to_instance(glow_mat)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(glow)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.75, 0.92, 1.0, 0.35)
	glass_mat.roughness = 0.05
	glass_mat.metallic_specular = 0.9
	var glass := _glass.to_instance(glass_mat)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(glass)


## Everything built through these helpers is lifted by _oy, the current storey's height.
func _off(p: Vector3) -> Vector3:
	return p + Vector3(0, _oy, 0)


## Adds a box to the mesh chunk its centre falls in (no collision, no storey offset).
func _vbox(center: Vector3, size: Vector3, color: Color, jitter := 0.0, skip_bottom := false) -> void:
	var key := Vector2i(floori(center.x / CHUNK), floori(center.z / CHUNK))
	var v: Voxel = _chunks.get(key)
	if v == null:
		v = Voxel.new(1000 + key.x * 97 + key.y)
		v.world_space = true
		_chunks[key] = v
	v.box(center, size, color, jitter, skip_bottom)


func _block(center: Vector3, size: Vector3, color: Color, jitter := 0.02, solid := false) -> void:
	_vbox(_off(center), size, color, jitter)
	if solid:
		_collide(center, size)


## A walkable slope from `from` to `to` (surface points), `width` wide.
func _ramp(from: Vector3, to: Vector3, width: float, thick := 0.3) -> void:
	var fwd := (to - from).normalized()
	var x_axis := Vector3.UP.cross(fwd).normalized()
	var y_axis := fwd.cross(x_axis)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thick, from.distance_to(to) + 0.3)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(Basis(x_axis, y_axis, fwd), (from + to) / 2.0 - y_axis * thick / 2.0)
	_body.add_child(col)


func _collide(center: Vector3, size: Vector3, tilt_x := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = _off(center)
	col.rotation.x = tilt_x
	_body.add_child(col)


## Level railing from a to b (floor points, same y, along x or z): handrail,
## middle rail and posts, with a solid 1 m collision wall.
func _railing(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) / 2.0
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var length := a.distance_to(b)
	var bar := func(y: float, t: float) -> Vector3:
		return Vector3(length, t, t) if along_x else Vector3(t, t, length)
	_block(Vector3(mid.x, a.y + 0.95, mid.z), bar.call(0.95, 0.09), P.METAL_DARK, 0.0)
	_block(Vector3(mid.x, a.y + 0.45, mid.z), bar.call(0.45, 0.05), P.METAL_DARK, 0.0)
	var posts := maxi(1, ceili(length / 0.8))
	for k in posts + 1:
		var p := a.lerp(b, float(k) / posts)
		_block(Vector3(p.x, a.y + 0.475, p.z), Vector3(0.06, 0.95, 0.06), P.METAL_DARK, 0.0)
	_collide(Vector3(mid.x, a.y + 0.5, mid.z), Vector3(length, 1.0, 0.12) if along_x else Vector3(0.12, 1.0, length))


## A straight bar from a to b at any angle (stair handrails), square in section.
func _bar(a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	var v := Voxel.new()
	v.box(Vector3.ZERO, Vector3(thick, thick, a.distance_to(b)), color)
	var bar := v.to_instance()
	bar.position = _off((a + b) / 2.0)
	bar.basis = Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	_root.add_child(bar)


## Records a rectangle (x/z plane) for the minimap. level -1 = every floor.
## kind: area, water, path, road, court, building, hall, room, stairs, wall (guessed if empty).
func _map(rect: Rect2, color: Color, label := "", level := -1, always_label := false, kind := "") -> void:
	if kind == "":
		if level >= 0:
			kind = "room"
		elif color == P.ASPHALT:
			kind = "road"
		elif color == P.BRICK:
			kind = "wall"
		elif color == P.COURT:
			kind = "court"
		else:
			kind = "area"
	map_shapes.append({"rect": rect, "color": color, "label": label, "level": level, "force": always_label, "kind": kind})


func _label(text: String, pos: Vector3, font_size: int, color: Color, yaw := 0.0, outline := 8) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = _off(pos)
	label.rotation.y = yaw
	label.font_size = font_size
	label.modulate = color
	label.outline_size = outline
	label.outline_modulate = Color(0.1, 0.08, 0.12)
	label.double_sided = false
	_root.add_child(label)
	return label


func _is_paved(x: float, z: float) -> bool:
	for r in _paved:
		if r.has_point(Vector2(x, z)):
			return true
	for r in _blocked:
		if r.has_point(Vector2(x, z)):
			return true
	return false


## True once a player is outside the university grounds.
func escaped(pos: Vector3) -> bool:
	var at := Vector2(pos.x, pos.z)
	if not bounds.has_point(at):
		return true
	for r in escape_rects:
		if r.has_point(at):
			return true
	return false


## Where someone who fell in at pos gets washed up: the fixed bank, or (for
## long rivers) the nearest point on the `side` edge.
func bank_for(w: Dictionary, pos: Vector3) -> Vector3:
	var side: Vector2 = w.get("side", Vector2.ZERO)
	if side == Vector2.ZERO:
		return w.bank
	var r: Rect2 = w.rect
	var x := pos.x if side.x == 0 else (r.end.x + 2.0 if side.x > 0 else r.position.x - 2.0)
	var z := pos.z if side.y == 0 else (r.end.y + 2.0 if side.y > 0 else r.position.y - 2.0)
	return Vector3(x, 0, z)


## The water a (sunk) position is in, or {}.
func water_at(pos: Vector3) -> Dictionary:
	for w in waters:
		if (w.rect as Rect2).has_point(Vector2(pos.x, pos.z)):
			return w
	return {}


## Solid ground everywhere except the water, which is a 2 m deep pit. Staff get
## invisible walls around the water (bridges excepted) so they never fall in.
func _ground_collision() -> void:
	var holes: Array = []
	for w in waters:
		holes.append(w.rect)
	for r in _subtract(world_rect.grow(10.0), holes):
		_collide(Vector3(r.get_center().x, -0.5, r.get_center().y), Vector3(r.size.x, 1, r.size.y))
	var npc_body := StaticBody3D.new()
	npc_body.name = "StaffOnlyWalls"
	npc_body.collision_layer = NPC_WALL_LAYER
	npc_body.collision_mask = 0
	_root.add_child(npc_body)
	for w in waters:
		var r: Rect2 = w.rect
		_collide(Vector3(r.get_center().x, -2.5, r.get_center().y), Vector3(r.size.x, 1, r.size.y))
		for part in _subtract(r, bridges):
			var shape := BoxShape3D.new()
			shape.size = Vector3(part.size.x, 3.0, part.size.y)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = Vector3(part.get_center().x, 0.5, part.get_center().y)
			npc_body.add_child(col)


## base minus the holes, as a few non-overlapping rectangles.
static func _subtract(base: Rect2, holes: Array) -> Array[Rect2]:
	var xs := [base.position.x, base.end.x]
	var zs := [base.position.y, base.end.y]
	for h: Rect2 in holes:
		var c := h.intersection(base)
		if c.has_area():
			xs.append_array([c.position.x, c.end.x])
			zs.append_array([c.position.y, c.end.y])
	xs.sort()
	zs.sort()
	var out: Array[Rect2] = []
	for j in zs.size() - 1:
		if zs[j + 1] - zs[j] < 0.001:
			continue
		var run_start := -INF
		for i in xs.size():
			var solid := false
			if i < xs.size() - 1 and xs[i + 1] - xs[i] > 0.001:
				solid = true
				var mid := Vector2((xs[i] + xs[i + 1]) / 2.0, (zs[j] + zs[j + 1]) / 2.0)
				for h: Rect2 in holes:
					if h.has_point(mid):
						solid = false
			elif i < xs.size() - 1:
				continue  # zero-width column: keep the current run going
			if solid and run_start == -INF:
				run_start = xs[i]
			elif not solid and run_start != -INF:
				out.append(Rect2(run_start, zs[j], xs[i] - run_start, zs[j + 1] - zs[j]))
				run_start = -INF
	return out


## Invisible walls around the playable area.
func _world_edges() -> void:
	var r := world_rect
	var c := r.get_center()
	_collide(Vector3(c.x, 5, r.position.y - 0.5), Vector3(r.size.x + 2, 12, 1))
	_collide(Vector3(c.x, 5, r.end.y + 0.5), Vector3(r.size.x + 2, 12, 1))
	_collide(Vector3(r.position.x - 0.5, 5, c.y), Vector3(1, 12, r.size.y + 2))
	_collide(Vector3(r.end.x + 0.5, 5, c.y), Vector3(1, 12, r.size.y + 2))


## Coarse grass beyond the academic block, out to the edge of the world.
func _outer_ground(skip_core: bool) -> void:
	var tile := 6.0
	var nx := ceili(world_rect.size.x / tile)
	var nz := ceili(world_rect.size.y / tile)
	for ix in nx:
		for iz in nz:
			var x := world_rect.position.x + (ix + 0.5) * tile
			var z := world_rect.position.y + (iz + 0.5) * tile
			if skip_core and absf(x) < 70.0 + tile / 2.0 and absf(z) < 70.0 + tile / 2.0:
				continue  # the fine 2 m grass of the academic block
			if _is_paved(x, z):
				continue
			var top := -_rng.randf() * 0.05
			_vbox(Vector3(x, top - 0.1, z), Vector3(tile, 0.2, tile), P.GRASS.lerp(P.GRASS_DARK, _rng.randf()), 0.02)


## Checkerboard of tiles with thin darker grout lines.
func _tiles(rect: Rect2, tile: float, a: Color, b: Color, top := 0.02) -> void:
	var nx := maxi(1, roundi(rect.size.x / tile))
	var nz := maxi(1, roundi(rect.size.y / tile))
	var tw := rect.size.x / nx
	var td := rect.size.y / nz
	var mid := rect.get_center()
	_vbox(_off(Vector3(mid.x, top - 0.065, mid.y)), Vector3(rect.size.x, 0.1, rect.size.y), a.darkened(0.25), 0.0, true)
	for ix in nx:
		for iz in nz:
			var c := a if (ix + iz) % 2 == 0 else b
			var cx := rect.position.x + (ix + 0.5) * tw
			var cz := rect.position.y + (iz + 0.5) * td
			_vbox(_off(Vector3(cx, top - 0.04, cz)), Vector3(tw - 0.04, 0.08, td - 0.04), c, 0.018, true)


# --- Ground ---------------------------------------------------------------------------

func _ground() -> void:
	for gx in range(-35, 35):
		for gz in range(-35, 35):
			var x := gx * 2.0 + 1.0
			var z := gz * 2.0 + 1.0
			if _is_paved(x, z):
				continue
			var top := -_rng.randf() * 0.05
			var c := P.GRASS.lerp(P.GRASS_DARK, _rng.randf())
			_vbox(Vector3(x, top - 0.1, z), Vector3(2, 0.2, 2), c, 0.02, true)


func _grass_details() -> void:
	var placed := 0
	while placed < 700:
		var x := _rng.randf_range(-40, 40)
		var z := _rng.randf_range(-33, 24)
		if _is_paved(x, z) or _is_paved(x + 0.5, z) or _is_paved(x, z + 0.5):
			continue
		placed += 1
		if _rng.randf() < 0.75:
			var shade := P.GRASS.lightened(_rng.randf_range(0.0, 0.15))
			for i in 3:
				var h := _rng.randf_range(0.12, 0.24)
				_vbox(Vector3(x + (i - 1) * 0.06, h / 2.0 - 0.02, z + _rng.randf_range(-0.05, 0.05)), Vector3(0.045, h, 0.045), shade)
		else:
			_vbox(Vector3(x, 0.07, z), Vector3(0.03, 0.16, 0.03), P.GRASS_DARK)
			_vbox(Vector3(x, 0.17, z), Vector3(0.1, 0.07, 0.1), P.FLOWERS[_rng.randi() % P.FLOWERS.size()])
			_vbox(Vector3(x, 0.19, z), Vector3(0.04, 0.04, 0.04), Color("ffe066"))


# --- Main building --------------------------------------------------------------------

func _main_building() -> void:
	_map(Rect2(-20.4, -4.4, 40.8, 12.8), Color("e7d2aa"), "", -1, false, "building")
	for level in 2:
		_oy = level * FLOOR_H
		for cx in ROOM_CENTERS:
			_tiles(Rect2(cx - 5 + T / 2, T / 2, 10 - T, 8 - T), 1.0, P.FLOOR_A, P.FLOOR_B)
		if level == 0:
			_tiles(Rect2(-20.4, -4.4, 40.8, 4.28), 1.0, P.VERANDAH_A, P.VERANDAH_B)
		else:
			_tiles(Rect2(-20.4, -4.4, 40.8, 4.28), 1.0, P.STONE, P.STONE_DARK)
		_map(Rect2(-20.4, -4.4, 40.8, 4.4), P.VERANDAH_A if level == 0 else P.STONE_DARK, "", level)

		for i in ROOM_CENTERS.size():
			if ROOM_LEVELS[i] == level:
				_classroom(i, ROOM_CENTERS[i])
		for r in OTHER_ROOMS:
			if r[1] == level:
				_other_room(r[0], r[2], r[3])
		for x in [-20.0, -10.0, 0.0, 10.0, 20.0]:
			var outer_neg: Variant = P.DADO_OUTSIDE if x == -20.0 else P.DADO_INSIDE
			var outer_pos: Variant = P.DADO_OUTSIDE if x == 20.0 else P.DADO_INSIDE
			_wall(false, WALL_Z_FRONT, WALL_Z_BACK, x, [], outer_neg, outer_pos)

		# Verandah pillars.
		for i in 11:
			var x := -20.0 + i * 4.0
			_block(Vector3(x, H / 2.0, -4.1), Vector3(0.45, H, 0.45), P.WALL, 0.0, true)
			_block(Vector3(x, 0.18, -4.1), Vector3(0.58, 0.36, 0.58), P.TRIM)
			_block(Vector3(x, H - 0.12, -4.1), Vector3(0.56, 0.24, 0.56), P.TRIM)
		if level == 1:
			# Balcony railing between the pillars.
			_block(Vector3(0, 0.5, -4.25), Vector3(40.6, 1.0, 0.16), P.WALL, 0.0, true)
			_block(Vector3(0, 1.03, -4.25), Vector3(40.8, 0.07, 0.24), P.TRIM, 0.0)
			for k in 5:
				_block(Vector3(-16.0 + k * 8.0, H - 0.03, -2.2), Vector3(0.6, 0.06, 0.6), P.SHIRT, 0.0)
				_glow.box(_off(Vector3(-16.0 + k * 8.0, H - 0.065, -2.2)), Vector3(0.44, 0.02, 0.44), P.GLOW)
			for k in 9:
				nav_points.append(_off(Vector3(-18 + k * 4.5, 0, -2)))

		# Slab above this storey: ceiling below, floor (or roof) above.
		_block(Vector3(0, H + 0.2, 2), Vector3(41.2, 0.4, 13.2), Color("f7f3ea"), 0.0, true)
		_block(Vector3(0, H + 0.2, -4.62), Vector3(41.4, 0.44, 0.1), P.TRIM, 0.0)
		_block(Vector3(0, H + 0.2, 8.62), Vector3(41.4, 0.44, 0.1), P.TRIM, 0.0)
		_block(Vector3(-20.66, H + 0.2, 2), Vector3(0.1, 0.44, 13.4), P.TRIM, 0.0)
		_block(Vector3(20.66, H + 0.2, 2), Vector3(0.1, 0.44, 13.4), P.TRIM, 0.0)

	for x in STAIR_X:
		_oy = 0.0
		_stairs(x)
	_oy = 2 * FLOOR_H
	var roof_top := 0.0
	_block(Vector3(0, roof_top + 0.005, 2), Vector3(40.8, 0.02, 12.8), P.ROOF, 0.0)
	for z in [-4.5, 8.5]:
		_block(Vector3(0, roof_top + 0.22, z), Vector3(41.2, 0.44, 0.2), P.WALL, 0.0)
		_block(Vector3(0, roof_top + 0.47, z), Vector3(41.3, 0.06, 0.26), P.TRIM, 0.0)
	for x in [-20.5, 20.5]:
		_block(Vector3(x, roof_top + 0.22, 2), Vector3(0.2, 0.44, 13.2), P.WALL, 0.0)
		_block(Vector3(x, roof_top + 0.47, 2), Vector3(0.26, 0.06, 13.3), P.TRIM, 0.0)

	# Rooftop clutter: water tank, AC units, solar panels.
	_block(Vector3(14, roof_top + 0.7, 5), Vector3(1.8, 1.4, 1.8), Color("2c2e36"))
	_block(Vector3(14, roof_top + 1.45, 5), Vector3(1.2, 0.1, 1.2), Color("3a3d47"))
	for i in 3:
		_block(Vector3(-14 + i * 1.3, roof_top + 0.35, 6.5), Vector3(1.0, 0.7, 0.6), P.PAPER, 0.03)
		_block(Vector3(-14 + i * 1.3, roof_top + 0.35, 6.19), Vector3(0.5, 0.5, 0.02), P.METAL_DARK)
	for i in 6:
		_block(Vector3(-4 + i * 1.6, roof_top + 0.25, 4), Vector3(1.4, 0.08, 2.2), Color("2f4a8a"), 0.02)
		_block(Vector3(-4 + i * 1.6, roof_top + 0.1, 4), Vector3(0.1, 0.2, 0.1), P.METAL)

	# College name board on the front parapet.
	_block(Vector3(0, roof_top + 1.25, -4.5), Vector3(17, 1.4, 0.2), Color("24315e"), 0.0)
	_block(Vector3(0, roof_top + 1.25, -4.5), Vector3(17.3, 1.55, 0.14), P.TRIM, 0.0)
	_label(UNI_NAME, Vector3(0, roof_top + 1.35, -4.62), 96, Color("ffd24a"), PI, 16)
	_label(UNI_MOTTO, Vector3(0, roof_top + 0.8, -4.62), 44, Color("ffffff"), PI, 10)
	_oy = 0.0

	_verandah_props()


## Ramped staircase outside one end of the building, climbing from the back
## (z = 8) to a landing that joins the first-floor balcony (z = -4.4..0).
func _stairs(xc: float) -> void:
	var side := signf(xc)  # -1 west, +1 east
	var run := 8.0
	var rise := FLOOR_H
	var steps := 18
	for k in steps:
		var h := (k + 1) * rise / steps
		var z := run - (k + 0.5) * run / steps
		_block(Vector3(xc, h / 2.0, z), Vector3(2.0, h, run / steps + 0.01), P.STONE if k % 2 == 0 else P.STONE_DARK, 0.0)
	# Walkable slope (steps are just looks) and solid fill beneath it.
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise) + 0.4
	_collide(Vector3(xc, rise / 2.0 - 0.15 * cos(angle), run / 2.0 - 0.15 * sin(angle)), Vector3(2.0, 0.3, length), angle)
	for k in range(2, 9):
		var top := rise * (k - 0.5) / run - 0.25  # stays just under the ramp surface
		_collide(Vector3(xc, top / 2.0, run - k + 0.5), Vector3(2.0, top, 1.0))
	# Landing that joins the balcony, with a support pillar.
	var inner := 20.4 * side
	var outer := xc + side * 1.0
	var land := Rect2(minf(inner, outer), -4.4, absf(outer - inner), 4.4)
	_block(Vector3(land.get_center().x, rise - 0.2, -2.2), Vector3(land.size.x, 0.4, 4.4), Color("f7f3ea"), 0.0, true)
	_oy = rise
	_tiles(land, 1.0, P.STONE, P.STONE_DARK)
	_oy = 0.0
	_block(Vector3(outer - side * 0.2, rise / 2.0, -4.2), Vector3(0.4, rise, 0.4), P.WALL, 0.0, true)
	# Railings: both sides of the flight (a handrail following the slope on
	# posts standing on the steps), and around the landing.
	for rx in [xc - 1.05, xc + 1.05]:
		_bar(Vector3(rx, 0.95, run + 0.05), Vector3(rx, rise + 0.95, -0.05), 0.09, P.METAL_DARK)
		_bar(Vector3(rx, 0.45, run + 0.05), Vector3(rx, rise + 0.45, -0.05), 0.05, P.METAL_DARK)
		_collide(Vector3(rx, rise / 2.0 + 0.5, run / 2.0), Vector3(0.12, 1.0, length), angle)
		for k in 6:
			var z := run - 0.05 - k * (run - 0.1) / 5.0
			var foot := rise * (run - z) / run
			_block(Vector3(rx, foot + 0.475, z), Vector3(0.06, 0.95, 0.06), P.METAL_DARK, 0.0)
	_railing(Vector3(outer, rise, 0.0), Vector3(outer, rise, -4.4))
	# Close the gap between the top of the ramp and the building wall.
	var ramp_edge := xc - side * 1.05
	_railing(Vector3(inner, rise, -0.06), Vector3(ramp_edge, rise, -0.06))
	_railing(Vector3(land.position.x, rise, -4.35), Vector3(land.end.x, rise, -4.35))
	_map(Rect2(xc - 1.0, 0.0, 2.0, run), P.STONE_DARK, "Stairs", -1, false, "stairs")
	_map(land, P.STONE, "", 1)
	nav_points.append(Vector3(xc, 0, run + 0.9))
	nav_points.append(Vector3(xc + side * 1.9, 0, run + 1.2))  # round the outer corner
	nav_points.append(Vector3(xc, rise / 2.0, run / 2.0))
	nav_points.append(Vector3(xc, rise, -0.6))
	nav_points.append(Vector3((inner + outer) / 2.0, rise, -2.2))


## A non-class room: decor, extra hiding places, somewhere to lie low.
func _other_room(cx: float, kind: String, sign_text: String) -> void:
	var accent := Color("8a8f9c")
	_wall(true, cx - 5, cx + 5, WALL_Z_FRONT, [[cx - 4.0, cx - 1.6, 1.0, 2.3], [cx + 2.8, cx + 4.2, 0.0, 2.3]], P.DADO_OUTSIDE, P.DADO_INSIDE)
	_window_frame(true, cx - 4.0, cx - 1.6, WALL_Z_FRONT, 1.0, 2.3, true)
	_door(cx + 2.8, cx + 4.2, accent)
	_wall(true, cx - 5, cx + 5, WALL_Z_BACK, [[cx - 4.4, cx - 2.6, 1.0, 2.3], [cx + 2.6, cx + 4.4, 1.0, 2.3]], P.DADO_INSIDE, P.DADO_OUTSIDE)
	_window_frame(true, cx - 4.4, cx - 2.6, WALL_Z_BACK, 1.0, 2.3, false)
	_window_frame(true, cx + 2.6, cx + 4.4, WALL_Z_BACK, 1.0, 2.3, false)
	_block(Vector3(cx + 3.5, 2.72, -T / 2 - 0.03), Vector3(1.9, 0.4, 0.05), Color("3a3d47"), 0.0)
	_label(sign_text, Vector3(cx + 3.5, 2.72, -T / 2 - 0.06), 34, Color.WHITE, PI, 8)
	_map(Rect2(cx - 5, 0, 10, 8), Color("b9b0a4"), kind.capitalize(), int(_oy / FLOOR_H + 0.5))
	match kind:
		"computer":
			for row in 3:
				var z := 2.0 + row * 1.8
				_block(Vector3(cx - 1.0, 0.38, z), Vector3(6.0, 0.76, 0.7), Color("dcdfe6"), 0.02, true)
				for k in 5:
					var x := cx - 3.4 + k * 1.2
					_block(Vector3(x, 0.99, z + 0.1), Vector3(0.6, 0.45, 0.06), Color("26262e"), 0.0)
					_glow.box(_off(Vector3(x, 0.99, z + 0.065)), Vector3(0.52, 0.37, 0.01), Color("7fd0ea"))
					_block(Vector3(x, 0.8, z - 0.15), Vector3(0.45, 0.03, 0.15), Color("3a3d47"), 0.0)
		"seminar":
			_block(Vector3(cx, 0.15, 7.0), Vector3(9.5, 0.3, 1.8), P.WOOD_DARK, 0.0, true)
			_block(Vector3(cx, 1.9, WALL_Z_BACK - T / 2 - 0.03), Vector3(4.5, 2.0, 0.04), Color.WHITE, 0.0)
			for row in 4:
				for k in 6:
					var p := Vector3(cx - 3.6 + k * 1.2, 0, 1.3 + row * 1.2)
					_block(p + Vector3(0, 0.44, 0), Vector3(0.5, 0.06, 0.45), Color("e0524f"), 0.02)
					_block(p + Vector3(0, 0.72, 0.2), Vector3(0.5, 0.5, 0.06), Color("e0524f"), 0.02)
					_block(p + Vector3(0, 0.22, 0), Vector3(0.4, 0.44, 0.4), P.METAL_DARK, 0.0)
		"music":
			_block(Vector3(cx - 2.5, 0.4, 6.5), Vector3(1.8, 0.8, 0.7), Color("26262e"), 0.0, true)
			for k in 8:
				_block(Vector3(cx - 3.3 + k * 0.2, 0.82, 6.2), Vector3(0.16, 0.03, 0.3), Color.WHITE, 0.0)
			_block(Vector3(cx + 2.0, 0.3, 6.0), Vector3(0.6, 0.6, 0.6), Color("e0524f"), 0.0, true)
			_block(Vector3(cx + 2.9, 0.25, 6.3), Vector3(0.45, 0.5, 0.45), Color("ffd24a"), 0.0, true)
			_block(Vector3(cx + 2.4, 1.1, 6.6), Vector3(0.5, 0.04, 0.5), Color("ffd24a"), 0.0)
			_block(Vector3(cx + 2.4, 0.55, 6.6), Vector3(0.04, 1.1, 0.04), P.METAL, 0.0)
			_interactable("piano", Vector3(cx - 2.5, 0, 5.5), "Play the piano")
			_interactable("drums", Vector3(cx + 2.4, 0, 5.1), "Play the drums")
			_block(Vector3(cx - 0.5, 0.62, 7.74), Vector3(0.35, 1.2, 0.12), Color("b0703e"), 0.0)
		"store":
			# Stacks of crates and old benches: great for lying low.
			for k in 14:
				var p := Vector3(cx + _rng.randf_range(-4.0, 3.5), 0, _rng.randf_range(2.0, 7.2))
				var s := _rng.randf_range(0.6, 1.0)
				_block(p + Vector3(0, s / 2.0, 0), Vector3(s, s, s), P.WOOD.darkened(_rng.randf_range(0.0, 0.3)), 0.04, true)
				if _rng.randf() < 0.5:
					_block(p + Vector3(0.05, s + 0.3, 0.05), Vector3(0.6, 0.6, 0.6), P.WOOD, 0.04, true)
	var light := OmniLight3D.new()
	light.position = _off(Vector3(cx, 2.7, 4))
	light.light_color = Color(1.0, 0.95, 0.86)
	light.light_energy = 0.4 if kind == "store" else 0.9
	light.omni_range = 8.5
	_root.add_child(light)
	for p in [Vector2(cx + 3.4, 1.0), Vector2(cx + 3.4, 5.8), Vector2(cx + 3.5, 0.5), Vector2(cx + 3.5, -1.2)]:
		nav_points.append(_off(Vector3(p.x, 0, p.y)))


func _classroom(i: int, cx: float) -> void:
	var room_color: Color = P.CLASS_COLORS[i]
	var lab := i == 3
	_map(Rect2(cx - 5, 0, 10, 8), room_color.lerp(Color.WHITE, 0.35), _room_name(i).capitalize(), ROOM_LEVELS[i])

	# Front wall: grilled window + door. Back wall: two open windows (escape route!).
	_wall(true, cx - 5, cx + 5, WALL_Z_FRONT, [[cx - 4.0, cx - 1.6, 1.0, 2.3], [cx + 2.8, cx + 4.2, 0.0, 2.3]], P.DADO_OUTSIDE, P.DADO_INSIDE)
	_window_frame(true, cx - 4.0, cx - 1.6, WALL_Z_FRONT, 1.0, 2.3, true)
	_door(cx + 2.8, cx + 4.2, room_color)
	_wall(true, cx - 5, cx + 5, WALL_Z_BACK, [[cx - 4.4, cx - 2.6, 1.0, 2.3], [cx + 2.6, cx + 4.4, 1.0, 2.3]], P.DADO_INSIDE, P.DADO_OUTSIDE)
	_window_frame(true, cx - 4.4, cx - 2.6, WALL_Z_BACK, 1.0, 2.3, false)
	_window_frame(true, cx + 2.6, cx + 4.4, WALL_Z_BACK, 1.0, 2.3, false)

	# Room sign above the door, facing the verandah.
	_block(Vector3(cx + 3.5, 2.72, -T / 2 - 0.03), Vector3(1.5, 0.4, 0.05), room_color, 0.0)
	_label(_room_name(i), Vector3(cx + 3.5, 2.72, -T / 2 - 0.06), 44, Color.WHITE, PI, 10)

	# Teacher's dais, blackboard, clock.
	var back_in := WALL_Z_BACK - T / 2
	_block(Vector3(cx, 0.045, 7.15), Vector3(9.5, 0.07, 1.5), P.WOOD_DARK, 0.0)
	_block(Vector3(cx, 1.75, back_in - 0.03), Vector3(3.9, 1.5, 0.06), P.WOOD_DARK, 0.0)
	_block(Vector3(cx, 1.75, back_in - 0.07), Vector3(3.7, 1.3, 0.03), P.BOARD, 0.0)
	_block(Vector3(cx, 1.02, back_in - 0.1), Vector3(3.7, 0.05, 0.12), P.WOOD_DARK, 0.0)
	for k in 3:
		_block(Vector3(cx - 1.2 + k * 0.3, 1.06, back_in - 0.1), Vector3(0.08, 0.025, 0.025), P.CHALK, 0.0)
	var chalk := _label(ROOM_SUBJECTS[i], Vector3(cx, 1.85, back_in - 0.09), 30, P.CHALK, PI, 0)
	chalk.modulate.a = 0.9
	_block(Vector3(cx, 2.78, back_in - 0.03), Vector3(0.46, 0.46, 0.05), Color("2a2a30"), 0.0)
	_block(Vector3(cx, 2.78, back_in - 0.06), Vector3(0.38, 0.38, 0.02), Color.WHITE, 0.0)
	_block(Vector3(cx, 2.83, back_in - 0.075), Vector3(0.025, 0.12, 0.01), Color("2a2a30"), 0.0)
	_block(Vector3(cx + 0.05, 2.78, back_in - 0.075), Vector3(0.1, 0.02, 0.01), Color("e0524f"), 0.0)

	# Teacher's table and chair, with the attendance register.
	var dais := 0.08
	_block(Vector3(cx + 1.6, dais + 0.76, 6.9), Vector3(1.7, 0.06, 0.8), P.WOOD, 0.02)
	_block(Vector3(cx + 1.6, dais + 0.45, 6.52), Vector3(1.7, 0.6, 0.04), P.WOOD_DARK, 0.0)
	for sx in [-0.8, 0.8]:
		_block(Vector3(cx + 1.6 + sx, dais + 0.37, 6.9), Vector3(0.06, 0.74, 0.76), P.WOOD_DARK, 0.0)
	_collide(Vector3(cx + 1.6, dais + 0.4, 6.9), Vector3(1.7, 0.8, 0.8))
	_interactable("register", Vector3(cx + 1.6, 0, 6.1), "Sign the attendance register", {"room": i})
	_block(Vector3(cx + 1.6, dais + 0.8, 6.95), Vector3(0.34, 0.04, 0.44), Color("2f5fb0"), 0.0)
	_block(Vector3(cx + 1.1, dais + 0.86, 7.0), Vector3(0.24, 0.16, 0.32), Color("e0524f"), 0.03)
	_block(Vector3(cx + 2.2, dais + 0.9, 6.95), Vector3(0.08, 0.22, 0.08), Color("7fd0ea"), 0.0)
	_block(Vector3(cx + 1.6, dais + 0.46, 7.55), Vector3(0.5, 0.06, 0.5), P.WOOD, 0.0)
	_block(Vector3(cx + 1.6, dais + 0.75, 7.8), Vector3(0.5, 0.55, 0.05), P.WOOD, 0.0)
	_block(Vector3(cx + 1.6, dais + 0.22, 7.55), Vector3(0.42, 0.44, 0.42), P.WOOD_DARK, 0.0)

	# Student benches: 2 columns x 3 rows, two students per bench.
	for row in 3:
		for bench_x in [cx - 2.4, cx + 0.9]:
			var desk_z := 1.9 + row * 1.5
			_bench(bench_x, desk_z, lab)
			seats[i].append(_off(Vector3(bench_x - 0.45, 0.02, desk_z - 0.62)))
			seats[i].append(_off(Vector3(bench_x + 0.45, 0.02, desk_z - 0.62)))
			if _rng.randf() < 0.6:
				var book: Color = P.BAGS[_rng.randi() % P.BAGS.size()]
				_block(Vector3(bench_x + _rng.randf_range(-0.6, 0.6), 0.815, desk_z), Vector3(0.22, 0.04, 0.3), book, 0.03)
			if lab:
				_block(Vector3(bench_x - 0.5, 0.86, desk_z + 0.1), Vector3(0.07, 0.14, 0.07), Color("7fe0a0"), 0.0)
				_block(Vector3(bench_x + 0.3, 0.84, desk_z + 0.1), Vector3(0.09, 0.1, 0.09), Color("ff8ab0"), 0.0)

	# Tube lights on the side walls, fans and a warm room light.
	for side in [-1.0, 1.0]:
		var wx: float = cx + side * (5 - T / 2 - 0.04)
		_block(Vector3(wx, 2.6, 4), Vector3(0.06, 0.08, 1.3), P.SHIRT, 0.0)
		_glow.box(_off(Vector3(wx - side * 0.05, 2.6, 4)), Vector3(0.05, 0.05, 1.18), P.GLOW)
	for fx in [cx - 2.2, cx + 2.2]:
		_fan(Vector3(fx, H - 0.35, 3.8))
	var light := OmniLight3D.new()
	light.position = _off(Vector3(cx, 2.7, 4))
	light.light_color = Color(1.0, 0.95, 0.86)
	light.light_energy = 1.1
	light.omni_range = 8.5
	light.omni_attenuation = 0.8
	_root.add_child(light)

	# Lockers on the verandah side of the front wall: hiding spots.
	for k in 3:
		_locker(Vector3(cx - 0.8 + k * 0.8, 0, -T / 2.0 - 0.3), room_color)

	# Nav points: aisles, front of room, both sides of the door.
	for p in [Vector2(cx - 0.75, 1.0), Vector2(cx - 0.75, 5.8), Vector2(cx, 7.0), Vector2(cx + 3.4, 1.0),
			Vector2(cx + 3.4, 5.8), Vector2(cx + 3.5, 0.5), Vector2(cx + 3.5, -1.2)]:
		nav_points.append(_off(Vector3(p.x, 0, p.y)))

	# Posters, dustbin, lab extras.
	var side_in := cx - 5 + T / 2 + 0.02
	_block(Vector3(side_in, 1.8, 2.5), Vector3(0.02, 0.7, 0.5), Color("ffd24a"), 0.0)
	_block(Vector3(side_in, 1.8, 5.2), Vector3(0.02, 0.6, 0.9), Color("7fd0ea"), 0.0)
	_block(Vector3(cx + 4.5, 0.25, 0.5), Vector3(0.36, 0.5, 0.36), Color("48b06a"), 0.02, true)
	if lab:
		_block(Vector3(cx - 3.7, 0.45, 7.3), Vector3(1.6, 0.9, 0.7), P.METAL, 0.0, true)
		_block(Vector3(cx - 3.7, 0.91, 7.3), Vector3(0.6, 0.02, 0.4), Color("3a3d45"), 0.0)
		_block(Vector3(cx - 3.7, 1.15, 7.55), Vector3(0.05, 0.45, 0.05), P.METAL, 0.0)
		# Blocky skeleton in the corner, as every lab has.
		var sk := Vector3(cx - 4.4, 0, 5.8)
		_block(sk + Vector3(0, 0.05, 0), Vector3(0.4, 0.1, 0.4), P.METAL_DARK, 0.0)
		_block(sk + Vector3(0, 0.6, 0), Vector3(0.05, 1.1, 0.05), P.METAL, 0.0)
		_block(sk + Vector3(0, 1.35, 0), Vector3(0.36, 0.5, 0.12), Color("f1ecdc"), 0.0)
		_block(sk + Vector3(0, 1.73, 0), Vector3(0.24, 0.26, 0.24), Color("f1ecdc"), 0.0)
		_block(sk + Vector3(0.06, 1.82, -0.121), Vector3(0.05, 0.05, 0.01), Color("2a2a30"), 0.0)
		_block(sk + Vector3(-0.06, 1.82, -0.121), Vector3(0.05, 0.05, 0.01), Color("2a2a30"), 0.0)


func _locker(base: Vector3, accent: Color) -> void:
	for part in locker_parts(accent):
		_block(base + part[0], part[1], part[2], 0.0)
	_collide(base + Vector3(0, 0.95, 0), Vector3(0.74, 1.9, 0.56))
	_add_hide(base + LOCKER_EYE, base + Vector3(0, 0.05, -0.85), 0.0, "Hide in locker")


## Where a hider stands in a locker: towards the back, so the door is at arm's length.
const LOCKER_EYE := Vector3(0, 0.05, 0.12)


## A locker in its own frame (x across, y up, z depth, door facing -z), as
## [centre, size, colour] boxes. It is hollow, made of thin panels, so from
## inside you see its walls and the back of the door, and you look out
## through the real louvre slots in the door at eye height (1.63 m).
static func locker_parts(accent: Color) -> Array:
	var body := Color("5f8fb8")
	var door := body.lightened(0.1)
	var slat := Color("2a3a4a")
	var parts := [
		[Vector3(-0.355, 0.95, 0.0), Vector3(0.03, 1.9, 0.56), body],           # sides
		[Vector3(0.355, 0.95, 0.0), Vector3(0.03, 1.9, 0.56), body],
		[Vector3(0.0, 0.95, 0.265), Vector3(0.74, 1.9, 0.03), body.darkened(0.2)],  # back
		[Vector3(0.0, 1.885, 0.0), Vector3(0.74, 0.03, 0.56), body],             # top
		[Vector3(0.0, 0.03, 0.0), Vector3(0.74, 0.06, 0.56), body.darkened(0.3)],   # floor
		# Door: solid below and above the vent, stiles either side of it.
		[Vector3(0.0, 0.71, -0.28), Vector3(0.68, 1.3, 0.025), door],
		[Vector3(0.0, 1.85, -0.28), Vector3(0.68, 0.04, 0.025), door],
		[Vector3(-0.29, 1.595, -0.28), Vector3(0.1, 0.47, 0.025), door],
		[Vector3(0.29, 1.595, -0.28), Vector3(0.1, 0.47, 0.025), door],
		[Vector3(0.24, 1.0, -0.3), Vector3(0.04, 0.16, 0.02), P.METAL],           # handle
		[Vector3(0.0, 1.93, -0.27), Vector3(0.3, 0.06, 0.02), accent],            # class-colour tag
		[Vector3(0.0, 1.62, 0.2), Vector3(0.3, 0.03, 0.1), P.METAL],              # coat hook rail
	]
	for y: float in [1.45, 1.57, 1.69]:  # louvre slats; the eye looks through the gap between the middle ones
		parts.append([Vector3(0.0, y, -0.28), Vector3(0.48, 0.025, 0.02), slat])
	return parts


func _add_hide(pos: Vector3, out: Vector3, yaw: float, label: String) -> void:
	lockers.append({"pos": _off(pos), "out": _off(out), "yaw": yaw, "label": label})
	interactables.append({"kind": "hide", "pos": _off(out), "label": label, "index": lockers.size() - 1})


## What a ping on this spot is called: the object right there, else the place.
const OBJECT_NAMES := {
	"counter": "Canteen counter", "register": "Attendance register", "notice": "Notice board", "car": "Principal's car",
	"bell": "Staff room bell", "alarm": "Fire alarm", "service_gate": "Service gate", "toilet": "Toilet",
	"cistern": "Cistern", "return_book": "Library desk", "piano": "Piano", "drums": "Drums", "essay": "Detention desk",
	"seat": "Desk", "hoop": "Basketball hoop",
}
const PICKUP_NAMES := {"exam_paper": "Exam paper", "medical_note": "Medical notes cupboard", "canteen_key": "Canteen key"}


func object_near(pos: Vector3, radius := 1.4) -> String:
	var best := radius
	var out := ""
	for it: Dictionary in interactables:
		var at: Vector3 = it.pos
		if absf(at.y - pos.y) > 2.2:
			continue
		var d := Vector2(at.x - pos.x, at.z - pos.z).length()
		var r := 0.8 if it.kind == "seat" else radius
		if d >= minf(best, r):
			continue
		best = d
		match str(it.kind):
			"hide":
				out = "Washroom stall" if "stall" in str(it.label).to_lower() else "Locker"
			"pickup":
				out = PICKUP_NAMES.get(str(it.get("item", "")), "Something useful")
			_:
				out = OBJECT_NAMES.get(str(it.kind), str(it.kind).capitalize())
	for rim: Vector3 in rims:
		if rim.distance_to(pos) < 1.5:
			return "Basketball hoop"
	return out


func place_name(pos: Vector3) -> String:
	var room := room_of(pos)
	if room >= 0:
		return ["Class A", "Class B", "Class C", "Lab"][room]
	var best := INF
	var out := ""
	var lvl := level_of(pos)
	for s: Dictionary in map_shapes:
		var rect: Rect2 = s.rect
		if str(s.label) == "" or not rect.has_point(Vector2(pos.x, pos.z)):
			continue
		if int(s.level) >= 0 and int(s.level) != lvl:
			continue
		if rect.get_area() < best:
			best = rect.get_area()
			out = str(s.label).replace("\n", " ")
	var near := false
	if out == "":
		# Not inside a named area (a corridor, a lawn): "near" the closest one.
		var p2 := Vector2(pos.x, pos.z)
		best = 18.0
		for s: Dictionary in map_shapes:
			var rect: Rect2 = s.rect
			if str(s.label) == "" or (int(s.level) >= 0 and int(s.level) != lvl):
				continue
			var d := p2.distance_to(p2.clamp(rect.position, rect.end))
			if d < best:
				best = d
				out = str(s.label).replace("\n", " ")
				near = true
	if out == out.to_upper():
		out = out.capitalize()
	return ("Near " + out) if near and out != "" else out


func _interactable(kind: String, pos: Vector3, label: String, extra := {}) -> void:
	var entry := {"kind": kind, "pos": _off(pos), "label": label}
	entry.merge(extra)
	interactables.append(entry)


func _detention_block() -> void:
	# Principal's office / detention: a sealed room behind the basketball court.
	var c := Vector3(-32, 0, 11)
	var w := 7.0
	var d := 5.0
	_tiles(Rect2(c.x - w / 2, c.z - d / 2, w, d), 1.0, P.FLOOR_A, P.FLOOR_B)
	_wall(true, c.x - w / 2, c.x + w / 2, c.z - d / 2, [[c.x - 2.0, c.x - 0.6, 1.2, 2.3]], P.DADO_OUTSIDE, P.DADO_INSIDE)
	_window_frame(true, c.x - 2.0, c.x - 0.6, c.z - d / 2, 1.2, 2.3, true)
	_wall(true, c.x - w / 2, c.x + w / 2, c.z + d / 2, [], P.DADO_INSIDE, P.DADO_OUTSIDE)
	_wall(false, c.z - d / 2, c.z + d / 2, c.x - w / 2, [], P.DADO_OUTSIDE, P.DADO_INSIDE)
	_wall(false, c.z - d / 2, c.z + d / 2, c.x + w / 2, [], P.DADO_INSIDE, P.DADO_OUTSIDE)
	_block(c + Vector3(0, H + 0.14, 0), Vector3(w + 0.6, 0.28, d + 0.6), Color("f7f3ea"), 0.0, true)
	_block(c + Vector3(0, H + 0.36, 0), Vector3(w + 0.7, 0.16, d + 0.7), P.TRIM, 0.0)
	# Closed door and sign on the court side.
	_block(c + Vector3(1.8, 1.1, -d / 2 - 0.13), Vector3(1.1, 2.2, 0.06), Color("7a4a2a"), 0.0)
	_block(c + Vector3(2.2, 1.1, -d / 2 - 0.17), Vector3(0.05, 0.14, 0.04), P.METAL, 0.0)
	_block(c + Vector3(0, 2.75, -d / 2 - 0.14), Vector3(3.2, 0.5, 0.05), Color("24315e"), 0.0)
	_label("PRINCIPAL  ·  DETENTION", c + Vector3(0, 2.75, -d / 2 - 0.17), 40, Color("ffd24a"), PI, 8)
	# Inside: a lonely bench, a desk and a stern poster.
	_block(c + Vector3(0, 0.23, 1.8), Vector3(2.4, 0.46, 0.45), P.WOOD, 0.02, true)
	_block(c + Vector3(-2.3, 0.4, 0), Vector3(0.9, 0.8, 1.6), P.WOOD_DARK, 0.02, true)
	_block(c + Vector3(-2.3, 0.82, 0.2), Vector3(0.5, 0.02, 0.7), P.PAPER, 0.0)
	_interactable("essay", c + Vector3(-1.4, 0, 0), "Write lines (get out sooner)")
	_block(c + Vector3(0, 1.8, d / 2 - T / 2 - 0.02), Vector3(1.6, 0.8, 0.02), P.PAPER, 0.0)
	_label("DISCIPLINE IS\nTHE KEY TO SUCCESS", c + Vector3(0, 1.8, d / 2 - T / 2 - 0.04), 26, Color("e0524f"), PI, 0)
	var light := OmniLight3D.new()
	light.position = c + Vector3(0, 2.7, 0)
	light.omni_range = 6.0
	light.light_color = Color(1.0, 0.95, 0.86)
	_root.add_child(light)


## Minimap shapes for everything outside the main building.
func _map_outdoors() -> void:
	var stone := Color("d9d0bf")
	_map(Rect2(-40, -33, 80, 57), Color("78b457"))  # academic block lawns
	_map(Rect2(-12, -12, 24, 7.6), stone, "Plaza", -1, false, "path")
	_map(Rect2(-2, -33, 4, 21), stone, "", -1, false, "path")
	_map(Rect2(12, -11, 10, 2), stone, "", -1, false, "path")
	_map(Rect2(22, -27, 14, 14), stone, "", -1, false, "path")
	_map(Rect2(-34, -31, 12, 8), P.ASPHALT, "Parking")
	_map(Rect2(-38, -14, 14, 16), P.COURT, "Court")
	_map(Rect2(24, -20, 10, 6.2), Color("ffd24a"), "Canteen", -1, false, "building")
	_map(Rect2(25, -3, 6, 10), Color("c9d6e8"), "Staff room", -1, false, "building")
	_map(Rect2(31, -3, 6, 10), Color("e8d9bf"), "Library", -1, false, "building")
	_map(Rect2(24, 12, 6, 5), Color("bfe3ea"), "Washroom", -1, false, "building")
	_map(Rect2(-35.5, 8.5, 7, 5), Color("c9a0a0"), "Detention", -1, false, "building")
	_map(Rect2(6, -31.6, 2.4, 2.4), Color.WHITE, "Guard", -1, false, "building")
	# Boundary walls, with the gates left open.
	var brick := Color("b95c43")
	_map(Rect2(-40.3, -33.3, 36.1, 0.6), brick)
	_map(Rect2(4.2, -33.3, 36.1, 0.6), brick)
	_map(Rect2(-40.3, 23.7, 50.3, 0.6), brick)
	_map(Rect2(13, 23.7, 27.3, 0.6), brick)
	_map(Rect2(10, 23.6, 3, 0.8), Color("ffd24a"), "Broken wall", -1, true)
	_map(Rect2(-40.3, -33.3, 0.6, 57.6), brick)
	_map(Rect2(39.7, -33.3, 0.6, 16.3), brick)
	_map(Rect2(39.7, -15.4, 0.6, 39.7), brick)
	_map(Rect2(39.5, -17, 1.0, 1.6), Color("ffd24a"), "Service gate", -1, true)
	_map(Rect2(-3.6, -33.6, 7.2, 1.2), Color("ffd24a"), "Main gate", -1, true)


func _staff_block() -> void:
	# Staff room (x 25..31) and library (x 31..37), z -3..7.
	var x0 := 25.0
	var x1 := 37.0
	var z0 := -3.0
	var z1 := 7.0
	_tiles(Rect2(x0 + T / 2, z0 + T / 2, 6 - T, 10 - T), 1.0, P.FLOOR_A, P.FLOOR_B)
	_tiles(Rect2(31 + T / 2, z0 + T / 2, 6 - T, 10 - T), 1.0, Color("e8d9bf"), Color("c9b48f"))
	_wall(true, x0, x1, z0, [[26.3, 28.7, 1.0, 2.3], [33.0, 34.4, 0.0, 2.3]], P.DADO_OUTSIDE, P.DADO_INSIDE)
	_window_frame(true, 26.3, 28.7, z0, 1.0, 2.3, true)
	_wall(true, x0, x1, z1, [[26.5, 29.5, 1.0, 2.3], [32.5, 35.5, 1.0, 2.3]], P.DADO_INSIDE, P.DADO_OUTSIDE)
	_window_frame(true, 26.5, 29.5, z1, 1.0, 2.3, true)
	_window_frame(true, 32.5, 35.5, z1, 1.0, 2.3, true)
	_wall(false, z0, z1, x0, [[1.2, 2.6, 0.0, 2.3]], P.DADO_OUTSIDE, P.DADO_INSIDE)
	_wall(false, z0, z1, 31.0, [], P.DADO_INSIDE, P.DADO_INSIDE)
	_wall(false, z0, z1, x1, [], P.DADO_INSIDE, P.DADO_OUTSIDE)
	_block(Vector3(31, H + 0.14, 2), Vector3(12.6, 0.28, 10.6), Color("f7f3ea"), 0.0, true)
	_block(Vector3(31, H + 0.36, 2), Vector3(12.8, 0.16, 10.8), P.TRIM, 0.0)
	for zz in [1.25, 2.55]:
		_block(Vector3(x0, 1.15, zz), Vector3(T + 0.08, 2.3, 0.1), P.WOOD_DARK, 0.0)
	for xx in [33.05, 34.35]:
		_block(Vector3(xx, 1.15, z0), Vector3(0.1, 2.3, T + 0.08), P.WOOD_DARK, 0.0)
	_block(Vector3(x0 - 0.15, 2.72, 1.9), Vector3(0.05, 0.4, 1.6), Color("24315e"), 0.0)
	_label("STAFF ROOM", Vector3(x0 - 0.18, 2.72, 1.9), 40, Color("ffd24a"), -PI / 2, 8)
	_block(Vector3(33.7, 2.72, z0 - 0.15), Vector3(1.6, 0.4, 0.05), Color("24315e"), 0.0)
	_label("LIBRARY", Vector3(33.7, 2.72, z0 - 0.18), 40, Color("ffd24a"), PI, 8)

	# Staff room: big table, tea, the exam papers, a cupboard with a medical note.
	_block(Vector3(28.2, 0.76, 2.0), Vector3(3.2, 0.06, 1.2), P.WOOD, 0.02)
	_block(Vector3(28.2, 0.38, 2.0), Vector3(3.0, 0.7, 1.0), P.WOOD_DARK, 0.0)
	_collide(Vector3(28.2, 0.4, 2.0), Vector3(3.2, 0.8, 1.2))
	for cx in [27.2, 28.2, 29.2]:
		for cz in [1.05, 2.95]:
			_block(Vector3(cx, 0.45, cz), Vector3(0.45, 0.06, 0.45), P.WOOD, 0.02)
			_block(Vector3(cx, 0.22, cz), Vector3(0.38, 0.44, 0.38), P.WOOD_DARK, 0.0)
	_block(Vector3(26.3, 0.45, 3.0), Vector3(0.5, 0.06, 0.5), Color("e0524f"), 0.0)
	_block(Vector3(26.3, 0.22, 3.0), Vector3(0.4, 0.44, 0.4), Color("e0524f").darkened(0.25), 0.0)
	_block(Vector3(27.4, 0.9, 2.2), Vector3(0.3, 0.24, 0.3), P.METAL, 0.0)
	for k in 4:
		_block(Vector3(27.8 + k * 0.2, 0.83, 1.8), Vector3(0.08, 0.1, 0.08), Color("c68a5c"), 0.0)
	_block(Vector3(29.0, 0.86, 1.8), Vector3(0.36, 0.14, 0.46), P.PAPER, 0.0)
	_block(Vector3(29.0, 0.94, 1.8), Vector3(0.3, 0.02, 0.4), Color("e0524f"), 0.0)
	_label("EXAM", Vector3(29.0, 0.96, 1.8), 14, Color("e0524f"), 0.0, 0).rotation.x = -PI / 2
	_interactable("pickup", Vector3(29.0, 0, 0.95), "Steal the exam paper", {"item": "exam_paper"})
	_block(Vector3(30.35, 0.95, 6.55), Vector3(0.9, 1.9, 0.55), P.WOOD_DARK, 0.02, true)
	_block(Vector3(30.35, 0.95, 6.27), Vector3(0.02, 1.7, 0.01), Color("2a1a0e"), 0.0)
	_interactable("pickup", Vector3(30.35, 0, 5.6), "Forge a medical note", {"item": "medical_note"})
	_block(Vector3(x0 + T / 2 + 0.02, 1.7, 5.0), Vector3(0.02, 0.9, 1.4), P.BOARD, 0.0)
	var staff_light := OmniLight3D.new()
	staff_light.position = Vector3(28, 2.7, 2)
	staff_light.omni_range = 7.0
	staff_light.light_color = Color(1.0, 0.95, 0.86)
	_root.add_child(staff_light)
	# Office bell by the staff room door.
	_block(Vector3(x0 - 0.16, 1.55, 3.4), Vector3(0.06, 0.3, 0.3), P.METAL_DARK, 0.0)
	_block(Vector3(x0 - 0.22, 1.55, 3.4), Vector3(0.08, 0.2, 0.2), Color("ffd24a"), 0.0)
	_interactable("bell", Vector3(x0 - 0.8, 0, 3.4), "Ring the staff room bell")

	# Library: shelves full of colourful books, reading table, librarian's desk.
	for sz in [2.2, 4.0, 5.8]:
		_block(Vector3(33.5, 1.0, sz), Vector3(3.4, 2.0, 0.5), P.WOOD_DARK, 0.0, true)
		for row in 4:
			var bx := 31.95
			while bx < 35.0:
				var w := _rng.randf_range(0.08, 0.16)
				var h := _rng.randf_range(0.28, 0.4)
				var book: Color = P.BAGS[_rng.randi() % P.BAGS.size()]
				for side in [-1.0, 1.0]:
					_vbox(Vector3(bx + w / 2, 0.3 + row * 0.46 + h / 2, sz + side * 0.26), Vector3(w - 0.01, h, 0.04), book)
				bx += w
	_block(Vector3(32.6, 0.76, 0.2), Vector3(1.6, 0.06, 0.9), P.WOOD, 0.02)
	_block(Vector3(32.6, 0.38, 0.2), Vector3(0.1, 0.76, 0.1), P.WOOD_DARK, 0.0)
	_collide(Vector3(32.6, 0.4, 0.2), Vector3(1.6, 0.8, 0.9))
	_block(Vector3(35.5, 0.4, 0.5), Vector3(0.6, 0.8, 1.4), P.WOOD, 0.02, true)
	_block(Vector3(35.5, 0.86, 0.3), Vector3(0.3, 0.1, 0.4), Color("4f86e0"), 0.0)
	_interactable("return_book", Vector3(34.8, 0, 0.5), "Return the overdue library book")
	_block(Vector3(x1 - T / 2 - 0.02, 1.9, 3.5), Vector3(0.02, 0.6, 1.8), P.PAPER, 0.0)
	_label("SILENCE\nPLEASE", Vector3(x1 - T / 2 - 0.04, 1.9, 3.5), 34, Color("e0524f"), -PI / 2, 0)
	var lib_light := OmniLight3D.new()
	lib_light.position = Vector3(34, 2.7, 2)
	lib_light.omni_range = 7.0
	lib_light.light_color = Color(1.0, 0.93, 0.8)
	_root.add_child(lib_light)

	for p in [Vector2(23.6, 1.9), Vector2(26.2, 0.6), Vector2(28.2, -1.6), Vector2(28.2, 4.6),
			Vector2(33.7, -4.3), Vector2(33.7, -1.6), Vector2(36.2, -1.5), Vector2(36.2, 3.1), Vector2(34, 0.9)]:
		nav_points.append(Vector3(p.x, 0, p.y))


func _washrooms() -> void:
	var x0 := 24.0
	var x1 := 30.0
	var z0 := 12.0
	var z1 := 17.0
	_tiles(Rect2(x0 + T / 2, z0 + T / 2, 6 - T, 5 - T), 0.5, Color("dfeef2"), Color("bcd8e0"))
	_wall(false, z0, z1, x0, [[13.6, 14.8, 0.0, 2.3]], P.DADO_OUTSIDE, Color("8fc9d6"))
	_wall(false, z0, z1, x1, [], Color("8fc9d6"), P.DADO_OUTSIDE)
	_wall(true, x0, x1, z0, [[25.6, 27.6, 1.9, 2.4]], P.DADO_OUTSIDE, Color("8fc9d6"))
	_window_frame(true, 25.6, 27.6, z0, 1.9, 2.4, true)
	_wall(true, x0, x1, z1, [], Color("8fc9d6"), P.DADO_OUTSIDE)
	_block(Vector3(27, H + 0.14, 14.5), Vector3(6.6, 0.28, 5.6), Color("f7f3ea"), 0.0, true)
	_block(Vector3(27, H + 0.36, 14.5), Vector3(6.8, 0.16, 5.8), P.TRIM, 0.0)
	_block(Vector3(x0 - 0.15, 2.72, 14.2), Vector3(0.05, 0.4, 1.8), Color("3f86a8"), 0.0)
	_label("WASHROOM", Vector3(x0 - 0.18, 2.72, 14.2), 40, Color.WHITE, -PI / 2, 8)
	# Three stalls along the east wall: hiding spots.
	for k in 4:
		_block(Vector3(29.1, 1.0, 12.2 + k * 1.4), Vector3(1.55, 2.0, 0.06), Color("8fc9d6"), 0.0, true)
	for k in 3:
		var zc := 12.9 + k * 1.4
		_block(Vector3(29.4, 0.25, zc), Vector3(0.45, 0.5, 0.4), Color.WHITE, 0.0)
		_block(Vector3(29.7, 0.6, zc), Vector3(0.2, 0.5, 0.4), Color.WHITE, 0.0)
		_block(Vector3(28.33, 1.0, zc - 0.35), Vector3(0.05, 1.8, 0.6), Color("5f8fb8"), 0.0)
		_add_hide(Vector3(29.1, 0.05, zc), Vector3(27.6, 0.05, zc), PI / 2, "Hide in the stall")
		_interactable("toilet", Vector3(28.9, 0, zc - 0.4), "Use the toilet")
		_interactable("cistern", Vector3(29.55, 0, zc + 0.45), "Hide an item in the cistern")
	for k in 2:
		_block(Vector3(25.0 + k * 1.2, 0.8, z1 - 0.4), Vector3(0.6, 0.12, 0.45), Color.WHITE, 0.0)
		_block(Vector3(25.0 + k * 1.2, 0.4, z1 - 0.3), Vector3(0.12, 0.7, 0.12), P.METAL, 0.0)
		_glass.box(Vector3(25.0 + k * 1.2, 1.6, z1 - T / 2 - 0.02), Vector3(0.6, 0.7, 0.02), Color.WHITE)
	var light := OmniLight3D.new()
	light.position = Vector3(27, 2.7, 14.5)
	light.omni_range = 6.0
	light.light_color = Color(0.9, 0.97, 1.0)
	_root.add_child(light)
	nav_points.append(Vector3(22.6, 0, 14.2))
	nav_points.append(Vector3(25.4, 0, 14.2))


func _service_gate() -> void:
	# Locked gate in the east wall; the canteen key opens it.
	var gate := StaticBody3D.new()
	gate.name = "ServiceGate"
	gate.position = SERVICE_GATE_POS
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 2.6, 1.6)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.3
	gate.add_child(col)
	var v := Voxel.new(5)
	for rail_y in [0.2, 1.2, 2.2]:
		v.box(Vector3(0, rail_y, 0), Vector3(0.08, 0.08, 1.6), Color("2f6a4a"))
	for b in 8:
		v.box(Vector3(0, 1.2, -0.7 + b * 0.2), Vector3(0.05, 2.2, 0.05), Color("2f6a4a"))
	v.box(Vector3(-0.1, 1.2, 0.0), Vector3(0.12, 0.18, 0.14), Color("ffd24a"))
	gate.add_child(v.to_instance())
	_root.add_child(gate)
	service_gate = gate
	_block(SERVICE_GATE_POS + Vector3(-0.3, 2.7, 0), Vector3(0.05, 0.36, 1.4), Color("e0524f"), 0.0)
	_label("STAFF ONLY", SERVICE_GATE_POS + Vector3(-0.33, 2.7, 0), 32, Color.WHITE, -PI / 2, 0)
	_interactable("service_gate", SERVICE_GATE_POS + Vector3(-0.9, 0, 0), "Unlock the service gate")
	nav_points.append(Vector3(37.5, 0, -16.2))


func _cctv_and_alarms() -> void:
	var specs := [
		[Vector3(-19.55, 2.95, -4.1), -PI / 2, 0.55, 0.5],
		[Vector3(19.55, 2.95, -4.1), PI / 2, 0.55, 0.45],
		[Vector3(-3.8, 3.25, -32.3), PI, 0.75, 0.35],
		[Vector3(0.0, FLOOR_H + 2.95, -3.75), PI / 2, 1.3, 0.3],  # first-floor balcony
	]
	for s in specs:
		add_cctv(s[0], s[1], s[2], s[3])

	# Fire alarm boxes on two verandah pillars.
	for x in [-8.0, 8.0]:
		_block(Vector3(x, 1.5, -3.83), Vector3(0.3, 0.4, 0.1), Color("e0524f"), 0.0)
		_block(Vector3(x, 1.45, -3.77), Vector3(0.14, 0.08, 0.04), Color.WHITE, 0.0)
		_label("FIRE", Vector3(x, 1.64, -3.77), 18, Color.WHITE, 0.0, 0)
		_interactable("alarm", Vector3(x, 0, -3.1), "Pull the fire alarm")


## A sweeping camera on a bracket. It watches 16 m ahead and calls the nearest staff.
func add_cctv(pos: Vector3, base_yaw: float, sweep: float, speed: float) -> void:
	var node := Node3D.new()
	node.position = pos
	var tilt := Node3D.new()
	tilt.rotation.x = -0.35
	node.add_child(tilt)
	var v := Voxel.new(6)
	v.box(Vector3(0, 0, -0.12), Vector3(0.18, 0.16, 0.36), Color("e8e6e0"))
	v.box(Vector3(0, 0, -0.31), Vector3(0.12, 0.1, 0.04), Color("22232b"))
	v.box(Vector3(0, 0.1, -0.12), Vector3(0.22, 0.03, 0.42), Color("c9c5bb"))
	tilt.add_child(v.to_instance())
	var led := Voxel.new(7)
	led.box(Vector3(0.06, 0.05, -0.3), Vector3(0.03, 0.03, 0.01), Color("ff3030"))
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color("ff3030")
	led_mat.emission_enabled = true
	led_mat.emission = Color("ff3030")
	led_mat.emission_energy_multiplier = 4.0
	var led_mi := led.to_instance(led_mat)
	led_mi.name = "Led"
	tilt.add_child(led_mi)
	_root.add_child(node)
	_vbox(pos + Vector3(0, 0.2, 0), Vector3(0.06, 0.48, 0.06), P.METAL_DARK)  # up to the ceiling or down onto a pole
	cctv.append({"node": node, "pos": pos, "base_yaw": base_yaw, "sweep": sweep, "speed": speed})


func _nav_outdoors() -> void:
	var pts := [
		# verandah and in front of it
		Vector2(-18, -2), Vector2(-14, -2), Vector2(-10, -2), Vector2(-6, -2), Vector2(-2, -2), Vector2(2, -2),
		Vector2(6, -2), Vector2(10, -2), Vector2(14, -2), Vector2(18, -2),
		Vector2(-16, -6), Vector2(-8, -6), Vector2(-3, -6), Vector2(3, -6), Vector2(8, -6), Vector2(16, -6),
		# plaza, gate path, road, chai stall
		Vector2(-13, -8), Vector2(13, -8), Vector2(-2, -11), Vector2(2, -11), Vector2(0, -14), Vector2(0, -19),
		Vector2(0, -24), Vector2(0, -29), Vector2(0, -33), Vector2(0, -36.5), Vector2(-8, -38), Vector2(8, -38),
		Vector2(-10, -42),
		# east: canteen
		Vector2(14, -10), Vector2(21, -10), Vector2(24, -12), Vector2(27, -21.5), Vector2(31, -21.5),
		# sides and back of the building
		Vector2(23, -6), Vector2(24.3, 4), Vector2(23, 11), Vector2(-22, -6), Vector2(-24.3, 4), Vector2(-22, 11),
		Vector2(-15, 11), Vector2(-5, 11), Vector2(5, 11), Vector2(15, 11), Vector2(11.5, 20),
		# west: court and parking
		Vector2(-31, -6), Vector2(-20, -24), Vector2(-28, -21), Vector2(-12, -20),
	]
	for p in pts:
		nav_points.append(Vector3(p.x, 0, p.y))


func _room_name(i: int) -> String:
	return ["CLASS A", "CLASS B", "CLASS C", "LAB"][i]


func _bench(x: float, z: float, lab: bool) -> void:
	var top_col := Color("3a3d45") if lab else P.WOOD
	var frame_col := P.METAL if lab else P.WOOD_DARK
	_block(Vector3(x, 0.76, z), Vector3(1.8, 0.06, 0.52), top_col, 0.03)
	_block(Vector3(x, 0.5, z + 0.24), Vector3(1.8, 0.46, 0.04), frame_col, 0.0)
	_block(Vector3(x, 0.58, z - 0.02), Vector3(1.72, 0.03, 0.44), frame_col, 0.0)
	for sx in [-0.87, 0.87]:
		_block(Vector3(x + sx, 0.37, z), Vector3(0.06, 0.74, 0.5), frame_col, 0.0)
		_block(Vector3(x + sx, 0.22, z - 0.62), Vector3(0.06, 0.44, 0.3), frame_col, 0.0)
	_block(Vector3(x, 0.46, z - 0.62), Vector3(1.8, 0.05, 0.32), top_col, 0.03)
	_block(Vector3(x, 0.78, z - 0.8), Vector3(1.8, 0.26, 0.04), top_col, 0.0)
	_block(Vector3(x - 0.87, 0.62, z - 0.8), Vector3(0.06, 0.34, 0.04), frame_col, 0.0)
	_block(Vector3(x + 0.87, 0.62, z - 0.8), Vector3(0.06, 0.34, 0.04), frame_col, 0.0)
	_collide(Vector3(x, 0.4, z), Vector3(1.8, 0.8, 0.52))


func _fan(pos: Vector3) -> void:
	_block(Vector3(pos.x, (pos.y + H) / 2.0, pos.z), Vector3(0.04, H - pos.y, 0.04), P.METAL_DARK, 0.0)
	var v := Voxel.new()
	v.box(Vector3.ZERO, Vector3(0.2, 0.12, 0.2), P.SHIRT)
	v.box(Vector3(0.5, -0.02, 0), Vector3(0.8, 0.02, 0.15), P.SHIRT_SHADE)
	v.box(Vector3(-0.5, -0.02, 0), Vector3(0.8, 0.02, 0.15), P.SHIRT_SHADE)
	v.box(Vector3(0, -0.02, 0.5), Vector3(0.15, 0.02, 0.8), P.SHIRT_SHADE)
	v.box(Vector3(0, -0.02, -0.5), Vector3(0.15, 0.02, 0.8), P.SHIRT_SHADE)
	var fan := v.to_instance()
	fan.position = _off(pos)
	fan.rotation.y = _rng.randf() * TAU
	_root.add_child(fan)
	fans.append(fan)


## Wall along X (fixed z) or along Z (fixed x). Holes: [[a0, a1, y0, y1], ...] sorted.
## dado_neg/dado_pos: Color or null for the painted band on each face.
func _wall(along_x: bool, a0: float, a1: float, fixed: float, holes: Array, dado_neg: Variant, dado_pos: Variant) -> void:
	var cur := a0
	for hole in holes:
		if hole[0] > cur:
			_wall_seg(along_x, cur, hole[0], fixed, 0.0, H, dado_neg, dado_pos)
		if hole[2] > 0.0:
			_wall_seg(along_x, hole[0], hole[1], fixed, 0.0, hole[2], dado_neg, dado_pos)
		if hole[3] < H:
			_wall_seg(along_x, hole[0], hole[1], fixed, hole[3], H, dado_neg, dado_pos)
		cur = hole[1]
	if cur < a1:
		_wall_seg(along_x, cur, a1, fixed, 0.0, H, dado_neg, dado_pos)


func _wall_seg(along_x: bool, a0: float, a1: float, fixed: float, y0: float, y1: float, dado_neg: Variant, dado_pos: Variant) -> void:
	var length := a1 - a0
	var mid := (a0 + a1) / 2.0
	var cy := (y0 + y1) / 2.0
	var center := Vector3(mid, cy, fixed) if along_x else Vector3(fixed, cy, mid)
	var size := Vector3(length, y1 - y0, T) if along_x else Vector3(T, y1 - y0, length)
	_block(center, size, wall_color, 0.0, true)
	if y0 >= DADO:
		return
	var top := minf(y1, DADO)
	for side in [-1.0, 1.0]:
		var col: Variant = dado_neg if side < 0 else dado_pos
		if col == null:
			continue
		var off: float = side * (T / 2.0 + 0.012)
		var band_c := Vector3(mid, (y0 + top) / 2.0, fixed + off) if along_x else Vector3(fixed + off, (y0 + top) / 2.0, mid)
		var band_s := Vector3(length, top - y0, 0.024) if along_x else Vector3(0.024, top - y0, length)
		_vbox(_off(band_c), band_s, col)
		if top >= DADO - 0.001:
			var line_c := Vector3(mid, DADO, fixed + off * 1.2) if along_x else Vector3(fixed + off * 1.2, DADO, mid)
			var line_s := Vector3(length, 0.05, 0.035) if along_x else Vector3(0.035, 0.05, length)
			_vbox(_off(line_c), line_s, (col as Color).darkened(0.2))


func _window_frame(along_x: bool, a0: float, a1: float, fixed: float, y0: float, y1: float, grill: bool) -> void:
	var frame := frame_color
	var length := a1 - a0
	var mid := (a0 + a1) / 2.0
	var depth := T + 0.06
	_block(_axis(along_x, mid, y0 - 0.03, fixed), _size(along_x, length + 0.16, 0.08, depth + 0.1), P.WALL_SHADE, 0.0)
	_block(_axis(along_x, mid, y1 + 0.04, fixed), _size(along_x, length + 0.08, 0.08, depth), frame, 0.0)
	_block(_axis(along_x, a0 + 0.04, (y0 + y1) / 2.0, fixed), _size(along_x, 0.08, y1 - y0, depth), frame, 0.0)
	_block(_axis(along_x, a1 - 0.04, (y0 + y1) / 2.0, fixed), _size(along_x, 0.08, y1 - y0, depth), frame, 0.0)
	# Open shutters folded against the wall.
	if grill:
		var bars := int(length / 0.2)
		for b in range(1, bars):
			_block(_axis(along_x, a0 + b * length / bars, (y0 + y1) / 2.0, fixed), _size(along_x, 0.03, y1 - y0, 0.03), P.METAL_DARK, 0.0)
		_block(_axis(along_x, mid, (y0 + y1) / 2.0, fixed), _size(along_x, length - 0.1, 0.03, 0.03), P.METAL_DARK, 0.0)
		_collide(_axis(along_x, mid, (y0 + y1) / 2.0, fixed), _size(along_x, length, y1 - y0, 0.1))
	else:
		_glass.box(_off(_axis(along_x, a0 + length * 0.25, (y0 + y1) / 2.0, fixed + 0.05)), _size(along_x, length * 0.46, y1 - y0 - 0.1, 0.02), Color.WHITE)


func _axis(along_x: bool, a: float, y: float, fixed: float) -> Vector3:
	return Vector3(a, y, fixed) if along_x else Vector3(fixed, y, a)


func _size(along_x: bool, length: float, height: float, depth: float) -> Vector3:
	return Vector3(length, height, depth) if along_x else Vector3(depth, height, length)


func _door(a0: float, a1: float, color: Color) -> void:
	var width := a1 - a0
	_block(Vector3(a0 + 0.05, 1.15, 0), Vector3(0.1, 2.3, T + 0.08), P.WOOD_DARK, 0.0)
	_block(Vector3(a1 - 0.05, 1.15, 0), Vector3(0.1, 2.3, T + 0.08), P.WOOD_DARK, 0.0)
	_block(Vector3((a0 + a1) / 2.0, 2.34, 0), Vector3(width, 0.1, T + 0.08), P.WOOD_DARK, 0.0)
	# Door leaf swung open into the room, resting along the hinge side.
	var leaf_z := T / 2.0 + (width - 0.1) / 2.0 + 0.02
	_block(Vector3(a1 - 0.14, 1.12, leaf_z), Vector3(0.06, 2.2, width - 0.12), color, 0.02, true)
	_block(Vector3(a1 - 0.18, 1.12, leaf_z + 0.3), Vector3(0.03, 0.2, 0.06), P.METAL, 0.0)
	_block(Vector3(a1 - 0.18, 1.6, leaf_z), Vector3(0.02, 0.5, width - 0.5), color.lightened(0.15), 0.0)


func _verandah_props() -> void:
	# Lights under the verandah roof.
	for i in 5:
		var x := -16.0 + i * 8.0
		_block(Vector3(x, H - 0.03, -2.2), Vector3(0.6, 0.06, 0.6), P.SHIRT, 0.0)
		_glow.box(Vector3(x, H - 0.065, -2.2), Vector3(0.44, 0.02, 0.44), P.GLOW)

	# Water cooler.
	_block(Vector3(0, 0.6, -0.45), Vector3(0.8, 1.2, 0.5), P.METAL, 0.02, true)
	_block(Vector3(0, 1.25, -0.45), Vector3(0.84, 0.1, 0.54), Color("3f86a8"), 0.0)
	for tx in [-0.2, 0.2]:
		_block(Vector3(tx, 0.85, -0.74), Vector3(0.06, 0.08, 0.1), P.METAL_DARK, 0.0)
	_block(Vector3(0, 0.62, -0.74), Vector3(0.6, 0.04, 0.12), P.METAL_DARK, 0.0)

	# Notice boards.
	for spec in [[-10.0, "NOTICE BOARD"], [10.0, "EXAMS FROM MONDAY"]]:
		var nx: float = spec[0]
		var face := -T / 2.0
		_block(Vector3(nx, 1.65, face - 0.03), Vector3(1.9, 1.15, 0.06), P.WOOD_DARK, 0.0)
		_block(Vector3(nx, 1.65, face - 0.065), Vector3(1.75, 1.0, 0.02), Color("c9975c"), 0.02)
		for k in 6:
			var paper: Color = [P.PAPER, Color("ffe8a3"), Color("bfe3ff"), Color("ffc9d6")][_rng.randi() % 4]
			var px := nx - 0.6 + (k % 3) * 0.6 + _rng.randf_range(-0.08, 0.08)
			var py := 1.9 - (k / 3) * 0.48 + _rng.randf_range(-0.05, 0.05)
			_block(Vector3(px, py, face - 0.08), Vector3(0.36, 0.4, 0.01), paper, 0.0)
			_block(Vector3(px, py + 0.17, face - 0.087), Vector3(0.04, 0.04, 0.01), Color("e0524f"), 0.0)
		_label(spec[1], Vector3(nx, 2.38, face - 0.04), 32, Color("ffd24a"), PI)
		_interactable("notice", Vector3(nx, 0, -1.0), "Stick a meme on the notice board")

	# Dustbins and planters at the pillars.
	for x in [-18.0, -6.0, 6.0, 18.0]:
		_planter(Vector3(x, 0, -4.1 + 0.0), 0.7)
	for x in [-12.0, 12.0]:
		_block(Vector3(x, 0.3, -3.6), Vector3(0.4, 0.6, 0.4), Color("3f86a8"), 0.02, true)
		_block(Vector3(x, 0.62, -3.6), Vector3(0.44, 0.05, 0.44), Color("2c5e78"), 0.0)


func _planter(pos: Vector3, size: float) -> void:
	_block(pos + Vector3(-size * 0.9, 0.25, 0), Vector3(size, 0.5, size), P.TRIM, 0.02, true)
	_block(pos + Vector3(-size * 0.9, 0.5, 0), Vector3(size * 0.85, 0.04, size * 0.85), Color("5a3a22"), 0.0)
	_bush(pos + Vector3(-size * 0.9, 0.5, 0), 0.7)


func _bush(pos: Vector3, scale: float) -> void:
	var c: Color = P.LEAVES[_rng.randi() % P.LEAVES.size()]
	_vbox(pos + Vector3(0, 0.3 * scale, 0), Vector3(0.9, 0.6, 0.9) * scale, c, 0.04)
	for k in 3:
		var off := Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(0.3, 0.6), _rng.randf_range(-0.35, 0.35)) * scale
		_vbox(pos + off, Vector3(0.5, 0.45, 0.5) * scale, c.lightened(0.08), 0.04)


# --- Boundary, gate, road ---------------------------------------------------------------

func _boundary_and_gate() -> void:
	_brick_wall(true, -40, -4.2, -33)
	_brick_wall(true, 4.2, 40, -33)
	_brick_wall(true, -40, 10, 24)
	_brick_wall(true, 13, 40, 24)
	_brick_wall(false, -33, 24, -40)
	_brick_wall(false, -33, -17, 40)
	_brick_wall(false, -15.4, 24, 40)
	# Broken section of the back wall: low enough to vault. Crates help.
	_block(Vector3(11.5, 0.55, 24), Vector3(3, 1.1, 0.4), P.BRICK, 0.04, true)
	for k in 5:
		_block(Vector3(10.2 + k * 0.6, 1.1 + _rng.randf() * 0.12, 24 + _rng.randf_range(-0.1, 0.1)), Vector3(0.45, 0.2, 0.3), P.BRICK.lightened(0.1), 0.05)
	_block(Vector3(11.8, 0.3, 23.1), Vector3(0.6, 0.6, 0.6), P.WOOD, 0.03, true)
	_block(Vector3(11.2, 0.3, 23.2), Vector3(0.6, 0.6, 0.6), P.WOOD.darkened(0.1), 0.03, true)

	# Gate pillars and arch.
	for x in [-3.8, 3.8]:
		_block(Vector3(x, 1.8, -33), Vector3(1.1, 3.6, 1.1), P.STONE, 0.02, true)
		_block(Vector3(x, 3.7, -33), Vector3(1.3, 0.2, 1.3), P.TRIM, 0.0)
		_block(Vector3(x, 4.0, -33), Vector3(0.4, 0.4, 0.4), P.METAL_DARK, 0.0)
		_glow.box(Vector3(x, 4.35, -33), Vector3(0.36, 0.3, 0.36), P.GLOW)
	_block(Vector3(0, 4.1, -33), Vector3(7.4, 0.8, 0.5), Color("24315e"), 0.0)
	_label("ACADEMIC BLOCK", Vector3(0, 4.1, -33.26), 60, Color("ffd24a"), PI, 12)
	_label("Have a great day!", Vector3(0, 4.1, -32.74), 52, Color("ffd24a"), 0.0, 12)

	# Gate leaves, swung open inwards.
	for side in [-1.0, 1.0]:
		var gx: float = side * 3.21
		for rail_y in [0.25, 2.0]:
			_block(Vector3(gx, rail_y, -31.5), Vector3(0.07, 0.08, 2.8), P.METAL_DARK, 0.0)
		for b in 12:
			_block(Vector3(gx, 1.12, -32.8 + b * 0.24), Vector3(0.04, 1.9, 0.04), P.METAL_DARK, 0.0)
		_collide(Vector3(gx, 1.1, -31.5), Vector3(0.12, 2.2, 2.8))

	# Guard booth.
	var booth := Vector3(7.2, 0, -30.4)
	_block(booth + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 2.4), P.SHIRT, 0.02, true)
	_block(booth + Vector3(0, 0.3, 0), Vector3(2.45, 0.6, 2.45), Color("3f86a8"), 0.0)
	_block(booth + Vector3(0, 2.5, 0), Vector3(3.0, 0.18, 3.0), P.TRIM, 0.0)
	_glass.box(booth + Vector3(-1.21, 1.5, 0), Vector3(0.02, 0.8, 1.4), Color.WHITE)
	_block(booth + Vector3(-1.215, 1.5, 0), Vector3(0.03, 0.9, 1.5), Color("2c5e78"), 0.0)
	_block(booth + Vector3(0.3, 1.0, 1.21), Vector3(0.8, 2.0, 0.03), Color("2c5e78"), 0.0)
	_label("SECURITY", booth + Vector3(-1.23, 2.2, 0), 40, Color("24315e"), -PI / 2, 0)
	# Boom barrier (raised).
	_block(Vector3(2.5, 0.5, -31.8), Vector3(0.3, 1.0, 0.3), P.METAL_DARK, 0.0, true)
	for k in 6:
		_block(Vector3(2.5, 1.2 + k * 0.4, -31.8), Vector3(0.12, 0.4, 0.12), Color("e0524f") if k % 2 == 0 else Color.WHITE, 0.0)


func _brick_wall(along_x: bool, a0: float, a1: float, fixed: float, height := 2.2) -> void:
	var length := a1 - a0
	var pieces := maxi(1, int(round(length / 2.0)))
	var piece := length / pieces
	for p in pieces:
		var mid := a0 + (p + 0.5) * piece
		_block(_axis(along_x, mid, height / 2.0, fixed), _size(along_x, piece, height, 0.4), P.BRICK, 0.04)
		_block(_axis(along_x, mid, height + 0.06, fixed), _size(along_x, piece, 0.12, 0.5), P.BRICK_CAP, 0.02)
		if p % 2 == 0:
			_block(_axis(along_x, a0 + p * piece, (height + 0.3) / 2.0, fixed), _size(along_x, 0.6, height + 0.3, 0.6), P.BRICK.darkened(0.12), 0.02)
			_block(_axis(along_x, a0 + p * piece, height + 0.36, fixed), _size(along_x, 0.7, 0.1, 0.7), P.BRICK_CAP, 0.0)
	_collide(_axis(along_x, (a0 + a1) / 2.0, height / 2.0 + 0.2, fixed), _size(along_x, length, height + 0.4, 0.5))


# --- Canteen, parking, court, plaza ----------------------------------------------------

func _canteen() -> void:
	_tiles(Rect2(12, -11, 10, 2), 1.0, P.STONE, P.STONE_DARK)
	_tiles(Rect2(22, -27, 14, 14), 1.0, P.STONE, P.STONE_DARK)
	var yellow := Color("ffd24a")
	# Back wall with a service door (x 30.4..31.6) and a painted mural outside.
	_block(Vector3(27.15, 1.4, -13.9), Vector3(6.5, 2.8, 0.24), yellow, 0.0, true)
	_block(Vector3(32.85, 1.4, -13.9), Vector3(2.5, 2.8, 0.24), yellow, 0.0, true)
	_block(Vector3(31.0, 2.5, -13.9), Vector3(1.2, 0.6, 0.24), yellow, 0.0, true)
	_block(Vector3(30.45, 1.1, -13.9), Vector3(0.1, 2.2, 0.3), P.WOOD_DARK, 0.0)
	_block(Vector3(31.55, 1.1, -13.9), Vector3(0.1, 2.2, 0.3), P.WOOD_DARK, 0.0)
	_block(Vector3(29.8, 1.1, -13.72), Vector3(1.1, 2.1, 0.05), Color("3f86a8"), 0.02, true)
	for k in 5:
		var stripe: Color = [Color("e0524f"), Color("f2a93b"), Color("48b06a"), Color("4f86e0"), Color("9a62d6")][k]
		_block(Vector3(24.6 + k * 1.1, 0.35, -13.77), Vector3(1.1, 0.7, 0.02), stripe, 0.0)
	_block(Vector3(27, 1.75, -13.77), Vector3(4.2, 1.0, 0.02), Color.WHITE, 0.0)
	_label("PAPPU'S CANTEEN\nSince 1990", Vector3(27, 1.75, -13.75), 44, Color("e0524f"), 0.0, 0)
	_block(Vector3(33, 1.6, -13.77), Vector3(0.5, 0.6, 0.02), Color("c68a5c"), 0.0)
	_block(Vector3(33, 1.95, -13.77), Vector3(0.1, 0.12, 0.02), Color.WHITE, 0.0)
	_interactable("counter", Vector3(28.5, 0, -20.6), "Buy a samosa")
	_interactable("pickup", Vector3(24.9, 0, -18.9), "Grab the service gate key", {"item": "canteen_key"})
	_block(Vector3(24.7, 1.15, -19.5), Vector3(0.12, 0.08, 0.04), Color("ffd24a"), 0.0)
	_block(Vector3(24.7, 1.1, -19.52), Vector3(0.04, 0.1, 0.02), P.METAL, 0.0)
	nav_points.append(Vector3(31, 0, -12.6))
	nav_points.append(Vector3(31, 0, -15.2))
	nav_points.append(Vector3(26.5, 0, -18.6))
	_block(Vector3(23.9, 1.4, -17), Vector3(0.24, 2.8, 6.4), yellow, 0.0, true)
	_block(Vector3(34.1, 1.4, -17), Vector3(0.24, 2.8, 6.4), yellow, 0.0, true)
	_block(Vector3(29, 2.9, -17.2), Vector3(10.8, 0.2, 7.2), P.TRIM, 0.0, true)
	_block(Vector3(29, 0.5, -19.7), Vector3(9.2, 1.0, 0.6), P.WOOD, 0.02, true)
	_block(Vector3(29, 1.03, -19.7), Vector3(9.4, 0.06, 0.7), P.WOOD_DARK, 0.0)
	for k in 13:
		var c := Color("e0524f") if k % 2 == 0 else Color.WHITE
		_block(Vector3(23.6 + k * 0.84, 2.72, -21.0), Vector3(0.84, 0.08, 1.9), c, 0.0)
	_block(Vector3(29, 3.5, -20.6), Vector3(5, 1.0, 0.15), Color("e0524f"), 0.0)
	_label("CANTEEN", Vector3(29, 3.5, -20.7), 90, Color.WHITE, PI, 14)
	# Snacks on the counter: samosas, chai glasses, a big kettle.
	for k in 6:
		_block(Vector3(25 + (k % 3) * 0.22, 1.12 + (k / 3) * 0.1, -19.6), Vector3(0.18, 0.1, 0.18), Color("e0a050"), 0.05)
	_block(Vector3(25.3, 1.07, -19.6), Vector3(0.8, 0.02, 0.5), P.METAL, 0.0)
	for k in 5:
		_block(Vector3(27 + k * 0.18, 1.12, -19.6), Vector3(0.08, 0.12, 0.08), Color("c68a5c"), 0.0)
	_block(Vector3(30.5, 1.25, -19.6), Vector3(0.4, 0.4, 0.4), P.METAL, 0.0)
	_block(Vector3(30.75, 1.35, -19.6), Vector3(0.2, 0.06, 0.06), P.METAL, 0.0)
	for k in 3:
		_glass.box(Vector3(32 + k * 0.35, 1.2, -19.6), Vector3(0.26, 0.3, 0.26), Color.WHITE)
		_block(Vector3(32 + k * 0.35, 1.12, -19.6), Vector3(0.22, 0.12, 0.22), [Color("ffd24a"), Color("ff8ab0"), Color("7fe0a0")][k], 0.0)
	# Inside: fridge, shelves, menu board.
	_block(Vector3(33.3, 0.95, -15), Vector3(0.9, 1.9, 0.8), Color("e0524f"), 0.0, true)
	for row in 3:
		_block(Vector3(28, 0.9 + row * 0.5, -14.2), Vector3(4, 0.05, 0.4), P.WOOD_DARK, 0.0)
		for k in 8:
			_block(Vector3(26.3 + k * 0.48, 1.03 + row * 0.5, -14.2), Vector3(0.3, 0.2, 0.25), P.BAGS[(k + row) % P.BAGS.size()], 0.05)
	_block(Vector3(25.2, 1.9, -14.05), Vector3(1.6, 1.0, 0.04), P.BOARD, 0.0)
	_label("SAMOSA   15\nCHAI     10\nMAGGI    30", Vector3(25.2, 1.9, -14.1), 28, P.CHALK, PI, 0)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(29, 2.4, -17)
	lamp.light_color = Color(1.0, 0.9, 0.75)
	lamp.omni_range = 7.0
	_root.add_child(lamp)
	# Tables and plastic chairs outside.
	for tz in [-23.5, -26.0]:
		for tx in [25.0, 29.0, 33.0]:
			_block(Vector3(tx, 0.74, tz), Vector3(1.4, 0.06, 0.9), P.SHIRT, 0.02)
			_block(Vector3(tx, 0.36, tz), Vector3(0.12, 0.72, 0.12), P.METAL, 0.0)
			_collide(Vector3(tx, 0.38, tz), Vector3(1.4, 0.76, 0.9))
			extra_seats.append(Vector3(tx - 0.5, 0, tz - 0.72))
			for sx in [-0.5, 0.5]:
				for sz in [-0.72, 0.72]:
					var chair: Color = [Color("e0524f"), Color("3f86a8"), Color("48b06a")][_rng.randi() % 3]
					_block(Vector3(tx + sx, 0.42, tz + sz), Vector3(0.4, 0.06, 0.4), chair, 0.02)
					_block(Vector3(tx + sx, 0.2, tz + sz), Vector3(0.34, 0.4, 0.34), chair.darkened(0.2), 0.0)
					_block(Vector3(tx + sx, 0.66, tz + sz + signf(sz) * 0.18), Vector3(0.4, 0.44, 0.05), chair, 0.0)


func _parking() -> void:
	_block(Vector3(-28, -0.03, -27), Vector3(12, 0.1, 8), P.ASPHALT, 0.0)
	for k in 7:
		_block(Vector3(-33.5 + k * 1.9, 0.02, -28.2), Vector3(0.08, 0.02, 2.6), P.LINE, 0.0)
	for k in 6:
		var x := -32.55 + k * 1.9
		if _rng.randf() < 0.2:
			continue
		var col: Color = P.BAGS[_rng.randi() % P.BAGS.size()]
		_scooter(Vector3(x, 0, -28.2), col)
	_block(Vector3(-33.5, 1.2, -23.3), Vector3(0.1, 2.4, 0.1), P.METAL_DARK, 0.0)
	_block(Vector3(-33.5, 2.4, -23.3), Vector3(1.6, 0.5, 0.08), Color("3f86a8"), 0.0)
	_label("PARKING", Vector3(-33.5, 2.4, -23.36), 40, Color.WHITE, PI, 0)

	# The principal's shiny car (selfie quest).
	var car := Vector3(-27.5, 0, -24.9)
	_block(car + Vector3(0, 0.55, 0), Vector3(3.6, 0.6, 1.6), Color.WHITE, 0.0, true)
	_block(car + Vector3(0.2, 1.1, 0), Vector3(2.0, 0.55, 1.45), Color("2c3e5a"), 0.0)
	_block(car + Vector3(0.2, 1.4, 0), Vector3(1.9, 0.06, 1.4), Color.WHITE, 0.0)
	for wx in [-1.2, 1.2]:
		for wz in [-0.78, 0.78]:
			_block(car + Vector3(wx, 0.3, wz), Vector3(0.6, 0.6, 0.16), Color("26262e"), 0.0)
	_glow.box(car + Vector3(-1.81, 0.62, 0.55), Vector3(0.02, 0.14, 0.3), P.GLOW)
	_glow.box(car + Vector3(-1.81, 0.62, -0.55), Vector3(0.02, 0.14, 0.3), P.GLOW)
	_block(car + Vector3(1.81, 0.45, 0), Vector3(0.02, 0.18, 0.6), Color("ffd24a"), 0.0)
	_label("PRINCIPAL", car + Vector3(1.83, 0.45, 0), 22, Color("24315e"), PI / 2, 0)
	_interactable("car", car + Vector3(0, 0, -1.5), "Take a selfie with the principal's car")


func _scooter(p: Vector3, col: Color) -> void:
	_block(p + Vector3(0, 0.45, 0.15), Vector3(0.42, 0.4, 0.95), col, 0.02)
	_block(p + Vector3(0, 0.7, 0.3), Vector3(0.36, 0.1, 0.6), Color("26262e"), 0.0)
	_block(p + Vector3(0, 0.6, -0.42), Vector3(0.4, 0.8, 0.14), col, 0.0)
	_block(p + Vector3(0, 1.05, -0.45), Vector3(0.7, 0.06, 0.06), Color("26262e"), 0.0)
	_block(p + Vector3(0, 0.95, -0.52), Vector3(0.2, 0.14, 0.06), col.lightened(0.2), 0.0)
	_glow.box(p + Vector3(0, 0.95, -0.56), Vector3(0.12, 0.08, 0.02), P.GLOW)
	for wz in [-0.5, 0.55]:
		_block(p + Vector3(0, 0.18, wz), Vector3(0.14, 0.36, 0.36), Color("26262e"), 0.0)
		_block(p + Vector3(0, 0.18, wz), Vector3(0.15, 0.16, 0.16), P.METAL, 0.0)
	_collide(p + Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 1.5))


func _court() -> void:
	_block(Vector3(-31, -0.03, -6), Vector3(14, 0.1, 16), P.COURT, 0.0)
	var line := 0.08
	_block(Vector3(-31, 0.025, -13.2), Vector3(12.4, 0.01, line), P.LINE, 0.0)
	_block(Vector3(-31, 0.025, 1.2), Vector3(12.4, 0.01, line), P.LINE, 0.0)
	_block(Vector3(-37.2, 0.025, -6), Vector3(line, 0.01, 14.4), P.LINE, 0.0)
	_block(Vector3(-24.8, 0.025, -6), Vector3(line, 0.01, 14.4), P.LINE, 0.0)
	_block(Vector3(-31, 0.025, -6), Vector3(12.4, 0.01, line), P.LINE, 0.0)
	_block(Vector3(-31, 0.022, -6), Vector3(3.0, 0.01, 3.0), P.COURT.darkened(0.12), 0.0)
	for end in [[-13.6, 1.0], [1.6, -1.0]]:
		var z: float = end[0]
		var dir: float = end[1]
		_block(Vector3(-31, 1.6, z), Vector3(0.16, 3.2, 0.16), P.METAL_DARK, 0.0, true)
		_block(Vector3(-31, 3.1, z + dir * 0.35), Vector3(0.1, 0.1, 0.7), P.METAL_DARK, 0.0)
		# Solid backboard and rim so the ball really bounces off them.
		_block(Vector3(-31, 3.2, z + dir * 0.7), Vector3(1.6, 1.0, 0.06), P.SHIRT, 0.0, true)
		_block(Vector3(-31, 3.05, z + dir * 0.74), Vector3(0.5, 0.4, 0.02), Color("e0524f"), 0.0)
		var ring := z + dir * 1.0
		var rim := Color("ff7a2a")
		_block(Vector3(-31, 2.8, ring - 0.24), Vector3(0.52, 0.035, 0.035), rim, 0.0, true)
		_block(Vector3(-31, 2.8, ring + 0.24), Vector3(0.52, 0.035, 0.035), rim, 0.0, true)
		_block(Vector3(-31.24, 2.8, ring), Vector3(0.035, 0.035, 0.52), rim, 0.0, true)
		_block(Vector3(-30.76, 2.8, ring), Vector3(0.035, 0.035, 0.52), rim, 0.0, true)
		# Net: white strands hanging below the rim.
		for k in 4:
			var nx := -31.18 + k * 0.12
			_block(Vector3(nx, 2.62, ring - 0.2), Vector3(0.015, 0.34, 0.015), Color.WHITE, 0.0)
			_block(Vector3(nx, 2.62, ring + 0.2), Vector3(0.015, 0.34, 0.015), Color.WHITE, 0.0)


func _plaza() -> void:
	_tiles(Rect2(-12, -12, 24, 7.6), 1.0, P.STONE, P.STONE_DARK)
	_tiles(Rect2(-2, -33, 4, 21), 1.0, P.STONE, P.STONE_DARK)

	# Founder's statue.
	_block(Vector3(0, 0.15, -8.2), Vector3(2.4, 0.3, 2.4), P.STONE_DARK, 0.0, true)
	_block(Vector3(0, 0.85, -8.2), Vector3(1.2, 1.1, 1.2), P.STONE, 0.0, true)
	var bronze := Color("b08a4a")
	_block(Vector3(0, 1.75, -8.2), Vector3(0.9, 0.7, 0.5), bronze, 0.03)
	_block(Vector3(0, 2.3, -8.2), Vector3(0.5, 0.5, 0.45), bronze.lightened(0.05), 0.0)
	_block(Vector3(0, 2.58, -8.2), Vector3(0.52, 0.1, 0.47), bronze.darkened(0.1), 0.0)
	_block(Vector3(0, 2.1, -8.46), Vector3(0.2, 0.04, 0.02), bronze.darkened(0.25), 0.0)
	_label("OUR FOUNDER\nDame Beatrix Quibble", Vector3(0, 0.85, -8.82), 26, Color("3a2d26"), PI, 0)

	# Flagpole with the college flag.
	_block(Vector3(-7, 0.2, -8.5), Vector3(1.2, 0.4, 1.2), P.STONE_DARK, 0.0, true)
	_block(Vector3(-7, 3.4, -8.5), Vector3(0.1, 6.2, 0.1), P.SHIRT, 0.0)
	_block(Vector3(-6.4, 6.0, -8.5), Vector3(1.2, 0.26, 0.04), Color("24315e"), 0.0)
	_block(Vector3(-6.4, 5.74, -8.5), Vector3(1.2, 0.26, 0.04), Color("ffd24a"), 0.0)
	_block(Vector3(-6.4, 5.48, -8.5), Vector3(1.2, 0.26, 0.04), Color("24315e"), 0.0)

	# Benches.
	for spec in [[-8.0, -11.3], [8.0, -11.3], [-4.5, -11.3], [4.5, -11.3]]:
		_park_bench(Vector3(spec[0], 0, spec[1]))

	# Lamp posts along the gate path.
	for z in [-30.0, -25.0, -20.0, -15.0]:
		for x in [-2.7, 2.7]:
			_block(Vector3(x, 1.6, z), Vector3(0.12, 3.2, 0.12), P.METAL_DARK, 0.0, true)
			_block(Vector3(x, 0.15, z), Vector3(0.3, 0.3, 0.3), P.METAL_DARK, 0.0)
			_block(Vector3(x - signf(x) * 0.3, 3.2, z), Vector3(0.7, 0.06, 0.06), P.METAL_DARK, 0.0)
			_block(Vector3(x - signf(x) * 0.6, 3.12, z), Vector3(0.36, 0.14, 0.26), P.METAL_DARK, 0.0)
			_glow.box(Vector3(x - signf(x) * 0.6, 3.04, z), Vector3(0.28, 0.03, 0.2), P.GLOW)

	# Flower beds on the plaza corners.
	for c: Vector2 in [Vector2(-10.5, -6), Vector2(10.5, -6)]:
		_block(Vector3(c.x, 0.15, c.y), Vector3(2.2, 0.3, 2.2), P.STONE_DARK, 0.0, true)
		_block(Vector3(c.x, 0.3, c.y), Vector3(1.9, 0.04, 1.9), Color("5a3a22"), 0.0)
		for k in 14:
			var fx := c.x + _rng.randf_range(-0.8, 0.8)
			var fz := c.y + _rng.randf_range(-0.8, 0.8)
			_vbox(Vector3(fx, 0.42, fz), Vector3(0.04, 0.22, 0.04), P.GRASS_DARK)
			_vbox(Vector3(fx, 0.55, fz), Vector3(0.14, 0.1, 0.14), P.FLOWERS[_rng.randi() % P.FLOWERS.size()])


func _park_bench(p: Vector3) -> void:
	for sx in [-0.7, 0.7]:
		_block(p + Vector3(sx, 0.22, 0), Vector3(0.14, 0.44, 0.5), P.STONE_DARK, 0.0)
	for k in 3:
		_block(p + Vector3(0, 0.47, -0.16 + k * 0.16), Vector3(1.8, 0.05, 0.13), P.WOOD, 0.04)
	_block(p + Vector3(0, 0.78, 0.26), Vector3(1.8, 0.3, 0.06), P.WOOD, 0.04)
	for sx in [-0.7, 0.7]:
		_block(p + Vector3(sx, 0.68, 0.26), Vector3(0.1, 0.5, 0.08), P.STONE_DARK, 0.0)
	_collide(p + Vector3(0, 0.25, 0), Vector3(1.8, 0.5, 0.5))


# --- Trees, bushes, clouds ------------------------------------------------------------

func _trees_and_bushes() -> void:
	var inside := [
		Vector2(-16, -8), Vector2(16, -6), Vector2(-18, -20), Vector2(-10, -24), Vector2(12, -24),
		Vector2(18, -29), Vector2(-36, -20), Vector2(-37, 20), Vector2(-26, 20), Vector2(-20, 18),
		Vector2(-8, 14), Vector2(4, 18), Vector2(18, 14), Vector2(29, 20.5), Vector2(36, 11),
		Vector2(22, 20), Vector2(36, -6), Vector2(-25, 16), Vector2(38.5, -9), Vector2(-15, -29),
		Vector2(37, -30), Vector2(-37, -2), Vector2(8, 12), Vector2(-14, 21),
	]
	for p in inside:
		_tree(Vector3(p.x, 0, p.y), _rng.randi() % 3)

	# Hedge behind the building and bushes around.
	for k in 18:
		_bush(Vector3(-19 + k * 2.2, 0, 9.4), 1.0)
	for k in 30:
		var bx := _rng.randf_range(-38, 38)
		var bz := _rng.randf_range(-30, 22)
		if _is_paved(bx, bz) or _is_paved(bx + 1, bz + 1) or _is_paved(bx - 1, bz - 1):
			continue
		_bush(Vector3(bx, 0, bz), _rng.randf_range(0.7, 1.2))


func _tree(p: Vector3, kind: int) -> void:
	var trunk_h := _rng.randf_range(1.4, 2.4)
	var leaf: Color = P.LEAVES[_rng.randi() % P.LEAVES.size()]
	_block(p + Vector3(0, trunk_h / 2.0, 0), Vector3(0.38, trunk_h, 0.38), P.TRUNK, 0.03)
	_block(p + Vector3(0, 0.08, 0), Vector3(0.6, 0.16, 0.6), P.TRUNK.darkened(0.1), 0.0)
	_collide(p + Vector3(0, 1.25, 0), Vector3(0.45, 2.5, 0.45))
	match kind:
		0: # round canopy
			var s := _rng.randf_range(1.8, 2.6)
			_vbox(p + Vector3(0, trunk_h + s * 0.35, 0), Vector3(s, s * 0.8, s), leaf, 0.04)
			for k in 3:
				var off := Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(0.2, 0.9), _rng.randf_range(-0.7, 0.7)) * s * 0.5
				_vbox(p + Vector3(0, trunk_h + s * 0.35, 0) + off, Vector3.ONE * s * _rng.randf_range(0.45, 0.65), leaf.lightened(_rng.randf_range(0.0, 0.12)), 0.04)
		1: # pine: stacked shrinking layers
			var width := _rng.randf_range(2.0, 2.6)
			var y := trunk_h * 0.6
			for k in 4:
				_vbox(p + Vector3(0, y + 0.3, 0), Vector3(width, 0.6, width), leaf.darkened(0.08 - k * 0.04), 0.03)
				y += 0.55
				width *= 0.72
			_vbox(p + Vector3(0, y + 0.3, 0), Vector3(0.3, 0.5, 0.3), leaf.lightened(0.1), 0.0)
		_: # tall two-tier canopy
			_block(p + Vector3(0, trunk_h + 0.9, 0), Vector3(0.3, 1.8, 0.3), P.TRUNK, 0.03)
			_vbox(p + Vector3(0, trunk_h + 0.6, 0), Vector3(2.4, 0.9, 2.4), leaf, 0.04)
			_vbox(p + Vector3(0, trunk_h + 1.8, 0), Vector3(1.8, 1.0, 1.8), leaf.lightened(0.08), 0.04)
			_vbox(p + Vector3(0.4, trunk_h + 2.6, -0.2), Vector3(1.0, 0.7, 1.0), leaf.lightened(0.14), 0.04)


func _clouds() -> void:
	var v := Voxel.new(99)
	for k in int(world_rect.get_area() / 2400.0):
		var c := Vector3(_rng.randf_range(world_rect.position.x, world_rect.end.x), _rng.randf_range(32, 48),
				_rng.randf_range(world_rect.position.y, world_rect.end.y))
		var parts := _rng.randi_range(3, 5)
		for i in parts:
			var size := Vector3(_rng.randf_range(4, 9), _rng.randf_range(1.6, 2.8), _rng.randf_range(3, 6))
			var off := Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-2.5, 2.5))
			v.box(c + off, size, P.CLOUD, 0.02)
	clouds = v.to_instance()
	clouds.name = "Clouds"
	(clouds as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(clouds)
