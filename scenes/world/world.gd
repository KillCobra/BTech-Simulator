extends Node3D
## The game world: lighting, the voxel campus, player + NPC spawning, the
## rules Director and the HUD. With `preview = true` it is just a slowly
## orbiting backdrop for the menu.

const CampusBuilder := preload("res://scenes/world/campus_builder.gd")
const Director := preload("res://scenes/world/director.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const NpcScript := preload("res://scenes/npc/npc.gd")
const BallScript := preload("res://scenes/props/ball.gd")
const TrolleyScript := preload("res://scenes/props/trolley.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const P := preload("res://scripts/palette.gd")
const Voxel := preload("res://scripts/voxel.gd")
const StudentModel := preload("res://scenes/player/student_model.gd")

var preview := false
var preview_map := -1  # lobby: show this map from the air (-1 = the menu's close-up of the academic block)
var campus: RefCounted

var _players_root: Node3D
var _npcs_root: Node3D
var _spawner: MultiplayerSpawner
var _npc_spawner: MultiplayerSpawner
var _props_root: Node3D
var _prop_spawner: MultiplayerSpawner
var _director: Node
var _hud: CanvasLayer
var _fixed_cam: Camera3D
var _orbit_t := 0.0
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	if not preview:
		add_to_group("world")
	_build_environment()
	campus = CampusBuilder.new()
	var t0 := Time.get_ticks_msec()
	campus.build(self, maxi(preview_map, 0) if preview else Network.current_map)
	print("[world] built map %d in %d ms" % [campus.map_id, Time.get_ticks_msec() - t0])
	if preview:
		_fixed_cam = Camera3D.new()
		_fixed_cam.fov = 55
		_fixed_cam.far = 1500.0
		add_child(_fixed_cam)
		_fixed_cam.current = true
		return

	_players_root = _container("Players")
	_npcs_root = _container("Npcs")
	_spawner = _make_spawner("PlayerSpawner", _players_root, _spawn_player)
	_npc_spawner = _make_spawner("NpcSpawner", _npcs_root, _spawn_npc)
	_props_root = _container("Props")
	_prop_spawner = _make_spawner("PropSpawner", _props_root, _spawn_prop)

	_director = Director.new()
	_director.name = "Director"
	_director.campus = campus
	_director.players_root = _players_root
	_director.npc_spawner = _npc_spawner
	_director.prop_spawner = _prop_spawner
	add_child(_director)

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup_map(campus)
	_director.toasted.connect(_hud.toast)
	_director.effect.connect(_on_effect)
	_setup_debug_camera()
	_apply_round_event()
	Sfx.set_music("calm")
	Sfx.set_ambience(true)

	if multiplayer.is_server():
		Network.all_loaded.connect(_spawn_all_players, CONNECT_ONE_SHOT)
		Network.late_joined.connect(_spawn_late)
		Network.player_leaving.connect(_director.save_departed)
		Network.player_left.connect(_on_player_left)
	Network.report_loaded()


func _container(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	return n


func _make_spawner(node_name: String, root: Node, fn: Callable) -> MultiplayerSpawner:
	var s := MultiplayerSpawner.new()
	s.name = node_name
	add_child(s)
	s.spawn_path = s.get_path_to(root)
	s.spawn_function = fn
	return s


func _process(delta: float) -> void:
	for fan in campus.fans:
		fan.rotate_y(delta * 9.0)
	(campus.clouds as Node3D).rotate_y(delta * 0.004)
	if preview:
		_orbit_t += delta * 0.035
		var target := Vector3(0, 1.5, -6)
		var radius := 30.0
		var height := 13.0
		if preview_map >= 0:
			# Circle the whole university so you can see what you're picking.
			var b: Rect2 = campus.bounds
			target = Vector3(b.get_center().x, 0, b.get_center().y)
			radius = maxf(b.size.x, b.size.y) * 0.55
			height = radius * 0.55
		_fixed_cam.position = target + Vector3(sin(_orbit_t) * radius, height + sin(_orbit_t * 0.7) * 3.0, -cos(_orbit_t) * radius)
		_fixed_cam.look_at(target)
		return
	if _fixed_cam:
		_fixed_cam.current = true
	var me := _players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	_step_replay(delta)
	_hud.refresh(_director, me, get_viewport().get_camera_3d(), _npcs_root, _players_root)
	_update_rain()
	_update_props()
	_update_heat_look(delta)
	_update_audio()
	if me and OS.get_cmdline_user_args().has("--trace") and Engine.get_process_frames() % 30 == 0:
		print("[trace] pos=%s vel=%s floor=%s" % [me.global_position, me.velocity, me.is_on_floor()])
		var t2 := _npcs_root.get_node_or_null("Teacher2")
		if t2:
			print("[trace] Teacher2=%s" % t2.global_position)


# --- Round events you can see: rain, a power cut ----------------------------------------------

var _power_cut := false
var _rain: CPUParticles3D


func _apply_round_event() -> void:
	match str(Network.round_rules.get("event", "")):
		"power_cut":
			_power_cut = true
			for light in find_children("*", "OmniLight3D", true, false):
				(light as OmniLight3D).light_energy *= 0.15
			_env.ambient_light_energy *= 0.6
		"rain":
			_sun.light_energy *= 0.55
			_rain = CPUParticles3D.new()
			_rain.amount = 900
			_rain.lifetime = 0.9
			_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			_rain.emission_box_extents = Vector3(18, 0.5, 18)
			_rain.direction = Vector3(0.1, -1, 0)
			_rain.spread = 3.0
			_rain.initial_velocity_min = 22.0
			_rain.initial_velocity_max = 26.0
			_rain.gravity = Vector3(0, -10, 0)
			var drop := QuadMesh.new()
			drop.size = Vector2(0.03, 0.6)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.8, 0.88, 1.0, 0.45)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			drop.material = mat
			_rain.mesh = drop
			add_child(_rain)


## The light warms and reddens, and the colour drains a little, as the heat rises. Derived from the
## replicated heat, so a late joiner sees the right look at once. (adjustment_enabled is on in _build_environment.)
const HEAT_SUN := [Color("ffe9c4"), Color("ffe9c4"), Color("ffdcae"), Color("ffc58c"), Color("ff9a78")]      # index = heat; 1 = the default look
const HEAT_AMBIENT := [Color("fff0dc"), Color("fff0dc"), Color("ffeadb"), Color("ffd8bc"), Color("ffb8a0")]
const HEAT_SAT := [1.12, 1.12, 1.12, 1.04, 0.92]
var _heat_k := -1.0  # the look's heat, eased between levels (-1: not applied yet, so the first frame snaps)


func _update_heat_look(delta: float) -> void:
	var target := float(clampi(int(_director.world.get("heat", 1)), 1, 4))
	if _heat_k == target:
		return  # settled: no per-frame Environment or Sun writes
	_heat_k = target if _heat_k < 0.0 else move_toward(_heat_k, target, delta * 0.5)  # about 2 s per level
	var lo := int(_heat_k)
	var hi := mini(lo + 1, 4)
	var f := _heat_k - float(lo)
	var sun0: Color = HEAT_SUN[lo]
	var sun1: Color = HEAT_SUN[hi]
	var amb0: Color = HEAT_AMBIENT[lo]
	var amb1: Color = HEAT_AMBIENT[hi]
	_sun.light_color = sun0.lerp(sun1, f)
	_env.ambient_light_color = amb0.lerp(amb1, f)
	_env.adjustment_saturation = lerpf(float(HEAT_SAT[lo]), float(HEAT_SAT[hi]), f)


## Rain follows the camera, and stops when there's a roof overhead.
func _update_rain() -> void:
	if _rain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_rain.global_position = cam.global_position + Vector3(0, 10, 0)
	if Engine.get_process_frames() % 10 == 0:
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + Vector3(0, 30, 0), 1))
		_rain.emitting = hit.is_empty()


