extends "res://scenes/world/maps/academic_kit.gd"
## Whispering Pines: a university lost in a pine forest. A river cuts the
## grounds in two; get across it (road bridge with a ranger, a rope bridge far
## west, or stepping stones east) and then out through the fence: the guarded
## south checkpoint, the old logging gate (crouch) or where a tree crushed the
## east fence (jump the trunk). North, a creek culvert (crouch) is close but watched.
##
## The university is Pinewood Lodges: two long timber lodges joined by the
## Great Hall (an H, two storeys) at x -60..60, z -44..32.
##
## Top view: lodges at x -60..60, z -44..32; fence at x ±220, z -300 and 80.

const RIVER := Rect2(-250, -192, 500, 18)
const ROAD_BRIDGE := Rect2(-38, -193, 6, 20)
const ROPE_BRIDGE := Rect2(-205, -193, 2.4, 20)
const GATE_X := -35.0
const LOG_GATE := [-261.2, -259.6]
const FALLEN := [-242.0, -238.0]
const CULVERT := [99.2, 100.8]

const CABINS := [
	Vector2(-170, -20), Vector2(-150, -20), Vector2(-130, -20), Vector2(-110, -20),
	Vector2(-170, 6), Vector2(-150, 6), Vector2(-130, 6), Vector2(-110, 6),
]
# [rect, floors, wall, trim, title, front]
const BUILDINGS := [
	[Rect2(100, -52, 30, 22), 2, Color("eef3ee"), Color("24315e"), "OBSERVATORY", Vector2(0, -1)],
	[Rect2(-96, -248, 28, 18), 2, Color("b88a5a"), Color("3a4a2a"), "RANGER STATION", Vector2(1, 0)],
	[Rect2(-150, -130, 36, 20), 2, Color("e8d5c4"), Color("5a7a3a"), "FORESTRY SCHOOL", Vector2(0, 1)],
	[Rect2(50, -150, 30, 20), 1, Color("c9b48f"), Color("7a4a2a"), "DINING LODGE", Vector2(0, -1)],
]


func _plan() -> void:
	c.bounds = Rect2(-220, -300, 440, 380)
	c.world_rect = Rect2(-250, -330, 500, 440)
	c.goal_text = "ESCAPE THE UNIVERSITY!  Cross the river, get through the forest fence.  [M] map"
	c.win_text = "The bus to the city is right on time."
	map_rect(c.world_rect, Color("4f8f45"))
	map_rect(Rect2(-180, -32, 84, 56), Color("78b457"), "Cabins")
	# Gravel road from the academic gate to the south checkpoint, split around the river.
	c.academic_rect = Rect2(-62, -46, 124, 80)
	trail(Rect2(-3, -116, 6, 70))
	trail(Rect2(-20, -50, 40, 6))                   # forecourt of the south lodge
	walk(Rect2(30, -68, 24, 14), DIRT, DIRT_DARK, "Parking")
	trail(Rect2(-38, -116, 41, 6))
	trail(Rect2(-38, -174, 6, 58))
	trail(Rect2(-38, -300, 6, 108))
	trail(Rect2(-38, -310, 6, 10))
	road(Rect2(-250, -320, 500, 10), true)
	# Footpaths.
	# Forest trails wander (only the lodge forecourt stays straight).
	curve_trail([Vector2(-3, -49)] + wander(Vector2(-62, -49), Vector2(-160, -49), 4.0))  # to the cabins
	curve_trail(wander(Vector2(3, -70), Vector2(115, -70), 4.0))  # to the observatory
	trail(Rect2(10, 32.5, 3, 32))                   # north lodge -> north woods
	curve_trail(wander(Vector2(11.5, 63.5), Vector2(100, 63.5), 3.0))
	trail(Rect2(98.5, 62, 3, 18))                   # -> creek culvert
	curve_trail(wander(Vector2(-38, -260.5), Vector2(-221, -260.4), 4.0))  # south bank -> logging gate
	curve_trail(wander(Vector2(-32, -240.5), Vector2(221, -240), 5.0))  # south bank -> fallen tree
	curve_trail(wander(Vector2(-35, -155), Vector2(80, -155), 2.5))  # road -> dining lodge
	walk(Rect2(52, -104, 16, 16), DIRT, DIRT_DARK, "Campfire")
	water(RIVER, Vector3.ZERO, "River", Vector2(0, 1))
	bridge_area(ROAD_BRIDGE)
	bridge_area(ROPE_BRIDGE)
	keep_clear(Rect2(-250, -198, 500, 36))           # banks and the river patrol path
	keep_clear(Rect2(-220, -296, 440, 8))            # patrol track inside the south fence
	keep_clear(Rect2(-180, -32, 84, 56))            # cabin clearing
	for b in BUILDINGS:
		reserve((b[0] as Rect2).grow(0.6))
		map_rect(b[0], (b[2] as Color).darkened(0.3), (b[4] as String).capitalize(), false, "building")
	for p: Vector2 in CABINS:
		reserve(Rect2(p.x - 4, p.y - 3, 8, 6))
		map_rect(Rect2(p.x - 4, p.y - 3, 8, 6), Color("8a5a3a"), "", false, "building")


