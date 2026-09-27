extends CharacterBody3D
## First-person student. Built in code so every peer constructs an identical
## node tree from the spawn data. The owning peer simulates movement and
## publishes net_* state; other peers smoothly interpolate towards it.

const StudentModel := preload("res://scenes/player/student_model.gd")
const Viewmodel := preload("res://scenes/player/viewmodel.gd")

const WALK_SPEED := 3.6
const SPRINT_SPEED := 6.4
const CROUCH_SPEED := 1.8
const JUMP_VELOCITY := 4.6
const ACCEL := 14.0
const MOUSE_SENS := 0.0022
const RADIUS := 0.3
const STAND_HEIGHT := 1.72
const CROUCH_HEIGHT := 1.1
const EYE_HEIGHT := 1.58
const CROUCH_EYE_HEIGHT := 1.0
const SIT_EYE_HEIGHT := 1.12
const SIT_SHOT := 2.0  # seconds of third person when you sit down
const FOV := 75.0
const SPRINT_FOV := 83.0

# Replicated from the owning peer.
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_speed := 0.0
var crouching := false
var sprinting := false
var hidden := false  # inside a locker
var seated := false  # sitting on a classroom chair
var hand_up := false  # asking the teacher a question
var tumbling := false  # knocked over (shoved, slipped, run over...)

var display_name := ""
var look := {}
var interact_hint := ""  # shown by the HUD (local player only)

var phone_until := 0.0  # local: show staff on the HUD until this time (seconds)
var phone_ready := 0.0  # local: when the staff tracker can scan again
var charge := 0.0       # local: basketball shot power while charging (HUD)

var _charge_start := 0.0

var _world: Node
var _director: Node
var _interactables: Array = []
var _target := {}
var _step := 0.0
var _lockers: Array = []
var _locker := -1
var _instrument := -1  # interactable index of the piano/drums being played
var _dev_walk: Array = []  # Vector3 waypoints or String actions (dev test bot)
var _dev_wait := 0.0
var _dev_crouch := false
var _dev_power := 0.6

var _capsule: CapsuleShape3D
var _shape: CollisionShape3D
var _model: Node3D
var _head: Node3D
var _camera: Camera3D
var _viewmodel: Node3D
var _label: Label3D
var _bubble: Label3D     # quick shouts over your head
var _bubble_t := 0.0
var _talk_mark := false  # "((( )))" by the name while they're on the mic
var _bob := 0.0
# Talking to staff: a local third-person shot of the two of you (see _start_talk).
var _talk_npc: Node = null
var _talk_line := ""
var _talk_old := ""        # what they were saying before, so we can spot the reply
var _talk_t := 0.0
var _talk_reply_at := -1.0
var _talk_reply_text := ""  # kept after their speech bubble fades
var _talk_blend := 0.0     # 0 = first person, 1 = conversation shot
var _talk_shot := Transform3D()
var _talk_cam: Camera3D
var _sit_intro := 0.0      # seconds left of the third-person "sitting down" shot
var _cine_fov := 55.0
var _escape_t := 0.0       # seconds left of the look back at the university you just escaped
var spectating := -1       # escaped: watching this friend (peer id), -1 = not
var cctv := -1             # escaped: watching this CCTV camera (index), -1 = not
var _tumble_t := 0.0       # local: seconds left on the floor
var _tilt := 0.0           # knocked-over lean of the body (all peers)
var _riding := ""          # local: name of the trolley we're sitting in
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(peer_id: int, player_name: String, look_data: Dictionary, spawn_pos: Vector3, yaw: float) -> void:
	name = str(peer_id)
	display_name = player_name
	look = look_data
	position = spawn_pos
	rotation.y = yaw
	net_position = spawn_pos
	net_yaw = yaw
	_build()
	set_multiplayer_authority(peer_id)


func _build() -> void:
	collision_layer = 2
	collision_mask = 3
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = STAND_HEIGHT / 2.0
	add_child(_shape)

	_model = StudentModel.new()
	_model.build(look)
	add_child(_model)

	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 26
	_label.outline_size = 10
	_label.modulate = Color(1, 1, 1, 0.9)
	var tag: Array = Profile.TAGS.get(str(look.get("tag", "")), Profile.TAGS[""])
	_label.modulate = tag[1]
	_label.outline_modulate = tag[2]
	_label.position.y = STAND_HEIGHT + 0.3
	add_child(_label)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 34
	_bubble.outline_size = 12
	_bubble.no_depth_test = true
	_bubble.modulate = Color("ffd24a")
	_bubble.position.y = STAND_HEIGHT + 0.75
	add_child(_bubble)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = EYE_HEIGHT
	add_child(_head)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 0.03
	_head.add_child(_camera)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var config := SceneReplicationConfig.new()
	for prop in [".:net_position", ".:net_yaw", ".:net_pitch", ".:net_speed", ".:crouching", ".:sprinting", ".:hidden", ".:seated", ".:hand_up", ".:tumbling"]:
		config.add_property(NodePath(prop))
		config.property_set_spawn(NodePath(prop), true)
		config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	Network.add_join_filter(sync)
	add_child(sync)


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	if _world:
		_lockers = _world.campus.lockers
		_interactables = _world.campus.interactables
		_director = _world.get_node_or_null("Director")
	if is_multiplayer_authority():
		_camera.current = true
		_label.visible = false
		_model.set_shadow_only()
		_viewmodel = Viewmodel.new()
		_viewmodel.build(look)
		_camera.add_child(_viewmodel)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--at="):
				var at := arg.trim_prefix("--at=").split_floats(",")  # x,z or x,y,z
				position = Vector3(at[0], at[1] + 0.05, at[2]) if at.size() == 3 else Vector3(at[0], 0.05, at[1])
				seated = false
			if arg == "--spectate":  # dev: watch the first friend, a few seconds in
				get_tree().create_timer(9.0).timeout.connect(func():
					for other in get_parent().get_children():
						if other != self:
							spectate(int(str(other.name)))
							return)
			if arg == "--bell":  # dev: ring the bell at the gate (escaped)
				get_tree().create_timer(8.0).timeout.connect(func(): _request("outside_bell", {}))
			if arg.begins_with("--walk="):
				for point in arg.trim_prefix("--walk=").split(";"):
					if point.begins_with("!"):
						_dev_walk.append(point.trim_prefix("!"))
					else:
						var v := point.split_floats(",")
						_dev_walk.append(Vector3(v[0], 0, v[1]))