## Things every peer derives from replicated Director state.
var _prop_clock := 0.0
var _prop_synced := -1.0


func _update_props() -> void:
	# Guests receive `elapsed` 5x a second: tick a local clock between updates so
	# cameras sweep smoothly instead of in steps.
	if _director.elapsed != _prop_synced:
		_prop_synced = _director.elapsed
		_prop_clock = _director.elapsed
	else:
		_prop_clock += get_process_delta_time()
	var t: float = _prop_clock
	var sharp: bool = int(_director.world.get("heat", 1)) >= 3  # heat 3+: the CCTV LEDs blink faster
	for cam in campus.cctv:
		var node: Node3D = cam.node
		node.rotation.y = _director.cctv_yaw(cam, t)
		node.get_child(0).get_node("Led").visible = int(t * (6.0 if sharp else 2.0)) % 2 == 0 and not _power_cut
	_update_coins(t)
	_update_puddles(t)
	var gate_open: bool = float(_director.world.gate_until) > t
	var gate: Node3D = campus.service_gate
	gate.visible = not gate_open
	(gate.get_child(0) as CollisionShape3D).disabled = gate_open


## Spinning gold coins where the Director says money is lying around.
var _coins: Array[MeshInstance3D] = []


func _update_coins(t: float) -> void:
	var list: Array = _director.world.get("coins", [])
	while _coins.size() < list.size():
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.17
		mesh.bottom_radius = 0.17
		mesh.height = 0.05
		mesh.radial_segments = 16
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("ffc93c")
		mat.metallic = 0.6
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = Color("ffb000")
		mat.emission_energy_multiplier = 0.6
		mesh.material = mat
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_coins.append(mi)
	for k in _coins.size():
		var mi := _coins[k]
		mi.visible = k < list.size()
		if mi.visible:
			var pos: Vector3 = list[k].p
			var h: float = list[k].get("h", 0.55)  # low under desks and chairs
			mi.position = pos + Vector3(0, h + sin(t * 2.5 + k) * (0.08 if h > 0.3 else 0.03), 0)
			mi.rotation = Vector3(PI / 2.0, t * 3.0 + k, 0)


