@tool
extends EditorPlugin

var autosave_interval := 60.0
var timer: Timer

func _enter_tree() -> void:
    timer = Timer.new()
    timer.wait_time = autosave_interval
    timer.timeout.connect(_on_autosave)
    add_child(timer)
    timer.start()

func _on_autosave() -> void:
    EditorInterface.save_all_scenes()
    print("[Autosave] Scenes saved at ", Time.get_time_string_from_system())
