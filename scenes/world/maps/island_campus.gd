extends "res://scenes/world/maps/academic_kit.gd"
## Lagoon Island: the university fills a palm-fringed island. Ways off: the
## 150 m bridge to the mainland (toll guards at the island end, an officer
## walking it), sneaking aboard the ferry at the east pier, or hopping the
## rocks across the west lagoon to a fisherman's boat.
##
## The university is the Marine Institute: a three-storey U of white wings
## closed by a two-storey north block round a courtyard (x -60..60, z -44..30).
##
## Top view: institute at x -60..60, z -44..30; island x -190..190,
## z -210..80; mainland south of z -360.

const ISLAND := Rect2(-190, -210, 380, 290)
const BRIDGE := Rect2(-5, -362, 10, 154)
const PIER := Rect2(186, -62, 44, 6)
const FERRY := Rect2(230, -70, 22, 22)
const ISLET := Rect2(-252, -112, 20, 20)
const BOAT := Rect2(-259, -106, 6, 8)
const ROCKS_Z := -102.0

# [rect, floors, wall, trim, title, front]
const BUILDINGS := [
	[Rect2(60, -122, 40, 24), 3, Color("dfe6ea"), Color("3aa4a0"), "MARINE BIOLOGY", Vector2(-1, 0)],
	[Rect2(-110, -122, 46, 26), 2, Color("bfe3ea"), Color("2f6fd6"), "AQUARIUM", Vector2(1, 0)],
	[Rect2(-120, -64, 36, 22), 3, Color("f3e3c3"), Color("d9774f"), "ISLAND LIBRARY", Vector2(1, 0)],
	[Rect2(-150, 52, 44, 12), 4, Color("ffc9d6"), Color("e0524f"), "CORAL HOUSE", Vector2(0, -1)],
	[Rect2(-80, 52, 44, 12), 4, Color("fff0c9"), Color("f2a93b"), "SHELL HOUSE", Vector2(0, -1)],
	[Rect2(100, 52, 44, 12), 4, Color("c9f0e0"), Color("48b06a"), "REEF HOUSE", Vector2(0, -1)],
	[Rect2(140, -96, 20, 18), 1, Color("f4f4f0"), Color("3f86a8"), "BOATHOUSE", Vector2(0, 1)],
	[Rect2(110, -44, 34, 20), 2, Color("f2d7a0"), Color("9a62d6"), "STUDENT UNION", Vector2(-1, 0)],
]