## A quick shout over this student's head (everyone sees and hears it).
func shout(text: String) -> void:
	_bubble.text = text
	_bubble_t = 2.2
	Sfx.voice(text, global_position + Vector3(0, 1.6, 0), 1.0 + (int(str(name)) % 7) * 0.06)


## Server -> owner: move this student (detention, back to class).
@rpc("any_peer", "call_local", "reliable")
func teleport(pos: Vector3, yaw: float) -> void:
	if not _from_server() or not is_multiplayer_authority():
		return
	hidden = false
	seated = false
	_locker = -1
	position = pos
	rotation.y = yaw
	velocity = Vector3.ZERO
	net_position = pos


## Server -> owner: a friend boosted us up.
@rpc("any_peer", "call_local", "reliable")
func launch(impulse: Vector3) -> void:
	if not _from_server() or not is_multiplayer_authority():
		return
	velocity.y = impulse.y
	var fwd := -transform.basis.z
	velocity.x += fwd.x * 2.0
	velocity.z += fwd.z * 2.0


## Server -> owner: knocked over. You fly along `push`, lie there, then get up.
@rpc("any_peer", "call_local", "reliable")
func tumble(push: Vector3, seconds: float) -> void:
	if not _from_server() or not is_multiplayer_authority() or hidden:
		return
	_riding = ""
	seated = false
	_sit_intro = 0.0
	_tumble_t = seconds
	tumbling = true
	velocity = push
	Sfx.play("footstep", 2.0, 0.45)


## Server -> owner: hop into a trolley (or out of it, with "").
@rpc("any_peer", "call_local", "reliable")
func ride(trolley_name: String) -> void:
	if not _from_server() or not is_multiplayer_authority():
		return
	_riding = trolley_name
	seated = false


func _trolley(trolley_name: String) -> Node3D:
	return _world.get_node("Props").get_node_or_null(trolley_name) if _world and trolley_name != "" else null


func _grabbed() -> bool:
	if _director == null:
		return false
	return bool(_director.status.get(multiplayer.get_unique_id(), {}).get("grabbed", false))


func _from_server() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 1 or sender == 0


func _toggle_locker(i: int) -> void:
	if hidden and _director and float(_director.things.get("held", {}).get(str(_locker), -1.0)) > _director.elapsed:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.toast("It won't open! Someone's holding the door shut!", Color("ff9a4a"))
		Sfx.play("deny", -4.0, 0.8)
		return
	if hidden:
		position = _lockers[_locker].out
		hidden = false
		_locker = -1
		return
	_locker = i
	hidden = true
	crouching = false
	sprinting = false
	velocity = Vector3.ZERO
	position = _lockers[i].pos
	rotation.y = _lockers[i].yaw  # peek out through the vents
	_head.rotation.x = 0.0
	_shape.disabled = true  # now, not next frame: never pushed out through the locker walls


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if spectating >= 0 and (event.is_action_pressed("jump") or event.is_action_pressed("interact")):
		spectate(-1)  # back to your own eyes
		get_viewport().set_input_as_handled()
		return
	if cctv >= 0:
		if event.is_action_pressed("jump"):
			watch_cctv(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") and _world:
			watch_cctv((cctv + 1) % maxi(1, _world.campus.cctv.size()))
			get_viewport().set_input_as_handled()
		return
	if _sit_intro > 0.0:
		if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
			_sit_intro = 0.0  # skip the shot, stay seated
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if seated and _talk_npc == null:
		for up in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "crouch"]:
			if event.is_action_pressed(up):
				_stand()
				break
	if _talk_npc != null:
		for skip in ["interact", "move_forward", "move_back", "move_left", "move_right", "jump"]:
			if event.is_action_pressed(skip):
				_end_talk()
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var sens: float = MOUSE_SENS * Settings.mouse_sensitivity
		var limit := 0.5 if hidden else 1.45
		rotate_y(-event.relative.x * sens)
		if hidden:
			var base: float = _lockers[_locker].yaw
			rotation.y = base + clampf(wrapf(rotation.y - base, -PI, PI), -0.6, 0.6)
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * sens, -limit, limit)
		if _viewmodel:
			_viewmodel.add_sway(event.relative)
		return
	if _instrument >= 0:
		for n in 8:
			if event.is_action_pressed("note_%d" % (n + 1)):
				_request("note", {"i": _instrument, "n": n + 1})
				if _viewmodel:
					_viewmodel.play("reach")
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_instrument = -1
			get_viewport().set_input_as_handled()
			return
		for move in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
			if event.is_action_pressed(move):
				_instrument = -1  # walk away from the keys and you're moving again
				return
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("use_1") and not hidden:
		_request("use", {"slot": 0})
	elif event.is_action_pressed("use_2") and not hidden:
		_request("use", {"slot": 1})
	elif event.is_action_pressed("use_3") and not hidden:
		_request("use", {"slot": 2})
	elif event.is_action_pressed("phone"):
		_use_phone()
	elif event.is_action_pressed("throw") and not hidden:
		var fwd := -_camera.global_transform.basis.z
		_request("throw", {"from": _camera.global_position + fwd * 0.4, "dir": fwd})
		if _viewmodel:
			_viewmodel.play("throw")
	elif event.is_action_pressed("ping"):
		_ping()
	elif event.is_action_pressed("proxy") and not hidden:
		_request("proxy", {})
	elif event.is_action_pressed("raise_hand") and not hidden:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.open_questions()
	elif event.is_action_pressed("primary") and not hidden:
		if _my_ball():
			_charge_start = Time.get_ticks_msec() / 1000.0  # hold to charge the shot
		else:
			_request("shove", {})
			if _viewmodel:
				_viewmodel.play("shove")
	elif event.is_action_released("primary") and _charge_start > 0.0:
		var power := clampf((Time.get_ticks_msec() / 1000.0 - _charge_start) / 1.2, 0.1, 1.0)
		_charge_start = 0.0
		_request("ball_throw", {"dir": -_camera.global_transform.basis.z, "power": power})
		if _viewmodel:
			_viewmodel.play("throw")


