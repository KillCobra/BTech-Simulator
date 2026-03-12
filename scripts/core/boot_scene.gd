extends Node

func _ready() -> void:
	await get_tree().process_frame
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.start_game()
