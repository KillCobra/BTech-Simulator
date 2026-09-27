extends "res://scenes/world/maps/academic_kit.gd"
## Grand Campus: a walled university town. Boulevard south to the main gate,
## hostels up north, a stadium and hedge maze west, a lake and research park
## east. Ways out: the guarded main gate, a torn fence (crouch), a storm drain
## (crouch) and a construction site's scaffolding over the north wall.
##
## The university itself is the Old Quadrangle: four three-storey wings round a
## courtyard (x -42..42, z -110..-10), joined on every floor, with the classrooms
## spread over all floors.
##
## Top view: quadrangle at x -42..42, z -110..-10; walls at x ±200, z -262 and 100.

const LAKE := Rect2(80, -236, 104, 76)
const BOARDWALK := Rect2(128, -236, 3, 76)
const PIER := Rect2(100, -172, 3, 12)
const STADIUM := Rect2(-186, -246, 104, 70)
const MAZE := Rect2(-130, -52, 40, 40)
const SITE := Rect2(140, 50, 56, 48)
const DRAIN_Z := -200.0
const FENCE_HOLE := [-116.0, -114.4]
const QX := 42.0  # the quadrangle spans x -QX..QX

# [rect, floors, wall, trim, title, front]
const BUILDINGS := [
	[Rect2(-50, -160, 34, 22), 3, Color("f3e3c3"), Color("d9774f"), "ADMINISTRATION", Vector2(1, 0)],
	[Rect2(16, -162, 36, 26), 4, Color("dfe6ea"), Color("5b6bd6"), "CENTRAL LIBRARY", Vector2(-1, 0)],
	[Rect2(16, -204, 40, 30), 3, Color("e8d5c4"), Color("24315e"), "CONVOCATION HALL", Vector2(-1, 0)],
	[Rect2(-54, -244, 40, 24), 3, Color("f3e3c3"), Color("9a62d6"), "FACULTY OF ARTS", Vector2(1, 0)],
	[Rect2(16, -246, 40, 26), 3, Color("dfe6ea"), Color("3aa4a0"), "FACULTY OF SCIENCE", Vector2(-1, 0)],
	[Rect2(-186, -160, 44, 26), 2, Color("f2d7a0"), Color("e0524f"), "SPORTS COMPLEX", Vector2(0, 1)],
	[Rect2(-182, -102, 36, 22), 1, Color("c9ccd2"), Color("4a4f5a"), "WORKSHOPS", Vector2(0, -1)],
	[Rect2(-176, 52, 46, 16), 4, Color("f2c9a0"), Color("8a4b2a"), "ASTER HOSTEL", Vector2(0, -1)],
	[Rect2(-118, 52, 46, 16), 4, Color("e8d5c4"), Color("2f6a4a"), "BIRCH HOSTEL", Vector2(0, -1)],
	[Rect2(-46, 54, 30, 18), 1, Color("f3e3c3"), Color("f2a93b"), "MESS HALL", Vector2(0, -1)],
	[Rect2(76, 52, 46, 16), 4, Color("f2c9a0"), Color("5b6bd6"), "CEDAR HOSTEL", Vector2(0, -1)],
	[Rect2(80, -104, 40, 24), 3, Color("eef3ee"), Color("2f6fd6"), "BIOTECH INSTITUTE", Vector2(0, -1)],
	[Rect2(140, -104, 44, 24), 3, Color("dfe6ea"), Color("9a62d6"), "QUANTUM LAB", Vector2(0, -1)],
]