func _plan() -> void:
	c.bounds = Rect2(-260, -360, 520, 500)
	c.world_rect = Rect2(-260, -420, 520, 560)
	c.escape_rects.append(FERRY)
	c.escape_rects.append(BOAT)
	c.goal_text = "ESCAPE THE UNIVERSITY!  The bridge, the ferry, or hop the rocks to a boat.  [M] map"
	c.win_text = "Sea breeze, no attendance. Perfect."
	c.map_outside = Color("5cb6e0")
	# The sea, in four pieces around the island (and around the islet).
	var sea := Color("4aa8d0")
	map_rect(c.world_rect, sea)
	water(Rect2(-260, 80, 520, 60), Vector3.ZERO, "", Vector2(0, -1), false)
	water(Rect2(190, -360, 70, 440), Vector3.ZERO, "", Vector2(-1, 0), false)
	water(Rect2(-190, -360, 380, 150), Vector3.ZERO, "Lagoon", Vector2(0, 1), false)
	water(Rect2(-260, -360, 70, 248), Vector3.ZERO, "", Vector2(1, 0), false)
	water(Rect2(-260, -92, 70, 172), Vector3.ZERO, "", Vector2(1, 0), false)
	water(Rect2(-232, -112, 42, 20), Vector3.ZERO, "", Vector2(1, 0), false)
	water(Rect2(-260, -112, 8, 20), Vector3(-242, 0, -96), "", Vector2.ZERO, false)
	bridge_area(BRIDGE)
	bridge_area(PIER)
	bridge_area(FERRY)
	bridge_area(BOAT)
	map_rect(ISLAND, Color("78b457"))
	map_rect(ISLET, SAND)
	map_rect(Rect2(-260, -420, 520, 60), Color("78b457"))
	# Beaches all round the island.
	walk(Rect2(-190, 66, 380, 14), SAND, SAND_DARK)
	walk(Rect2(-190, -210, 380, 14), SAND, SAND_DARK, "Beach")
	walk(Rect2(-190, -196, 14, 262), SAND, SAND_DARK)
	walk(Rect2(176, -196, 14, 262), SAND, SAND_DARK)
	walk(ISLET, SAND, SAND_DARK)
	walk(Rect2(-260, -366, 520, 8), SAND, SAND_DARK)
	# Roads.
	c.academic_rect = Rect2(-62, -46, 124, 78)
	road(Rect2(-4, -196, 8, 150), false)                 # toll plaza -> institute
	walk(Rect2(-20, -50, 40, 6))                         # forecourt
	walk(Rect2(66, -46, 26, 14), P.ASPHALT, P.ASPHALT.lightened(0.05), "Parking")
	road(Rect2(-172, 40, 344, 8), true)                  # north ring
	road(Rect2(-172, -182, 344, 8), true)                # south ring
	road(Rect2(-172, -182, 8, 230), false)               # west ring
	road(Rect2(164, -182, 8, 230), false)                # east ring
	road(Rect2(164, -62, 24, 6), true, false)            # to the pier
	road(Rect2(60, -8, 104, 6), true, false)             # institute -> east ring
	road(Rect2(-260, -404, 520, 10), true)               # mainland coast road
	walk(Rect2(-14, -210, 28, 14), P.STONE, P.STONE_DARK, "Toll")
	walk(Rect2(-3, 30.4, 6, 9.6))                        # north block -> north ring
	# Winding island paths between the buildings (not everything follows the ring road).
	curve_walk([Vector2(-60, -108), Vector2(-56, -92), Vector2(-68, -78), Vector2(-78, -68), Vector2(-80, -54)], 2.6)  # aquarium -> library
	curve_walk([Vector2(56, -110), Vector2(44, -96), Vector2(30, -78), Vector2(14, -62), Vector2(5, -52)], 2.6)  # marine biology -> institute
	curve_walk([Vector2(150, -74), Vector2(140, -63), Vector2(124, -58), Vector2(108, -50), Vector2(104, -36)], 2.6)  # boathouse -> union
	for b in BUILDINGS:
		reserve((b[0] as Rect2).grow(0.6))
		map_rect(b[0], (b[2] as Color).darkened(0.3), (b[4] as String).capitalize(), false, "building")
	keep_clear(Rect2(-10, -196, 20, 163))                # along the main road
	keep_clear(Rect2(102, -180, 4, 176))                 # staff shortcut east of the institute
	reserve(Rect2(-170, 60, 10, 10))                     # lighthouse
	map_rect(Rect2(-170, 60, 10, 10), Color.WHITE, "Lighthouse", false, "building")


func _build() -> void:
	lay_paving()
	lay_water()
	_institute()
	_shores()
	for b in BUILDINGS:
		building(b[0], b[1], b[2], b[3], b[4], b[5])
	_bridge()
	_ferry()
	_rocks_and_boat()
	_lighthouse(Vector2(-165, 65))
	_beach_life()
	_mainland()
	_staff_and_students()
	_nav()
	forest(ISLAND.grow(-2), 520, [0, 2], true)
	forest(Rect2(-150, -170, 300, 200), 260, [0, 2])
	forest(Rect2(-256, -418, 512, 50), 120, [0], true)
	bushes(ISLAND, 300)
	flowers(ISLAND, 700)
	exit_marker(Vector2(0, -364), "Bridge to the mainland (guarded)")
	exit_marker(FERRY.get_center(), "Ferry (east pier)")
	exit_marker(BOAT.get_center(), "Fishing boat (rock hop)")


