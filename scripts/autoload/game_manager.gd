extends Node

func start_game(scene_path: String = "res://scenes/initial_hostel.tscn") -> void:
    if SaveSystem.has_save():
        var data := SaveSystem.load_game()
        if data.has("time_of_day"):
            TimeOfDayManager.set_time_of_day(float(data["time_of_day"]))

    await SceneLoader.load_scene(scene_path)
    GameState.transition_to(GameState.State.PLAYING)
