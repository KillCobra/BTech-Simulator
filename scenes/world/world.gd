extends Node3D
## The game world: lighting, the voxel campus, player + NPC spawning, the
## rules Director and the HUD. With `preview = true` it is just a slowly
## orbiting backdrop for the menu.

const CampusBuilder := preload("res://scenes/world/campus_builder.gd")
const Director := preload("res://scenes/world/director.gd")
const PlayerScript := preload("res://scenes/player/player.gd")
const NpcScript := preload("res://scenes/npc/npc.gd")
const BallScript := preload("res://scenes/props/ball.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const P := preload("res://scripts/palette.gd")
const Voxel := preload("res://scripts/voxel.gd")

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
	_hud.refresh(_director, me, get_viewport().get_camera_3d(), _npcs_root, _players_root)
	_update_props()
	_update_audio()
	if me and OS.get_cmdline_user_args().has("--trace") and Engine.get_process_frames() % 30 == 0:
		print("[trace] pos=%s vel=%s floor=%s" % [me.global_position, me.velocity, me.is_on_floor()])
		var t2 := _npcs_root.get_node_or_null("Teacher2")
		if t2:
			print("[trace] Teacher2=%s" % t2.global_position)


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
	for cam in campus.cctv:
		var node: Node3D = cam.node
		node.rotation.y = _director.cctv_yaw(cam, t)
		node.get_child(0).get_node("Led").visible = int(t * 2.0) % 2 == 0
	_update_coins(t)
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
	if _director.round_over:
		Sfx.set_music("")
	elif st.get("state", "") == "chased":
		Sfx.set_music("chase")
	else:
		Sfx.set_music("calm")


func _on_effect(kind: String, pos: Vector3, extra: String) -> void:
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
