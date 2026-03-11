extends Node

func _ready() -> void:
    await get_tree().process_frame
    GameManager.start_game()
