extends Node

signal scene_loaded(scene_path: String)

func load_scene(scene_path: String) -> void:
    GameState.transition_to(GameState.State.LOADING)
    get_tree().change_scene_to_file(scene_path)
    await get_tree().process_frame
    scene_loaded.emit(scene_path)