func _build() -> void:
	lay_paving()
	lay_water()
	_lodges()
	for b in BUILDINGS:
		building(b[0], b[1], b[2], b[3], b[4], b[5])
	_fences()
	_river_crossings()
	_cabins()
	_observatory_dome()
	_campfire(Vector2(60, -96))
	_outside()
	for t in [Vector2(-120, -160), Vector2(110, -162), Vector2(70, 50), Vector2(-150, -280), Vector2(150, -285)]:
		_watchtower(t)
	_staff_and_students()
	_nav()
	# The forest itself: mostly pines, thick everywhere that isn't a path.
	forest(Rect2(-248, -328, 496, 436), 2300, [1, 1, 1, 0, 2])
	bushes(Rect2(-220, -300, 440, 380), 700)
	for k in 160:
		var at := Vector2(rng.randf_range(-215, 215), rng.randf_range(-295, 75))
		if free_at(at.x, at.y) and free_at(at.x + 1.5, at.y + 1.5):
			rock(at, rng.randf_range(0.8, 1.8))
	flowers(Rect2(-220, -300, 440, 380), 700)


## Pinewood Lodges: south and north lodges joined by the Great Hall, two storeys of timber.
func _lodges() -> void:
	begin_campus()
	style = {
		"wall": Color("d9a86a"), "trim": Color("5a3a22"), "floor": [Color("c9955c"), Color("b8844e")],
		"hall": [Color("8a5a3a"), Color("7a4a2a")], "dado_in": Color("7a9a5a"), "dado_hall": Color("5a3a22"),
		"dado_out": Color("5a3a22"), "frame": Color("3a4a2a"), "roof": Color("3f5a3a"), "ceiling": Color("e8d5b0"),
	}
	# South lodge: the entrance faces the trail to the checkpoint.
	wing(Rect2(-60, -44, 120, 20), true, 2, [
		[["staff", 12], ["washroom", 8], ["office", 10], ["computer", 12], ["empty", 8.2, {"kids": true}], ["lobby", 10, {"gate": true, "name": "Pinewood Lodges"}],
			["class", 10, {"idx": 0}], ["detention", 8], ["music", 12], ["store", 23.2]],
		[["empty", 10], ["empty", 10, {"kids": true}], ["computer", 12], ["art", 12], ["washroom", 8], ["empty", 13.2],
			["class", 10, {"idx": 1}], ["empty", 10], ["store", 25.2]],
	], [
		[["empty", 10], ["passage", 6], ["lecture", 18], ["empty", 10], ["store", 11], ["passage", 10], ["art", 12], ["passage", 6], ["empty", 10], ["store", 27]],
		[["lecture", 18], ["empty", 10], ["empty", 10], ["music", 12], ["store", 70]],
	], {"title": c.UNI_NAME, "front": "a", "cams": [0, 1]})
	# North lodge.
	wing(Rect2(-60, 12, 120, 20), true, 2, [
		[["empty", 10], ["passage", 6], ["washroom", 8], ["lab", 10, {"idx": 3}], ["store", 8.2], ["passage", 10], ["computer", 12], ["passage", 6], ["empty", 10], ["store", 30]],
		[["empty", 10, {"kids": true}], ["art", 12], ["washroom", 8], ["empty", 12.2], ["class", 10, {"idx": 2}], ["empty", 10], ["store", 48]],
	], [
		[["lecture", 18], ["empty", 10], ["music", 12], ["empty", 10], ["store", 70]],
		[["empty", 10], ["lecture", 18], ["empty", 10], ["store", 82]],
	], {"ends": [true, true], "title": "SOUTH LODGE", "front": "b", "cams": [1]})
	# The Great Hall between them: canteen and library.
	wing(Rect2(-10, -23.6, 20, 35.2), false, 2, [
		[["passage", 6], ["canteen", 15.6]],
		[["empty", 12], ["store", 9.6]],
	], [
		[["library", 14], ["passage", 6], ["lecture", 15.2]],
		[["lecture", 18], ["store", 17.2]],
	], {"ends": [false, false], "notice": false, "alarm": false})
	service_door(Vector3(60.0, 0, 22.0), false)
	# Yards either side of the hall.
	court(Vector2(-35, -6))
	assembly_point(Vector2(35, -6))
	_campfire(Vector2(45, 4))
	for p: Vector2 in [Vector2(-52, -18), Vector2(-52, 6), Vector2(-18, 6), Vector2(20, -18), Vector2(54, 6), Vector2(24, 6)]:
		tree(p, 1)
	for x: float in [20.0, 28.0]:
		bench(Vector2(x, -14))
	principal_car(Vector2(40, -61))
	nav_line(Vector2(-58, -6), Vector2(-12, -6))
	nav_line(Vector2(12, -6), Vector2(58, -6))
	nav_line(Vector2(-12, -21), Vector2(-12, 9))
	nav_line(Vector2(12, -21), Vector2(12, 9))
	c.staff_loops = {
		"peon": [Vector3(-54, 0, -34), Vector3(54, 0, -34), Vector3(0, 0, -34), Vector3(0, 0, 0), Vector3(0, 0, -34)],
		"prefect": [Vector3(-56, 0, -6), Vector3(-14, 0, -6), Vector3(-14, 0, 8), Vector3(-56, 0, 8)],
		"proctor": [Vector3(-54, 3.6, 22), Vector3(54, 3.6, 22)],
		"vp": [Vector3(-54, 3.6, -34), Vector3(54, 3.6, -34), Vector3(14, 0, -6), Vector3(56, 0, -6)],
	}
	c.core_walks = [
		[Vector3(-50, 0, -34), Vector3(50, 0, -34)],
		[Vector3(-50, 0, 22), Vector3(50, 0, 22)],
		[Vector3(14, 0, -18), Vector3(56, 0, -18), Vector3(56, 0, 8), Vector3(14, 0, 8)],
		[Vector3(-50, 3.6, -34), Vector3(50, 3.6, -34)],
	]
	finish_campus()