func _update_audio() -> void:
	if float(_director.world.alarm_until) > _director.elapsed and not _director.round_over:
		Sfx.start_loop("siren", "alarm", -8.0)
	else:
		Sfx.stop_loop("alarm")
	var st: Dictionary = _director.status.get(multiplayer.get_unique_id(), {})
	# Lockdown (heat 4): a low throbbing drone under everything, until you are out or the round ends.
	if int(_director.world.get("heat", 1)) >= 4 and not _director.round_over and st.get("state", "") != "escaped":
		Sfx.start_loop("drone", "heat", -14.0)
	else:
		Sfx.stop_loop("heat")
	if _director.round_over:
		Sfx.set_music("")
	elif st.get("state", "") == "chased":
		Sfx.set_music("chase")
	else:
		Sfx.set_music("calm")


func _on_effect(kind: String, pos: Vector3, extra: String) -> void:
	_hud.on_effect(kind, pos, extra)
	if kind == "win":  # look back at the university you just escaped
		var me := _players_root.get_node_or_null(str(multiplayer.get_unique_id()))
		var a: Rect2 = campus.academic_rect
		if me:
			me.escape_shot(Vector3(a.get_center().x, 4.0, a.get_center().y))
	match kind:
		"bell":
			Sfx.play("bell")
		"office_bell":
			Sfx.play_at("bell", pos, 0.0, 1.5)
		"pickup":
			Sfx.play("pickup")
		"swish":
			Sfx.play_at("pickup", pos, 2.0)
		"quest":
			Sfx.play("pickup", 0.0, 1.3)
		"coin":
			Sfx.play("pickup", -2.0, 1.7)
		"paper":
			Sfx.play("paper", 0.0, 1.2)
		"badge":
			Sfx.play("win", -4.0, 1.2)
		"win":
			Sfx.play("win")
		"caught":
			Sfx.play("caught")
		"heat":  # "level|why": a low stinger, and at lockdown the klaxon (the drone starts in _update_audio)
			var lvl := int(extra.get_slice("|", 0))
			if lvl >= 4:
				Sfx.play("klaxon", -2.0)
			else:
				Sfx.play("heat_hit", -2.0, 0.85 + 0.1 * lvl)
		"whistle":
			Sfx.play_at("whistle", pos, 2.0)
			if extra == str(multiplayer.get_unique_id()):
				Sfx.play("alarm_spotted")
		"paper":
			Sfx.play_at("paper", pos)
			_drop_paper_ball(pos)
		"paper_arc":
			_fly_paper_ball(pos, extra)
		"stash":
			Sfx.play_at("paper", pos, 0.0, 0.7)
		"splash":
			Sfx.play_at("flush", pos, -2.0, 1.4)
		"flush":
			Sfx.play_at("flush", pos, 2.0)
		"note":
			var parts := extra.split(":")
			var n := int(parts[1]) if parts.size() > 1 else 1
			if parts[0] == "piano":
				Sfx.play_at("piano", pos, 4.0, [1.0, 1.125, 1.25, 1.333, 1.5, 1.667, 1.875, 2.0][clampi(n - 1, 0, 7)])
			else:
				var kit := [["kick", 1.0], ["snare", 1.0], ["hat", 1.0], ["tom", 0.8], ["tom", 1.0], ["tom", 1.25], ["crash", 1.0], ["snare", 1.5]]
				var d: Array = kit[clampi(n - 1, 0, 7)]
				Sfx.play_at(d[0], pos, 4.0, d[1])
		"ping", "camera":
			Sfx.play("click", 0.0, 0.7 if kind == "camera" else 1.0)
		"gate":
			Sfx.play_at("click", pos, 4.0, 0.8)
		"boost":
			Sfx.play_at("paper", pos, 0.0, 0.6)
		"shove":
			Sfx.play_at("footstep", pos, 6.0, 0.5)
			Sfx.play_at("deny", pos, -4.0, 1.4)
		"throw":
			Sfx.play_at("paper", pos, -4.0, 1.6)
		"tumble":
			Sfx.play_at("footstep", pos, 8.0, 0.4)
			Sfx.play_at("deny", pos, -6.0, 0.8)
		"books":
			_spill_books(pos, extra)
			Sfx.play_at("footstep", pos, 6.0, 0.45)
		"spray":
			_spray_cloud(pos, extra)
		"samosa_arc":
			_fly_samosa(pos, extra)
		"ring":
			for k in 3:
				get_tree().create_timer(k * 0.45).timeout.connect(Sfx.play_at.bind("phone", pos, 8.0, 1.1))
			if extra == str(multiplayer.get_unique_id()):
				Sfx.play("phone", 0.0, 1.1)
		"pa":
			Sfx.play("bell", -14.0, 2.2)
		"shout":
			var parts := extra.split("|", true, 1)
			var who := _players_root.get_node_or_null(parts[0])
			if who and parts.size() > 1:
				who.shout(parts[1])


