extends RefCounted
## The single colour palette for the game: saturated, warm, toy-like.
## Keep every colour here so the diorama look stays consistent.

# Nature
const GRASS := Color("8cc45c")
const GRASS_DARK := Color("74b04e")
const LEAVES := [Color("5fae4a"), Color("4e9a3e"), Color("86c95a"), Color("3f8a45")]
const TRUNK := Color("8a5a3a")
const FLOWERS := [Color("ff6b8a"), Color("ffd24a"), Color("ffffff"), Color("b07cff"), Color("ff9a3c")]
const WATER := Color("7fd0ea")
const CLOUD := Color("ffffff")

# Buildings
const WALL := Color("f3e3c3")
const WALL_SHADE := Color("e7d2aa")
const DADO_INSIDE := Color("a9d3a4")
const DADO_OUTSIDE := Color("c8704f")
const TRIM := Color("d9774f")
const ROOF := Color("b9b0a4")
const BRICK := Color("b95c43")
const BRICK_CAP := Color("e2c9a6")
const STONE := Color("d9d0bf")
const STONE_DARK := Color("c4baa6")
const VERANDAH_A := Color("c0634a")
const VERANDAH_B := Color("a9533e")
const FLOOR_A := Color("efe4cc")
const FLOOR_B := Color("d9c6a4")
const ASPHALT := Color("4a4d57")
const LINE := Color("f4f1e6")
const COURT := Color("d9784c")

# Furniture
const WOOD := Color("b0703e")
const WOOD_DARK := Color("7a4a2a")
const METAL := Color("9aa3ad")
const METAL_DARK := Color("4a4f5a")
const BOARD := Color("2f5d4a")
const CHALK := Color("f3f6ee")
const PAPER := Color("fbf6e8")
const GLOW := Color("fff6e0")

# Uniform
const SHIRT := Color("f4f4f0")
const SHIRT_SHADE := Color("dcdfe6")
const TROUSERS := Color("2b3a67")
const SHOES := Color("26262e")
const BELT := Color("3a2d26")
const ID_CARD := Color("ffffff")
const ID_STRAP := Color("2f6fd6")

const CLASS_COLORS := [Color("e0524f"), Color("4f86e0"), Color("48b06a"), Color("9a62d6")]
const SKIN := [Color("f6d5b5"), Color("f2c9a0"), Color("e0ac7e"), Color("d09a6a"), Color("c68a5c"), Color("a86e45"), Color("8a5a36"), Color("6b4028")]
const HAIR := [Color("1f1a17"), Color("3b2618"), Color("5a3a22"), Color("8a4b2a"), Color("c9a25a"), Color("b9b6b0"), Color("3a5bc4"), Color("d65ba0")]
const EYES := [Color("1c1c24"), Color("4a2e1c"), Color("2f6fd6"), Color("3a8a4a"), Color("8a6a2a")]
const BAGS := [Color("e0524f"), Color("f2a93b"), Color("3aa4a0"), Color("5b6bd6"), Color("333845"), Color("d65ba0")]
const CLOTH := [Color("f4f4f0"), Color("2b3a67"), Color("26262e"), Color("5a5f6e"), Color("8a2a3a"), Color("2f6a4a"),
	Color("b8a06a"), Color("9fc6ea"), Color("f2b8c6"), Color("f2a93b"), Color("7a4a2a"), Color("5b6bd6")]

# Character-creator options (index = saved value).
const HAIR_STYLE_NAMES := ["Side fringe", "Long", "Spiky", "Ponytail", "Buzz cut", "Top bun", "Curly", "Mohawk"]
const HAIR_STYLES := 8
const FACIAL_NAMES := ["None", "Moustache", "Beard", "Stubble"]
const GLASSES_NAMES := ["None", "Round", "Square", "Shades"]
const HAT_NAMES := ["None", "Cap", "Beanie", "Headband"]
const BAG_STYLE_NAMES := ["Backpack", "Sling bag", "No bag"]
const HEIGHT_NAMES := ["Short", "Average", "Tall"]
const HEIGHTS := [0.94, 1.0, 1.06]
# [id, label, shirt, trousers/skirt, accent (jacket/vest/track/coat)]
const UNIFORMS := [
	["classic", "Classic", "f4f4f0", "2b3a67", "2b3a67"],
	["blazer", "Blazer", "f4f4f0", "3a3d47", "24315e"],
	["sweater", "Sweater vest", "f4f4f0", "2b3a67", "8a2a3a"],
	["sports", "Sports tracksuit", "f4f4f0", "24315e", "24315e"],
	["kurta", "Kurta", "f4f1e6", "f4f4f0", "f2a93b"],
	["skirt", "Skirt & socks", "f4f4f0", "2b3a67", "2b3a67"],
	["labcoat", "Lab coat", "9fc6ea", "3a3d47", "fbfbf6"],
]


