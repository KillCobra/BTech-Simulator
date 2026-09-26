extends "res://scenes/world/maps/grounds.gd"
## First Day: the small starter map. The original two-storey academic block
## inside its compound wall; sneak out and reach the chai stall across the road.

const CHAI := Rect2(-16, -50, 12, 8)


func _plan() -> void:
	classic = true
	c.world_rect = Rect2(-70, -60, 140, 130)
	c.bounds = c.world_rect.grow(10.0)  # the only way out is the chai stall
	c.escape_rects.append(CHAI)
	c.goal_text = "Sneak out of college and reach the CHAI STALL across the road.  [M] map"
	c.win_text = "Enjoy your chai."
	road(Rect2(-70, -41, 140, 6), true)
	walk(Rect2(-70, -35, 140, 1.6))
	walk(Rect2(-70, -42.4, 140, 1.4))
	map_rect(CHAI, Color("7fe0a0"), "", false, "building")


func _build() -> void:
	lay_paving()
	stall(Vector2(-10, -45), Color("ffd24a"), "CHAI  ·  SUTTA  ·  MAGGI", Vector2(0, 1))
	stall(Vector2(8, -46), Color("7fd0ea"), "PHOTOCOPY", Vector2(0, 1))
	nav_line(Vector2(0, -33), Vector2(0, -37))
	nav_line(Vector2(-60, -38), Vector2(60, -38), 8.0)
	for x in range(-54, 55, 6):
		for z in range(-58, 67, 6):
			var outside: bool = absi(x) > 42 or z > 27 or z < -44
			if not outside or rng.randf() > 0.6:
				continue
			var px := x + rng.randf_range(-1.5, 1.5)
			var pz := z + rng.randf_range(-1.5, 1.5)
			if free_at(px, pz) and not CHAI.grow(3).has_point(Vector2(px, pz)):
				tree(Vector2(px, pz))
	exit_marker(CHAI.get_center(), "Chai stall")
