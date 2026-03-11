extends Node3D

signal interactable_found(target: Node)
signal interactable_lost()
signal interacted(target: Node)

@export var interaction_range := 2.5
@export_flags_3d_physics var interactable_mask := 4

var _current_interactable: Node = null

func _physics_process(_delta: float) -> void:
    if GameState.current_state != GameState.State.PLAYING:
        return

    var nearest := _find_nearest_interactable()
    if nearest != _current_interactable:
        if _current_interactable:
            interactable_lost.emit()
        _current_interactable = nearest
        if _current_interactable:
            interactable_found.emit(_current_interactable)

    if _current_interactable and Input.is_action_just_pressed("interact"):
        var can_interact := true
        if _current_interactable.has_method("can_interact"):
            can_interact = bool(_current_interactable.call("can_interact"))
        if can_interact:
            if _current_interactable.has_method("on_interact"):
                _current_interactable.call("on_interact")
            interacted.emit(_current_interactable)

func _find_nearest_interactable() -> Node:
    var sphere := SphereShape3D.new()
    sphere.radius = interaction_range

    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = sphere
    query.transform = Transform3D(Basis(), global_position)
    query.collision_mask = interactable_mask
    query.collide_with_bodies = true
    query.collide_with_areas = true

    var hits := get_world_3d().direct_space_state.intersect_shape(query, 16)
    var nearest: Node = null
    var nearest_dist := INF

    for hit in hits:
        var collider: Object = hit.get("collider")
        if collider is Node:
            var node := collider as Node
            if not node.is_in_group("interactable"):
                continue
            var dist := global_position.distance_to((node as Node3D).global_position)
            if dist < nearest_dist:
                nearest_dist = dist
                nearest = node

    return nearest