## The basketball this player is holding, if any.
## Ping what's under the crosshair: a person by name, an object by name, or a place.
func _ping() -> void:
	var hit := _aim(1 | 2 | 4 | 16)
	if not hit.has("position"):
		return
	var args := {"pos": hit.position, "kind": "place"}
	var col: Object = hit.collider
	if col and col.has_method("say"):  # staff or a student
		args.npc = str(col.name)
		args.label = str(col.display_name) if str(col.display_name) != "" else "Student"
		args.kind = "person"
	elif col and col.has_method("teleport"):  # a classmate
		args.player = int(str(col.name))
		args.label = str(col.display_name)
		args.kind = "person"
	elif col and col.get("holder") != null:
		args.label = "Basketball"
		args.kind = "object"
	elif _world:
		var thing: String = _world.campus.object_near(hit.position)
		if thing != "":
			args.label = thing
			args.kind = "object"
		else:
			var place: String = _world.campus.place_name(hit.position)
			args.label = place if place != "" else "Over here"
	_request("ping", args)


func _my_ball() -> Node:
	if _world == null:
		return null
	var my_id := int(str(name))
	for ball in _world.get_node("Props").get_children():
		if ball.get("holder") != null and ball.holder == my_id:
			return ball
	return null


func _request(action: String, args: Dictionary) -> void:
	if _director:
		_director.request.rpc_id(1, action, args)


func _aim(mask: int) -> Dictionary:
	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * 30.0
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


## Takes the phone out (or puts it away): the HUD shows its screen.
func _use_phone() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.toggle_phone()


## Phone tracker app: shows staff around you for 5 s, then 20 s to recharge.
func scan_staff() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < phone_ready:
		return false
	phone_ready = now + 20.0
	phone_until = now + 5.0
	Sfx.play("phone")
	return true


func _phone_open() -> bool:
	var hud := get_tree().get_first_node_in_group("hud")
	return hud != null and hud.phone_open()


func _interact() -> void:
	if hidden:
		_toggle_locker(-1)
		return
	if seated:
		_stand()
		return
	if _viewmodel:
		_viewmodel.play("reach")
	if _my_ball():
		_request("ball_drop", {})
		return
	if _target.get("type", "") == "ball":
		_request("ball_grab", {"ball": _target.name})
		return
	match _target.get("type", ""):
		"hide":
			if _grabbed():
				var hud := get_tree().get_first_node_in_group("hud")
				if hud:
					hud.toast("You're grabbed! Shove free first.", Color("ff6a6a"))
				return
			_toggle_locker(_target.index)
		"object":
			var kind: String = _interactables[_target.index].kind
			if kind in ["piano", "drums"]:
				_instrument = _target.index
			elif kind == "essay":
				var hud := get_tree().get_first_node_in_group("hud")
				if hud:
					hud.open_essay()
			elif kind == "seat":
				_sit(_target.index)
			elif kind == "counter":
				_open_shop()
			else:
				_request("interact", {"i": _target.index})
		"npc":
			if _target.name == "Uncle":
				_open_shop()
				return
			_start_talk(str(_target.name), str(_target.get("line", "")))  # first: note what they were saying
			_request("talk", {"npc": _target.name})
		"friend":
			_request("boost", {"friend": _target.id})
		"vouch":
			_request("vouch", {"friend": _target.id})
		"trolley":
			_request("trolley", {"name": _target.name})
		"hold":
			_request("hold_door", {"i": _target.index, "friend": _target.friend})
		"give":
			if _target.has("cash"):
				_request("give", {"to": _target.id, "cash": int(_target.cash)})
			else:
				_request("give", {"to": _target.id, "slot": int(_target.slot)})


## Asks the teacher a question (picked on the HUD): hand up for a few seconds.
func ask(kind: int, question: String) -> void:
	_request("ask", {"kind": kind, "q": question})
	hand_up = true
	if _viewmodel:
		_viewmodel.play("raise")
	get_tree().create_timer(2.4).timeout.connect(func(): hand_up = false)


## Pappu Uncle's canteen: the HUD shows the shop, and he greets you.
func _open_shop() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.open_shop()
	var counter := -1
	for i in _interactables.size():
		if _interactables[i].kind == "counter":
			counter = i
	if counter != -1:
		_request("interact", {"i": counter})