func _plan() -> void:
	c.bounds = Rect2(-200, -262, 400, 362)
	c.world_rect = Rect2(-236, -300, 472, 436)
	c.goal_text = "ESCAPE THE UNIVERSITY!  Main gate, fence hole, storm drain or scaffolding.  [M] map"
	c.win_text = "The chai outside the gate tastes like freedom."
	# Roads.
	c.academic_rect = Rect2(-QX - 2.0, -112, QX * 2.0 + 4.0, 104)
	road(Rect2(-5, -274, 10, 162), false)           # boulevard: quadrangle entrance -> main gate
	road(Rect2(-196, 36, 392, 8), true)             # north road (hostels)
	road(Rect2(-196, -124, 392, 8), true)           # ring road
	road(Rect2(-196, -258, 392, 6), true, false)    # inner south road
	road(Rect2(-66, -252, 8, 288), false)           # west road
	road(Rect2(58, -252, 8, 288), false)            # east road
	road(Rect2(-236, -286, 472, 10), true)          # city road outside
	# Paths and plazas.
	walk(Rect2(-9, -262, 4, 150))
	walk(Rect2(5, -262, 4, 150))
	walk(Rect2(-20, -116, 40, 6), P.STONE, P.STONE_DARK)  # forecourt of the quadrangle
	# Not all straight lines: a roundabout round the founder's statue, a promenade
	# round the lake, and footpaths worn across the lawns.
	curve_road(ellipse(Vector2(0, -140), 9.0, 9.0, 32), 5.0)
	round_lawn(Vector2(0, -140), 6.4)
	curve_walk(_rounded_loop(Rect2(76, -240, 112, 86), 12.0), 3.0)
	curve_walk([Vector2(-QX - 3.0, -20), Vector2(-50, -4), Vector2(-45, 12), Vector2(-38, 26), Vector2(-31, 38)])  # back door -> mess hall
	curve_walk([Vector2(-18, -176), Vector2(-11, -170), Vector2(10, -166), Vector2(14, -156)], 2.6)  # Fountain Sq. -> library
	walk(Rect2(-22, -276, 44, 2))                   # forecourt outside the gate
	walk(Rect2(-236, -290, 472, 4))                 # far pavement
	walk(Rect2(-52, -192, 34, 32), P.STONE, P.STONE_DARK, "Fountain Sq.")
	walk(Rect2(76, -52, 60, 34), P.ASPHALT, P.ASPHALT.lightened(0.05), "Parking")
	walk(SITE, DIRT, DIRT_DARK, "Construction")
	# Running track around the football field.
	for r in [Rect2(STADIUM.position.x, STADIUM.position.y, STADIUM.size.x, 6), Rect2(STADIUM.position.x, STADIUM.end.y - 6, STADIUM.size.x, 6),
			Rect2(STADIUM.position.x, STADIUM.position.y + 6, 6, STADIUM.size.y - 12), Rect2(STADIUM.end.x - 6, STADIUM.position.y + 6, 6, STADIUM.size.y - 12)]:
		walk(r, P.COURT, P.COURT.darkened(0.05))
	keep_clear(STADIUM)
	map_rect(STADIUM.grow(-6), Color("6fbf4f"), "Stadium")
	keep_clear(MAZE)
	map_rect(MAZE, Color("3f8a45"), "Hedge maze")
	keep_clear(Rect2(-80, -240, 8, 54))
	# Water.
	water(LAKE, Vector3(110, 0, -154), "Lake")
	bridge_area(BOARDWALK)
	bridge_area(PIER)
	for b in BUILDINGS:
		reserve((b[0] as Rect2).grow(0.6))
		map_rect(b[0], (b[2] as Color).darkened(0.3), (b[4] as String).capitalize(), false, "building")
	reserve(Rect2(-170, -40, 30, 18))  # greenhouse
	map_rect(Rect2(-170, -40, 30, 18), Color("bfe3ea"), "Greenhouse", false, "building")


func _build() -> void:
	lay_paving()
	lay_water()
	_quadrangle()
	for b in BUILDINGS:
		building(b[0], b[1], b[2], b[3], b[4], b[5])
	_perimeter()
	_main_gate()
	_outside()
	_boulevard()
	_stadium()
	_maze()
	_greenhouse()
	_lake()
	_parking()
	_construction()
	_fountain(Vector2(-35, -176))
	_staff_and_students()
	_nav()
	# Trees everywhere else, a thick belt along the walls.
	forest(Rect2(-198, -260, 396, 358), 900)
	for x in range(-194, 195, 9):
		for z: float in [-248.0, 94.0]:
			if free_at(x, z) and rng.randf() < 0.8:
				tree(Vector2(x + rng.randf_range(-2, 2), z + rng.randf_range(-2, 2)))
	bushes(Rect2(-198, -260, 396, 358), 420)
	flowers(Rect2(-198, -260, 396, 358), 900)


