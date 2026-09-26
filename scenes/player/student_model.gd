extends Node3D
## Blocky character (students, teachers, staff) with procedural walk/crouch/sit
## animation. Origin at the feet, facing -Z. ~1.72 m tall, eyes at ~1.58 m.
##
## Look keys (all optional except skin/hair): hair_style, eyes, facial (0-3) or
## mustache, glasses_style (0-3) or glasses, uniform (classic/blazer/sweater/
## sports/kurta/skirt/labcoat), shirt, trousers, accent, tie (Color/null), shoes,
## bag (Color/null), bag_style (0-2), hat (0-3), hat_color, cap (Color, guards),
## id_card, book, height.

const Voxel := preload("res://scripts/voxel.gd")
const P := preload("res://scripts/palette.gd")

const HIP_HEIGHT := 0.78
const CROUCH_HIP_HEIGHT := 0.46

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _phase := 0.0
var _crouch := 0.0
var _sit := 0.0  # 0 standing .. 1 seated
var _cup: MeshInstance3D


func build(look: Dictionary) -> void:
	var skin: Color = look.skin
	var uniform: String = look.get("uniform", "classic")
	var shirt: Color = look.get("shirt", P.SHIRT)
	var trousers: Color = look.get("trousers", P.TROUSERS)
	var accent: Color = look.get("accent", trousers)
	var shoes: Color = look.get("shoes", P.SHOES)
	var tie: Variant = look.get("tie", null)
	if uniform in ["sports", "kurta"]:
		tie = null
	var h: float = look.get("height", 1.0)
	scale = Vector3(1.0, h, 1.0) if h != 1.0 else Vector3.ONE

	_hips = _pivot(self, Vector3(0, HIP_HEIGHT, 0))
	_leg_l = _pivot(_hips, Vector3(-0.1, 0, 0))
	_leg_r = _pivot(_hips, Vector3(0.1, 0, 0))
	for leg in [_leg_l, _leg_r]:
		var v := Voxel.new()
		if uniform == "skirt":
			# Bare legs with knee socks under the skirt.
			v.box(Vector3(0, -0.2, 0), Vector3(0.15, 0.4, 0.17), skin)
			v.box(Vector3(0, -0.53, 0), Vector3(0.16, 0.3, 0.18), Color.WHITE)
		else:
			v.box(Vector3(0, -0.36, 0), Vector3(0.17, 0.72, 0.2), trousers)
			if uniform == "sports":
				v.box(Vector3(0.087 * (1 if leg == _leg_r else -1), -0.36, 0), Vector3(0.01, 0.7, 0.05), Color.WHITE)
		v.box(Vector3(0, -0.73, -0.035), Vector3(0.19, 0.1, 0.29), shoes)
		v.box(Vector3(0, -0.77, -0.035), Vector3(0.195, 0.025, 0.295), shoes.lightened(0.4) if uniform == "sports" else shoes.darkened(0.3))
		leg.add_child(v.to_instance())

	_torso = _pivot(_hips, Vector3.ZERO)
	var t := Voxel.new()
	_build_outfit(t, look, uniform, shirt, trousers, accent, tie)
	_build_bag(t, look)
	_torso.add_child(t.to_instance())

	# Sleeves follow the outermost layer (jacket, tracksuit, coat...).
	var sleeve: Color = accent if uniform in ["blazer", "sports", "labcoat"] else shirt
	if uniform == "kurta":
		sleeve = shirt
	_arm_l = _pivot(_torso, Vector3(-0.3, 0.52, 0))
	_arm_r = _pivot(_torso, Vector3(0.3, 0.52, 0))
	for arm in [_arm_l, _arm_r]:
		var a := Voxel.new()
		var long_sleeve: bool = uniform in ["blazer", "sports", "labcoat", "kurta"]
		a.box(Vector3(0, -0.12, 0), Vector3(0.15, 0.26, 0.17), sleeve)
		if long_sleeve:
			a.box(Vector3(0, -0.33, 0), Vector3(0.14, 0.18, 0.15), sleeve)
			if uniform == "sports":
				a.box(Vector3(0.075 * (1 if arm == _arm_r else -1), -0.2, 0), Vector3(0.01, 0.38, 0.05), Color.WHITE)
		else:
			a.box(Vector3(0, -0.34, 0), Vector3(0.12, 0.2, 0.13), skin)
		a.box(Vector3(0, -0.47, 0), Vector3(0.12, 0.08, 0.13), skin.darkened(0.08))
		if arm == _arm_l and look.get("book", false):
			a.box(Vector3(0, -0.46, -0.1), Vector3(0.05, 0.3, 0.22), Color("e0524f"))
		arm.add_child(a.to_instance())

	_head = _pivot(_torso, Vector3(0, 0.56, 0))
	var hd := Voxel.new()
	_build_head(hd, look, skin)
	_head.add_child(hd.to_instance())