## Picks what [E] would act on: a friend (boost, or hand them something), a staff
## member, or an object.
func _find_target() -> Dictionary:
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var me := global_position
	for p in get_parent().get_children():
		if p == self or p.hidden:
			continue
		var to_friend: Vector3 = p.global_position - me
		to_friend.y = 0
		if to_friend.length() >= 1.5 or absf(p.global_position.y - me.y) >= 1.0 \
				or not (to_friend.length() < 0.4 or fwd.dot(to_friend.normalized()) > 0.5):
			continue
		var fst: Dictionary = _director.status.get(int(str(p.name)), {}) if _director else {}
		if not (fst.get("question", {}) as Dictionary).is_empty():
			return {"type": "vouch", "id": int(str(p.name)), "label": "Vouch for %s (\"They're with me!\")" % p.display_name}
		if p.crouching:
			return {"type": "friend", "id": int(str(p.name)), "label": "Get a boost from %s" % p.display_name}
		# Standing friend: hand over your first item (contraband goes in their bag, so it's
		# THEIR problem if they're caught), or Rs 10 if your pockets are empty.
		var st: Dictionary = _director.status.get(int(str(name)), {}) if _director else {}
		var items: Array = st.get("items", [])
		if not items.is_empty():
			var item_name: String = _director.ITEMS.get(items[0], "item")
			var sneaky: bool = items[0] in _director.CONTRABAND
			return {"type": "give", "id": int(str(p.name)), "slot": 0,
				"label": ("Slip the %s into %s's bag" if sneaky else "Give %s the %s") % ([item_name, p.display_name] if sneaky else [p.display_name, item_name])}
		if int(st.get("cash", 0)) >= 10:
			return {"type": "give", "id": int(str(p.name)), "cash": 10, "label": "Give %s Rs 10" % p.display_name}
	if _world:
		for npc in _world.get_node("Npcs").get_children():
			if npc.display_name == "" or npc.role == "extra":
				continue
			var to: Vector3 = npc.global_position - me
			if absf(to.y) > 1.6 or int(npc.alert) == 2:
				continue  # another floor, or chasing you
			to.y = 0
			if to.length() < 2.4 and fwd.dot(to.normalized()) > 0.5:
				var my_room: int = _director.current_room(int(str(name))) if _director else Network.local_info.classroom
				var own_teacher: bool = npc.role == "teacher" and npc.room == my_room
				var label := "Ask %s for a hall pass" % npc.display_name if own_teacher else "Talk to %s" % npc.display_name
				var line := "Excuse me, %s... may I go to the washroom?" % npc.display_name if own_teacher \
						else "Um, hello %s!" % npc.display_name
				if npc.name == "Uncle":
					label = "Open the canteen shop"
					line = "Uncle, what have you got?"
				return {"type": "npc", "name": str(npc.name), "label": label, "line": line}
	if _world:
		var my_id := int(str(name))
		for prop in _world.get_node("Props").get_children():
			var to_prop: Vector3 = prop.global_position - me
			to_prop.y = 0
			if prop.get("pusher") != null:  # a trolley
				if absf(prop.global_position.y - me.y) > 1.2 or to_prop.length() > 2.2 or (to_prop.length() > 0.9 and fwd.dot(to_prop.normalized()) < 0.3):
					continue
				var label := "Push the trolley"
				if prop.pusher == my_id:
					label = "Let go of the trolley (it keeps rolling!)"
				elif crouching and prop.rider == -1:
					label = "Hop in the trolley"
				elif prop.pusher != -1:
					continue
				return {"type": "trolley", "name": str(prop.name), "label": label}
			if prop.get("holder") == null:
				continue
			if prop.holder == -1 and to_prop.length() < 1.8 and (to_prop.length() < 1.2 or fwd.dot(to_prop.normalized()) > 0.3):
				return {"type": "ball", "name": str(prop.name), "label": "Pick up the basketball"}
	var best := {}
	var best_score := INF
	for i in _interactables.size():
		var it: Dictionary = _interactables[i]
		var to: Vector3 = it.pos - me
		to.y = 0
		var d := to.length()
		if absf(it.pos.y - me.y) > 1.6:
			continue  # another floor
		var dot := fwd.dot(to.normalized()) if d > 0.01 else 1.0
		var score := d * (1.5 - dot)  # near, and what you are looking at
		if d < 1.9 and (d < 0.6 or dot > 0.1) and score < best_score:
			best_score = score
			best = {"type": "hide" if it.kind == "hide" else "object", "index": it.get("index", i) if it.kind == "hide" else i, "label": it.label}
			if it.kind == "hide":
				var spot: Vector3 = _lockers[int(it.index)].pos
				for p in get_parent().get_children():
					if p != self and p.hidden and p.global_position.distance_to(spot) < 0.4:
						best = {"type": "hold", "index": int(it.index), "friend": int(str(p.name)),
							"label": "Hold the door shut on %s (prank!)" % p.display_name}
			if it.kind == "pickup" and _director and float(_director.world.taken.get(i, -1.0)) > _director.elapsed:
				best.label = "(already taken)"
			if it.kind == "cistern" and _director and _director.world.stash.has(str(i)):
				best.label = "Take back the %s" % _director.ITEMS.get(_director.world.stash[str(i)], "thing")
	return best