## The Old Quadrangle: four wings round a courtyard, three storeys. The east and
## west wings run into the south and north wings, and a link doorway on every
## storey joins their corridors, so you can walk the whole ring on any floor.
func _quadrangle() -> void:
	begin_campus()
	style = {
		"wall": Color("ead9b8"), "trim": Color("8a3a2a"), "floor": [Color("efe4cc"), Color("d9c6a4")],
		"hall": [Color("b85a44"), Color("a04c3a")], "dado_in": Color("a9c3d3"), "dado_hall": Color("8a3a2a"),
		"dado_out": Color("8a6a4a"), "frame": Color("2f4a6a"), "roof": Color("6a4a3a"), "ceiling": Color("f7f3ea"),
	}
	# Where the east / west wings meet the long wings: no windows, a link doorway at x = ±32.
	var hidden := [[-QX, -QX + 20.0], [QX - 20.0, QX]]
	var b := {"blind": true}
	# South wing: the main entrance faces the boulevard; its north side joins the east / west wings.
	wing(Rect2(-QX, -110, QX * 2.0, 20), true, 3, [
		[["staff", 12], ["office", 10], ["washroom", 10.2], ["lobby", 10, {"gate": true, "name": "Old Quadrangle"}],
			["class", 10, {"idx": 0}], ["detention", 8], ["library", 14.2]],
		[["empty", 10, {"kids": true}], ["computer", 12], ["empty", 10, {"kids": true}], ["washroom", 8], ["empty", 10], ["art", 12], ["store", 12.4]],
		[["lecture", 18], ["music", 10], ["empty", 10, {"kids": true}], ["washroom", 8], ["empty", 10], ["store", 18.4]],
	], [
		[["washroom", 8, b], ["link", 4], ["store", 8, b], ["canteen", 19.5], ["passage", 5], ["music", 10], ["computer", 9.5],
			["store", 8, b], ["link", 4], ["lecture", 8, b]],
		[["empty", 8, b], ["link", 4], ["store", 8, b], ["empty", 11], ["empty", 11, {"kids": true}], ["music", 11], ["empty", 11],
			["store", 8, b], ["link", 4], ["empty", 8, b]],
		[["store", 8, b], ["link", 4], ["empty", 8, b], ["computer", 11], ["empty", 11], ["art", 11], ["empty", 11],
			["store", 8, b], ["link", 4], ["store", 8, b]],
	], {"title": c.UNI_NAME, "front": "a", "cams": [0, 1, 2], "notice": true, "alarm": true, "blind_b": hidden})
	# East wing (courtyard on its west side), between the south and north wings.
	wing(Rect2(QX - 20.0, -90, 20, 60), false, 3, [
		[["passage", 6], ["empty", 10], ["washroom", 8], ["art", 12], ["empty", 14.4]],
		[["class", 10, {"idx": 1}], ["empty", 10], ["washroom", 8], ["empty", 10, {"kids": true}], ["computer", 12.4]],
		[["empty", 10], ["music", 10], ["empty", 10], ["lecture", 20.4]],
	], [
		[["computer", 12], ["empty", 10], ["store", 8], ["lecture", 18], ["empty", 12]],
		[["empty", 10], ["empty", 10, {"kids": true}], ["lecture", 18], ["empty", 10], ["store", 12]],
		[["lecture", 18], ["empty", 10], ["empty", 10], ["art", 12], ["store", 10]],
	], {"ends": [false, false], "join": [true, true], "cams": [1]})
	# West wing (courtyard on its east side).
	wing(Rect2(-QX, -90, 20, 60), false, 3, [
		[["empty", 10], ["washroom", 8], ["computer", 12], ["empty", 10], ["store", 10.4]],
		[["empty", 10], ["lecture", 18], ["empty", 10, {"kids": true}], ["store", 12.4]],
		[["empty", 10], ["empty", 10], ["lab", 10, {"idx": 3}], ["washroom", 8], ["store", 12.4]],
	], [
		[["passage", 6], ["empty", 10], ["passage", 6], ["music", 10], ["empty", 10], ["passage", 6], ["store", 12]],
		[["empty", 10], ["computer", 12], ["empty", 10], ["art", 12], ["store", 16]],
		[["lecture", 18], ["empty", 10], ["empty", 10, {"kids": true}], ["store", 22]],
	], {"ends": [false, false], "join": [true, true], "cams": [2]})
	# North wing: back door to the hostels (west end) and a locked staff door (east end).
	wing(Rect2(-QX, -30, QX * 2.0, 20), true, 3, [
		[["store", 3.2, b], ["link", 4], ["washroom", 8, b], ["lecture", 19.5], ["passage", 5], ["empty", 10], ["art", 9.5],
			["store", 8, b], ["link", 4], ["store", 3.2, b]],
		[["store", 3.2, b], ["link", 4], ["empty", 8, b], ["empty", 11, {"kids": true}], ["computer", 11], ["empty", 11], ["washroom", 11],
			["store", 8, b], ["link", 4], ["store", 3.2, b]],
		[["store", 3.2, b], ["link", 4], ["empty", 8, b], ["class", 10, {"idx": 2}], ["empty", 10], ["washroom", 10], ["art", 14],
			["store", 8, b], ["link", 4], ["store", 3.2, b]],
	], [
		[["empty", 10], ["lecture", 18], ["empty", 10], ["music", 10], ["store", 36]],
		[["lecture", 18], ["empty", 10], ["art", 12], ["store", 44]],
		[["empty", 10], ["lecture", 18], ["computer", 12], ["store", 44]],
	], {"ends": [true, true], "title": "SOUTH WING", "front": "b", "cams": [0, 2], "blind_a": hidden})
	service_door(Vector3(QX, 0, -20), false)
	# Courtyard (x -22..22, z -90..-30): court, lawns, a fountain and the assembly point.
	slab(Rect2(-21.4, -89.4, 42.8, 59.0), 0.02, 0.08, P.GRASS, 0.02, P.GRASS_DARK)
	walk_slab(Rect2(-3, -89.4, 6, 59.0))
	walk_slab(Rect2(-21.4, -62, 42.8, 5))
	court(Vector2(-12.5, -77))
	_fountain(Vector2(12.5, -44))
	assembly_point(Vector2(12.5, -76))
	for p: Vector2 in [Vector2(-17, -34), Vector2(-7, -34), Vector2(-18, -48), Vector2(19, -86), Vector2(-19, -87)]:
		tree(p, 0)
	for x: float in [-16.0, -8.0]:
		bench(Vector2(x, -55))
	nav_line(Vector2(0, -89), Vector2(0, -31))
	nav_line(Vector2(-20, -59.5), Vector2(20, -59.5))
	nav_line(Vector2(0, -114), Vector2(0, -89))
	c.staff_loops = {
		"peon": [Vector3(-36, 0, -100), Vector3(36, 0, -100), Vector3(0, 0, -100), Vector3(0, 0, -60), Vector3(0, 0, -34), Vector3(0, 0, -60)],
		"prefect": [Vector3(-18, 0, -59.5), Vector3(18, 0, -59.5), Vector3(0, 0, -33), Vector3(0, 0, -86)],
		# The proctor walks the first-floor ring, the vice principal the second.
		"proctor": [Vector3(32, 3.6, -86), Vector3(32, 3.6, -34), Vector3(-32, 3.6, -34), Vector3(-32, 3.6, -86)],
		"vp": [Vector3(-36, 7.2, -20), Vector3(36, 7.2, -20), Vector3(32, 7.2, -60), Vector3(36, 7.2, -100), Vector3(-36, 7.2, -100), Vector3(-32, 7.2, -60)],
	}
	c.core_walks = [
		[Vector3(-36, 0, -100), Vector3(36, 0, -100)],
		[Vector3(-18, 0, -59.5), Vector3(18, 0, -59.5)],
		[Vector3(-36, 3.6, -100), Vector3(36, 3.6, -100)],
		[Vector3(-36, 0, -20), Vector3(36, 0, -20)],
		[Vector3(32, 3.6, -84), Vector3(32, 3.6, -36)],
	]
	finish_campus()