# --- Chaos you can see: wet floors, extinguisher smoke, spilled books, flying samosas -----------------

var _puddle_nodes: Array[Node3D] = []


## Wet floors (and extinguisher foam) where the Director says they are.
func _update_puddles(_t: float) -> void:
	var list: Array = _director.things.get("puddles", [])
	while _puddle_nodes.size() < list.size():
		var root := Node3D.new()
		var disc := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.height = 0.02
		mesh.radial_segments = 20
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.05
		mat.metallic = 0.3
		mesh.material = mat
		disc.mesh = mesh
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(disc)
		var sign := Voxel.new(9)
		sign.box(Vector3(0, 0.35, 0), Vector3(0.36, 0.6, 0.04), Color("ffd24a"))
		sign.box(Vector3(0, 0.42, 0.03), Vector3(0.24, 0.2, 0.01), Color("26262e"))
		var sign_node := sign.to_instance()
		sign_node.name = "Sign"
		root.add_child(sign_node)
		add_child(root)
		_puddle_nodes.append(root)
	for k in _puddle_nodes.size():
		var node := _puddle_nodes[k]
		node.visible = k < list.size()
		if not node.visible:
			continue
		var pd: Dictionary = list[k]
		var foam: bool = str(pd.get("kind", "")) == "foam"
		node.position = (pd.p as Vector3) + Vector3(0, 0.02, 0)
		var disc: MeshInstance3D = node.get_child(0)
		disc.scale = Vector3(float(pd.r), 1.0, float(pd.r))
		var mat: StandardMaterial3D = (disc.mesh as CylinderMesh).material
		mat.albedo_color = Color(1, 1, 1, 0.8) if foam else Color(0.55, 0.8, 1.0, 0.45)
		node.get_node("Sign").visible = not foam
		node.get_node("Sign").position = Vector3(float(pd.r) * 0.7, 0, 0)