## The Marine Institute: a U of three-storey wings, closed by a two-storey north block.
func _institute() -> void:
	begin_campus()
	style = {
		"wall": Color("f4f4f0"), "trim": Color("3aa4a0"), "floor": [Color("eef3f4"), Color("d9e6e8")],
		"hall": [Color("bfe3ea"), Color("a9d3de")], "dado_in": Color("7fd0ea"), "dado_hall": Color("3aa4a0"),
		"dado_out": Color("3f86a8"), "frame": Color("3aa4a0"), "roof": Color("d9d0bf"), "ceiling": Color("fbfbf6"),
	}
	# Main block: entrance towards the bridge.
	wing(Rect2(-60, -44, 120, 20), true, 3, [
		[["staff", 12], ["washroom", 8], ["office", 10], ["library", 16], ["store", 4.2], ["lobby", 10, {"gate": true, "name": "Marine Institute"}],
			["class", 10, {"idx": 0}], ["computer", 12], ["detention", 8], ["store", 25.2]],
		[["empty", 10], ["lecture", 18], ["empty", 10, {"kids": true}], ["washroom", 8], ["computer", 12], ["empty", 10], ["art", 12], ["store", 30.4]],
		[["lecture", 18], ["empty", 10], ["empty", 10], ["music", 12], ["washroom", 8], ["empty", 10, {"kids": true}], ["store", 42.4]],
	], [
		[["lecture", 18], ["passage", 6], ["canteen", 24], ["passage", 10], ["music", 12], ["empty", 10], ["passage", 6], ["store", 34]],
		[["empty", 10], ["empty", 10], ["lecture", 18], ["computer", 12], ["store", 70]],
		[["art", 12], ["empty", 10], ["lecture", 18], ["empty", 10], ["store", 70]],
	], {"title": c.UNI_NAME, "front": "a", "cams": [0, 1, 2]})
	# West arm (courtyard on its east side).
	wing(Rect2(-60, -23.6, 20, 54), false, 3, [
		[["empty", 10], ["washroom", 8], ["store", 26.4]],
		[["empty", 10, {"kids": true}], ["computer", 12], ["store", 22.4]],
		[["class", 10, {"idx": 2}], ["washroom", 8], ["store", 26.4]],
	], [
		[["passage", 6], ["empty", 10], ["passage", 6], ["store", 32]],
		[["lecture", 18], ["store", 36]],
		[["empty", 10], ["art", 12], ["store", 32]],
	], {"ends": [false, true], "cams": [2]})
	# East arm; its north end is the locked staff door.
	wing(Rect2(40, -23.6, 20, 54), false, 3, [
		[["passage", 6], ["empty", 10], ["passage", 6], ["store", 32]],
		[["class", 10, {"idx": 1}], ["empty", 10], ["store", 34]],
		[["empty", 10], ["music", 12], ["store", 32]],
	], [
		[["computer", 12], ["washroom", 8], ["store", 24.4]],
		[["empty", 10, {"kids": true}], ["lecture", 18], ["store", 16.4]],
		[["lecture", 18], ["empty", 10], ["store", 16.4]],
	], {"ends": [false, true], "cams": [1]})
	service_door(Vector3(50.0, 0, 30.4), true)
	# North block: two storeys between the arms.
	wing(Rect2(-39.6, 10.4, 79.2, 20), true, 2, [
		[["passage", 6], ["empty", 10], ["washroom", 8], ["passage", 6], ["empty", 10], ["store", 29.8]],
		[["empty", 10], ["lab", 10, {"idx": 3}], ["computer", 12], ["store", 37.8]],
	], [
		[["lecture", 18], ["passage", 6], ["music", 12], ["store", 43.2]],
		[["empty", 10], ["lecture", 18], ["store", 51.2]],
	], {"ends": [false, false], "cams": [1]})
	# Courtyard with a pool and the court.
	slab(Rect2(-39.6, -23.4, 79.2, 33.6), 0.04, 0.08, P.STONE, 0.02, P.STONE_DARK)
	court(Vector2(-22, -7))
	assembly_point(Vector2(22, -14))
	box(Vector3(16, 0.1, 2), Vector3(14, 0.2, 7), Color("3f86a8"), 0.0)
	box(Vector3(16, 0.21, 2), Vector3(13, 0.02, 6), P.WATER.lightened(0.1), 0.0)
	for p: Vector2 in [Vector2(-36, 6), Vector2(36, 6), Vector2(-4, -20), Vector2(34, -20)]:
		palm(p)
	principal_car(Vector2(78, -39))
	nav_line(Vector2(-36, -12), Vector2(36, -12))
	nav_line(Vector2(0, -22), Vector2(0, 8))
	c.staff_loops = {
		"peon": [Vector3(-54, 0, -34), Vector3(54, 0, -34), Vector3(0, 0, -34), Vector3(0, 0, -12), Vector3(0, 0, -34)],
		"prefect": [Vector3(-36, 0, -12), Vector3(36, 0, -12), Vector3(0, 0, 8), Vector3(0, 0, -20)],
		"proctor": [Vector3(-54, 3.6, -34), Vector3(54, 3.6, -34), Vector3(50, 3.6, -18), Vector3(50, 3.6, 26), Vector3(50, 3.6, -18)],
		"vp": [Vector3(-50, 7.2, -18), Vector3(-50, 7.2, 26), Vector3(-50, 7.2, -18), Vector3(-54, 7.2, -34), Vector3(54, 7.2, -34)],
	}
	c.core_walks = [
		[Vector3(-50, 0, -34), Vector3(50, 0, -34)],
		[Vector3(-30, 0, -12), Vector3(30, 0, -12)],
		[Vector3(-50, 3.6, -34), Vector3(50, 3.6, -34)],
		[Vector3(-30, 0, 20.4), Vector3(30, 0, 20.4)],
	]
	finish_campus()


