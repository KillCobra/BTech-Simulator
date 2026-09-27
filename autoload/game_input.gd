extends Node
## Registers keyboard actions at startup so project.godot stays readable, and
## lets players rebind them (saved to user://controls.cfg).

const PATH := "user://controls.cfg"

## [action, label, default keys]. Only these appear in the controls screen.
const BINDINGS := [
	["move_forward", "Move forward", [KEY_W, KEY_UP]],
	["move_back", "Move back", [KEY_S, KEY_DOWN]],
	["move_left", "Move left", [KEY_A, KEY_LEFT]],
	["move_right", "Move right", [KEY_D, KEY_RIGHT]],
	["sprint", "Sprint", [KEY_SHIFT]],
	["crouch", "Crouch", [KEY_CTRL, KEY_C]],
	["jump", "Jump", [KEY_SPACE]],
	["interact", "Interact / use", [KEY_E]],
	["use_1", "Item slot 1", [KEY_1]],
	["use_2", "Item slot 2", [KEY_2]],
	["use_3", "Item slot 3", [KEY_3]],
	["phone", "Phone", [KEY_Q]],
	["throw", "Throw paper ball", [KEY_G]],
	["ping", "Ping", [KEY_T]],
	["proxy", "Answer for a friend", [KEY_R]],
	["raise_hand", "Raise hand (ask a question)", [KEY_H]],
	["scoreboard", "Scores", [KEY_TAB]],
	["map", "Big map", [KEY_M]],
	["map_floor", "Map: change floor", [KEY_F]],
	["leave_game", "Leave the game", [KEY_F10]],
]

signal rebound


func _ready() -> void:
	for b in BINDINGS:
		_add(b[0], b[2])
	for n in 8:  # instrument notes (music room), not rebindable
		_add("note_%d" % (n + 1), [KEY_1 + n])
	if not InputMap.has_action("primary"):
		InputMap.add_action("primary")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("primary", click)
	_load()


func _add(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		InputMap.action_add_event(action, _key_event(key))


static func _key_event(key: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	return ev


## Short name of the first key bound to an action, e.g. "E" or "Shift".
func key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			return ["", "Left click", "Right click", "Middle click"][clampi(ev.button_index, 0, 3)] if ev.button_index <= 3 else "Mouse %d" % ev.button_index
	return "—"


## Replaces the main (first) binding of an action and saves.
func rebind(action: StringName, event: InputEvent) -> void:
	var events := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	for i in range(1, events.size()):
		if not _same(events[i], event):
			InputMap.action_add_event(action, events[i])
	# The same key can't drive two actions.
	for b in BINDINGS:
		if b[0] == action:
			continue
		for ev in InputMap.action_get_events(b[0]):
			if _same(ev, event):
				InputMap.action_erase_event(b[0], ev)
	_save()
	rebound.emit()


func reset_defaults() -> void:
	for b in BINDINGS:
		InputMap.action_erase_events(b[0])
		for key in b[2]:
			InputMap.action_add_event(b[0], _key_event(key))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	rebound.emit()


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


func _save() -> void:
	var cfg := ConfigFile.new()
	for b in BINDINGS:
		var list := []
		for ev in InputMap.action_get_events(b[0]):
			if ev is InputEventKey:
				list.append("k%d" % ev.physical_keycode)
			elif ev is InputEventMouseButton:
				list.append("m%d" % ev.button_index)
		cfg.set_value("keys", b[0], list)
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for b in BINDINGS:
		if not cfg.has_section_key("keys", b[0]):
			continue
		var list: Array = cfg.get_value("keys", b[0], [])
		if list.is_empty():
			continue
		InputMap.action_erase_events(b[0])
		for code in list:
			var s := str(code)
			if s.begins_with("k"):
				InputMap.action_add_event(b[0], _key_event(int(s.substr(1))))
			elif s.begins_with("m"):
				var mb := InputEventMouseButton.new()
				mb.button_index = int(s.substr(1)) as MouseButton
				InputMap.action_add_event(b[0], mb)
