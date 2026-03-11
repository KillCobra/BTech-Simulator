extends Node3D

signal active_camera_changed(camera_name: String)

@export var first_camera_path: NodePath = NodePath("Camera1")
@export var second_camera_path: NodePath = NodePath("Camera2")
@export var use_tween := true
@export var tween_time := 0.2

var _active := 0

func _ready() -> void:
    _set_current_camera(0)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("camera_switch"):
        switch_camera()

func switch_camera() -> void:
    _set_current_camera(1 if _active == 0 else 0)

func get_active_basis() -> Basis:
    var cam := _get_active_camera()
    return cam.global_basis if cam else global_basis

func _set_current_camera(index: int) -> void:
    _active = index
    var cam1 := get_node_or_null(first_camera_path) as Camera3D
    var cam2 := get_node_or_null(second_camera_path) as Camera3D
    if cam1:
        cam1.current = index == 0
    if cam2:
        cam2.current = index == 1

    if use_tween and cam1 and cam2:
        var from := cam2 if index == 0 else cam1
        var to := cam1 if index == 0 else cam2
        from.fov = to.fov
        var tween := create_tween()
        tween.tween_property(from, "global_position", to.global_position, tween_time)

    var active := _get_active_camera()
    if active:
        active_camera_changed.emit(active.name)

func _get_active_camera() -> Camera3D:
    var cam1 := get_node_or_null(first_camera_path) as Camera3D
    var cam2 := get_node_or_null(second_camera_path) as Camera3D
    return cam1 if _active == 0 else cam2