## Sand dropping into the water all round the land.
func _shores() -> void:
	var edge := func(center: Vector3, size: Vector3):
		c._vbox(center, size, SAND_DARK)
	for r: Rect2 in [ISLAND, ISLET]:
		var m := r.get_center()
		edge.call(Vector3(m.x, -0.17, r.position.y - 0.2), Vector3(r.size.x + 0.8, 0.34, 0.4))
		edge.call(Vector3(m.x, -0.17, r.end.y + 0.2), Vector3(r.size.x + 0.8, 0.34, 0.4))
		edge.call(Vector3(r.position.x - 0.2, -0.17, m.y), Vector3(0.4, 0.34, r.size.y))
		edge.call(Vector3(r.end.x + 0.2, -0.17, m.y), Vector3(0.4, 0.34, r.size.y))
	edge.call(Vector3(0, -0.17, -359.8), Vector3(520, 0.34, 0.4))
	# Surf: a pale line just offshore.
	for k in 40:
		var x := -185.0 + k * 9.5
		box(Vector3(x, -0.2, -211.2), Vector3(6.0, 0.03, 0.5), Color("e8f6fb"), 0.0)
		box(Vector3(x, -0.2, 81.2), Vector3(6.0, 0.03, 0.5), Color("e8f6fb"), 0.0)


func _bridge() -> void:
	var deck := Color("b9b6b0")
	bridge(BRIDGE, false, true, deck)
	for z in range(-218, -356, -12):
		for x: float in [-4.6, 4.6]:
			lamp(Vector2(x, z))
		box(Vector3(0, -1.6, z), Vector3(8, 3.2, 1.2), deck.darkened(0.2), 0.0)  # piers into the sea
	for z in range(-210, -362, -3):
		box(Vector3(0, 0.045, z + 1.5), Vector3(0.14, 0.02, 1.4), P.LINE, 0.0)
	# Toll plaza.
	booth(Vector2(-10.5, -201), "TOLL")
	booth(Vector2(10.5, -201), "TOLL")
	barrier(Vector2(-4.4, -204))
	barrier(Vector2(4.4, -206))
	var zone := Rect2(-16, -214, 32, 22)
	post("TollGuard1", "Officer Tamura (Toll)", Vector2(-6.5, -199), Vector2(0.2, 1), zone, 501)
	post("TollGuard2", "Officer Diallo (Toll)", Vector2(6.5, -203), Vector2(-0.2, 1), zone, 502)
	camera(Vector2(-12.5, -206), 4.4, facing(Vector2(0.4, 1)), 0.6, 0.3)
	camera(Vector2(12.5, -206), 4.4, facing(Vector2(-0.4, 1)), 0.6, 0.35)
	signpost(Vector2(-14, -190), "MAINLAND BRIDGE\nSTUDENTS: EXIT PASS ONLY", facing(Vector2(0, 1)), Color("24315e"), Color("ffd24a"))
	gate(Vector2(0, -209.5), true, 10.0, Vector2(0, -1), c.UNI_NAME, "Mind the gulls!")