## Knocked-over staff drop their books: a few blocks that tumble and settle.
func _spill_books(pos: Vector3, extra: String) -> void:
	var dir := Vector2.ZERO
	var f := extra.split_floats(",")
	if f.size() == 2:
		dir = Vector2(f[0], f[1])
	for k in 3 + randi() % 3:
		var book := RigidBody3D.new()
		book.collision_layer = 0
		book.collision_mask = 1
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.22, 0.05, 0.3)
		var col := CollisionShape3D.new()
		col.shape = shape
		book.add_child(col)
		var v := Voxel.new(k)
		v.box(Vector3.ZERO, Vector3(0.22, 0.05, 0.3), [Color("e0524f"), Color("4f86e0"), Color("7fe0a0"), Color("ffd24a"), Color("9a62d6")][randi() % 5])
		v.box(Vector3(0.0, 0.0, 0.0), Vector3(0.2, 0.052, 0.28), Color("fbf6e8"))
		book.add_child(v.to_instance())
		add_child(book)
		book.global_position = pos + Vector3(randf_range(-0.2, 0.2), 1.3, randf_range(-0.2, 0.2))
		book.linear_velocity = Vector3(dir.x * 0.4 + randf_range(-2, 2), randf_range(2.0, 4.0), dir.y * 0.4 + randf_range(-2, 2))
		book.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		get_tree().create_timer(7.0).timeout.connect(book.queue_free)


## Fire extinguisher: a burst of white smoke that hangs about for a while.
func _spray_cloud(pos: Vector3, extra: String) -> void:
	var f := extra.split_floats(",")
	var dir := Vector3(f[0], 0, f[1]) if f.size() == 2 else Vector3.FORWARD
	var puff := CPUParticles3D.new()
	puff.amount = 180
	puff.lifetime = 6.0
	puff.one_shot = true
	puff.explosiveness = 0.25
	puff.direction = dir
	puff.spread = 22.0
	puff.initial_velocity_min = 3.0
	puff.initial_velocity_max = 6.0
	puff.damping_min = 2.5
	puff.damping_max = 3.5
	puff.gravity = Vector3(0, 0.15, 0)
	puff.scale_amount_min = 0.9
	puff.scale_amount_max = 2.0
	var q := SphereMesh.new()
	q.radius = 0.35
	q.height = 0.7
	q.radial_segments = 8
	q.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.96, 0.97, 1.0, 0.42)
	q.material = mat
	puff.mesh = q
	add_child(puff)
	puff.global_position = pos + dir * 0.9
	puff.emitting = true
	Sfx.play_at("flush", pos, 4.0, 2.2)
	get_tree().create_timer(9.0).timeout.connect(puff.queue_free)


## A samosa arcing from `from` to "x,y,z".
func _fly_samosa(from: Vector3, extra: String) -> void:
	var to := _vec(extra)
	var v := Voxel.new(4)
	v.box(Vector3.ZERO, Vector3(0.18, 0.1, 0.18), Color("e0a050"))
	v.box(Vector3(0, 0.06, 0), Vector3(0.1, 0.05, 0.1), Color("c9853a"))
	var s := v.to_instance()
	add_child(s)
	s.position = from
	var t_end := clampf(from.distance_to(to) / 14.0, 0.2, 1.0)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(s):
			s.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * 1.2, 0)
			s.rotation = Vector3(t * 12.0, t * 7.0, 0.0), 0.0, 1.0, t_end)
	tw.tween_callback(func(): Sfx.play_at("paper", to, 0.0, 0.6))
	tw.tween_callback(s.queue_free)


