extends "res://scenes/world/maps/academic_kit.gd"
## Downtown Campus: the university takes up whole city blocks of towers, fenced
## off from the streets around it. Ways out: the south checkpoint (two guards),
## the west checkpoint (one guard), the metro station inside the campus
## (a transit officer) or a torn fence behind the bins in the north alley (crouch).
##
## The university is Quibble Towers: two six-storey towers (x -46..46,
## z -32..-12 and 10..30) with a sunken courtyard between them. Classes are
## spread from the first floor to the fifth: a long way down.
##
## Top view: towers at x -46..46, z -32..30; fence at x ±190, z -250 and 60.

const METRO := Rect2(44, -214, 14, 10)
const METRO_IN := Rect2(45, -213.5, 12, 5.5)
const ALLEY := [-151.0, -149.4]
const WEST_GAP := [-95.0, -85.0]

# [rect, floors, wall, trim, title, front]
const BUILDINGS := [
	[Rect2(-178, -80, 56, 40), 8, Color("dfe6ea"), Color("24315e"), "SCHOOL OF LAW", Vector2(1, 0)],
	[Rect2(-178, -24, 56, 50), 4, Color("c9ccd2"), Color("4a4f5a"), "CAR PARK", Vector2(1, 0)],
	[Rect2(-100, -80, 48, 34), 3, Color("f2d7a0"), Color("e0524f"), "STUDENT UNION", Vector2(0, -1)],
	[Rect2(52, -80, 48, 34), 10, Color("eef3ee"), Color("2f6fd6"), "ENGINEERING TOWER", Vector2(0, -1)],
	[Rect2(122, -80, 56, 40), 12, Color("bfe3ea"), Color("24315e"), "BUSINESS SCHOOL", Vector2(-1, 0)],
	[Rect2(122, -24, 56, 50), 3, Color("f3e3c3"), Color("9a62d6"), "SPORTS ARENA", Vector2(-1, 0)],
	[Rect2(-178, -160, 56, 56), 7, Color("f4f4f0"), Color("48b06a"), "MEDICAL SCHOOL", Vector2(1, 0)],
	[Rect2(14, -160, 40, 36), 4, Color("ffc9d6"), Color("8a2a3a"), "ARTS CENTRE", Vector2(-1, 0)],
	[Rect2(122, -160, 56, 56), 6, Color("c9d6e8"), Color("3a3d47"), "DATA CENTRE", Vector2(-1, 0)],
	[Rect2(-178, -240, 56, 56), 9, Color("f2c9a0"), Color("8a4b2a"), "WEST DORMS", Vector2(1, 0)],
	[Rect2(-96, -236, 70, 30), 5, Color("f3e3c3"), Color("d9774f"), "ADMINISTRATION", Vector2(0, 1)],
	[Rect2(122, -240, 56, 56), 9, Color("e8d5c4"), Color("2f6a4a"), "EAST DORMS", Vector2(-1, 0)],
	[Rect2(70, -160, 30, 24), 2, Color("fff0c9"), Color("f2a93b"), "CAFETERIA", Vector2(0, -1)],
]
const QUAD := Rect2(-100, -162, 88, 64)