## Points round a rectangle with rounded corners (a loop path).
func _rounded_loop(r: Rect2, radius: float) -> Array:
	var out := []
	var corners := [[Vector2(r.end.x - radius, r.end.y - radius), 0.0], [Vector2(r.position.x + radius, r.end.y - radius), PI / 2.0],
		[Vector2(r.position.x + radius, r.position.y + radius), PI], [Vector2(r.end.x - radius, r.position.y + radius), PI * 1.5]]
	for cn: Array in corners:
		out.append_array(ellipse(cn[0], radius, radius, 6, cn[1], cn[1] + PI / 2.0))
	out.append(out[0])
	return out


func walk_slab(r: Rect2) -> void:
	slab(r, 0.05, 0.1, P.STONE, 0.02, P.STONE_DARK)


func _perimeter() -> void:
	wall(true, -200, 200, -262, [[-7.4, 7.4]])
	wall(true, -200, 200, 100)
	wall(false, -262, 100, -200, [[-130, -100]])
	fence(false, -130, -100, -200, [FENCE_HOLE])
	wall(false, -262, 100, 200, [[DRAIN_Z - 0.8, DRAIN_Z + 0.8]])
	# Storm drain: a low concrete pipe through the east wall. Crouch to get through.
	var concrete := Color("a9a79f")
	for side: float in [-1.0, 1.0]:
		box(Vector3(200, 0.6, DRAIN_Z + side * 0.95), Vector3(8, 1.2, 0.3), concrete, 0.02, true)
	box(Vector3(200, 1.35, DRAIN_Z), Vector3(8, 0.3, 2.2), concrete, 0.02, true)
	box(Vector3(200, 2.45, DRAIN_Z), Vector3(0.5, 1.9, 1.6), P.BRICK, 0.04, true)
	box(Vector3(200, 0.03, DRAIN_Z), Vector3(8, 0.04, 1.5), Color("6a8a7a"), 0.0)
	for k in 5:
		box(Vector3(195.9, 0.6, DRAIN_Z - 0.6 + k * 0.3), Vector3(0.05, 1.1, 0.05), P.METAL_DARK, 0.0)  # bent grate
	signpost(Vector2(193, DRAIN_Z - 3), "STORM DRAIN\nKEEP OUT", facing(Vector2(1, 0)), Color("e0524f"))
	exit_marker(Vector2(0, -266), "Main gate (guarded)")
	exit_marker(Vector2(-201, -115), "Fence hole (crouch)")
	exit_marker(Vector2(201, DRAIN_Z), "Storm drain (crouch)")
	exit_marker(Vector2(171.5, 101), "Scaffolding")


func _main_gate() -> void:
	gate(Vector2(0, -262), true, 12.0, Vector2(0, -1), c.UNI_NAME, "Have a productive day!")
	booth(Vector2(12.5, -255))
	barrier(Vector2(-4.4, -259))
	var zone := Rect2(-16, -270, 32, 22)
	post("GateGuard1", "Officer Reyes (Security)", Vector2(-8.4, -256.5), Vector2(0, 1), zone, 301)
	post("GateGuard2", "Officer Mbeki (Security)", Vector2(9.8, -258.5), Vector2(0.4, 1), zone, 302)
	camera(Vector2(-10, -260.5), 4.2, facing(Vector2(0.3, 1)), 0.6, 0.35)
	camera(Vector2(10, -260.5), 4.2, facing(Vector2(-0.3, 1)), 0.6, 0.4)
	signpost(Vector2(-12, -250), "MAIN GATE\nID CARDS PLEASE", facing(Vector2(0, 1)), Color("24315e"), Color("ffd24a"))