## A thrown paper ball: flies along its arc, then lies where it hit for a while.
## extra = "from x,y,z|velocity x,y,z|flight time".
func _fly_paper_ball(landing: Vector3, extra: String) -> void:
	var parts := extra.split("|")
	if parts.size() < 3:
		_drop_paper_ball(landing)
		return
	var from := _vec(parts[0])
	var vel := _vec(parts[1])
	var t_end := maxf(0.05, float(parts[2]))
	var v := preload("res://scripts/voxel.gd").new()
	v.box(Vector3.ZERO, Vector3(0.12, 0.12, 0.12), Color("fbf6e8"))
	v.box(Vector3(0.03, 0.04, -0.02), Vector3(0.08, 0.06, 0.1), Color("e8e0cc"))
	var ball := v.to_instance()
	ball.position = from
	add_child(ball)
	Sfx.play_at("paper", from, -6.0, 1.6)
	var tween := create_tween()
	tween.tween_method(func(t: float):
		if is_instance_valid(ball):
			ball.position = from + vel * t + Vector3.DOWN * 4.9 * t * t
			ball.rotation = Vector3(t * 9.0, t * 6.0, 0.0), 0.0, t_end, t_end)
	tween.tween_callback(func():
		ball.position = landing
		Sfx.play_at("paper", landing))
	tween.tween_interval(6.0)
	tween.tween_callback(ball.queue_free)


static func _vec(text: String) -> Vector3:
	var f := text.split_floats(",")
	return Vector3(f[0], f[1], f[2]) if f.size() == 3 else Vector3.ZERO


func _drop_paper_ball(pos: Vector3) -> void:
	var v := preload("res://scripts/voxel.gd").new()
	v.box(Vector3.ZERO, Vector3(0.12, 0.12, 0.12), Color("fbf6e8"))
	var ball := v.to_instance()
	ball.position = pos + Vector3(0, 0.8, 0)
	add_child(ball)
	var tween := create_tween()
	tween.tween_property(ball, "position:y", pos.y + 0.06, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(6.0)
	tween.tween_callback(ball.queue_free)


# --- CCTV replay: the round's best moment, played back with puppets --------------------------------

signal replay_finished
var replaying := false
var _replay: Dictionary = {}
var _replay_t := 0.0
var _replay_root: Node3D
var _replay_cam: Camera3D
var _replay_puppets := {}   # key -> StudentModel
var _replay_prev_cam: Camera3D
var _replay_next_event := 0
var _replay_bubbles := {}  # key -> [Label3D, seconds left]


## Plays the Director's `replay` clip from a CCTV-style camera. Everyone's real body is
## hidden meanwhile; blocky stand-ins act the moment out.
func play_replay(clip: Dictionary) -> void:
	if clip.is_empty() or (clip.get("frames", []) as Array).is_empty():
		replay_finished.emit()
		return
	stop_replay()
	_replay = clip
	_replay_t = float((clip.frames as Array)[0][0])
	_replay_next_event = 0
	_replay_bubbles.clear()
	replaying = true
	_replay_root = Node3D.new()
	_replay_root.name = "Replay"
	add_child(_replay_root)
	var looks: Dictionary = clip.get("looks", {})
	for key in clip.keys:
		if not looks.has(key):
			continue
		var m: Node3D = StudentModel.new()
		m.build(looks[key])
		_replay_root.add_child(m)
		_replay_puppets[key] = m
		var bubble := Label3D.new()
		bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bubble.font_size = 34
		bubble.outline_size = 12
		bubble.no_depth_test = true
		bubble.position.y = 2.25
		m.add_child(bubble)
		_replay_bubbles[key] = [bubble, 0.0]
	_players_root.visible = false
	_npcs_root.visible = false
	var focus: Vector3 = clip.focus
	_replay_prev_cam = get_viewport().get_camera_3d()
	_replay_cam = Camera3D.new()
	_replay_cam.fov = 62.0
	add_child(_replay_cam)
	_replay_cam.global_transform = _cctv_spot(focus)
	_replay_cam.current = true
	print("[replay] playing '%s' (%d frames, %d people)" % [clip.title, (clip.frames as Array).size(), _replay_puppets.size()])



## High in a corner, looking down at `focus`, like a real camera (not through a wall).
func _cctv_spot(focus: Vector3) -> Transform3D:
	var eye := focus + Vector3(0, 1.2, 0)
	var space := get_world_3d().direct_space_state
	var best := eye + Vector3(4, 2.6, 4)
	var best_room := -1.0
	for k in 8:
		var a := k * TAU / 8.0 + 0.4
		var at := eye + Vector3(cos(a) * 5.0, 2.4, sin(a) * 5.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, at, 1))
		var room := 1.0 if hit.is_empty() else eye.distance_to(hit.position) / eye.distance_to(at)
		if room > best_room:
			best_room = room
			best = at if hit.is_empty() else eye.lerp(hit.position, 0.85)
		if room > 0.99:
			break
	return Transform3D(Basis(), best).looking_at(focus + Vector3(0, 0.6, 0), Vector3.UP)