func _build_outfit(t: Voxel, look: Dictionary, uniform: String, shirt: Color, trousers: Color, accent: Color, tie: Variant) -> void:
	# Base shirt, belt and collar.
	t.box(Vector3(0, 0.29, 0), Vector3(0.46, 0.56, 0.26), shirt)
	if uniform != "kurta":
		t.box(Vector3(0, 0.03, 0), Vector3(0.48, 0.07, 0.28), P.BELT)
		t.box(Vector3(0, 0.03, -0.142), Vector3(0.08, 0.05, 0.01), P.METAL)
	t.box(Vector3(-0.07, 0.54, -0.125), Vector3(0.1, 0.06, 0.03), shirt.darkened(0.1))
	t.box(Vector3(0.07, 0.54, -0.125), Vector3(0.1, 0.06, 0.03), shirt.darkened(0.1))
	if tie != null:
		var tc: Color = tie
		t.box(Vector3(0, 0.51, -0.14), Vector3(0.08, 0.07, 0.03), tc)
		t.box(Vector3(0, 0.31, -0.137), Vector3(0.07, 0.34, 0.02), tc)
		t.box(Vector3(0, 0.2, -0.139), Vector3(0.071, 0.04, 0.021), tc.lightened(0.35))
	elif uniform == "classic" or uniform == "labcoat":
		for k in 3:
			t.box(Vector3(0, 0.45 - k * 0.13, -0.135), Vector3(0.025, 0.025, 0.01), shirt.darkened(0.3))
	match uniform:
		"blazer":
			# Jacket open at the front to show shirt and tie, with lapels and buttons.
			for side in [-1.0, 1.0]:
				t.box(Vector3(side * 0.145, 0.27, -0.005), Vector3(0.18, 0.56, 0.28), accent)
				t.box(Vector3(side * 0.07, 0.44, -0.145), Vector3(0.05, 0.2, 0.012), accent.darkened(0.2))
			t.box(Vector3(0, 0.29, 0.07), Vector3(0.48, 0.56, 0.14), accent)
			t.box(Vector3(-0.15, 0.36, -0.147), Vector3(0.08, 0.05, 0.01), Color("ffd24a"))  # crest
			for k in 2:
				t.box(Vector3(0.075, 0.14 + k * 0.1, -0.147), Vector3(0.025, 0.025, 0.01), Color("ffd24a"))
		"sweater":
			# V-neck vest over the shirt.
			t.box(Vector3(0, 0.25, 0), Vector3(0.475, 0.44, 0.27), accent)
			for side in [-1.0, 1.0]:
				t.box(Vector3(side * 0.09, 0.44, -0.001), Vector3(0.12, 0.08, 0.27), accent)
			t.box(Vector3(0, 0.05, 0), Vector3(0.48, 0.05, 0.275), accent.darkened(0.2))
		"sports":
			# Zip-up track jacket with shoulder stripes.
			t.box(Vector3(0, 0.29, 0), Vector3(0.47, 0.57, 0.27), accent)
			t.box(Vector3(0, 0.29, -0.137), Vector3(0.02, 0.5, 0.01), Color.WHITE)
			for side in [-1.0, 1.0]:
				t.box(Vector3(side * 0.237, 0.29, 0), Vector3(0.01, 0.52, 0.06), Color.WHITE)
			t.box(Vector3(0, 0.56, 0), Vector3(0.36, 0.06, 0.28), accent.darkened(0.15))
		"kurta":
			# Long kurta down to the knees, with a patterned placket.
			t.box(Vector3(0, 0.12, 0), Vector3(0.48, 0.9, 0.28), shirt)
			t.box(Vector3(0, 0.4, -0.142), Vector3(0.06, 0.26, 0.01), accent)
			t.box(Vector3(0, -0.3, 0), Vector3(0.485, 0.05, 0.285), accent)
		"skirt":
			t.box(Vector3(0, -0.12, 0), Vector3(0.52, 0.26, 0.32), trousers)
			t.box(Vector3(0, -0.26, 0), Vector3(0.54, 0.04, 0.33), trousers.darkened(0.2))
		"labcoat":
			for side in [-1.0, 1.0]:
				t.box(Vector3(side * 0.15, 0.12, -0.004), Vector3(0.18, 0.9, 0.29), accent)
			t.box(Vector3(0, 0.12, 0.075), Vector3(0.49, 0.9, 0.15), accent)
			t.box(Vector3(0.16, 0.36, -0.15), Vector3(0.08, 0.1, 0.01), Color("9fc6ea"))  # pens
	if look.get("id_card", true):
		t.box(Vector3(0.1, 0.26, -0.152 if uniform in ["blazer", "labcoat", "sweater"] else -0.14), Vector3(0.1, 0.13, 0.012), P.ID_CARD)
		t.box(Vector3(0.1, 0.305, -0.16 if uniform in ["blazer", "labcoat", "sweater"] else -0.147), Vector3(0.1, 0.035, 0.005), P.ID_STRAP)