func _plan() -> void:
	c.bounds = Rect2(-190, -250, 380, 310)
	c.world_rect = Rect2(-240, -300, 480, 410)
	c.escape_rects.append(METRO_IN)
	c.goal_text = "ESCAPE THE UNIVERSITY!  A checkpoint, the back alley, or the metro.  [M] map"
	c.win_text = "Lost in the city crowd. Nobody takes attendance here."
	map_rect(c.world_rect, Color("b9b6b0"))
	map_rect(c.bounds, Color("78b457"))
	# Campus streets (closed to traffic).
	c.academic_rect = Rect2(-48, -44, 96, 76)
	road(Rect2(-5, -250, 10, 206), false)          # avenue: towers -> south checkpoint
	walk(Rect2(-46, -44, 92, 10), P.STONE, P.STONE_DARK, "Forecourt")
	road(Rect2(-186, -94, 372, 8), true)
	road(Rect2(-186, -174, 372, 8), true)
	road(Rect2(-114, -246, 8, 290), false)
	road(Rect2(106, -246, 8, 290), false)
	road(Rect2(-186, 36, 372, 8), true)
	road(Rect2(46, -4, 60, 6), true, false)        # courtyard -> east street
	walk(Rect2(-3, 30, 6, 6))                        # north tower -> north street
	# City streets outside.
	road(Rect2(-240, -272, 480, 14), true)
	road(Rect2(-240, 68, 480, 14), true)
	road(Rect2(-216, -272, 14, 354), false)
	road(Rect2(202, -272, 14, 354), false)
	road(Rect2(-202, -94, 12, 8), true, false)     # west checkpoint -> city
	road(Rect2(-5, -258, 10, 8), false, false)     # south checkpoint -> city
	# Pavements.
	walk(Rect2(-240, -258, 480, 6))
	walk(Rect2(-240, 62, 480, 6))
	walk(Rect2(-202, -252, 10, 314))
	walk(Rect2(192, -252, 10, 314))
	walk(Rect2(-11, -250, 6, 217))
	walk(Rect2(5, -250, 6, 217))
	walk(QUAD, P.STONE, P.STONE_DARK, "Central Quad")
	walk(Rect2(30, -224, 42, 24), P.STONE, P.STONE_DARK, "Metro")
	walk(Rect2(-186, 44, 372, 14), P.ASPHALT.lightened(0.1), P.ASPHALT.lightened(0.05))  # north alley
	for b in BUILDINGS:
		reserve((b[0] as Rect2).grow(0.6))
		map_rect(b[0], (b[2] as Color).darkened(0.3), (b[4] as String).capitalize(), false, "building")
	reserve(METRO)
	map_rect(METRO, Color("2f6fd6"), "METRO", true, "building")
	# The city beyond the fence: blocks of towers.
	for r in _skyline_rects():
		reserve(r)
		map_rect(r, Color("8a8f9c"), "", false, "building")


func _skyline_rects() -> Array:
	var out := []
	for x in range(-236, 236, 30):
		out.append(Rect2(x + 2, -298, 24, 24))
		out.append(Rect2(x + 2, 84, 24, 24))
	for z in range(-248, 60, 34):
		out.append(Rect2(-238, z + 2, 20, 28))
		out.append(Rect2(218, z + 2, 20, 28))
	return out


func _build() -> void:
	lay_paving()
	_towers()
	for b in BUILDINGS:
		building(b[0], b[1], b[2], b[3], b[4], b[5])
	var tints := [Color("dfe6ea"), Color("c9d6e8"), Color("f3e3c3"), Color("e8d5c4"), Color("bfe3ea"), Color("c9ccd2")]
	for r: Rect2 in _skyline_rects():
		building(r, rng.randi_range(5, 12), tints[rng.randi() % tints.size()], Color("4a4f5a"), "", Vector2(0, -1), 0.25)
	_fences_and_checkpoints()
	_metro()
	_quad()
	_streets()
	_staff_and_students()
	_nav()
	exit_marker(Vector2(0, -254), "North checkpoint (guarded)")
	exit_marker(Vector2(-194, -90), "West checkpoint (guarded)")
	exit_marker(METRO.get_center(), "Metro station")
	exit_marker(Vector2(-150.2, 61), "Alley fence (crouch)")