func stop_replay() -> void:
	if not replaying:
		return
	replaying = false
	if is_instance_valid(_replay_root):
		_replay_root.queue_free()
	if is_instance_valid(_replay_cam):
		_replay_cam.queue_free()
	_replay_puppets.clear()
	_players_root.visible = true
	_npcs_root.visible = true
	if is_instance_valid(_replay_prev_cam):
		_replay_prev_cam.current = true
	replay_finished.emit()


func _step_replay(delta: float) -> void:
	if not replaying:
		return
	_replay_t += delta * 0.85  # a touch of slow motion
	var frames: Array = _replay.frames
	var last: PackedFloat32Array = frames[frames.size() - 1]
	if _replay_t > last[0] + 0.6:
		stop_replay()
		return
	# What happened (and what was said) at this point of the clip.
	var events: Array = _replay.get("events", [])
	while _replay_next_event < events.size() and float(events[_replay_next_event].t) <= _replay_t:
		var ev: Dictionary = events[_replay_next_event]
		_replay_next_event += 1
		if ev.has("say") and _replay_bubbles.has(str(ev.say)):
			var b: Array = _replay_bubbles[str(ev.say)]
			(b[0] as Label3D).text = str(ev.text)
			b[1] = 2.6
		elif ev.has("fx"):
			if str(ev.fx) == "shout":
				var parts := str(ev.extra).split("|", true, 1)
				var key := "p" + parts[0]
				if parts.size() > 1 and _replay_bubbles.has(key):
					(_replay_bubbles[key][0] as Label3D).text = parts[1]
					_replay_bubbles[key][1] = 2.2
			else:
				_on_effect(str(ev.fx), ev.pos, str(ev.extra))
	for key in _replay_bubbles:
		var b: Array = _replay_bubbles[key]
		b[1] = maxf(0.0, float(b[1]) - delta)
		(b[0] as Label3D).visible = float(b[1]) > 0.0
	var i := 0
	while i < frames.size() - 2 and float(frames[i + 1][0]) < _replay_t:
		i += 1
	var a: PackedFloat32Array = frames[i]
	var b: PackedFloat32Array = frames[mini(i + 1, frames.size() - 1)]
	var span := maxf(b[0] - a[0], 0.001)
	var k := clampf((_replay_t - a[0]) / span, 0.0, 1.0)
	var keys: Array = _replay.keys
	for n in keys.size():
		var key: String = keys[n]
		var m: Node3D = _replay_puppets.get(key)
		if m == null:
			continue
		var o := 1 + n * 5
		if a[o + 1] < -900.0 or b[o + 1] < -900.0:
			m.visible = false
			continue
		var pa := Vector3(a[o], a[o + 1], a[o + 2])
		var pb := Vector3(b[o], b[o + 1], b[o + 2])
		var flags := int(b[o + 4])
		m.visible = flags & 4 == 0  # hidden in a locker
		var pos := pa.lerp(pb, k)
		var yaw := lerp_angle(a[o + 3], b[o + 3], k)
		var down := flags & 2 != 0
		m.global_transform = Transform3D(Basis.from_euler(Vector3(-1.35 if down else 0.0, yaw, 0)), pos)
		var speed := Vector2(pb.x - pa.x, pb.z - pa.z).length() / span
		m.animate(delta, 0.0 if down else speed, flags & 1 != 0, speed > 4.5, 0.0, flags & 8 != 0)
		if key == str(_replay.get("subject", "")) and m.visible and is_instance_valid(_replay_cam):
			# The camera pans to keep the star of the clip in shot, like a real CCTV.
			var look := _replay_cam.global_transform.looking_at(pos + Vector3(0, 0.9, 0), Vector3.UP)
			_replay_cam.global_transform = _replay_cam.global_transform.interpolate_with(look, minf(1.0, delta * 3.0))