func _fences() -> void:
	var gate_gap := [[GATE_X - 5.4, GATE_X + 5.4]]
	fence(true, -220, 220, -300, [], gate_gap)
	fence(true, -220, 220, 80, [CULVERT])
	fence(false, -300, 80, -220, [LOG_GATE])
	fence(false, -300, 80, 220, [], [FALLEN])
	# South checkpoint.
	gate(Vector2(GATE_X, -300), true, 8.0, Vector2(0, -1), c.UNI_NAME, "Mind the bears!")
	booth(Vector2(GATE_X + 9, -294))
	barrier(Vector2(GATE_X - 3.2, -297))
	var zone := Rect2(GATE_X - 14, -310, 28, 22)
	post("GateGuard1", "Officer Novak (Checkpoint)", Vector2(GATE_X - 6.6, -295), Vector2(0, 1), zone, 401)
	post("GateGuard2", "Officer Ansah (Checkpoint)", Vector2(GATE_X + 6.6, -297), Vector2(-0.3, 1), zone, 402)
	camera(Vector2(GATE_X - 6, -299), 4.2, facing(Vector2(0.3, 1)), 0.6, 0.35)
	# Old logging gate: rotten planks, a gap underneath.
	for k in 5:
		box(Vector3(-220.4, 1.5 + k * 0.35, -260.4), Vector3(0.12, 0.25, 3.4), P.WOOD.darkened(0.2 + 0.05 * (k % 2)), 0.05)
	for dz: float in [-1.8, 1.8]:
		box(Vector3(-220.4, 1.6, -260.4 + dz), Vector3(0.22, 3.2, 0.22), P.TRUNK, 0.03)
	signpost(Vector2(-214, -265), "OLD LOGGING ROAD\nCLOSED", facing(Vector2(1, 0)), Color("7a4a2a"))
	# A pine fell across the east fence: jump the trunk.
	box(Vector3(219, 0.36, -240), Vector3(14, 0.72, 0.8), P.TRUNK, 0.03, true)
	box(Vector3(213, 0.9, -240.3), Vector3(1.6, 0.6, 1.8), P.LEAVES[1], 0.04)
	for k in 4:
		box(Vector3(224 + k * 1.2, 0.8 + k * 0.1, -240 + (k % 2) * 0.6 - 0.3), Vector3(1.4, 1.2, 2.2), P.LEAVES[k % 4], 0.04)
	box(Vector3(220, 0.2, -238.6), Vector3(0.2, 0.4, 1.8), IRON, 0.0)
	# Creek culvert under the north fence.
	var concrete := Color("a9a79f")
	for side: float in [-1.0, 1.0]:
		box(Vector3(100 + side * 1.0, 0.65, 80), Vector3(0.3, 1.3, 4.0), concrete, 0.02, true)
	box(Vector3(100, 0.03, 80), Vector3(1.6, 0.04, 4.0), Color("6a8a7a"), 0.0)
	camera(Vector2(106, 76), 4.0, facing(Vector2(-1, -0.3)), 0.7, 0.4)
	exit_marker(Vector2(GATE_X, -304), "North checkpoint (guarded)")
	exit_marker(Vector2(-221, -260.4), "Logging gate (crouch)")
	exit_marker(Vector2(221, -240), "Fallen tree (jump)")
	exit_marker(Vector2(100, 81), "Creek culvert (crouch)")