## Quibble Towers: two six-storey towers facing each other across a courtyard.
func _towers() -> void:
	begin_campus()
	style = {
		"wall": Color("dfe6ea"), "trim": Color("24315e"), "floor": [Color("eef0f2"), Color("dfe2e6")],
		"hall": [Color("c9ccd2"), Color("b9bcc4")], "dado_in": Color("9fc6ea"), "dado_hall": Color("24315e"),
		"dado_out": Color("5a5f6e"), "frame": Color("24315e"), "roof": Color("8a8f9c"), "ceiling": Color("fbfbf6"),
	}
	var fill_a := [["empty", 10], ["lecture", 18], ["washroom", 8], ["empty", 10, {"kids": true}], ["art", 12], ["store", 30]]
	var fill_b := [["lecture", 18], ["empty", 10], ["computer", 12], ["empty", 10], ["music", 12], ["store", 40]]
	# South tower: the entrance faces the avenue.
	var south_a := [
		[["staff", 12], ["washroom", 8], ["office", 10], ["store", 6.2], ["lobby", 10, {"gate": true, "name": "Quibble Towers"}],
			["computer", 12], ["detention", 8], ["store", 21.2]],
		[["empty", 10], ["class", 10, {"idx": 0}], ["washroom", 8], ["empty", 10, {"kids": true}], ["computer", 12], ["store", 32.4]],
		fill_a, fill_a,
		[["empty", 10], ["empty", 10], ["class", 10, {"idx": 2}], ["washroom", 8], ["empty", 10, {"kids": true}], ["store", 34.4]],
		[["lecture", 18], ["empty", 10], ["washroom", 8], ["empty", 10], ["store", 36.4]],
	]
	var south_b := [
		[["lecture", 18], ["passage", 6], ["canteen", 24], ["passage", 10], ["music", 12], ["store", 22]],
		fill_b, fill_b, fill_b, fill_b, fill_b,
	]
	wing(Rect2(-46, -32, 92, 20), true, 6, south_a, south_b, {"title": c.UNI_NAME, "front": "a", "cams": [0, 1, 3, 4]})
	# North tower; its east door is the locked staff door.
	var north_a := [
		[["passage", 6], ["library", 16], ["washroom", 8], ["passage", 6], ["empty", 10], ["store", 36.4]],
		[["empty", 10, {"kids": true}], ["computer", 12], ["washroom", 8], ["empty", 10], ["store", 42.4]],
		fill_a,
		[["class", 10, {"idx": 1}], ["empty", 10], ["washroom", 8], ["lecture", 18], ["store", 36.4]],
		fill_a,
		[["empty", 10], ["lab", 10, {"idx": 3}], ["washroom", 8], ["empty", 10], ["store", 44.4]],
	]
	var north_b := [
		[["lecture", 18], ["empty", 10], ["music", 12], ["empty", 10], ["store", 42]],
		fill_b, fill_b, fill_b, fill_b, fill_b,
	]
	wing(Rect2(-46, 10, 92, 20), true, 6, north_a, north_b, {"ends": [true, false], "title": "SOUTH TOWER", "front": "b", "cams": [0, 3, 5]})
	service_door(Vector3(46.0, 0, 20.0), false)
	# The courtyard between them.
	slab(Rect2(-46, -11.8, 92, 21.6), 0.04, 0.08, P.STONE, 0.02, P.STONE_DARK)
	court(Vector2(-20, -1))
	assembly_point(Vector2(22, -6))
	for p: Vector2 in [Vector2(6, 6), Vector2(36, 6), Vector2(-40, 6), Vector2(-40, -8)]:
		tree(p, 0)
	for x: float in [10.0, 18.0, 26.0]:
		bench(Vector2(x, 6))
	principal_car(Vector2(-30, -38))
	nav_line(Vector2(-44, -10), Vector2(44, -10))
	nav_line(Vector2(-44, 8), Vector2(44, 8))
	nav_line(Vector2(0, -10), Vector2(0, 8))
	c.staff_loops = {
		"peon": [Vector3(-40, 0, -22), Vector3(40, 0, -22), Vector3(-25, 0, -22), Vector3(-25, 0, -8), Vector3(-25, 0, -22)],
		"prefect": [Vector3(-44, 0, -10), Vector3(44, 0, -10), Vector3(44, 0, 8), Vector3(-44, 0, 8)],
		"proctor": [Vector3(-40, 10.8, -22), Vector3(40, 10.8, -22)],
		"vp": [Vector3(-40, 14.4, 20), Vector3(40, 14.4, 20)],
	}
	c.core_walks = [
		[Vector3(-40, 0, -22), Vector3(40, 0, -22)],
		[Vector3(-40, 3.6, -22), Vector3(40, 3.6, -22)],
		[Vector3(-40, 7.2, 20), Vector3(40, 7.2, 20)],
		[Vector3(-30, 0, 8), Vector3(30, 0, 8)],
		[Vector3(-40, 14.4, -22), Vector3(40, 14.4, -22)],
	]
	finish_campus()