func _outside() -> void:
	stall(Vector2(-16, -294), Color("ffd24a"), "CHAI  ·  SUTTA  ·  MAGGI", Vector2(0, 1))
	stall(Vector2(-6, -294), Color("7fd0ea"), "PHOTOCOPY", Vector2(0, 1))
	stall(Vector2(14, -294), Color("ff8ab0"), "MOMOS", Vector2(0, 1))
	stall(Vector2(26, -294), Color("b07cff"), "OLD BOOKS", Vector2(0, 1))
	for x: float in [-40.0, 40.0, -120.0, 120.0]:
		stall(Vector2(x, -294), [Color("48b06a"), Color("f2a93b")][int(absf(x)) % 2], ["JUICE", "XEROX", "CYBER CAFE", "SAMOSA"][int(absf(x) / 40.0) % 4], Vector2(0, 1))
	signpost(Vector2(30, -289), "BUS STOP\nCITY CENTRE 4 KM", facing(Vector2(0, 1)), Color("3f86a8"))
	bus(Vector2(-60, -281), true, Color("e0524f"), "CITY 42")
	for k in 8:
		c._scooter(Vector3(-30 + k * 1.9 + (12 if k > 3 else 0), 0, -289), P.BAGS[rng.randi() % P.BAGS.size()])
	for x in range(-230, 231, 14):
		if absf(x) > 40:
			tree(Vector2(x, -297), 0)


func _boulevard() -> void:
	for z in range(-118, -258, -14):
		for x: float in [-10.0, 10.0]:
			lamp(Vector2(x, z))
		for x: float in [-13.0, 13.0]:
			if free_at(x, z - 7):
				tree(Vector2(x, z - 7), 0)
	for z: float in [-150.0, -210.0]:
		bench(Vector2(-11, z))
		bench(Vector2(11, z))
	signpost(Vector2(-11, -128), "ADMIN  ·  HEALTH  ·  HOSTELS\n< WEST          EAST >\nLIBRARY  ·  LAKE  ·  RESEARCH", facing(Vector2(0, 1)), Color("2f6a4a"))
	# Statue of the founder, in the middle of the ring road junction.
	box(Vector3(0, 0.2, -140), Vector3(4, 0.4, 4), P.STONE_DARK, 0.0, true)
	box(Vector3(0, 1.0, -140), Vector3(1.6, 1.2, 1.6), P.STONE, 0.0, true)
	var bronze := Color("b08a4a")
	box(Vector3(0, 2.1, -140), Vector3(1.0, 1.0, 0.6), bronze, 0.03)
	box(Vector3(0, 2.85, -140), Vector3(0.6, 0.6, 0.5), bronze.lightened(0.05), 0.0)
	box(Vector3(0.7, 2.6, -140), Vector3(0.9, 0.2, 0.2), bronze, 0.0)  # pointing at the gate
	label("DAME BEATRIX QUIBBLE\n\"Why walk when you can wander?\"", Vector3(0, 1.0, -140.82), 26, Color("3a2d26"), PI, 0)


func _stadium() -> void:
	var r := STADIUM
	var field := r.grow(-6)
	# Pitch markings and goals.
	var mid := field.get_center()
	box(Vector3(mid.x, 0.02, mid.y), Vector3(0.12, 0.02, field.size.y - 2), P.LINE, 0.0)
	for dx: float in [-1.0, 1.0]:
		var gx: float = mid.x + dx * (field.size.x / 2.0 - 1.5)
		box(Vector3(gx, 1.2, mid.y - 3.6), Vector3(0.12, 2.4, 0.12), Color.WHITE, 0.0, true)
		box(Vector3(gx, 1.2, mid.y + 3.6), Vector3(0.12, 2.4, 0.12), Color.WHITE, 0.0, true)
		box(Vector3(gx, 2.4, mid.y), Vector3(0.12, 0.12, 7.3), Color.WHITE, 0.0)
		box(Vector3(mid.x + dx * 8, 0.02, mid.y), Vector3(0.1, 0.02, 20), P.LINE, 0.0)
	# Bleachers on the east side: climb them to look over the whole west side.
	for k in 5:
		var x := -79.5 + k * 1.3
		box(Vector3(x, 0.25 + k * 0.45, -211), Vector3(1.3, 0.5 + k * 0.9, 50), [Color("4f86e0"), Color("f4f4f0")][k % 2], 0.02, true)
	signpost(Vector2(-78, -183), "UNNECESSARY SCIENCES\nFIGHTING PIGEONS", facing(Vector2(1, 0)), Color("24315e"), Color("ffd24a"))
	for x: float in [-186.0, -82.0]:
		for z: float in [-246.0, -176.0]:
			box(Vector3(x, 5, z), Vector3(0.3, 10, 0.3), P.METAL_DARK, 0.0, true)
			box(Vector3(x, 10.2, z), Vector3(1.6, 0.8, 0.3), P.METAL, 0.0)
			glow(Vector3(x, 10.2, z + 0.16), Vector3(1.4, 0.6, 0.02))


