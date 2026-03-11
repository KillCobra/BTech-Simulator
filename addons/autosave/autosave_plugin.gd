@tool
extends EditorPlugin

var autosave_interval := 60.0
var timer: Timer

func _enter_tree() -> void:
    if timer != null:
        return
    timer = Timer.new()
    timer.wait_time = max(1.0, autosave_interval)
    timer.one_shot = false
    timer.process_mode = Node.PROCESS_MODE_ALWAYS
    timer.timeout.connect(_on_autosave)
    add_child(timer)
    timer.start()

func _on_autosave() -> void:
    get_editor_interface().save_all_scenes()
    print("[Autosave] Scenes saved at ", Time.get_time_string_from_system())

func _exit_tree() -> void:
    if timer == null:
        return
    timer.stop()
    timer.queue_free()
    timer = null