func _fences_and_checkpoints() -> void:
	fence(true, -190, 190, -250, [], [[-6.2, 6.2]])
	fence(true, -190, 190, 60, [ALLEY])
	fence(false, -250, 60, -190, [], [WEST_GAP])
	fence(false, -250, 60, 190)
	# South checkpoint.
	gate(Vector2(0, -250), true, 10.0, Vector2(0, -1), c.UNI_NAME, "Enjoy the city!")
	booth(Vector2(10, -243))
	barrier(Vector2(-3.8, -247))
	var south := Rect2(-16, -262, 32, 24)
	post("GateGuard1", "Officer Walsh (Campus Police)", Vector2(-7.5, -245), Vector2(0.2, 1), south, 601)
	post("GateGuard2", "Officer Chen (Campus Police)", Vector2(7.5, -247), Vector2(-0.2, 1), south, 602)
	camera(Vector2(-9, -249), 4.4, facing(Vector2(0.3, 1)), 0.6, 0.35)
	camera(Vector2(9, -249), 4.4, facing(Vector2(-0.3, 1)), 0.6, 0.4)
	# West checkpoint.
	booth(Vector2(-182, -100))
	barrier(Vector2(-187, -93))
	post("GateGuard3", "Officer Obi (Campus Police)", Vector2(-184, -86.5), Vector2(1, -0.2), Rect2(-200, -102, 22, 24), 603)
	camera(Vector2(-189, -97), 4.2, facing(Vector2(1, 0.3)), 0.7, 0.3)
	signpost(Vector2(-180, -84), "WEST CHECKPOINT\nSHOW YOUR ID", facing(Vector2(1, 0)), Color("24315e"), Color("ffd24a"))
	# North alley: bins and a torn fence.
	for k in 4:
		var x := -158.0 + k * 2.2 + (3.0 if k > 1 else 0.0)
		box(Vector3(x, 0.7, 57.6), Vector3(1.8, 1.4, 1.2), [Color("2f6a4a"), Color("3f86a8"), Color("2f6a4a"), Color("5a5f6e")][k], 0.03, true)
		box(Vector3(x, 1.45, 57.6), Vector3(1.9, 0.1, 1.3), Color("26262e"), 0.0)
	for k in 6:
		box(Vector3(-146 + rng.randf_range(-1, 1), 0.2, 56 + rng.randf_range(-1, 1)), Vector3(0.5, 0.4, 0.4), P.PAPER.darkened(0.2), 0.05)
	signpost(Vector2(-140, 50), "SERVICE ALLEY\nNO STUDENTS", facing(Vector2(0, -1)), Color("5a5f6e"))


func _metro() -> void:
	var r := METRO
	var m := r.get_center()
	var tile := Color("e8e6e0")
	var blue := Color("2f6fd6")
	# Glass-and-steel entrance: open towards the north.
	box(Vector3(m.x, 1.8, r.position.y + 0.15), Vector3(r.size.x, 3.6, 0.3), blue, 0.0, true)
	for x: float in [r.position.x + 0.15, r.end.x - 0.15]:
		box(Vector3(x, 1.8, m.y), Vector3(0.3, 3.6, r.size.y), tile, 0.0, true)
	box(Vector3(m.x, 3.75, m.y), Vector3(r.size.x + 0.6, 0.3, r.size.y + 0.6), blue, 0.0, true)
	# Stairs going down (just paint: the station is "below").
	box(Vector3(m.x, 0.06, m.y), Vector3(r.size.x - 0.6, 0.04, r.size.y - 0.4), Color("3a3d47"), 0.0)
	for k in 8:
		box(Vector3(m.x, 0.09, METRO_IN.position.y + 0.3 + k * 0.62), Vector3(10, 0.02, 0.3), Color("5a5f6e").darkened(k * 0.06), 0.0)
	glow(Vector3(m.x, 3.55, m.y), Vector3(8, 0.06, 0.4))
	# Turnstiles across the mouth, with gaps to slip through.
	for k in 5:
		box(Vector3(r.position.x + 1.6 + k * 2.7, 0.5, r.end.y - 0.8), Vector3(0.4, 1.0, 0.9), P.METAL, 0.0, true)
	# Big M on a pole.
	box(Vector3(r.position.x - 1.5, 2.2, r.end.y + 1), Vector3(0.16, 4.4, 0.16), P.METAL_DARK, 0.0, true)
	box(Vector3(r.position.x - 1.5, 4.8, r.end.y + 1), Vector3(1.4, 1.4, 0.2), blue, 0.0)
	label("M", Vector3(r.position.x - 1.5, 4.8, r.end.y + 1.12), 150, Color.WHITE, 0.0, 10)
	label("METRO  ·  LINE 3 TO THE CITY", Vector3(m.x, 3.75, r.end.y + 0.32), 60, Color.WHITE, 0.0, 10)
	post("Transit", "Transit Officer Farah", Vector2(m.x + 4.5, r.end.y + 2.5), Vector2(-0.4, 1), Rect2(r.position.x - 4, r.position.y, r.size.x + 8, r.size.y + 8), 604)
	camera(Vector2(r.end.x + 0.6, r.end.y + 0.4), 3.4, facing(Vector2(-0.6, 1)), 0.7, 0.4)