func _physics_process(delta: float) -> void:
	var k := 1.0 - exp(-15.0 * delta)
	_shape.disabled = hidden
	_model.visible = not hidden or is_multiplayer_authority()
	if is_multiplayer_authority():
		if not hidden:
			_move(delta)
		elif _tumble_t > 0.0:
			_tumble_t = 0.0
			tumbling = false
		net_position = position
		net_yaw = rotation.y
		net_pitch = _head.rotation.x
		net_speed = 0.0 if hidden else Vector2(velocity.x, velocity.z).length()
		_update_camera(delta)
		if _viewmodel:
			_viewmodel.visible = not hidden and _talk_blend <= 0.0
			_viewmodel.phone_out = _phone_open()
			_viewmodel.animate(delta, net_speed, sprinting, crouching, is_on_floor())
		_target = {} if hidden or seated or _talk_npc != null else _find_target()
		_talk_step(delta)
		if _instrument >= 0 and (_instrument >= _interactables.size() or global_position.distance_to(_interactables[_instrument].pos) > 3.0):
			_instrument = -1  # walked away
		if _instrument >= 0 and _director and _director.status.get(int(str(name)), {}).get("state", "") == "chased":
			_instrument = -1  # someone's coming: hands off the keys
		if seated and _director and _director.status.get(int(str(name)), {}).get("state", "class") != "class":
			_stand()  # chased, caught...: on your feet
		if spectating >= 0:
			var friend: Node = get_parent().get_node_or_null(str(spectating))
			interact_hint = "Watching %s   [%s] back to you" % [friend.display_name if friend else "a friend", GameInput.key_label("jump")]
		elif cctv >= 0:
			interact_hint = "CCTV CAM %d/%d   [%s] next camera   [%s] back to you" % [cctv + 1, _world.campus.cctv.size(), GameInput.key_label("interact"), GameInput.key_label("jump")]
		elif _talk_npc != null or _sit_intro > 0.0:
			interact_hint = ""
		elif seated:
			interact_hint = "[%s] Stand up   (or just walk off)" % GameInput.key_label("interact")
		elif hidden:
			interact_hint = "[%s] Get out" % GameInput.key_label("interact")
		elif _instrument >= 0:
			interact_hint = "Playing the %s:  [1]-[8] notes    [%s] stop   (staff can hear you!)" % [_interactables[_instrument].kind, GameInput.key_label("interact")]
		elif _target.is_empty():
			interact_hint = ""
		else:
			interact_hint = "[%s] %s" % [GameInput.key_label("interact"), _target.label]
		var ball := _my_ball()
		if _viewmodel:
			_viewmodel.holding = ball != null
		charge = 0.0
		if ball:
			if _charge_start > 0.0:
				charge = clampf((Time.get_ticks_msec() / 1000.0 - _charge_start) / 1.2, 0.1, 1.0)
			interact_hint = "[Click] hold to charge, release to shoot     [%s] drop" % GameInput.key_label("interact")
		elif _grabbed():
			interact_hint = "GRABBED!  [Click] SHOVE to break free!"
		_footsteps(delta, true)
	else:
		_label.visible = not hidden
		_capsule.height = CROUCH_HEIGHT if crouching else STAND_HEIGHT
		_shape.position.y = _capsule.height / 2.0
		if position.distance_to(net_position) > 4.0:
			position = net_position
		position = position.lerp(net_position, k)
		rotation.y = lerp_angle(rotation.y, net_yaw, k)
		_head.rotation.x = lerpf(_head.rotation.x, net_pitch, k)
		_footsteps(delta, false)

	_bubble_t = maxf(0.0, _bubble_t - delta)
	_bubble.visible = _bubble_t > 0.0 and not hidden
	_bubble.position.y = _head.position.y + 0.85
	var talking: bool = Voice.is_speaking(int(str(name))) and not is_multiplayer_authority()
	if talking != _talk_mark:
		_talk_mark = talking
		_label.text = ("((  %s  ))" % display_name) if talking else display_name
	var eye := SIT_EYE_HEIGHT if seated else (CROUCH_EYE_HEIGHT if crouching else EYE_HEIGHT)
	_head.position.y = lerpf(_head.position.y, eye, minf(1.0, delta * (4.0 if seated else 12.0)))
	_label.position.y = _head.position.y + 0.45
	# In your own sitting-down shot, you sit once the camera has got there.
	var sit_now := seated and not (is_multiplayer_authority() and _sit_intro > SIT_SHOT - 0.5)
	_model.animate(delta, 0.0 if seated or tumbling else net_speed, crouching, sprinting, _head.rotation.x, sit_now)
	_model.pose_hand(delta, hand_up)
	_tilt = lerpf(_tilt, -1.35 if tumbling else 0.0, minf(1.0, delta * (10.0 if tumbling else 4.0)))
	_model.rotation.x = _tilt
	if is_multiplayer_authority():
		_camera.rotation.z = lerpf(_camera.rotation.z, 0.5 * sin(_tumble_t * 5.0) if tumbling else 0.0, minf(1.0, delta * 8.0))
		if tumbling:
			_head.position.y = lerpf(_head.position.y, 0.35, minf(1.0, delta * 10.0))


