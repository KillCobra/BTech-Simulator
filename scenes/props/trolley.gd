extends CharacterBody3D
## A canteen trolley. Push it (E), let go at speed and it rolls on by itself, flattening
## any staff (or friend) in its way. A crouching friend can hop in and ride.
## The host moves it; clients follow the replicated position.

const Voxel := preload("res://scripts/voxel.gd")
const FRICTION := 2.2      # m/s² once nobody is pushing
const PUSH_GAP := 1.15     # held this far in front of the pusher
const HIT_SPEED := 3.0     # faster than this and it knocks people over

var pusher := -1           # peer id pushing it, -1 = nobody
var rider := -1            # peer id riding in it
var net_position := Vector3.ZERO
var net_yaw := 0.0
var roll := Vector3.ZERO   # server: rolling velocity after a launch
var last_pusher := -1      # server: who gets the credit for what it hits

var _players: Node
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(data: Dictionary, players_root: Node) -> void:
	name = data.id
	position = data.pos
	rotation.y = float(data.get("yaw", 0.0))
	net_position = data.pos
	net_yaw = rotation.y
	_players = players_root
	collision_layer = 4
	collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.6, 1.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.3  # the wheels touch the floor
	add_child(col)

	var v := Voxel.new(5)
	var steel := Color("b8c0c8")
	var dark := Color("3a3d47")
	v.box(Vector3(0, 0.62, 0), Vector3(0.72, 0.05, 1.02), steel)          # top tray
	v.box(Vector3(0, 0.28, 0), Vector3(0.7, 0.04, 1.0), steel.darkened(0.15))  # bottom tray
	for x in [-0.33, 0.33]:
		for z in [-0.47, 0.47]:
			v.box(Vector3(x, 0.4, z), Vector3(0.04, 0.5, 0.04), steel.darkened(0.25))  # posts
			v.box(Vector3(x, 0.07, z), Vector3(0.08, 0.14, 0.14), dark)                # wheels
	v.box(Vector3(0, 0.9, 0.5), Vector3(0.7, 0.05, 0.05), Color("e0524f"))  # handle
	for x in [-0.33, 0.33]:
		v.box(Vector3(x, 0.78, 0.5), Vector3(0.04, 0.28, 0.04), steel.darkened(0.25))
	v.box(Vector3(-0.15, 0.7, -0.2), Vector3(0.3, 0.12, 0.3), Color("e0a050"))  # a tray of samosas
	v.box(Vector3(0.18, 0.72, 0.15), Vector3(0.16, 0.16, 0.16), Color("f4f1e6"))  # a chai urn
	add_child(v.to_instance())

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_interval = 0.05
	var config := SceneReplicationConfig.new()
	for prop in [".:net_position", ".:net_yaw", ".:pusher", ".:rider"]:
		config.add_property(NodePath(prop))
		config.property_set_spawn(NodePath(prop), true)
		config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	Network.add_join_filter(sync)
	add_child(sync)


func speed() -> float:
	return Vector2(roll.x, roll.z).length()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		if global_position.distance_to(net_position) > 3.0:
			global_position = net_position
		var k := 1.0 - exp(-16.0 * delta)
		global_position = global_position.lerp(net_position, k)
		rotation.y = lerp_angle(rotation.y, net_yaw, k)
		return
	var by: Node3D = _players.get_node_or_null(str(pusher)) if pusher != -1 else null
	if pusher != -1 and by == null:
		pusher = -1
	if rider != -1 and _players.get_node_or_null(str(rider)) == null:
		rider = -1
	if by:
		# Held in front of the pusher, facing where they face.
		var fwd := -by.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var want: Vector3 = by.global_position + fwd * PUSH_GAP
		roll = (want - global_position) / maxf(delta, 0.001)
		roll.y = 0.0
		roll = roll.limit_length(9.0)
		rotation.y = lerp_angle(rotation.y, atan2(-fwd.x, -fwd.z), minf(1.0, delta * 10.0))
	else:
		roll = roll.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = roll.x
	velocity.z = roll.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	var before := global_position
	move_and_slide()
	if pusher == -1 and get_slide_collision_count() > 0:
		roll *= 0.35  # hit a wall: clang, nearly stops
	if pusher == -1 and speed() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-roll.x, -roll.z), minf(1.0, delta * 4.0))
	if global_position.y < -3.0:
		global_position = before + Vector3(0, 0.3, 0)
	net_position = global_position
	net_yaw = rotation.y


## Where a rider sits.
func seat_position() -> Vector3:
	return global_position + Vector3(0, 0.45, 0)


## Server: grab the handle / let go. Letting go while moving launches it.
func grab(peer: int) -> void:
	pusher = peer
	last_pusher = peer


func release(push: Vector3) -> void:
	pusher = -1
	roll = push
	roll.y = 0.0
