extends Node3D
## First-person hands. At rest they hang low and relaxed at the bottom corners
## (just fists and cuffs in view). They sway a little when walking, pump when
## sprinting, and play short gestures: reach (E), shove (click), throw, and a
## two-handed hold while carrying the basketball. Local player only.

const Voxel := preload("res://scripts/voxel.gd")
const P := preload("res://scripts/palette.gd")

# Relaxed: low, close to the body, knuckles angled slightly inward.
const REST_L := Vector3(-0.23, -0.35, -0.3)
const REST_R := Vector3(0.23, -0.35, -0.3)
const REST_ROT_L := Vector3(0.55, 0.28, 0.12)
const REST_ROT_R := Vector3(0.55, -0.28, -0.12)
# Carrying the ball: both hands wrap it from the sides, in front and low.
const HOLD_L := Vector3(-0.2, -0.37, -0.44)
const HOLD_R := Vector3(0.2, -0.37, -0.44)
const HOLD_ROT_L := Vector3(0.3, -0.7, -0.4)
const HOLD_ROT_R := Vector3(0.3, 0.7, 0.4)

# Phone out: the right hand comes up, holding the phone screen towards you.
const PHONE_R := Vector3(0.17, -0.27, -0.34)
const PHONE_ROT_R := Vector3(1.25, -0.35, -0.1)

var holding := false
var phone_out := false

var _arm_l: Node3D
var _arm_r: Node3D
var _bob := 0.0
var _sway := Vector2.ZERO
var _sprint := 0.0
var _crouch := 0.0
var _hold := 0.0
var _phone := 0.0
var _phone_mesh: Node3D
var _land := 0.0
var _was_on_floor := true
var _gesture := ""
var _gesture_t := 0.0
const GESTURES := {"reach": 0.32, "shove": 0.34, "throw": 0.4, "raise": 2.4}


func build(look: Dictionary) -> void:
	var uniform: String = look.get("uniform", "classic")
	var sleeve: Color = look.get("shirt", P.SHIRT)
	if uniform in ["blazer", "sports", "labcoat"]:
		sleeve = look.get("accent", sleeve)
	_arm_l = _make_arm(look.skin, sleeve, true)
	_arm_r = _make_arm(look.skin, sleeve, false)
	_phone_mesh = _make_phone()
	_arm_r.add_child(_phone_mesh)


## A small phone in the fist, screen on top (facing you once the arm is raised).
func _make_phone() -> Node3D:
	var v := Voxel.new()
	v.box(Vector3(0, 0.03, -0.16), Vector3(0.078, 0.014, 0.15), Color("23252e"))
	v.box(Vector3(0, 0.038, -0.162), Vector3(0.066, 0.004, 0.124), Color("7fd0ea"))
	v.box(Vector3(0, 0.041, -0.2), Vector3(0.05, 0.003, 0.03), Color("ffd24a"))
	v.box(Vector3(0, 0.041, -0.152), Vector3(0.05, 0.003, 0.018), Color("fbf6e8"))
	v.box(Vector3(0, 0.041, -0.126), Vector3(0.05, 0.003, 0.018), Color("fbf6e8"))
	var mi := v.to_instance()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _make_arm(skin: Color, sleeve: Color, left: bool) -> Node3D:
	var pivot := Node3D.new()
	var side := -1.0 if left else 1.0
	var v := Voxel.new()
	# Forearm along -Z from the pivot (elbow) to the fist.
	v.box(Vector3(0, 0, 0.05), Vector3(0.066, 0.066, 0.2), sleeve)
	v.box(Vector3(0, 0, -0.06), Vector3(0.072, 0.072, 0.025), sleeve.darkened(0.12))
	v.box(Vector3(0, -0.002, -0.11), Vector3(0.054, 0.046, 0.085), skin)
	v.box(Vector3(0, -0.004, -0.17), Vector3(0.058, 0.044, 0.042), skin.darkened(0.06))
	v.box(Vector3(-side * 0.033, 0.006, -0.125), Vector3(0.018, 0.024, 0.045), skin.darkened(0.03))
	if left:
		v.box(Vector3(0, 0, -0.08), Vector3(0.062, 0.054, 0.024), Color("30323c"))
		v.box(Vector3(0, 0.029, -0.08), Vector3(0.03, 0.005, 0.024), Color("9fe0ff"))
	var mi := v.to_instance()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	add_child(pivot)
	return pivot