func _ferry() -> void:
	bridge(PIER, true, true)
	var f := FERRY
	var m := f.get_center()
	var hull := Color("e0524f")
	box(Vector3(m.x, -0.9, m.y), Vector3(f.size.x, 1.8, f.size.y), hull, 0.0)
	box(Vector3(m.x, -0.02, m.y), Vector3(f.size.x, 0.14, f.size.y), P.WOOD.lightened(0.1), 0.02)
	collide(Vector3(m.x, -0.1, m.y), Vector3(f.size.x, 0.2, f.size.y))
	for side: float in [-1.0, 1.0]:
		box(Vector3(m.x, 0.5, m.y + side * (f.size.y / 2.0 - 0.1)), Vector3(f.size.x, 1.0, 0.2), Color.WHITE, 0.0, true)
	box(Vector3(f.end.x - 0.1, 0.5, m.y), Vector3(0.2, 1.0, f.size.y), Color.WHITE, 0.0, true)
	# Cabin, funnel, lifebuoys.
	box(Vector3(m.x + 5, 1.6, m.y), Vector3(8, 3.2, 12), Color.WHITE, 0.0, true)
	for k in 4:
		box(Vector3(m.x + 1.0 - 0.05, 2.0, m.y - 4.5 + k * 3.0), Vector3(0.1, 1.0, 1.6), GLASS, 0.0)
	box(Vector3(m.x + 7, 4.4, m.y), Vector3(2.0, 2.4, 2.0), Color("ffd24a"), 0.0)
	box(Vector3(m.x + 7, 5.7, m.y), Vector3(2.1, 0.3, 2.1), Color("26262e"), 0.0)
	label("ISLAND FERRY", Vector3(m.x + 0.9, 2.9, m.y), 70, Color("24315e"), -PI / 2, 10)
	var post_at := Vector2(PIER.position.x - 3, PIER.get_center().y - 3)
	post("Harbor", "Harbor Master Olsen", post_at, Vector2(-1, 0.3), Rect2(176, -70, 16, 22), 503)
	camera(Vector2(190, -55.5), 3.8, facing(Vector2(-1, -0.2)), 0.8, 0.35)
	signpost(Vector2(183, -66), "FERRY TO THE CITY\nSTAFF & VISITORS ONLY", facing(Vector2(-1, 0)), Color("3f86a8"))


func _rocks_and_boat() -> void:
	var pts := []
	for k in 19:
		pts.append(Vector2(-191.5 - k * 2.15, ROCKS_Z + sin(k * 0.9) * 1.4))
	stones(pts, 1.3)
	signpost(Vector2(-180, ROCKS_Z + 5), "DANGER\nSLIPPERY ROCKS", facing(Vector2(1, 0)), Color("e0524f"))
	# The islet: a fisherman's hut and a little boat tied up on the far side.
	var hut := Vector3(-240, 0, -98)
	box(hut + Vector3(0, 1.1, 0), Vector3(4, 2.2, 3), P.WOOD, 0.03, true)
	box(hut + Vector3(0, 2.4, 0), Vector3(4.6, 0.3, 3.6), Color("3f86a8"), 0.02)
	for k in 3:
		box(hut + Vector3(-1.5 + k * 1.5, 0.3, 2.2), Vector3(0.6, 0.6, 0.6), P.WOOD_DARK, 0.03, true)
	palm(Vector2(-236, -108))
	palm(Vector2(-248, -94))
	var b := BOAT
	var m := b.get_center()
	box(Vector3(m.x, -0.6, m.y), Vector3(b.size.x, 1.2, b.size.y), Color("3f86a8"), 0.0)
	box(Vector3(m.x, -0.02, m.y), Vector3(b.size.x - 0.4, 0.12, b.size.y - 0.4), P.WOOD, 0.02)
	collide(Vector3(m.x, -0.1, m.y), Vector3(b.size.x, 0.2, b.size.y))
	box(Vector3(m.x, 1.8, m.y), Vector3(0.14, 3.6, 0.14), P.WOOD_DARK, 0.0)
	box(Vector3(m.x, 2.2, m.y - 0.95), Vector3(0.04, 2.4, 1.8), Color.WHITE, 0.0)
	bridge(Rect2(-253, -103.5, 1.2, 3), true, false)  # plank from the islet to the boat
	bridge_area(Rect2(-253, -103.5, 1.2, 3))