func _maze() -> void:
	# Hedge maze from a seeded depth-first carve: 8 x 8 cells of 5 m.
	var n := 8
	var cell := MAZE.size.x / n
	var seen := {}
	var open := {}  # "x,z|x2,z2" -> true
	var stack := [Vector2i(0, 0)]
	seen[Vector2i(0, 0)] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var options := []
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + d
			if nxt.x >= 0 and nxt.y >= 0 and nxt.x < n and nxt.y < n and not seen.has(nxt):
				options.append(nxt)
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Vector2i = options[rng.randi() % options.size()]
		seen[pick] = true
		open[_edge(cur, pick)] = true
		stack.append(pick)
	var hedge := Color("3f8a45")
	var h := 2.4
	for i in n:
		for j in n + 1:
			# Walls along x (between row j-1 and j), and along z (between column j-1 and j).
			var entrance := (j == 0 and i == 0) or (j == n and i == n - 1)
			if not entrance and (j == 0 or j == n or not open.has(_edge(Vector2i(i, j - 1), Vector2i(i, j)))):
				var p := Vector3(MAZE.position.x + (i + 0.5) * cell, h / 2.0, MAZE.position.y + j * cell)
				box(p, Vector3(cell + 0.8, h, 0.8), hedge, 0.05, true)
				box(p + Vector3(rng.randf_range(-1.5, 1.5), h / 2.0 + 0.15, 0), Vector3(1.2, 0.3, 0.7), hedge.lightened(0.08), 0.04)
			if j == 0 or j == n or not open.has(_edge(Vector2i(j - 1, i), Vector2i(j, i))):
				var q := Vector3(MAZE.position.x + j * cell, h / 2.0, MAZE.position.y + (i + 0.5) * cell)
				box(q, Vector3(0.8, h, cell + 0.8), hedge, 0.05, true)
	# A reward in the middle: a bench to catch your breath.
	bench(Vector2(MAZE.get_center().x, MAZE.get_center().y))
	signpost(Vector2(MAZE.position.x + 2.5, MAZE.position.y - 2), "HEDGE MAZE\nno running", facing(Vector2(0, -1)), Color("2f6a4a"))


static func _edge(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]


func _greenhouse() -> void:
	var r := Rect2(-170, -40, 30, 18)
	var mid := r.get_center()
	box(Vector3(mid.x, 0.3, mid.y), Vector3(r.size.x, 0.6, r.size.y), P.WALL_SHADE, 0.0, true)
	collide(Vector3(mid.x, 2.5, mid.y), Vector3(r.size.x, 5, r.size.y))
	for k in 11:
		var x := r.position.x + k * 3.0
		box(Vector3(x, 2.6, mid.y), Vector3(0.12, 0.12, r.size.y), Color.WHITE, 0.0)
		box(Vector3(x, 1.5, r.position.y), Vector3(0.12, 3.0, 0.12), Color.WHITE, 0.0)
		box(Vector3(x, 1.5, r.end.y), Vector3(0.12, 3.0, 0.12), Color.WHITE, 0.0)
	c._glass.box(Vector3(mid.x, 2.0, r.position.y), Vector3(r.size.x, 2.8, 0.04), Color.WHITE)
	c._glass.box(Vector3(mid.x, 2.0, r.end.y), Vector3(r.size.x, 2.8, 0.04), Color.WHITE)
	c._glass.box(Vector3(r.position.x, 2.0, mid.y), Vector3(0.04, 2.8, r.size.y), Color.WHITE)
	c._glass.box(Vector3(r.end.x, 2.0, mid.y), Vector3(0.04, 2.8, r.size.y), Color.WHITE)
	c._glass.box(Vector3(mid.x, 3.5, mid.y), Vector3(r.size.x, 0.04, r.size.y), Color.WHITE)
	box(Vector3(mid.x, 3.45, mid.y), Vector3(0.2, 1.2, r.size.y), Color.WHITE, 0.0)
	for k in 40:
		var p := Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), 0.6, rng.randf_range(r.position.y + 1, r.end.y - 1))
		c._bush(p, rng.randf_range(0.6, 1.1))
	flowers(Rect2(-190, -60, 60, 60), 220)