func _river_crossings() -> void:
	bridge(ROAD_BRIDGE, false, true, P.WOOD)
	var zone := Rect2(-46, -176, 22, 12)
	post("BridgeRanger", "Ranger Kim (Bridge)", Vector2(-41.5, -169), Vector2(0.2, 1), zone, 403)
	camera(Vector2(-31, -172), 3.6, facing(Vector2(-0.2, 1)), 0.8, 0.3)
	signpost(Vector2(-42, -166), "RIVER PATROL\nSTUDENTS NEED A PASS", facing(Vector2(0, 1)), Color("5a7a3a"))
	# Rope bridge: planks, no rails, far away from everything.
	bridge(ROPE_BRIDGE, false, false, P.WOOD.lightened(0.1))
	for z: float in [-194.0, -172.0]:
		for x: float in [-205.2, -202.4]:
			box(Vector3(x, 0.9, z), Vector3(0.2, 1.8, 0.2), P.WOOD_DARK, 0.0, true)
	for x: float in [-205.2, -202.4]:
		box(Vector3(x, 1.2, -183), Vector3(0.05, 0.05, 22), Color("c9a25a"), 0.0)
	# Stepping stones: jump from one to the next.
	var pts := []
	for k in 9:
		pts.append(Vector2(150 + sin(k * 1.3) * 1.2, -174.5 - k * 2.1))
	stones(pts, 1.25)
	signpost(Vector2(146, -168), "STEPPING STONES\nAT YOUR OWN RISK", facing(Vector2(0, 1)), Color("3f86a8"))


func _cabins() -> void:
	for p: Vector2 in CABINS:
		var base := Vector3(p.x, 0, p.y)
		box(base + Vector3(0, 1.4, 0), Vector3(8, 2.8, 6), P.WOOD, 0.03, true)
		for k in 6:
			box(base + Vector3(0, 0.25 + k * 0.46, -3.02), Vector3(8.04, 0.08, 0.04), P.WOOD_DARK, 0.0)
		box(base + Vector3(0, 3.0, 0), Vector3(8.8, 0.3, 6.8), Color("7a3a2a"), 0.02)
		box(base + Vector3(0, 3.4, 0), Vector3(7.2, 0.5, 5.2), Color("8a4a32"), 0.02)
		box(base + Vector3(0, 3.8, 0), Vector3(5.0, 0.4, 3.2), Color("7a3a2a"), 0.02)
		box(base + Vector3(-2, 1.1, -3.04), Vector3(1.1, 2.1, 0.06), P.WOOD_DARK, 0.0)
		for wx: float in [1.0, 2.8]:
			if rng.randf() < 0.3:
				glow(base + Vector3(wx, 1.6, -3.04), Vector3(0.9, 0.8, 0.04))
			else:
				box(base + Vector3(wx, 1.6, -3.04), Vector3(0.9, 0.8, 0.04), GLASS, 0.0)
		box(base + Vector3(3.2, 3.6, 1.5), Vector3(0.6, 1.4, 0.6), P.STONE_DARK, 0.0)
		# Hide in the woodshed.
		box(base + Vector3(-4.6, 0.6, 1.5), Vector3(1.0, 1.2, 2.0), P.WOOD_DARK, 0.03, true)
	signpost(Vector2(-100, -36), "CABINS\nlights out at 10", facing(Vector2(0, -1)), Color("7a4a2a"))


