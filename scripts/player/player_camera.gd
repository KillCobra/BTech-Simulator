extends Camera3D

@export var follow_speed := 5.0
@export var look_sensitivity := 0.2
var target: Node3D

var vertical_angle := 0.0
var min_vertical := deg_to_rad(-80)
var max_vertical := deg_to_rad(80)

func _process(delta):
	if target:
		global_transform.origin = global_transform.origin.lerp(target.global_transform.origin, follow_speed * delta)
	var mouse_delta = Input.get_last_mouse_velocity() * look_sensitivity
	rotate_y(-mouse_delta.x * delta)
	vertical_angle = clamp(vertical_angle - mouse_delta.y * delta, min_vertical, max_vertical)
	rotation.x = vertical_angle
	if Input.is_action_just_pressed("camera_switch"):
		# Example: toggle between first and third person
		if get_parent().has_node("ThirdPersonCamera"):
			var third_person = get_parent().get_node("ThirdPersonCamera")
			third_person.current = not third_person.current
			current = not current