func _footsteps(delta: float, local: bool) -> void:
	if net_speed < 0.3 or hidden:
		return
	_step += net_speed * delta
	if _step < 1.7:
		return
	_step = 0.0
	var vol := -20.0 if crouching else (-4.0 if sprinting else -12.0)
	if local:
		Sfx.play("footstep", vol, randf_range(0.85, 1.1))
	else:
		Sfx.play_at("footstep", global_position, vol + 4.0, randf_range(0.85, 1.1))


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# With the phone out you can still walk (no sprinting): the mouse taps the screen.
	var phone := _phone_open()
	var has_control := (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or phone) and _instrument < 0 and _talk_npc == null and spectating < 0 and cctv < 0 and _escape_t <= 0.0
	if _tumble_t > 0.0:
		# On the floor: slide to a stop, no control until you're up.
		_tumble_t -= delta
		tumbling = _tumble_t > 0.0
		crouching = false
		sprinting = false
		velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
		move_and_slide()
		return
	var cart := _trolley(_riding)
	if cart:
		crouching = true
		sprinting = false
		velocity = Vector3.ZERO
		position = cart.seat_position()
		if has_control and Input.is_action_just_pressed("jump"):
			_riding = ""
			velocity.y = JUMP_VELOCITY
			_request("trolley_off", {})
		return
	elif _riding != "":
		_riding = ""
	var input := Vector2.ZERO
	if has_control:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_dev_wait -= delta
	if not _dev_walk.is_empty() and _dev_wait <= 0.0:
		# Dev "--walk=x,z;!action;..." (for automated tests). Actions: interact,
		# use1..3, throw, proxy, crouch, stand, waitN (seconds).
		if _dev_walk[0] is String:
			var action: String = _dev_walk.pop_front()
			print("[bot] %s at %s" % [action, global_position])
			match action:
				"interact":
					_target = _find_target()
					print("[bot] target: %s" % str(_target.get("label", "none")))
					_interact()
				"use1", "use2", "use3":
					_request("use", {"slot": int(action.right(1)) - 1})
				"proxy":
					_request("proxy", {})
				"shove":
					_request("shove", {})
				"excuse0", "excuse1", "excuse2", "excuse3":
					_request("excuse", {"k": int(action.right(1))})
				"ping":
					_ping()
				"throw":
					_request("ball_throw", {"dir": -_camera.global_transform.basis.z, "power": _dev_power})
				"sit":  # sit down in your own seat
					var mine: Vector3 = _director.status.get(int(str(name)), {}).get("seat", Vector3.ZERO)
					for k in _interactables.size():
						if _interactables[k].kind == "seat" and (_interactables[k].pos as Vector3).distance_to(mine) < 0.1:
							_sit(k)
				"talk":  # step up to the nearest staff member and talk
					var near: Node3D = null
					for npc in _world.get_node("Npcs").get_children():
						if npc.role == "teacher" and (near == null \
								or npc.global_position.distance_to(global_position) < near.global_position.distance_to(global_position)):
							near = npc
					if near:
						position = near.global_position - near.forward() * 1.4
						_target = {"type": "npc", "name": str(near.name), "line": "Um, hello %s!" % near.display_name}
						_interact()
				"coin":  # stand on the nearest coin
					var best := Vector3.INF
					for c in _director.world.get("coins", []):
						if global_position.distance_to(c.p) < global_position.distance_to(best):
							best = c.p
					if best != Vector3.INF:
						position = best + Vector3(0, 0.05, 0)
				"counter":  # at Pappu Uncle's counter
					for it in _interactables:
						if it.kind == "counter":
							position = it.pos + Vector3(0, 0.05, 0)
				"bump":  # step into the path of the nearest walking student
					var near: Node3D = null
					for npc in _world.get_node("Npcs").get_children():
						if npc.role == "extra" and npc.pose == 0 and (near == null \
								or npc.global_position.distance_to(global_position) < near.global_position.distance_to(global_position)):
							near = npc
					if near:
						position = near.global_position + near.forward() * 0.5
						print("[bot] bumping %s at %s" % [near.name, near.global_position])
						get_tree().create_timer(1.5).timeout.connect(func():
							print("[bot] %s now at %s says '%s'" % [near.name, near.global_position, near.speech]))
				"crouch":
					_dev_crouch = true
				"stand":
					_dev_crouch = false
					_stand()
				_:
					if action.begins_with("wait"):
						_dev_wait = float(action.trim_prefix("wait"))
					elif action.begins_with("note") and _instrument >= 0:
						_request("note", {"i": _instrument, "n": int(action.trim_prefix("note"))})
					elif action == "paper":
						var pf := -_camera.global_transform.basis.z
						_request("throw", {"from": _camera.global_position + pf * 0.4, "dir": pf})
					elif action.begins_with("give"):  # give10 / giveslot0: to the nearest classmate
						for p in get_parent().get_children():
							if p != self:
								var what := action.trim_prefix("give")
								_request("give", {"to": int(str(p.name)), "slot": int(what.trim_prefix("slot"))} if what.begins_with("slot") else {"to": int(str(p.name)), "cash": int(what)})
								break
					elif action.begins_with("ask:"):  # raise your hand: ask:0 intelligent, 1 quirky, 2 mischievous
						var kind := int(action.trim_prefix("ask:"))
						var rng := RandomNumberGenerator.new()
						for q in preload("res://scripts/questions.gd").pick(_director.current_room(int(str(name))), rng):
							if q.kind == kind:
								ask(kind, q.q)
								break
					elif action == "examphoto":  # snap the exam paper in the staff room
						for k in _interactables.size():
							if _interactables[k].kind == "pickup" and _interactables[k].get("item", "") == "exam_paper":
								position = _interactables[k].pos + Vector3(0, 0.05, 0)
								_request("interact", {"i": k})
					elif action.begins_with("goto:"):  # stand by the nearest interactable (or item pickup, or trolley) of a kind
						var want := action.trim_prefix("goto:")
						var best := Vector3.INF
						var spots: Array = []
						for it in _interactables:
							if it.kind == want or str(it.get("item", "")) == want:
								spots.append(it.pos)
						var face := Vector3.INF
						for prop in _world.get_node("Props").get_children():
							if want == "trolley" and prop.get("pusher") != null:
								spots.append(prop.global_position + prop.global_transform.basis.z * 1.2)
						for at: Vector3 in spots:
							if global_position.distance_to(at) < global_position.distance_to(best):
								best = at
						if best != Vector3.INF:
							position = Vector3(best.x, maxf(best.y, 0.0) + 0.05, best.z)
							if want == "trolley":
								for prop in _world.get_node("Props").get_children():
									if prop.get("pusher") != null and (prop.global_position + prop.global_transform.basis.z * 1.2).distance_to(best) < 0.1:
										face = prop.global_position
							if face != Vector3.INF:
								rotation.y = atan2(-(face.x - position.x), -(face.z - position.z))
							print("[bot] at the %s: %s" % [want, best])
					elif action.begins_with("buy:"):
						_request("buy", {"what": action.trim_prefix("buy:")})
					elif action.begins_with("power"):
						_dev_power = float(action.trim_prefix("power"))
					elif action.begins_with("look:"):
						# Aim the camera at a world point x:y:z.
						var t := action.trim_prefix("look:").split_floats(":")
						var to := Vector3(t[0], t[1], t[2]) - _camera.global_position
						rotation.y = atan2(-to.x, -to.z)
						_head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
		else:
			var to: Vector3 = _dev_walk[0] - global_position
			to.y = 0
			if to.length() < 0.3:
				_dev_walk.pop_front()
			else:
				var local := transform.basis.inverse() * to.normalized()
				input = Vector2(local.x, local.z)
	if hidden:
		return  # just stepped into a locker
	if seated:
		if not _dev_walk.is_empty() and _dev_walk[0] is Vector3:
			_stand()  # dev bot: walking off gets you up
		velocity = Vector3.ZERO
		crouching = false
		sprinting = false
		return
	var want_crouch := (has_control and Input.is_action_pressed("crouch")) or _dev_crouch
	if crouching and not want_crouch and _blocked_above():
		want_crouch = true
	crouching = want_crouch
	sprinting = has_control and not phone and not crouching and input.y < 0.0 and Input.is_action_pressed("sprint")

	# Crouch-jumping works too: it's how you fit through a window.
	if has_control and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if _grabbed():
		speed *= 0.25  # held by the collar: shove to get away
	if _bumping(input):
		speed *= 0.7  # pushing past a student

	var target := (transform.basis * Vector3(input.x, 0, input.y)).normalized() * speed
	var accel := ACCEL if is_on_floor() else ACCEL * 0.3
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)

	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_capsule.height = height
	_shape.position.y = height / 2.0
	move_and_slide()