func _build_bag(t: Voxel, look: Dictionary) -> void:
	var bag: Variant = look.get("bag", null)
	if bag == null:
		return
	var b: Color = bag
	match int(look.get("bag_style", 0)):
		1:  # sling bag on the right hip, strap across the chest
			t.box(Vector3(0.26, 0.05, 0.02), Vector3(0.1, 0.24, 0.3), b)
			for k in 5:
				t.box(Vector3(0.16 - k * 0.075, 0.1 + k * 0.1, -0.145), Vector3(0.06, 0.07, 0.01), b.darkened(0.3))
				t.box(Vector3(-0.16 + k * 0.075, 0.1 + k * 0.1, 0.145), Vector3(0.06, 0.07, 0.01), b.darkened(0.3))
		_:
			t.box(Vector3(0, 0.3, 0.22), Vector3(0.4, 0.46, 0.18), b)
			t.box(Vector3(0, 0.22, 0.32), Vector3(0.3, 0.2, 0.05), b.darkened(0.2))
			t.box(Vector3(-0.19, 0.36, -0.132), Vector3(0.045, 0.36, 0.01), b.darkened(0.3))
			t.box(Vector3(0.19, 0.36, -0.132), Vector3(0.045, 0.36, 0.01), b.darkened(0.3))


func _build_head(h: Voxel, look: Dictionary, skin: Color) -> void:
	var eyes: Color = look.get("eyes", Color("1c1c24"))
	var hair: Color = look.hair
	h.box(Vector3(0, 0.03, 0), Vector3(0.14, 0.07, 0.14), skin.darkened(0.08))
	h.box(Vector3(0, 0.23, 0), Vector3(0.36, 0.34, 0.34), skin)
	for side in [-1.0, 1.0]:
		h.box(Vector3(side * 0.08, 0.24, -0.172), Vector3(0.05, 0.07, 0.01), eyes)
		h.box(Vector3(side * 0.08 + 0.012, 0.255, -0.1735), Vector3(0.015, 0.02, 0.005), Color.WHITE)
		h.box(Vector3(side * 0.13, 0.17, -0.171), Vector3(0.05, 0.03, 0.01), Color("ff9a8a"))
		h.box(Vector3(side * 0.08, 0.3, -0.172), Vector3(0.07, 0.02, 0.01), hair.darkened(0.15))  # eyebrows
	h.box(Vector3(0, 0.13, -0.172), Vector3(0.09, 0.02, 0.01), skin.darkened(0.35))

	var facial := int(look.get("facial", 1 if look.get("mustache", false) else 0))
	match facial:
		1:
			h.box(Vector3(0, 0.155, -0.175), Vector3(0.16, 0.035, 0.015), hair.darkened(0.2))
		2:
			h.box(Vector3(0, 0.155, -0.175), Vector3(0.16, 0.035, 0.015), hair.darkened(0.2))
			h.box(Vector3(0, 0.09, -0.16), Vector3(0.3, 0.12, 0.05), hair.darkened(0.15))
			for side in [-1.0, 1.0]:
				h.box(Vector3(side * 0.172, 0.16, -0.06), Vector3(0.03, 0.18, 0.16), hair.darkened(0.15))
		3:
			h.box(Vector3(0, 0.1, -0.1705), Vector3(0.28, 0.1, 0.008), skin.darkened(0.22))

	var glasses := int(look.get("glasses_style", 1 if look.get("glasses", false) else 0))
	if glasses > 0:
		var frame := Color("22232b") if glasses != 1 else Color("5a3a22")
		var lens := Color("bfe8ff") if glasses != 3 else Color("1c1c24")
		var gw := 0.11 if glasses == 1 else 0.13
		for side in [-1.0, 1.0]:
			h.box(Vector3(side * 0.08, 0.24, -0.18), Vector3(gw, 0.1 if glasses != 2 else 0.085, 0.012), frame)
			h.box(Vector3(side * 0.08, 0.24, -0.186), Vector3(gw - 0.035, 0.065 if glasses != 2 else 0.05, 0.004), lens)
		h.box(Vector3(0, 0.25, -0.18), Vector3(0.05, 0.015, 0.012), frame)

	_add_hair(h, hair, int(look.get("hair_style", 0)))

	var hat := int(look.get("hat", 0))
	var hat_color: Color = look.get("hat_color", Color("e0524f"))
	var cap: Variant = look.get("cap", null)
	if cap != null:
		hat = 1
		hat_color = cap
	match hat:
		1:
			h.box(Vector3(0, 0.45, 0.0), Vector3(0.4, 0.1, 0.38), hat_color)
			h.box(Vector3(0, 0.41, -0.24), Vector3(0.36, 0.03, 0.14), hat_color.darkened(0.2))
			h.box(Vector3(0, 0.45, -0.195), Vector3(0.08, 0.06, 0.01), Color("ffd24a"))
		2:
			h.box(Vector3(0, 0.45, 0.0), Vector3(0.4, 0.14, 0.38), hat_color)
			h.box(Vector3(0, 0.38, 0.0), Vector3(0.405, 0.05, 0.385), hat_color.darkened(0.2))
			h.box(Vector3(0, 0.55, 0.0), Vector3(0.1, 0.06, 0.1), Color.WHITE)
		3:
			h.box(Vector3(0, 0.37, 0.0), Vector3(0.385, 0.045, 0.365), hat_color)