func play(gesture: String) -> void:
	_gesture = gesture
	_gesture_t = 0.0


func add_sway(mouse_delta: Vector2) -> void:
	_sway += mouse_delta * 0.00025
	_sway = _sway.limit_length(0.03)


func animate(delta: float, speed: float, sprinting: bool, crouching: bool, on_floor: bool) -> void:
	var k := minf(1.0, delta * 10.0)
	var moving := clampf(speed / 3.5, 0.0, 1.5) if on_floor else 0.0
	_bob += delta * (5.0 + speed * 1.8) * (1.0 if moving > 0.05 else 0.0)
	_sprint = lerpf(_sprint, 1.0 if sprinting and on_floor and not holding else 0.0, k)
	_crouch = lerpf(_crouch, 1.0 if crouching else 0.0, k)
	_hold = lerpf(_hold, 1.0 if holding else 0.0, minf(1.0, delta * 12.0))
	_phone = move_toward(_phone, 1.0 if phone_out and not holding else 0.0, delta * 5.0)
	_phone_mesh.visible = _phone > 0.35
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	if on_floor and not _was_on_floor:
		_land = 1.0
	_was_on_floor = on_floor
	_land = move_toward(_land, 0.0, delta * 5.0)

	# Gentle walk swing: each hand rocks opposite to the other, like real arms.
	var swing := sin(_bob) * 0.022 * moving * (1.0 - _hold)
	var bounce := -absf(cos(_bob)) * 0.008 * moving
	var common := Vector3(-_sway.x, _sway.y + bounce - 0.03 * _land - 0.015 * _crouch, 0)

	# Sprint: arms pump forward and back.
	var pump := sin(_bob) * 0.09 * _sprint

	var gl := Vector3.ZERO
	var gr := Vector3.ZERO
	var grot := 0.0
	if _gesture != "":
		_gesture_t += delta
		var dur: float = GESTURES[_gesture]
		var t := sin(PI * clampf(_gesture_t / dur, 0.0, 1.0))
		match _gesture:
			"reach":
				gr = Vector3(-0.06, 0.1, -0.2) * t
				grot = 0.6 * t
			"shove":
				gl = Vector3(0.08, 0.14, -0.26) * t
				gr = Vector3(-0.08, 0.14, -0.26) * t
				grot = 0.9 * t
			"throw":
				gl = Vector3(0.05, 0.3, -0.12) * t
				gr = Vector3(-0.05, 0.3, -0.12) * t
				grot = 1.1 * t
			"raise":  # hand up high, held, then down
				var up := clampf(t * 2.5, 0.0, 1.0)
				gr = Vector3(-0.04, 0.5, 0.06) * up
				grot = 1.9 * up
		if _gesture_t >= dur:
			_gesture = ""

	var base_l := REST_L.lerp(HOLD_L, _hold)
	var base_r := REST_R.lerp(HOLD_R, _hold)
	_arm_l.position = base_l + common + Vector3(0, 0, swing + pump) + gl
	var ph := smoothstep(0.0, 1.0, _phone)
	base_r = base_r.lerp(PHONE_R, ph)
	_arm_r.position = base_r + common + Vector3(0, 0, (-swing - pump) * (1.0 - ph)) + gr
	var rot_l := REST_ROT_L.lerp(HOLD_ROT_L, _hold)
	var rot_r := REST_ROT_R.lerp(HOLD_ROT_R, _hold)
	_arm_l.rotation = rot_l + Vector3(pump * 2.0 + (grot if _gesture != "reach" else 0.0), 0, 0)
	_arm_r.rotation = rot_r.lerp(PHONE_ROT_R, ph) + Vector3((-pump * 2.0 + grot) * (1.0 - ph), 0, 0)
