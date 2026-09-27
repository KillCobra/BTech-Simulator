extends RefCounted
## The maps. First Day uses the original small academic block; the others
## build their own big multi-storey university and the grounds around it.
## Index = map id (what the host picks and every peer builds).

const RANDOM := -1
## The maps offered in the lobby (and picked by Random). The others still build and
## play (dev: --map=N), they're just parked until First Day and Grand Campus are great.
const PLAYABLE := [0, 1]

const LIST := [
	{"name": "First Day", "about": "The small starter school. Sneak out of the compound and reach the chai stall. Learn the ropes here."},
	{"name": "Grand Campus", "about": "The Old Quadrangle: four 3-storey wings round a courtyard. Then boulevards, hostels, a stadium and a lake inside a very big wall."},
	{"name": "Whispering Pines", "about": "Pinewood Lodges: H-shaped 2-storey timber halls in a forest. Cross the river, dodge the rangers, catch the bus."},
	{"name": "Lagoon Island", "about": "The Marine Institute: a 3-storey white U on an island. Take the long bridge, sneak onto the ferry or hop the rocks."},
	{"name": "Downtown Campus", "about": "Quibble Towers: two 6-storey towers, classes up to the 5th floor. Then city streets, checkpoints and the metro."},
]

const SCRIPTS := [
	preload("res://scenes/world/maps/first_day.gd"),
	preload("res://scenes/world/maps/grand_campus.gd"),
	preload("res://scenes/world/maps/forest_campus.gd"),
	preload("res://scenes/world/maps/island_campus.gd"),
	preload("res://scenes/world/maps/city_campus.gd"),
]


static func builder(id: int) -> RefCounted:
	return SCRIPTS[clampi(id, 0, SCRIPTS.size() - 1)].new()


static func title(id: int) -> String:
	return LIST[clampi(id, 0, LIST.size() - 1)].name