func _add_hair(h: Voxel, c: Color, style: int) -> void:
	if style == 7:  # mohawk: shaved sides, tall strip
		for k in 4:
			h.box(Vector3(0, 0.46 + (k % 2) * 0.03, -0.12 + k * 0.09), Vector3(0.07, 0.12, 0.09), c)
		h.box(Vector3(0, 0.42, 0.01), Vector3(0.37, 0.02, 0.35), c.darkened(0.1))
		return
	h.box(Vector3(0, 0.42, 0.01), Vector3(0.38, 0.08, 0.37), c)
	h.box(Vector3(0, 0.29, 0.155), Vector3(0.38, 0.22, 0.07), c)
	h.box(Vector3(-0.185, 0.32, 0.04), Vector3(0.03, 0.14, 0.28), c)
	h.box(Vector3(0.185, 0.32, 0.04), Vector3(0.03, 0.14, 0.28), c)
	match style:
		0: # side fringe
			h.box(Vector3(-0.07, 0.37, -0.175), Vector3(0.24, 0.07, 0.04), c)
		1: # long
			h.box(Vector3(0, 0.16, 0.16), Vector3(0.38, 0.34, 0.07), c)
			h.box(Vector3(-0.19, 0.2, 0.03), Vector3(0.04, 0.3, 0.3), c)
			h.box(Vector3(0.19, 0.2, 0.03), Vector3(0.04, 0.3, 0.3), c)
			h.box(Vector3(0, 0.38, -0.175), Vector3(0.36, 0.05, 0.04), c)
		2: # spiky
			for i in 4:
				h.box(Vector3(-0.13 + i * 0.087, 0.49, -0.05 + (i % 2) * 0.1), Vector3(0.07, 0.08, 0.07), c)
		3: # ponytail
			h.box(Vector3(0, 0.36, 0.22), Vector3(0.12, 0.12, 0.08), c)
			h.box(Vector3(0, 0.2, 0.25), Vector3(0.08, 0.22, 0.06), c)
			h.box(Vector3(0, 0.38, -0.175), Vector3(0.36, 0.05, 0.04), c)
		5: # top bun
			h.box(Vector3(0, 0.52, 0.05), Vector3(0.16, 0.12, 0.16), c)
			h.box(Vector3(0, 0.38, -0.175), Vector3(0.36, 0.05, 0.04), c)
		6: # curly: extra volume all round
			for i in 3:
				for j in 3:
					h.box(Vector3(-0.13 + i * 0.13, 0.47 + ((i + j) % 2) * 0.03, -0.12 + j * 0.13), Vector3(0.14, 0.1, 0.14), c)
			h.box(Vector3(0, 0.36, -0.17), Vector3(0.38, 0.08, 0.05), c)
		_: # buzz cut: just the base cap
			pass


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## For the local player: the body still casts a shadow but the camera never sees it.
func set_shadow_only(on := true) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Shows or hides a chai glass in the right hand.
func set_holding(on: bool) -> void:
	if on == (_cup != null and _cup.visible):
		return
	if _cup == null:
		var v := Voxel.new()
		v.box(Vector3(0, -0.5, -0.1), Vector3(0.08, 0.11, 0.08), Color("c68a5c"))
		v.box(Vector3(0, -0.44, -0.1), Vector3(0.085, 0.02, 0.085), Color("e8d2b0"))
		_cup = v.to_instance()
		_arm_r.add_child(_cup)
	_cup.visible = on