# --- Talking to staff --------------------------------------------------------------------

## What the HUD shows while you talk: {"who", "line", "reply"}; empty when not talking.
func talk_info() -> Dictionary:
	if _talk_npc == null or not is_instance_valid(_talk_npc):
		return {}
	# Your line first; their answer a beat later, and it stays up to be read.
	return {"who": str(_talk_npc.display_name), "line": _talk_line, "reply": _talk_reply_text if _talk_t >= 1.0 else ""}


func _talk_reply() -> String:
	var now: String = _talk_npc.speech
	return now if now != _talk_old and now != "" else ""


## Face them, and cut to a third-person shot of the two of you until they've answered.
func _start_talk(npc_name: String, line: String) -> void:
	var npc: Node3D = _world.get_node("Npcs").get_node_or_null(npc_name) if _world else null
	if npc == null:
		return
	_talk_npc = npc
	_talk_line = line
	_talk_old = str(npc.speech)
	_talk_t = 0.0
	_talk_reply_at = -1.0
	_talk_reply_text = ""
	var to := npc.global_position - global_position
	to.y = 0
	rotation.y = atan2(-to.x, -to.z)
	_head.rotation.x = 0.0
	velocity = Vector3.ZERO
	_cine_begin(_talk_frame(npc))


## Cuts to a third-person shot (you're in it, so your body is drawn); it
## glides in and back out to first person (see _talk_step).
func _cine_begin(shot: Transform3D, fov := 55.0) -> void:
	_talk_shot = shot
	_cine_fov = fov
	if _talk_cam == null:
		_talk_cam = Camera3D.new()
		_talk_cam.top_level = true
		_talk_cam.fov = 55.0
		add_child(_talk_cam)
	if not _talk_cam.current:
		_talk_cam.global_transform = _camera.global_transform
		_talk_cam.current = true
	_model.set_shadow_only(false)


func _cine_on() -> bool:
	return _talk_npc != null or _sit_intro > 0.0 or _escape_t > 0.0 or spectating >= 0 or cctv >= 0


## Escaped: look through CCTV camera `k` (-1: back to your own eyes). The staff
## tracker runs while you watch, so you can guide friends past them.
func watch_cctv(k: int) -> void:
	if not is_multiplayer_authority() or _world == null:
		return
	cctv = k if k < _world.campus.cctv.size() else -1
	if cctv >= 0:
		spectating = -1
		phone_until = Time.get_ticks_msec() / 1000.0 + 600.0
		_cctv_frame()
		_cine_begin(_talk_shot, 70.0)
	else:
		phone_until = 0.0


func _cctv_frame() -> void:
	var cam: Dictionary = _world.campus.cctv[cctv]
	var yaw: float = _director.cctv_yaw(cam, _director.elapsed) if _director else float(cam.base_yaw)
	var fwd := Vector3(-sin(yaw), -0.45, -cos(yaw)).normalized()
	var at: Vector3 = (cam.pos as Vector3) + fwd * 0.45  # just in front of the lens, not inside the camera
	_talk_shot = Transform3D(Basis(), at).looking_at(at + fwd, Vector3.UP)


## You're out: the camera swings round in front of you and looks back at the university.
func escape_shot(target: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	var away := global_position - target
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else -global_transform.basis.z
	var at := global_position + away * 4.5 + Vector3(0, 2.4, 0)
	_escape_t = 3.2
	_cine_begin(Transform3D(Basis(), at).looking_at(target.lerp(global_position + Vector3(0, 1.4, 0), 0.35), Vector3.UP), 62.0)


## Escaped: watch a friend still inside from over their shoulder (-1 stops).
func spectate(id: int) -> void:
	if not is_multiplayer_authority():
		return
	spectating = id
	if id >= 0:
		_spectate_frame()
		_cine_begin(_talk_shot, 65.0)


func _spectate_frame() -> void:
	var friend: Node3D = _world.get_node("Players").get_node_or_null(str(spectating)) if _world else null
	if friend == null or not is_instance_valid(friend):
		spectating = -1
		return
	var fwd := -friend.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var head := friend.global_position + Vector3(0, 1.5, 0)
	var at := head - fwd * 3.2 + Vector3(0, 0.9, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(head, at, 1, [friend.get_rid()]))
	if not hit.is_empty():
		at = head.lerp(hit.position, 0.85)
	_talk_shot = Transform3D(Basis(), at).looking_at(head + fwd * 2.0, Vector3.UP)


## Sit on chair `index` of the interactables: a quick third-person shot of you
## sitting down, then first person from the seat.
func _sit(index: int) -> void:
	var it: Dictionary = _interactables[index]
	var my_id := int(str(name))
	var hud := get_tree().get_first_node_in_group("hud")
	if _director:
		if int(it.room) != _director.current_room(my_id):
			if hud:
				hud.toast("Wrong class! You're in %s this period." % Network.CLASSROOMS[_director.current_room(my_id)], Color("ffb37a"))
			return
		for other in _director.status:
			if other != my_id and (_director.status[other].get("seat", Vector3.ZERO) as Vector3).distance_to(it.pos) < 0.1 \
					and _director.current_room(other) == int(it.room):
				if hud:
					hud.toast("That's someone else's seat.", Color("ffb37a"))
				return
	seated = true
	crouching = false
	sprinting = false
	velocity = Vector3.ZERO
	position = it.pos
	rotation.y = float(it.yaw)
	_head.rotation.x = 0.0
	_request("sit", {"room": int(it.room), "seat": int(it.seat)})
	_sit_intro = SIT_SHOT
	_cine_begin(_sit_frame(it.pos, float(it.yaw)), 62.0)


func _stand() -> void:
	seated = false
	_sit_intro = 0.0


## From the aisle, a little in front: you, sitting down (legs and all).
func _sit_frame(seat: Vector3, yaw: float) -> Transform3D:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := fwd.cross(Vector3.UP).normalized()
	# The bench partner's seat is on one side; the aisle is on the other.
	for it: Dictionary in _interactables:
		var d: Vector3 = (it.pos as Vector3) - seat
		if it.kind == "seat" and d.length() > 0.1 and d.length() < 1.2 and absf(d.y) < 0.5:
			side = -side if d.dot(side) > 0.0 else side
			break
	var look := seat + Vector3(0, 0.85, 0)
	var shots := [
		seat + side * 2.1 + fwd * 0.9 + Vector3(0, 1.3, 0),
		seat + side * 2.1 - fwd * 0.6 + Vector3(0, 1.4, 0),
		seat + fwd * 1.9 + side * 0.8 + Vector3(0, 1.5, 0),
		seat - fwd * 1.4 + Vector3(0, 2.1, 0),
	]
	var space := get_world_3d().direct_space_state
	var best: Vector3 = shots[0]
	var best_room := -1.0
	for at: Vector3 in shots:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(look, at, 1 | 2, [get_rid()]))
		var room := 1.0 if hit.is_empty() else look.distance_to(hit.position) / look.distance_to(at)
		if room > 0.95:
			best = at
			break
		if room > best_room:
			best_room = room
			best = look.lerp(hit.position, 0.85) if not hit.is_empty() else at
	return Transform3D(Basis(), best).looking_at(look, Vector3.UP)