func _quad() -> void:
	var q := QUAD
	var m := q.get_center()
	# Lawns with paths crossing the quad.
	for r: Rect2 in [Rect2(q.position.x + 2, q.position.y + 2, 40, 26), Rect2(m.x + 2, q.position.y + 2, 40, 26),
			Rect2(q.position.x + 2, m.y + 2, 40, 26), Rect2(m.x + 2, m.y + 2, 40, 26)]:
		slab(r, 0.08, 0.06, P.GRASS, 0.03, P.GRASS_DARK)
		for k in 3:
			tree(Vector2(rng.randf_range(r.position.x + 3, r.end.x - 3), rng.randf_range(r.position.y + 3, r.end.y - 3)), 0)
	# Statue of the founder in the middle.
	var p := Vector3(m.x, 0, m.y)
	box(p + Vector3(0, 0.3, 0), Vector3(5, 0.6, 5), P.STONE_DARK, 0.0, true)
	box(p + Vector3(0, 1.3, 0), Vector3(1.6, 1.4, 1.6), P.STONE, 0.0, true)
	var bronze := Color("b08a4a")
	box(p + Vector3(0, 2.5, 0), Vector3(1.0, 1.0, 0.6), bronze, 0.03)
	box(p + Vector3(0, 3.25, 0), Vector3(0.6, 0.6, 0.5), bronze.lightened(0.05), 0.0)
	box(p + Vector3(0, 3.62, 0), Vector3(0.9, 0.14, 0.8), Color("26262e"), 0.0)  # mortarboard
	label("DAME BEATRIX QUIBBLE\nFounder, Wanderer", p + Vector3(0, 1.3, -0.82), 26, Color("3a2d26"), PI, 0)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		bench(Vector2(m.x, m.y) + d * 6.0)


func _streets() -> void:
	# Street trees and lamps along the avenue.
	for z in range(-40, -248, -12):
		for x: float in [-9.5, 9.5]:
			lamp(Vector2(x, z))
		for x: float in [-12.5, 12.5]:
			if z % 24 == 0:
				tree(Vector2(x, z - 6), 0)
	# Parked cars and food trucks along the cross streets.
	var cols := [Color("e0524f"), Color("f4f4f0"), Color("3f86a8"), Color("26262e"), Color("f2a93b"), Color("48b06a")]
	for z: float in [-87.5, -167.5, 42.5]:
		for k in 24:
			var x := -180.0 + k * 15.0
			if absf(x) < 14 or absf(x + 110) < 8 or absf(x - 110) < 8 or rng.randf() < 0.35:
				continue
			car(Vector2(x, z), true, cols[rng.randi() % cols.size()])
	bus(Vector2(-60, -87.4), true, Color("ffd24a"), "TACOS")
	bus(Vector2(70, -167.4), true, Color("ff8ab0"), "BUBBLE TEA")
	bus(Vector2(-150, -265), true, Color("e0524f"), "CITY 12")
	bus(Vector2(80, 75), true, Color("3f86a8"), "CITY 5")
	for k in 10:
		car(Vector2(-200 + k * 42.0, -268 if k % 2 == 0 else -262), true, cols[k % cols.size()])
		car(Vector2(-190 + k * 40.0, 72 if k % 2 == 0 else 78), true, cols[(k + 2) % cols.size()])
	# Traffic lights at the crossings.
	for at: Vector2 in [Vector2(-9, -98), Vector2(9, -98), Vector2(-9, -178), Vector2(9, -178), Vector2(-102, -98), Vector2(102, -178)]:
		box(Vector3(at.x, 1.8, at.y), Vector3(0.14, 3.6, 0.14), P.METAL_DARK, 0.0, true)
		box(Vector3(at.x, 3.8, at.y), Vector3(0.4, 1.1, 0.4), Color("26262e"), 0.0)
		c._glow.box(Vector3(at.x, 4.1, at.y - 0.21), Vector3(0.2, 0.2, 0.02), Color("ff4a4a"))
		box(Vector3(at.x, 3.5, at.y - 0.21), Vector3(0.2, 0.2, 0.02), Color("2f6a4a"), 0.0)
	# Zebra crossings.
	for z: float in [-90.0, -170.0]:
		for k in 6:
			box(Vector3(-3.75 + k * 1.5, 0.065, z + 6.5), Vector3(0.8, 0.02, 2.4), P.LINE, 0.0)
	for x in range(-180, 181, 20):
		if absf(x) > 14:
			bench(Vector2(x, 59))
	signpost(Vector2(12, -246), "CITY CENTRE  ↑\nMETRO  →", facing(Vector2(0, 1)), Color("2f6a4a"))


