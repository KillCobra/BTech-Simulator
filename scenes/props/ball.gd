extends RigidBody3D
## A basketball. The server simulates it; clients just follow the replicated
## transform. While someone holds it, every peer places it in front of that
## player's hands, so it looks right with no extra network traffic.

const Voxel := preload("res://scripts/voxel.gd")
const RADIUS := 0.13

var holder := -1           # peer id holding it, -1 = loose
var last_thrower := -1     # server: who gets the points
var net_position := Vector3.ZERO
var net_rotation := Vector3.ZERO

var _players: Node
var _was_above := {}       # server: rim index -> ball was above that rim last frame


func setup(data: Dictionary, players_root: Node) -> void:
	name = data.id
	position = data.pos
	net_position = data.pos
	_players = players_root
	collision_layer = 4
	collision_mask = 1
	mass = 0.6
	continuous_cd = true
	var bouncy := PhysicsMaterial.new()
	bouncy.bounce = 0.72
	bouncy.friction = 0.6
	physics_material_override = bouncy
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0  # no air drag: shot arcs stay predictable
	angular_damp = 0.4

	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var v := Voxel.new(3)
	var orange := Color("ff7a2a")
	v.box(Vector3.ZERO, Vector3(0.24, 0.24, 0.24), orange)
	v.box(Vector3.ZERO, Vector3(0.245, 0.02, 0.245), Color("3a2412"))
	v.box(Vector3.ZERO, Vector3(0.02, 0.245, 0.245), Color("3a2412"))
	var mesh := v.to_instance()
	add_child(mesh)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_interval = 0.05
	var config := SceneReplicationConfig.new()
	for prop in [".:net_position", ".:net_rotation", ".:holder"]:
		config.add_property(NodePath(prop))
		config.property_set_spawn(NodePath(prop), true)
		config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	Network.add_join_filter(sync)
	add_child(sync)


func _ready() -> void:
	# Only the host runs physics; everyone else follows net_*.
	freeze = not multiplayer.is_server()


## Where a player's hands hold the ball: in front of the camera, a bit low.
func hand_position(p: Node3D) -> Vector3:
	var head: Node3D = p.get_node("Head")
	var fwd := -head.global_transform.basis.z
	var down := -head.global_transform.basis.y
	return head.global_position + fwd * 0.62 + down * 0.36


func _physics_process(delta: float) -> void:
	var held_by := _players.get_node_or_null(str(holder)) if holder != -1 else null
	if multiplayer.is_server():
		if holder != -1 and held_by == null:
			release(global_position, Vector3.ZERO)  # holder left the game
		if held_by:
			freeze = true
			global_position = hand_position(held_by)
		net_position = global_position
		net_rotation = rotation
		if holder == -1 and linear_velocity.length() > 0.5 and OS.get_cmdline_user_args().has("--trace") \
				and Engine.get_physics_frames() % 4 == 0:
			print("[ball] %s v=%s" % [global_position, linear_velocity])
	else:
		if held_by:
			global_position = hand_position(held_by)
		else:
			if global_position.distance_to(net_position) > 3.0:
				global_position = net_position
			var k := 1.0 - exp(-18.0 * delta)
			global_position = global_position.lerp(net_position, k)
			rotation = rotation.lerp(net_rotation, k)


## Server: someone grabs it.
func grab(peer: int) -> void:
	holder = peer
	freeze = true


## Server: let go (throw or drop).
func release(from: Vector3, velocity: Vector3) -> void:
	holder = -1
	global_position = from
	freeze = false
	linear_velocity = velocity
	angular_velocity = Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))


## Server: true once when the ball drops down through a rim.
func check_basket(rims: Array) -> bool:
	var scored := false
	for i in rims.size():
		var rim: Vector3 = rims[i]
		var flat := Vector2(global_position.x - rim.x, global_position.z - rim.z).length()
		var above: bool = global_position.y > rim.y
		if _was_above.get(i, false) and not above and flat < 0.24 and linear_velocity.y < 0.0 and holder == -1:
			scored = true
		_was_above[i] = above and flat < 0.5
	return scored