func _end_talk() -> void:
	_talk_npc = null  # the camera then glides back (see _talk_step)


## Over your shoulder onto their face, or from the side if a wall is in the way.
func _talk_frame(npc: Node3D) -> Transform3D:
	var me := global_position
	var them := npc.global_position
	var dir := them - me
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else -global_transform.basis.z
	var side := dir.cross(Vector3.UP).normalized()
	var face := them + Vector3(0, 1.5, 0)
	var mid := (me + them) / 2.0 + Vector3(0, 1.45, 0)
	var shots := [
		[me - dir * 2.0 + side * 1.0 + Vector3(0, 1.95, 0), face],
		[me - dir * 2.0 - side * 1.0 + Vector3(0, 1.95, 0), face],
		[mid + side * 2.4 + Vector3(0, 0.25, 0), mid],
		[mid - side * 2.4 + Vector3(0, 0.25, 0), mid],
	]
	var space := get_world_3d().direct_space_state
	var best: Array = []
	var best_room := -1.0
	for shot: Array in shots:
		var at: Vector3 = shot[0]
		var look_at_point: Vector3 = shot[1]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(look_at_point, at, 1, [get_rid()]))
		var room := 1.0
		if not hit.is_empty():
			room = look_at_point.distance_to(hit.position) / look_at_point.distance_to(at)
			at = look_at_point.lerp(hit.position, 0.85)  # pull in, just short of the wall
		if room > 0.95:
			best = [at, look_at_point]
			break
		if room > best_room:
			best_room = room
			best = [at, look_at_point]
	return Transform3D(Basis(), best[0]).looking_at(best[1], Vector3.UP)


func _talk_step(delta: float) -> void:
	if _talk_npc != null:
		_talk_t += delta
		var reply := _talk_reply() if is_instance_valid(_talk_npc) else ""
		if reply != "" and _talk_reply_at < 0.0:
			_talk_reply_at = _talk_t
			_talk_reply_text = reply
		var st: Dictionary = _director.status.get(int(str(name)), {}) if _director else {}
		var done: bool = not is_instance_valid(_talk_npc) or hidden or st.get("state", "class") != "class" \
				or _talk_npc.global_position.distance_to(global_position) > 4.0 or _talk_t > 7.0 \
				or (_talk_reply_at < 0.0 and _talk_t > 3.5) \
				or (_talk_reply_at >= 0.0 and _talk_t > maxf(_talk_reply_at, 1.0) + 3.0)
		if done:
			_end_talk()
	if _sit_intro > 0.0:
		_sit_intro = maxf(0.0, _sit_intro - delta)
	if _escape_t > 0.0:
		_escape_t = maxf(0.0, _escape_t - delta)
	if spectating >= 0:
		_spectate_frame()
	if cctv >= 0:
		_cctv_frame()
	if _talk_cam == null:
		return
	var on := _cine_on()
	_talk_blend = move_toward(_talk_blend, 1.0 if on else 0.0, delta / (0.45 if on else 0.35))
	var k := smoothstep(0.0, 1.0, _talk_blend)
	_talk_cam.global_transform = _camera.global_transform.interpolate_with(_talk_shot, k)
	_talk_cam.fov = lerpf(_camera.fov, _cine_fov, k)
	if not on and _talk_blend <= 0.0 and _talk_cam.current:
		_camera.current = true
		_model.set_shadow_only()


## Walking into a (walking) NPC student: the host pushes them aside, we slow a little.
func _bumping(input: Vector2) -> bool:
	if _world == null or input == Vector2.ZERO:
		return false
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	for npc in _world.get_node("Npcs").get_children():
		if npc.role != "extra" or npc.pose != 0:
			continue
		var to: Vector3 = npc.global_position - global_position
		if absf(to.y) > 1.0:
			continue
		to.y = 0.0
		if to.length() < 0.8 and dir.dot(to.normalized()) > 0.3:
			return true
	return false


func _blocked_above() -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = RADIUS * 0.9
	probe.height = STAND_HEIGHT
	params.shape = probe
	params.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT / 2.0 + 0.02, 0))
	params.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _update_camera(delta: float) -> void:
	var moving := net_speed > 0.3 and is_on_floor()
	if moving:
		_bob += delta * (6.0 + net_speed * 1.6)
	var amount := clampf(net_speed / WALK_SPEED, 0.0, 1.6) if moving else 0.0
	var target := Vector3(cos(_bob) * 0.025, absf(sin(_bob)) * 0.04, 0) * amount
	_camera.position = _camera.position.lerp(target, minf(1.0, delta * 10.0))
	var base_fov: float = Settings.fov
	_camera.fov = lerpf(_camera.fov, base_fov + (SPRINT_FOV - FOV) * (1.0 if sprinting else 0.0), minf(1.0, delta * 6.0))