func _lighthouse(at: Vector2) -> void:
	var p := Vector3(at.x, 0, at.y)
	for k in 9:
		var s := 4.0 - k * 0.2
		box(p + Vector3(0, 1.0 + k * 2.0, 0), Vector3(s, 2.0, s), Color.WHITE if k % 2 == 0 else Color("e0524f"), 0.0, k < 2)
	collide(p + Vector3(0, 9, 0), Vector3(3.6, 18, 3.6))
	box(p + Vector3(0, 18.2, 0), Vector3(3.4, 0.4, 3.4), P.METAL_DARK, 0.0)
	glow(p + Vector3(0, 19.2, 0), Vector3(1.8, 1.6, 1.8))
	box(p + Vector3(0, 20.3, 0), Vector3(2.6, 0.6, 2.6), Color("e0524f"), 0.0)
	var beam := OmniLight3D.new()
	beam.position = p + Vector3(0, 19.2, 0)
	beam.light_color = Color(1.0, 0.95, 0.7)
	beam.omni_range = 18.0
	c._root.add_child(beam)
	camera(Vector2(at.x + 2.3, at.y - 2.3), 3.5, 0.0, PI, 0.15)


func _beach_life() -> void:
	# Umbrellas and loungers along the south and north beaches.
	for k in 22:
		var x := -170.0 + k * 16.0 + rng.randf_range(-3, 3)
		for z: float in [-206.0, 76.0]:
			if absf(x) < 20 or rng.randf() < 0.35:
				continue
			var col: Color = [Color("e0524f"), Color("ffd24a"), Color("3f86a8"), Color("ff8ab0")][rng.randi() % 4]
			box(Vector3(x, 1.2, z), Vector3(0.1, 2.4, 0.1), Color.WHITE, 0.0, true)
			box(Vector3(x, 2.4, z), Vector3(2.6, 0.18, 2.6), col, 0.0)
			box(Vector3(x, 2.55, z), Vector3(1.6, 0.14, 1.6), col.lightened(0.15), 0.0)
			box(Vector3(x + 1.2, 0.25, z + 0.4), Vector3(0.8, 0.12, 1.9), Color.WHITE, 0.02)
			for lx: float in [-0.34, 0.34]:
				for lz: float in [-0.85, 0.85]:
					box(Vector3(x + 1.2 + lx, 0.1, z + 0.4 + lz), Vector3(0.06, 0.2, 0.06), Color.WHITE, 0.0)
			box(Vector3(x + 1.2, 0.45, z + 1.2), Vector3(0.8, 0.4, 0.12), Color.WHITE, 0.0)
	# Beach volleyball.
	var v := Vector3(-40, 0, -205)
	for dx: float in [-5.0, 5.0]:
		box(v + Vector3(dx, 1.2, 0), Vector3(0.12, 2.4, 0.12), Color.WHITE, 0.0, true)
	box(v + Vector3(0, 2.1, 0), Vector3(10, 0.6, 0.03), Color("26262e"), 0.0)
	box(v + Vector3(0, 0.02, 0), Vector3(16, 0.04, 8), SAND.lightened(0.05), 0.0)
	# Surf club hut and a sign.
	stall(Vector2(150, -206), Color("48b06a"), "SURF CLUB", Vector2(0, 1))
	stall(Vector2(-120, 76), Color("ffd24a"), "COCONUTS", Vector2(0, -1))
	signpost(Vector2(-12, -186), "WELCOME TO LAGOON ISLAND\nNO SWIMMING IN CLASS HOURS", facing(Vector2(0, -1)), Color("3aa4a0"))


