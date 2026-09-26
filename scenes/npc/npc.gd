extends CharacterBody3D
## A teacher or guard. The server's Director decides what it does (go_to /
## face); this node walks there and publishes net_* state. Clients only
## interpolate and show the speech bubble and alert marker.

const StudentModel := preload("res://scenes/player/student_model.gd")

const RADIUS := 0.3
const HEIGHT := 1.72
const EYE_HEIGHT := 1.55

# Replicated from the server.
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_speed := 0.0
var speech := ""
var alert := 0  # 0 calm, 1 suspicious, 2 chasing
var pose := 0   # 0 standing, 1 sitting
var holding := false  # chai glass in hand
var stunned := false  # knocked over by a shove

var _knock := Vector3.ZERO
var _stun_time := 0.0
var _push := Vector3.ZERO  # bumped by a player walking into us
# Drawn between physics ticks: the body moves 60 times a second, but the model
# and the name/speech tags are placed every frame (else text judders and looks
# smeared on high refresh-rate screens).
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _cur_yaw := 0.0
var _tilt := 0.0  # knocked-over lean
var _tag: Label3D

var role := ""
var room := -1
var display_name := ""

# Server-side movement orders.
var move_speed := 2.0
var look_yaw := 0.0
var _path: Array[Vector3] = []
var _stuck_time := 0.0
var _speech_time := 0.0

var voice_pitch := 1.0

var _model: Node3D
var _speech_label: Label3D
var _alert_label: Label3D
var _last_speech := ""
var _step := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(data: Dictionary) -> void:
	name = data.id
	role = data.role
	room = data.room
	display_name = data.name
	position = data.pos
	rotation.y = data.yaw
	net_position = data.pos
	net_yaw = data.yaw
	look_yaw = data.yaw
	pose = data.get("pose", 0)
	voice_pitch = data.get("voice", 1.0)
	collision_layer = 2
	collision_mask = 1 | 8  # world + staff-only walls (keep out of the water)

	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = HEIGHT / 2.0
	add_child(shape)

	_model = StudentModel.new()
	_model.build(data.look)
	_model.top_level = true
	add_child(_model)

	var tag := Label3D.new()
	_tag = tag
	tag.top_level = true
	tag.text = display_name
	tag.visible = display_name != ""
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 22
	tag.outline_size = 8
	tag.modulate = Color(1, 0.9, 0.7)
	tag.position.y = HEIGHT + 0.2
	add_child(tag)

	_speech_label = Label3D.new()
	_speech_label.top_level = true
	_speech_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech_label.font_size = 34
	_speech_label.outline_size = 12
	_speech_label.position.y = HEIGHT + 0.55
	_speech_label.no_depth_test = true
	add_child(_speech_label)

	_alert_label = Label3D.new()
	_alert_label.top_level = true
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.font_size = 90
	_alert_label.outline_size = 18
	_alert_label.position.y = HEIGHT + 0.95
	_alert_label.no_depth_test = true
	add_child(_alert_label)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	# Background students update a bit less often (they walk between classes).
	sync.replication_interval = 0.1 if role == "extra" else 0.05
	var config := SceneReplicationConfig.new()
	for prop in [".:net_position", ".:net_yaw", ".:net_speed", ".:speech", ".:alert", ".:pose", ".:holding", ".:stunned"]:
		config.add_property(NodePath(prop))
		config.property_set_spawn(NodePath(prop), true)
		config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	Network.add_join_filter(sync)
	add_child(sync)
	_prev_pos = position
	_cur_pos = position
	_prev_yaw = rotation.y
	_cur_yaw = rotation.y


# --- Orders (server) ------------------------------------------------------------------

func go_to(path: Array[Vector3], speed: float) -> void:
	_path = path
	move_speed = speed
	_stuck_time = 0.0


func stop(face_yaw: float) -> void:
	_path.clear()
	look_yaw = face_yaw


## Server: knocked back and down for a moment by a shove.
func stun(knock: Vector3, seconds := 2.2) -> void:
	stunned = true
	pose = 0
	holding = false
	_knock = knock
	_stun_time = seconds