func _observatory_dome() -> void:
	var p := Vector3(115, 6.8, -41)
	for k in 4:
		var s := 12.0 - k * 2.8
		box(p + Vector3(0, k * 1.0, 0), Vector3(s, 1.0, s), Color("f4f4f0").darkened(0.03 * k), 0.0)
	box(p + Vector3(0, 2.2, -2.5), Vector3(1.2, 1.6, 6.0), Color("2c2e36"), 0.0)
	box(p + Vector3(0, 3.1, -4.6), Vector3(0.6, 0.6, 2.4), P.METAL, 0.0)


func _campfire(at: Vector2) -> void:
	var p := Vector3(at.x, 0, at.y)
	for k in 6:
		var a := k * TAU / 6.0
		box(p + Vector3(cos(a) * 0.7, 0.12, sin(a) * 0.7), Vector3(0.4, 0.24, 0.4), P.STONE_DARK, 0.03)
	box(p + Vector3(0, 0.07, 0), Vector3(0.8, 0.14, 0.14), P.TRUNK, 0.0)
	box(p + Vector3(0, 0.18, 0), Vector3(0.14, 0.14, 0.8), P.TRUNK, 0.0)
	glow(p + Vector3(0, 0.45, 0), Vector3(0.36, 0.4, 0.36))
	var fire := OmniLight3D.new()
	fire.position = p + Vector3(0, 0.8, 0)
	fire.light_color = Color(1.0, 0.6, 0.3)
	fire.omni_range = 6.0
	c._root.add_child(fire)
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var q := p + d * 3.2
		box(q + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 2.6) if d.x != 0 else Vector3(2.6, 0.5, 0.5), P.TRUNK, 0.03, true)


func _watchtower(at: Vector2) -> void:
	var p := Vector3(at.x, 0, at.y)
	var h := 6.0
	for dx: float in [-1.3, 1.3]:
		for dz: float in [-1.3, 1.3]:
			box(p + Vector3(dx, h / 2.0, dz), Vector3(0.24, h, 0.24), P.WOOD_DARK, 0.02, true)
	box(p + Vector3(0, h, 0), Vector3(3.4, 0.2, 3.4), P.WOOD, 0.02, true)
	for side: float in [-1.0, 1.0]:
		box(p + Vector3(side * 1.65, h + 0.5, 0), Vector3(0.1, 0.8, 3.4), P.WOOD_DARK, 0.0)
		box(p + Vector3(0, h + 0.5, side * 1.65), Vector3(3.4, 0.8, 0.1), P.WOOD_DARK, 0.0)
	box(p + Vector3(0, h + 2.4, 0), Vector3(4.0, 0.2, 4.0), Color("7a3a2a"), 0.02)
	for dx: float in [-1.6, 1.6]:
		for dz: float in [-1.6, 1.6]:
			box(p + Vector3(dx, h + 1.2, dz), Vector3(0.14, 2.2, 0.14), P.WOOD_DARK, 0.0)
	for k in 12:
		box(p + Vector3(0, 0.3 + k * 0.5, -1.45), Vector3(0.8, 0.06, 0.06), P.WOOD_DARK, 0.0)
	for sx: float in [-0.43, 0.43]:
		box(p + Vector3(sx, h / 2.0, -1.45), Vector3(0.06, h, 0.06), P.WOOD_DARK, 0.0)
	# The camera sweeps all the way round.
	c.add_cctv(p + Vector3(0, h + 1.9, 0), rng.randf() * TAU, PI, 0.18, p.y)  # bracket up to the roof; watches the ground