static func uniform_index(id: String) -> int:
	for i in UNIFORMS.size():
		if UNIFORMS[i][0] == id:
			return i
	return 0


const TEACHER_SHIRTS := [Color("9fc6ea"), Color("f2b8c6"), Color("f4f1e6"), Color("c9e0a8")]
const TEACHER_TROUSERS := [Color("5a5f6e"), Color("6e5440"), Color("3a3d47")]
const KHAKI := Color("b8a06a")
const KHAKI_DARK := Color("8f7a4a")
const GREY_HAIR := Color("b9b6b0")


static func make_teacher_look(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"skin": SKIN[rng.randi() % SKIN.size()],
		"hair": GREY_HAIR if rng.randf() < 0.5 else HAIR[rng.randi() % HAIR.size()],
		"hair_style": [0, 4, 1][rng.randi() % 3],
		"glasses": rng.randf() < 0.7,
		"mustache": rng.randf() < 0.5,
		"shirt": TEACHER_SHIRTS[rng.randi() % TEACHER_SHIRTS.size()],
		"trousers": TEACHER_TROUSERS[rng.randi() % TEACHER_TROUSERS.size()],
		"tie": Color("24315e") if rng.randf() < 0.5 else null,
		"bag": null,
		"id_card": false,
		"book": true,
	}


static func make_guard_look(seed_value: int, cap: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"skin": SKIN[1 + rng.randi() % (SKIN.size() - 1)],
		"hair": HAIR[rng.randi() % HAIR.size()],
		"hair_style": 4,
		"glasses": false,
		"mustache": true,
		"shirt": KHAKI,
		"trousers": KHAKI_DARK,
		"tie": null,
		"bag": null,
		"id_card": false,
		"cap": Color("24315e") if cap else null,
	}


## Applies character-creator choices on top of a look. Colours arrive as
## "#rrggbb" strings (or old palette indices); everything is validated, since
## it comes from other players over the network.
static func apply_prefs(look: Dictionary, prefs: Dictionary) -> Dictionary:
	var legacy := {"skin": SKIN, "hair": HAIR, "bag": BAGS}
	for key in ["skin", "hair", "eyes", "shirt", "trousers", "accent", "shoes", "bag", "hat_color", "tie"]:
		if not prefs.has(key):
			continue
		var v: Variant = prefs[key]
		if v is String and Color.html_is_valid(v):
			look[key] = Color.html(v)
		elif (v is int or v is float) and legacy.has(key):
			var options: Array = legacy[key]
			look[key] = options[clampi(int(v), 0, options.size() - 1)]
	if prefs.has("uniform"):
		var u: Array = UNIFORMS[uniform_index(str(prefs.uniform))]
		look.uniform = u[0]
		look.shirt = look.get("shirt", Color(u[2])) if prefs.has("shirt") else Color(u[2])
		look.trousers = look.get("trousers", Color(u[3])) if prefs.has("trousers") else Color(u[3])
		look.accent = look.get("accent", Color(u[4])) if prefs.has("accent") else Color(u[4])
	for spec in [["hair_style", HAIR_STYLES], ["facial", FACIAL_NAMES.size()], ["hat", HAT_NAMES.size()],
			["bag_style", BAG_STYLE_NAMES.size()], ["glasses_style", GLASSES_NAMES.size()]]:
		if prefs.has(spec[0]):
			look[spec[0]] = clampi(int(prefs[spec[0]]), 0, spec[1] - 1)
	if prefs.has("glasses") and not prefs.has("glasses_style"):
		look.glasses_style = 1 if bool(prefs.glasses) else 0
	if prefs.has("height"):
		look.height = HEIGHTS[clampi(int(prefs.height), 0, HEIGHTS.size() - 1)]
	if int(look.get("bag_style", 0)) == 2:
		look.bag = null
	return look


## Deterministic appearance for a student. Tie colour marks the classroom.
static func make_look(seed_value: int, classroom: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"skin": SKIN[rng.randi() % SKIN.size()],
		"hair": HAIR[rng.randi() % 5],
		"hair_style": rng.randi() % HAIR_STYLES,
		"glasses": rng.randf() < 0.3,
		"bag": BAGS[rng.randi() % BAGS.size()],
		"tie": CLASS_COLORS[clampi(classroom, 0, CLASS_COLORS.size() - 1)],
		"uniform": "classic",
	}