## Hand up (asking a question): call after animate().
var _hand := 0.0


func pose_hand(delta: float, up: bool) -> void:
	_hand = move_toward(_hand, 1.0 if up else 0.0, delta * 4.0)
	if _hand <= 0.0:
		return
	var h := smoothstep(0.0, 1.0, _hand)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, PI * 0.95, h)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.25, h)


func animate(delta: float, speed: float, crouching: bool, sprinting: bool, look_pitch: float, sitting := false) -> void:
	var k := minf(1.0, delta * 12.0)
	# Sitting down (and getting up) takes about half a second: hips lower,
	# knees bend, and the body leans forward a little on the way.
	_sit = move_toward(_sit, 1.0 if sitting else 0.0, delta * 2.2)
	if _sit > 0.0:
		var s := smoothstep(0.0, 1.0, _sit)
		_hips.position.y = lerpf(HIP_HEIGHT, 0.5, s)
		_leg_l.rotation.x = 1.45 * s
		_leg_r.rotation.x = 1.45 * s
		_torso.rotation.x = -0.4 * sin(s * PI)
		_arm_l.rotation.x = 0.5 * s
		_arm_r.rotation.x = (0.7 if _cup and _cup.visible else 0.5) * s
		_head.rotation.x = lerpf(_head.rotation.x, clampf(look_pitch, -0.8, 0.8), k)
		return
	_crouch = lerpf(_crouch, 1.0 if crouching else 0.0, k)
	var amount := clampf(speed / 3.5, 0.0, 1.0) * (1.0 if sprinting else 0.65)
	_phase += delta * (4.0 + speed * 1.6) if speed > 0.2 else 0.0
	var swing := sin(_phase) * amount * 0.8

	_hips.position.y = lerpf(HIP_HEIGHT, CROUCH_HIP_HEIGHT, _crouch) + absf(cos(_phase)) * amount * 0.04
	var crouch_leg := _crouch * 1.1
	_leg_l.rotation.x = swing + crouch_leg
	_leg_r.rotation.x = -swing + crouch_leg
	_torso.rotation.x = lerpf(-0.08 * amount, -0.35, _crouch) if sprinting or _crouch > 0.01 else 0.0
	_arm_l.rotation.x = -swing * 0.9 + _crouch * 0.4
	_arm_r.rotation.x = 1.0 if _cup and _cup.visible else swing * 0.9 + _crouch * 0.4
	_arm_l.rotation.z = -0.06
	_arm_r.rotation.z = 0.06
	_head.rotation.x = lerpf(_head.rotation.x, clampf(look_pitch, -0.8, 0.8) - _torso.rotation.x, k)