func _lake() -> void:
	bridge(BOARDWALK, false)
	bridge(PIER, false)
	box(Vector3(101.5, 0.1, -172.5), Vector3(3.2, 0.2, 1.0), P.WOOD_DARK, 0.0)
	# Rowing boats, lily pads and a family of blocky ducks.
	for k in 3:
		var p := Vector3(96 + k * 4.0, -0.18, -176 - k)
		box(p, Vector3(1.4, 0.35, 3.2), [Color("e0524f"), Color("f4f4f0"), Color("3f86a8")][k], 0.0)
		box(p + Vector3(0, 0.1, 0), Vector3(1.0, 0.2, 2.6), P.WOOD, 0.0)
	for k in 30:
		var p := Vector3(rng.randf_range(LAKE.position.x + 3, LAKE.end.x - 3), -0.21, rng.randf_range(LAKE.position.y + 3, LAKE.end.y - 3))
		if absf(p.x - 129.5) > 4:
			box(p, Vector3(0.9, 0.04, 0.9), Color("4e9a3e"), 0.03)
	for k in 5:
		var p := Vector3(150 + k * 1.1, -0.15, -200 + (k % 2) * 0.8)
		var s := 1.0 if k == 0 else 0.6
		box(p, Vector3(0.4, 0.3, 0.6) * s, Color.WHITE if k > 0 else Color("f2e8d0"), 0.0)
		box(p + Vector3(0, 0.25, -0.25) * s, Vector3(0.22, 0.22, 0.22) * s, Color("3f8a45") if k == 0 else Color.WHITE, 0.0)
		box(p + Vector3(0, 0.22, -0.42) * s, Vector3(0.1, 0.06, 0.14) * s, Color("f2a93b"), 0.0)
	signpost(Vector2(100, -156), "LAKE QUIBBLE\nNO SWIMMING", facing(Vector2(0, 1)), Color("3f86a8"))
	for x in range(86, 182, 12):
		bench(Vector2(x, -156.5))


func _parking() -> void:
	principal_car(Vector2(126, -20.5))
	for row in 3:
		for k in 10:
			if rng.randf() < 0.3:
				continue
			car(Vector2(80 + k * 5.6, -46 + row * 11), false, [Color("e0524f"), Color("f4f4f0"), Color("3f86a8"), Color("26262e"), Color("f2a93b")][rng.randi() % 5])


func _construction() -> void:
	var r := SITE
	# Site fence with an opening on the south side.
	fence(true, r.position.x, r.end.x, r.position.y, [], [[160, 168]], 2.4)
	fence(false, r.position.y, r.end.y - 2, r.position.x, [], [], 2.4)
	# Crane: a lattice tower and a long jib.
	var base := Vector3(186, 0, 60)
	for k in 12:
		box(base + Vector3(0, 1.5 + k * 3.0, 0), Vector3(1.4, 3.0, 1.4), Color("ffd24a") if k % 2 == 0 else Color("f2a93b"), 0.0, k < 1)
	box(base + Vector3(-14, 36.5, 0), Vector3(34, 1.0, 1.0), Color("ffd24a"), 0.0)
	box(base + Vector3(3, 35.5, 0), Vector3(3, 3, 2.2), Color("f4f4f0"), 0.0)
	box(base + Vector3(-26, 30, 0), Vector3(0.06, 12, 0.06), P.METAL_DARK, 0.0)
	box(base + Vector3(-26, 23.6, 0), Vector3(1.6, 0.8, 1.6), P.WOOD, 0.0)
	collide(base + Vector3(0, 18, 0), Vector3(1.4, 36, 1.4))
	# Scaffolding ramp up to the top of the north wall, and a plank over it.
	var x0 := 170.0
	var x1 := 173.0
	var z0 := 70.0
	var z1 := 96.0
	var rise := 4.0
	var run := z1 - z0
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise) + 0.4
	c._collide(Vector3((x0 + x1) / 2.0, rise / 2.0 - 0.1, (z0 + z1) / 2.0), Vector3(x1 - x0, 0.2, length), -angle)
	var steps := 26
	for k in steps:
		var z := z0 + (k + 0.5) * run / steps
		var y := rise * (k + 0.5) / steps
		var rise_k := rise / steps
		box(Vector3((x0 + x1) / 2.0, y - rise_k / 2.0, z), Vector3(x1 - x0, 0.1 + rise_k, run / steps + 0.02), P.WOOD if k % 2 == 0 else P.WOOD_DARK, 0.03)
	for k in 7:
		var z := z0 + k * run / 6.0
		var y := rise * k / 6.0
		for x: float in [x0, x1]:
			box(Vector3(x, (y + 1.0) / 2.0, z), Vector3(0.1, y + 1.0, 0.1), P.METAL, 0.0)
		box(Vector3((x0 + x1) / 2.0, y / 2.0, z), Vector3(x1 - x0, 0.08, 0.08), P.METAL, 0.0)
	# Platform over the wall, then a drop into the fields outside.
	box(Vector3((x0 + x1) / 2.0, rise - 0.06, 99.0), Vector3(x1 - x0, 0.12, 6.4), P.WOOD, 0.02, true)
	for x: float in [x0, x1]:
		box(Vector3(x, rise / 2.0, 96.5), Vector3(0.1, rise, 0.1), P.METAL, 0.0)
	# Sand, cement, pipes.
	box(Vector3(150, 0.8, 80), Vector3(6, 1.6, 5), SAND, 0.04, true)
	box(Vector3(150, 1.8, 80), Vector3(4, 0.6, 3), SAND.lightened(0.05), 0.04, true)
	for k in 6:
		box(Vector3(158 + (k % 3) * 0.9, 0.2 + (k / 3) * 0.4, 62), Vector3(0.8, 0.4, 0.5), P.PAPER.darkened(0.1), 0.03, true)
	for k in 4:
		box(Vector3(160 + k * 1.3, 0.6, 88), Vector3(1.2, 1.2, 6), Color("a9a79f"), 0.02, true)
	signpost(Vector2(164, 47), "CONSTRUCTION SITE\nNO STUDENTS!", facing(Vector2(0, -1)), Color("f2a93b"), Color("26262e"))
	camera(Vector2(141, 51), 4.0, facing(Vector2(1, 1)), 0.9, 0.3)