func _staff_and_students() -> void:
	patrol("Police1", "Officer Grant (Campus Police)", [Vector2(-7.5, -40), Vector2(-7.5, -240), Vector2(7.5, -240), Vector2(7.5, -40)], 1.8, 5.0, 15.0, "guard")
	patrol("Police2", "Officer Yamamoto (Campus Police)", [Vector2(-182, -90), Vector2(182, -90)], 1.8, 5.0, 15.0, "guard")
	patrol("Police3", "Officer Mensah (Campus Police)", [Vector2(-182, -170), Vector2(182, -170)], 1.8, 5.0, 15.0, "guard")
	patrol("Janitor", "Mr. Kovac (Janitor)", [Vector2(-182, 51), Vector2(182, 51)], 1.4, 4.6, 13.0, "builder")
	patrol("Prof", "Prof. Oyelaran", [Vector2(-98, -100), Vector2(-14, -100), Vector2(-14, -160), Vector2(-98, -160)], 1.4, 4.4, 13.0, "teacher")
	patrol("Dean", "Dean Rossi", [Vector2(-110, 30), Vector2(-110, -240), Vector2(110, -240), Vector2(110, 30)], 1.5, 4.6, 13.0, "teacher")
	for loop in [[Vector2(-8, -60), Vector2(-8, -230)], [Vector2(8, -80), Vector2(8, -200)], [Vector2(-170, -90), Vector2(170, -90)],
			[Vector2(-170, -170), Vector2(170, -170)], [Vector2(-80, -131), Vector2(-66, -131)], [Vector2(40, -200), Vector2(20, -196)],
			[Vector2(-150, 40), Vector2(150, 40)]]:
		stroll(loop)


func _nav() -> void:
	for x: float in [-7.5, 7.5]:
		nav_line(Vector2(x, -39), Vector2(x, -254))
	nav_line(Vector2(0, -250), Vector2(0, -266))
	nav_line(Vector2(-182, -90), Vector2(182, -90))
	nav_line(Vector2(-182, -170), Vector2(182, -170))
	nav_line(Vector2(-182, 40), Vector2(182, 40))
	nav_line(Vector2(-182, 51), Vector2(182, 51))
	nav_line(Vector2(-110, -242), Vector2(-110, 40))
	nav_line(Vector2(110, -242), Vector2(110, 40))
	nav_line(Vector2(-110, -244), Vector2(110, -244))
	nav_line(Vector2(48, -1), Vector2(106, -1))
	nav_line(Vector2(0, 32), Vector2(0, 36))
	nav_line(Vector2(-50, -39), Vector2(50, -39))
	nav_line(Vector2(-50, -39), Vector2(-50, 34))
	nav_line(Vector2(50, -39), Vector2(50, 34))
	nav_line(Vector2(-190, -90), Vector2(-206, -90))
	nav_line(Vector2(-98, -100), Vector2(-14, -100))
	nav_line(Vector2(-98, -160), Vector2(-14, -160))
	nav_line(Vector2(-14, -100), Vector2(-14, -160))
	nav_line(Vector2(-98, -100), Vector2(-98, -160))
	nav_line(Vector2(51, -200), Vector2(51, -176))
	nav_line(Vector2(-230, -265), Vector2(230, -265), 12.0)
