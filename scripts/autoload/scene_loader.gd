extends Node

signal scene_loaded(scene_path: String)

const LOADING_SCENE_PATH := "res://scenes/loading.tscn"

var _current_scene: Node
var _loading_scene: Node

func load_scene(scene_path: String) -> void:
	GameState.transition_to(GameState.State.LOADING)

	_show_loading()
	var err: int = ResourceLoader.load_threaded_request(scene_path)
	if err != OK:
		push_error("Failed to start async load: %s (err %d)" % [scene_path, err])
		_hide_loading()
		return

	var progress: Array[float] = []
	while true:
		var status: int = ResourceLoader.load_threaded_get_status(scene_path, progress)
		_update_loading_progress(progress)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Async load failed: %s" % scene_path)
			_hide_loading()
			return
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break

	var packed: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		push_error("Async load returned null: %s" % scene_path)
		_hide_loading()
		return

	_swap_scene(packed)
	_hide_loading()
	scene_loaded.emit(scene_path)

func _swap_scene(packed: PackedScene) -> void:
	var root := get_tree().root
	var previous: Node = get_tree().current_scene
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	get_tree().current_scene = instance
	_current_scene = instance
	if previous != null:
		previous.queue_free()

func _show_loading() -> void:
	if _loading_scene != null:
		return
	var packed: PackedScene = load(LOADING_SCENE_PATH) as PackedScene
	if packed == null:
		return
	_loading_scene = packed.instantiate()
	get_tree().root.add_child(_loading_scene)

func _hide_loading() -> void:
	if _loading_scene == null:
		return
	_loading_scene.queue_free()
	_loading_scene = null

func _update_loading_progress(progress: Array[float]) -> void:
	if _loading_scene == null:
		return
	if _loading_scene.has_method("set_progress"):
		var value: float = progress[0] if progress.size() > 0 else 0.0
		_loading_scene.set_progress(value)