func _fountain(at: Vector2) -> void:
	var p := Vector3(at.x, 0, at.y)
	box(p + Vector3(0, 0.3, 0), Vector3(8, 0.6, 8), P.STONE_DARK, 0.0, true)
	box(p + Vector3(0, 0.5, 0), Vector3(7, 0.1, 7), P.WATER, 0.0)
	box(p + Vector3(0, 1.25, 0), Vector3(1.2, 1.5, 1.2), P.STONE, 0.0, true)
	box(p + Vector3(0, 2.1, 0), Vector3(2.6, 0.3, 2.6), P.STONE, 0.0)
	box(p + Vector3(0, 2.3, 0), Vector3(2.2, 0.1, 2.2), P.WATER, 0.0)
	box(p + Vector3(0, 2.9, 0), Vector3(0.3, 1.2, 0.3), P.WATER.lightened(0.3), 0.0)
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		bench(Vector2(at.x + d.x * 8, at.y + d.z * 8))


func _staff_and_students() -> void:
	patrol("Coach", "Coach Brennan (Sports)", [Vector2(-88, -170), Vector2(-192, -170), Vector2(-193, -110), Vector2(-140, -112)], 1.9, 5.2, 15.0, "coach")
	patrol("Warden", "Mrs. Petrova (Hostel Warden)", [Vector2(-190, 40), Vector2(-60, 46), Vector2(70, 40)], 1.6, 4.6, 14.0, "teacher")
	patrol("Security3", "Officer Silva (Security)", [Vector2(8, -120), Vector2(190, -120), Vector2(191, -250), Vector2(140, -255),
		Vector2(70, -255), Vector2(70, -140)], 1.9, 5.0, 15.0, "guard")
	patrol("Dean", "Dean Fujimoto", [Vector2(-9, -118), Vector2(-9, -150), Vector2(-56, -150), Vector2(-60, -114)], 1.5, 4.6, 13.0, "teacher")
	patrol("Foreman", "Site Foreman Ruiz", [Vector2(150, 58), Vector2(192, 58), Vector2(192, 94), Vector2(178, 94), Vector2(192, 58)], 1.6, 4.8, 14.0, "builder")
	stroll([Vector2(-7, -118), Vector2(-7, -240)])
	stroll([Vector2(7, -118), Vector2(7, -200)])
	stroll([Vector2(-150, 40), Vector2(40, 40)])
	stroll([Vector2(90, -152), Vector2(180, -152)])
	stroll([Vector2(-48, -166), Vector2(-22, -186), Vector2(-48, -186)])
	stroll([Vector2(-120, -118), Vector2(30, -118)])


func _nav() -> void:
	for x: float in [-7.0, 7.0]:
		nav_line(Vector2(x, -114), Vector2(x, -258))
	nav_line(Vector2(0, -258), Vector2(0, -280))
	nav_line(Vector2(-200, -280), Vector2(200, -280), 12.0)
	nav_line(Vector2(-194, 40), Vector2(194, 40))
	nav_line(Vector2(-194, -120), Vector2(194, -120))
	nav_line(Vector2(-194, -255), Vector2(194, -255))
	nav_line(Vector2(-62, -250), Vector2(-62, 34))
	nav_line(Vector2(62, -250), Vector2(62, 34))
	nav_line(Vector2(-58, -114), Vector2(58, -114))
	nav_line(Vector2(-58, -114), Vector2(-58, 38))
	nav_line(Vector2(58, -114), Vector2(58, 38))
	nav_line(Vector2(-192, -250), Vector2(-192, -110))
	nav_line(Vector2(191, -250), Vector2(191, -126))
	nav_line(Vector2(191, -114), Vector2(191, 34))
	nav_line(Vector2(191, 46), Vector2(191, 94))
	nav_line(Vector2(129.5, -236), Vector2(129.5, -160), 8.0)
	nav_line(Vector2(84, -156), Vector2(182, -156))
	nav_line(Vector2(-55, -40), Vector2(-55, -150))
	nav_line(Vector2(-194, 46), Vector2(-194, 94))
	nav_line(Vector2(-194, -110), Vector2(-194, 30))
