extends CharacterBody3D

@export var walk_speed := 6.0
@export var sprint_speed := 10.0
@export var jump_velocity := 6.0
@export var rotation_speed := 10.0
@export var camera_manager_path: NodePath

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

    var move_input := Vector2(
        Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
        Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
    )

    var world_dir := _camera_relative_direction(move_input)
    var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

    if world_dir.length() > 0.001:
        velocity.x = world_dir.x * speed
        velocity.z = world_dir.z * speed
        var target_basis := Basis.looking_at(world_dir, Vector3.UP)
        basis = basis.slerp(target_basis, clampf(delta * rotation_speed, 0.0, 1.0))
    else:
        velocity.x = move_toward(velocity.x, 0.0, speed)
        velocity.z = move_toward(velocity.z, 0.0, speed)

    move_and_slide()

func _camera_relative_direction(input_vec: Vector2) -> Vector3:
    if input_vec.length() < 0.001:
        return Vector3.ZERO

    var active_basis := global_basis
    var manager := get_node_or_null(camera_manager_path)
    if manager and manager.has_method("get_active_basis"):
        active_basis = manager.get_active_basis()

    var cam_forward := -active_basis.z
    cam_forward.y = 0.0
    cam_forward = cam_forward.normalized()
    var cam_right := active_basis.x
    cam_right.y = 0.0
    cam_right = cam_right.normalized()

    return (cam_forward * input_vec.y + cam_right * input_vec.x).normalized()