func _outside() -> void:
	signpost(Vector2(GATE_X + 10, -325), "BUS STOP\nCITY 12 KM", facing(Vector2(0, 1)), Color("3f86a8"))
	box(Vector3(GATE_X + 14, 1.3, -326), Vector3(4.0, 0.12, 1.6), P.METAL, 0.0)
	box(Vector3(GATE_X + 14, 0.45, -326.2), Vector3(3.4, 0.1, 0.5), P.WOOD, 0.0, true)
	for dx: float in [-1.5, 1.5]:
		box(Vector3(GATE_X + 14 + dx, 0.2, -326.2), Vector3(0.1, 0.4, 0.4), P.METAL, 0.0)
	bus(Vector2(60, -315), true, Color("48b06a"), "CITY 7")
	for k in 3:
		car(Vector2(-120 + k * 70, -313 + (k % 2) * 5), true, [Color("e0524f"), Color("f4f4f0"), Color("3f86a8")][k])


func _staff_and_students() -> void:
	patrol("Ranger1", "Ranger Okoye", [Vector2(-212, -166), Vector2(-60, -166)], 1.8, 5.0, 15.0, "ranger")
	patrol("Ranger2", "Ranger Nakamura", [Vector2(-20, -166), Vector2(212, -166)], 1.8, 5.0, 15.0, "ranger")
	patrol("Ranger3", "Ranger Duarte", [Vector2(-212, -292), Vector2(-60, -292), Vector2(-35, -250), Vector2(212, -292)], 1.8, 5.2, 15.0, "ranger")
	patrol("Keeper", "Groundskeeper Bello", [Vector2(13, 63.5), Vector2(96, 63.5), Vector2(100, 74), Vector2(11.5, 40)], 1.5, 4.6, 13.0, "builder")
	patrol("Warden", "Warden Castillo", [Vector2(-104, -49), Vector2(-176, -49), Vector2(-176, 20), Vector2(-104, 20)], 1.5, 4.6, 13.0, "teacher")
	patrol("Professor", "Prof. Adeyemi", [Vector2(0, -60), Vector2(0, -113), Vector2(-35, -113), Vector2(-35, -154), Vector2(40, -154)], 1.4, 4.4, 12.0, "teacher")
	stroll([Vector2(0, -50), Vector2(0, -110)])
	stroll([Vector2(-60, -49), Vector2(-150, -49)])
	stroll([Vector2(20, -70), Vector2(100, -70)])
	stroll([Vector2(54, -102), Vector2(66, -102), Vector2(66, -90), Vector2(54, -90)])
	stroll([Vector2(-35, -154), Vector2(60, -154)])


func _nav() -> void:
	nav_line(Vector2(0, -47), Vector2(0, -113))
	nav_line(Vector2(-64, -48), Vector2(64, -48))
	nav_line(Vector2(-64, -48), Vector2(-64, 34))
	nav_line(Vector2(64, -48), Vector2(64, 34))
	nav_line(Vector2(-64, 34), Vector2(64, 34))
	nav_line(Vector2(0, -113), Vector2(-35, -113))
	nav_line(Vector2(-35, -113), Vector2(-35, -174))
	nav_line(Vector2(-35, -174), Vector2(-35, -192), 6.0)
	nav_line(Vector2(-35, -192), Vector2(-35, -310))
	nav_line(Vector2(-3, -49), Vector2(-160, -49))
	nav_line(Vector2(3, -70), Vector2(115, -70))
	nav_line(Vector2(11.5, 34), Vector2(11.5, 63.5))
	nav_line(Vector2(11.5, 63.5), Vector2(100, 63.5))
	nav_line(Vector2(100, 63.5), Vector2(100, 78))
	nav_line(Vector2(-35, -154), Vector2(80, -154))
	nav_line(Vector2(-212, -166), Vector2(212, -166))
	nav_line(Vector2(-203.8, -166), Vector2(-203.8, -198), 6.0)
	nav_line(Vector2(-218, -260.5), Vector2(-38, -260.5))
	nav_line(Vector2(-32, -240.5), Vector2(218, -240.5))
	nav_line(Vector2(-212, -292), Vector2(212, -292), 12.0)
	nav_line(Vector2(-212, -200), Vector2(212, -200), 12.0)
	nav_line(Vector2(-176, -40), Vector2(-176, 20))
	nav_line(Vector2(-104, -40), Vector2(-104, 20))
	nav_line(Vector2(-176, 20), Vector2(-104, 20))