func _mainland() -> void:
	stall(Vector2(-18, -372), Color("ffd24a"), "SHACK CAFE  ·  CHAI", Vector2(0, 1))
	stall(Vector2(18, -372), Color("ff8ab0"), "ICE CREAM", Vector2(0, 1))
	bus(Vector2(40, -399), true, Color("3f86a8"), "CITY 9")
	signpost(Vector2(10, -368), "MAINLAND\nYOU MADE IT", facing(Vector2(0, 1)), Color("48b06a"))
	for x in range(-250, 251, 16):
		if absf(x) > 30:
			palm(Vector2(x + rng.randf_range(-3, 3), -386 + rng.randf_range(-3, 3)))


func _staff_and_students() -> void:
	patrol("BridgeCop", "Officer Byrne (Bridge)", [Vector2(2.5, -216), Vector2(2.5, -356)], 1.6, 5.0, 15.0, "guard")
	patrol("Lifeguard", "Lifeguard Santos", [Vector2(-183, -190), Vector2(-183, 60)], 1.8, 5.2, 15.0, "coach")
	patrol("Coach", "Coach Mwangi", [Vector2(-150, -199.5), Vector2(150, -199.5)], 1.8, 5.0, 14.0, "coach")
	patrol("Warden", "Ms. Rahimi (Hostel Warden)", [Vector2(-168, 44), Vector2(168, 44)], 1.6, 4.6, 14.0, "teacher")
	patrol("Marine", "Dr. Laurent (Marine Biology)", [Vector2(168, 40), Vector2(168, -178), Vector2(104, -178), Vector2(104, -5), Vector2(160, -5)], 1.5, 4.6, 13.0, "teacher")
	patrol("Security", "Officer Petrov (Security)", [Vector2(-168, 40), Vector2(-168, -178), Vector2(-6, -178), Vector2(-6, -48)], 1.8, 5.0, 14.0, "guard")
	stroll([Vector2(-100, -199.5), Vector2(100, -199.5)])
	stroll([Vector2(-150, 69.5), Vector2(150, 69.5)])
	stroll([Vector2(6, -48), Vector2(6, -180)])
	stroll([Vector2(170, -30), Vector2(170, -150)])
	stroll([Vector2(-60, 44), Vector2(80, 44)])


func _nav() -> void:
	nav_line(Vector2(0, -47), Vector2(0, -196))
	nav_line(Vector2(-64, -47), Vector2(64, -47))
	nav_line(Vector2(-64, -47), Vector2(-64, 34))
	nav_line(Vector2(64, -47), Vector2(64, 34))
	nav_line(Vector2(-64, 34), Vector2(64, 34))
	nav_line(Vector2(0, -196), Vector2(0, -362), 8.0)
	nav_line(Vector2(-168, 44), Vector2(168, 44))
	nav_line(Vector2(-168, -178), Vector2(168, -178))
	nav_line(Vector2(-168, -178), Vector2(-168, 44))
	nav_line(Vector2(168, -178), Vector2(168, 44))
	nav_line(Vector2(168, -59), Vector2(229, -59), 6.0)
	nav_line(Vector2(62, -5), Vector2(164, -5))
	nav_line(Vector2(0, 32), Vector2(0, 40))
	nav_line(Vector2(-183, -199.5), Vector2(183, -199.5), 12.0)
	nav_line(Vector2(-183, 69.5), Vector2(183, 69.5), 12.0)
	nav_line(Vector2(104, -178), Vector2(104, -5))
	nav_line(Vector2(-6, -178), Vector2(-6, -48))
	nav_line(Vector2(-183, -196), Vector2(-183, 66), 12.0)
	nav_line(Vector2(183, -196), Vector2(183, 66), 12.0)
	nav_line(Vector2(-250, -380), Vector2(250, -380), 12.0)