## Dev: "--cam=x,y,z,tx,ty,tz" pins a camera at a spot looking at a target (for screenshots).
func _setup_debug_camera() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--cam="):
			continue
		var v := arg.trim_prefix("--cam=").split_floats(",")
		if v.size() != 6:
			return
		_fixed_cam = Camera3D.new()
		_fixed_cam.fov = 70
		add_child(_fixed_cam)
		_fixed_cam.position = Vector3(v[0], v[1], v[2])
		_fixed_cam.look_at(Vector3(v[3], v[4], v[5]))
		_hud.debug_camera = true


# --- Spawning ---------------------------------------------------------------------------

func _spawn_all_players() -> void:
	var ids: Array = Network.players.keys()
	ids.sort()
	var seats_taken := {}
	var seat_map := {}
	for id in ids:
		var info: Dictionary = Network.players[id]
		var room: int = info.classroom
		var seat: int = seats_taken.get(room, 0)
		seats_taken[room] = seat + 1
		var room_seats: Array = campus.seats[room]
		var pos: Vector3 = room_seats[seat % room_seats.size()]
		seat_map[id] = pos
		var look := P.apply_prefs(P.make_look(id, int(info.classroom)), info.get("look", {}))
		_spawner.spawn({"id": id, "name": info.name, "look": look, "pos": pos, "yaw": campus.classes[room].yaw, "seated": true})
	_director.start(seat_map, Network.round_minutes)


func _spawn_late(id: int) -> void:
	if not Network.players.has(id) or _players_root.has_node(str(id)):
		return
	var info: Dictionary = Network.players[id]
	var room: int = _director.current_room(id)
	var pos: Vector3 = _director.free_seat(room)
	_director.add_player(id, pos)
	var look := P.apply_prefs(P.make_look(id, int(info.classroom)), info.get("look", {}))
	_spawner.spawn({"id": id, "name": info.name, "look": look, "pos": pos, "yaw": campus.classes[room].yaw, "seated": true})


func _spawn_player(data: Dictionary) -> Node:
	var player: CharacterBody3D = PlayerScript.new()
	player.setup(data.id, data.name, data.look, data.pos, data.get("yaw", PI))  # face the blackboard
	player.seated = bool(data.get("seated", false))
	print("[peer %d] spawned %s (%s)" % [multiplayer.get_unique_id(), data.name, data.id])
	return player


func _spawn_prop(data: Dictionary) -> Node:
	if str(data.get("kind", "")) == "trolley":
		var trolley: CharacterBody3D = TrolleyScript.new()
		trolley.setup(data, _players_root)
		return trolley
	var ball: RigidBody3D = BallScript.new()
	ball.setup(data, _players_root)
	return ball


func _spawn_npc(data: Dictionary) -> Node:
	var npc: CharacterBody3D = NpcScript.new()
	npc.setup(data)
	return npc


func _on_player_left(id: int) -> void:
	var node := _players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()


# --- Look -------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3d8fe6")
	sky_mat.sky_horizon_color = Color("a9d6f2")
	sky_mat.sky_curve = 0.18
	sky_mat.ground_bottom_color = Color("6a8f5a")
	sky_mat.ground_horizon_color = Color("a9d6f2")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color("fff0dc")
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.ssil_intensity = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("d8e8f0")
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("ffe9c4")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	# A bit more bias and blended cascades: no acne or shimmer on block faces and corners.
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	_env = env
	_sun = sun
	_apply_graphics()
	Settings.changed.connect(_apply_graphics)


func _apply_graphics() -> void:
	Settings.apply_graphics(_env, _sun)
	# Dev: --gfx=ssao:0,ssil:0,msaa:0,taa:1,fxaa:0,shadow:0 (A/B render tests).
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--gfx="):
			continue
		for pair in arg.trim_prefix("--gfx=").split(","):
			var kv := pair.split(":")
			if kv.size() != 2:
				continue
			var on := int(kv[1])
			match kv[0]:
				"ssao": _env.ssao_enabled = on != 0
				"ssil": _env.ssil_enabled = on != 0
				"glow": _env.glow_enabled = on != 0
				"shadow": _sun.shadow_enabled = on != 0
				"msaa": get_tree().root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(on, 0, 3)]
				"taa": get_tree().root.use_taa = on != 0
				"fxaa": get_tree().root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on != 0 else Viewport.SCREEN_SPACE_AA_DISABLED
				"bevel": Voxel.material().set_shader_parameter("bevel_light", on / 100.0)