## Server: a player bumped into us; stumble aside without stopping our walk.
func nudge(v: Vector3) -> void:
	v.y = 0.0
	if v.length() > _push.length():
		_push = v


func is_idle() -> bool:
	return _path.is_empty()


func say(text: String, seconds := 2.5) -> void:
	speech = text
	_speech_time = seconds


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0, -cos(rotation.y))


static func yaw_towards(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


# --- Simulation ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Walking students don't block players (they get pushed aside); seated ones do.
	if role == "extra":
		collision_layer = 2 if pose == 1 else 16
	var jumped := false
	if multiplayer.is_server():
		var before := position
		_server_step(delta)
		jumped = before.distance_to(position) > 2.0
	else:
		if position.distance_to(net_position) > 5.0:
			position = net_position
			jumped = true
		var k := 1.0 - exp(-12.0 * delta)
		position = position.lerp(net_position, k)
		rotation.y = lerp_angle(rotation.y, net_yaw, k)
	_prev_pos = position if jumped else _cur_pos
	_prev_yaw = rotation.y if jumped else _cur_yaw
	_cur_pos = position
	_cur_yaw = rotation.y
	_model.animate(delta, 0.0 if stunned else net_speed, false, alert == 2, 0.0, pose == 1)
	_model.set_holding(holding)
	# Fall flat on their back when shoved, then get up.
	_tilt = lerpf(_tilt, -1.35 if stunned else 0.0, minf(1.0, delta * (10.0 if stunned else 4.0)))
	_speech_label.text = speech
	_alert_label.text = ["", "?", "!"][alert]
	_alert_label.modulate = Color("ffd24a") if alert == 1 else Color("ff4a4a")
	if speech != _last_speech:
		_last_speech = speech
		if speech != "":
			Sfx.voice(speech, global_position + Vector3(0, 1.6, 0), voice_pitch)
	_step += net_speed * delta
	if _step > 1.5:
		_step = 0.0
		Sfx.play_at("footstep", global_position, -14.0 if net_speed < 3.0 else -6.0, randf_range(0.8, 1.0))


func _process(_delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var pos := _prev_pos.lerp(_cur_pos, f)
	_model.global_transform = Transform3D(Basis.from_euler(Vector3(_tilt, lerp_angle(_prev_yaw, _cur_yaw, f), 0)), pos)
	_tag.global_position = pos + Vector3(0, HEIGHT + 0.2, 0)
	_speech_label.global_position = pos + Vector3(0, HEIGHT + 0.55, 0)
	_alert_label.global_position = pos + Vector3(0, HEIGHT + 0.95, 0)


func _server_step(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if stunned:
		_stun_time -= delta
		velocity.x = _knock.x
		velocity.z = _knock.z
		_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
		move_and_slide()
		if _stun_time <= 0.0:
			stunned = false
		net_position = position
		net_speed = 0.0
		return

	var flat_vel := Vector3.ZERO
	while not _path.is_empty():
		var to := _path[0] - global_position
		to.y = 0
		if to.length() < 0.4:
			_path.pop_front()
			_stuck_time = 0.0
			continue
		flat_vel = to.normalized() * move_speed
		break

	velocity.x = flat_vel.x + _push.x
	velocity.z = flat_vel.z + _push.z
	_push = _push.move_toward(Vector3.ZERO, 12.0 * delta)
	var before := global_position
	move_and_slide()

	if flat_vel != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, yaw_towards(flat_vel), minf(1.0, delta * 10.0))
		# Skip a waypoint if we're wedged against something.
		if before.distance_to(global_position) < move_speed * delta * 0.2:
			_stuck_time += delta
			if _stuck_time > 0.8 and not _path.is_empty():
				_path.pop_front()
				_stuck_time = 0.0
	else:
		rotation.y = lerp_angle(rotation.y, look_yaw, minf(1.0, delta * 5.0))

	if _speech_time > 0.0:
		_speech_time -= delta
		if _speech_time <= 0.0:
			speech = ""

	net_position = position
	net_yaw = rotation.y
	net_speed = Vector2(velocity.x, velocity.z).length()
