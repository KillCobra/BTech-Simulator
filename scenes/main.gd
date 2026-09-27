extends Node
## Owns the flow: main menu -> lobby -> world, and back to the menu on leave.
## The menu floats over a slowly orbiting preview of the campus.

const WorldScript := preload("res://scenes/world/world.gd")
const Maps := preload("res://scenes/world/maps/maps.gd")
const SettingsPanel := preload("res://scenes/ui/settings_panel.gd")
const StudentModel := preload("res://scenes/player/student_model.gd")
const P := preload("res://scripts/palette.gd")
const Rules := preload("res://scripts/rules.gd")
const LOOK_PATH := "user://look.cfg"

const INK := Color("2a1a0e")
const GOLD := Color("ffc93c")
const PANEL := Color(0.09, 0.09, 0.16, 0.84)

var _ui: Control
var _world: Node3D

# Widgets that outlive the function that builds them.
var _name_edit: LineEdit
var _room_picker: OptionButton
var _status: Label
var _lobby_list: VBoxContainer
var _map_about: Label
var _map_name: Label
var _start_btn: Button
var _ready_btn: Button
var _ready_note: Label


func _ready() -> void:
	add_to_group("main")
	Network.players_changed.connect(_refresh_lobby)
	Network.connected_ok.connect(_show_lobby)
	Network.connection_failed.connect(_show_menu.bind("Could not connect to host."))
	Network.server_closed.connect(_return_to_menu.bind("Host ended the session."))
	Network.game_started.connect(_start_world)
	Network.returned_to_lobby.connect(_on_returned_to_lobby)
	Network.lobby_map_changed.connect(_on_lobby_map_changed)
	Network.local_info.name = Settings.player_name
	Network.local_info.look = _load_look()
	_fit_window()
	_show_menu("")
	# Draw the menu first, then go fullscreen (if chosen), then build the map behind it.
	# Building takes a moment; the window mustn't sit half-drawn meanwhile (the old
	# splash in a corner and a black slab round it).
	await _drawn()
	Settings.window_ready()
	await _drawn()
	_load_world(true)
	_apply_dev_args()


## Waits until the current frame has been drawn (headless: one frame).
func _drawn() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## The menus are laid out for 1280 x 880 (the project's base size; the UI scales with
## the window). The window opens at its project size straight away, so nothing jumps
## after the splash; it only shrinks here on a screen too small for it.
const WINDOW_SIZE := Vector2i(1280, 880)


func _fit_window() -> void:
	if DisplayServer.get_name() == "headless" or Settings.fullscreen \
			or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen()
	var free := DisplayServer.screen_get_usable_rect(screen)
	var size := DisplayServer.window_get_size()
	if size.x <= free.size.x and size.y <= free.size.y - 40:
		return
	var fit := minf(float(free.size.x) / size.x, float(free.size.y - 40) / size.y)
	var want := Vector2i(Vector2(size) * fit)
	DisplayServer.window_set_size(want)
	DisplayServer.window_set_position(free.position + (free.size - want) / 2)


## Called by the end-of-round screen.
func leave_game() -> void:
	_return_to_menu("You left the session.")


func _on_returned_to_lobby() -> void:
	_close_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_lobby()


# --- Lobby background: an aerial tour of the picked map ---------------------------------------

var _cycle_timer: Timer
var _cycle_map := 0


func _on_lobby_map_changed() -> void:
	if is_instance_valid(_map_about):
		_map_about.text = _map_blurb()
	if is_instance_valid(_map_name):
		var shown := "Random" if Network.map_choice == Maps.RANDOM else ("Daily challenge" if Network.map_choice == Network.DAILY else Maps.title(Network.map_choice))
		_map_name.text = "MAP:  %s   ·   %s" % [shown, "RACE: first out wins" if Network.game_mode == "race" else "CLASS: escape together"]
	_show_map_preview()


func _map_blurb() -> String:
	var mode := "\nRACE: the first one out wins (+%d). Paper balls on rivals make staff look." % Rules.RACE_WIN_BONUS \
			if Network.game_mode == "race" else ""
	if Network.map_choice == Maps.RANDOM:
		return "A surprise! One of your unlocked maps, picked when class starts." + mode
	if Network.map_choice == Network.DAILY:
		var d := Rules.daily(Rules.today())
		var done := "  (done today!)" if Profile.daily_done == int(d.date) else "  (+%d XP, +Rs %d when you escape)" % [Rules.DAILY_XP, Rules.DAILY_RS]
		return "DAILY CHALLENGE%s\n%s%s" % [done, Rules.daily_text(d), mode]
	return Maps.LIST[Network.map_choice].about + mode


## Rebuilds the background for the lobby's map. Random: show each map in turn.
func _show_map_preview() -> void:
	if Network.in_game:
		return
	if _cycle_timer == null:
		_cycle_timer = Timer.new()
		_cycle_timer.wait_time = 7.0
		_cycle_timer.timeout.connect(func():
			_cycle_map = (_cycle_map + 1) % Maps.LIST.size()
			_load_preview_map(_cycle_map))
		add_child(_cycle_timer)
	if Network.map_choice == Maps.RANDOM:
		_load_preview_map(_cycle_map)
		if _cycle_timer.is_stopped():
			_cycle_timer.start()
	else:
		_cycle_timer.stop()
		_load_preview_map(int(Rules.daily(Rules.today()).map) if Network.map_choice == Network.DAILY else Network.map_choice)


func _load_preview_map(id: int) -> void:
	if _world and _world.preview and _world.preview_map == id:
		return
	_load_world(true, id)


## Dev shortcuts, passed after "--":
##   --name=Raj --room=2 --host --autostart=1   private local round (tests, CI)
##   --session-host=NAME / --session-join=NAME   online session between two games
func _apply_dev_args() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if args.has("name"):
		_name_edit.text = args.name
	if args.has("room"):
		_room_picker.select(clampi(int(args.room), 0, Network.CLASSROOMS.size() - 1))
	if args.has("shot"):
		_take_screenshot(args.shot, int(args.get("shot_delay", "4")))
	if args.has("speed"):  # dev: --speed=4 runs the game 4x faster
		Engine.time_scale = float(args.speed)
	if args.has("shots"):  # dev: --shots=prefix --at_times=5,30,60 (real seconds), then quit
		_take_screenshots(str(args.shots), str(args.get("at_times", "5")).split_floats(","))
	if args.has("pref"):  # dev: --pref=uniform:blazer,hat:1 (look overrides for screenshots)
		for pair in str(args.pref).split(","):
			var kv := pair.split(":", true, 1)
			Network.local_info.look[kv[0]] = int(kv[1]) if kv[1].is_valid_int() else kv[1]
	if args.has("tab"):
		_creator_tab = int(args.tab)
	if args.has("minutes"):
		Network.round_minutes = float(args.minutes)
	if args.has("map"):  # dev: --map=N (0..3, -1 random)
		Network.map_choice = int(args.map)
	if args.has("host"):
		_apply_local_info()
		if Network.host_local() != OK:
			_status.text = "Couldn't start a local round."
			return
		_show_lobby()
		if args.has("autostart"):
			var needed := int(args.autostart)
			var try_start := func():
				if Network.players.size() >= needed:
					Network.start_game()
			Network.players_changed.connect(try_start)
			try_start.call()
	if args.has("session-host") or args.has("session-join"):
		# Dev: --session-host=NAME / --session-join=NAME [--session-pw=X] [--autostart=N]
		_apply_local_info()
		var pw := str(args.get("session-pw", ""))
		if args.has("session-host"):
			var problem: String = await Network.create_session(args["session-host"], pw)
			print("[session] create: '%s'" % problem)
			if problem == "":
				_show_lobby()
			if args.has("autostart"):
				var needed := int(args.autostart)
				Network.players_changed.connect(func():
					print("[session] players: %d" % Network.players.size())
					if Network.players.size() >= needed:
						Network.start_game())
		else:
			await get_tree().create_timer(float(args.get("join_delay", "0"))).timeout
			print("[session] join: '%s'" % await Network.join_session(args["session-join"], pw))
	if args.has("online-host"):
		# Dev: online host that swaps codes through files (--code-out, --reply-in).
		_on_host_online_pressed()
		Network.invite_ready.connect(func(code: String):
			var f := FileAccess.open(args["code-out"], FileAccess.WRITE)
			f.store_string(code))
		if args.has("autostart"):
			var needed := int(args.autostart)
			Network.players_changed.connect(func():
				if Network.players.size() >= needed:
					Network.start_game())
		while not Network.in_game:
			await get_tree().create_timer(0.5).timeout
			if FileAccess.file_exists(args["reply-in"]):
				var reply := FileAccess.get_file_as_string(args["reply-in"])
				DirAccess.remove_absolute(args["reply-in"])
				print("[online] host got reply: %s" % Network.accept_reply(reply))
	elif args.has("online-join"):
		Network.reply_ready.connect(func(code: String):
			var f := FileAccess.open(args["reply-out"], FileAccess.WRITE)
			f.store_string(code)
			print("[online] reply written (%d chars)" % code.length()))
		while not FileAccess.file_exists(args["online-join"]):
			await get_tree().create_timer(0.3).timeout
		await get_tree().create_timer(0.3).timeout
		var invite := FileAccess.get_file_as_string(args["online-join"])
		print("[online] invite read (%d chars)" % invite.length())
		_apply_local_info()
		print("[online] join: %s" % await Network.join_online(invite))



## --shot=path.png [--shot_delay=seconds]: save a screenshot, then quit.
func _take_screenshot(path: String, delay: int) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _take_screenshots(prefix: String, times: PackedFloat64Array) -> void:
	var start := Time.get_ticks_msec()
	for t in times:
		while Time.get_ticks_msec() - start < int(t * 1000.0):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, int(t * 10.0)])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _world == null or _world.preview:
		return
	var director := _world.get_node_or_null("Director")
	var over: bool = director != null and director.round_over
	if event.is_action_pressed("ui_cancel") and not over:
		if is_instance_valid(_pause):
			_close_pause()
		else:
			_open_pause()
	elif event is InputEventMouseButton and event.pressed and not over and not is_instance_valid(_pause) \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _modal_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("leave_game"):
		_return_to_menu("You left the session.")


# --- Pause menu (the game keeps running: it's multiplayer) ----------------------------------

var _pause: CanvasLayer


func _open_pause() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause = CanvasLayer.new()
	_pause.layer = 20
	add_child(_pause)
	var shade := ColorRect.new()
	shade.add_to_group("pause_menu")
	shade.color = Color(0.03, 0.03, 0.08, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.theme = _make_theme()
	_pause.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	_fill_pause(panel)


func _fill_pause(panel: PanelContainer) -> void:
	for child in panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	var note := Label.new()
	note.text = "The game keeps running for everyone else!"
	note.add_theme_font_size_override("font_size", 14)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)
	box.add_child(_button("RESUME", _close_pause, GOLD))
	box.add_child(_button("SETTINGS", func(): _show_settings_in(panel, _fill_pause.bind(panel)), Color("7fd0ea")))
	box.add_child(_button("LEAVE GAME", leave_game, Color("e7d2aa")))


## A test or detention lines are on screen (they need the mouse).
func _modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and n.is_visible_in_tree():
			return true
	return false


func _close_pause() -> void:
	if is_instance_valid(_pause):
		remove_child(_pause)
		_pause.queue_free()
	_pause = null
	# Only grab the mouse back if nothing else needs it (a test, lines, results).
	var hud := get_tree().get_first_node_in_group("hud")
	if _world and not _world.preview and (hud == null or hud.should_capture()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_settings_in(panel: PanelContainer, back: Callable) -> void:
	for child in panel.get_children():
		child.queue_free()
	var settings: VBoxContainer = SettingsPanel.new()
	settings.closed.connect(back)
	panel.add_child(settings)


func _load_world(as_preview: bool, map_id := -1) -> void:
	if not as_preview or map_id < 0:
		if _cycle_timer:
			_cycle_timer.stop()
	if _world:
		# Out of the tree right away: its collision must not linger into the new world's first frame.
		remove_child(_world)
		_world.queue_free()
	_world = WorldScript.new()
	_world.preview = as_preview
	_world.preview_map = map_id
	_world.name = "Preview" if as_preview else "World"
	add_child(_world)
	move_child(_world, 0)


# --- Screens ------------------------------------------------------------------------------

func _show_menu(status: String) -> void:
	var box := _new_screen()

	_name_edit = LineEdit.new()
	_name_edit.text = Network.local_info.name
	_name_edit.max_length = 16
	box.add_child(_field("YOUR NAME", _name_edit))

	_room_picker = _make_room_picker()
	box.add_child(_field("CLASSROOM", _room_picker))

	var online_caption := Label.new()
	online_caption.text = "ONE PLAYER CREATES A SESSION, FRIENDS JOIN IT BY NAME"
	online_caption.add_theme_font_size_override("font_size", 13)
	online_caption.modulate = Color(1, 1, 1, 0.7)
	box.add_child(online_caption)
	var online_row := HBoxContainer.new()
	online_row.add_theme_constant_override("separation", 12)
	online_row.add_child(_button("CREATE SESSION", _show_session_form.bind(true), Color("ff9a3c")))
	online_row.add_child(_button("JOIN SESSION", _show_session_form.bind(false), Color("b07cff")))
	box.add_child(online_row)
	var misc_row := HBoxContainer.new()
	misc_row.add_theme_constant_override("separation", 12)
	var panel: PanelContainer = box.get_parent()
	misc_row.add_child(_button("SETTINGS", func(): _show_settings_in(panel, _show_menu.bind("")), Color("b9e6a0")))
	misc_row.add_child(_button("QUIT", get_tree().quit, Color("e7d2aa")))
	box.add_child(misc_row)
	if OS.get_cmdline_user_args().has("--session-form") and not has_meta("dev_settings"):  # dev: screenshot the form
		set_meta("dev_settings", true)
		_show_session_form.call_deferred(not OS.get_cmdline_user_args().has("--join-form"))
	if OS.get_cmdline_user_args().has("--settings") and not has_meta("dev_settings"):  # dev: screenshot the settings
		set_meta("dev_settings", true)
		_show_settings_in.call_deferred(panel, _show_menu.bind(""))
		if OS.get_cmdline_user_args().has("--controls"):
			(func(): panel.get_child(panel.get_child_count() - 1)._show_controls()).call_deferred()

	if status != "":
		print("[menu] %s" % status)
	_status = Label.new()
	_status.text = status
	_status.add_theme_color_override("font_color", Color("ffb37a"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)


func _show_lobby() -> void:
	var box := _new_screen()
	# The lobby has the most to show: a one-line logo leaves room for it.
	var logo: Label = box.get_parent().get_parent().get_child(0)
	logo.text = "BUNK MASTER"
	logo.add_theme_font_size_override("font_size", 46)

	var heading := Label.new()
	heading.text = "LOBBY"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	box.add_child(heading)
	box.add_child(_profile_strip())

	# Your name and classroom, both changeable until class starts.
	var me_row := HBoxContainer.new()
	me_row.add_theme_constant_override("separation", 12)
	var lobby_name := LineEdit.new()
	lobby_name.text = Network.local_info.name
	lobby_name.max_length = 16
	lobby_name.placeholder_text = "Your name"
	var rename := func(_t = ""):
		var wanted := lobby_name.text.strip_edges()
		if wanted == "" or wanted == Network.local_info.name:
			return
		Settings.set_value("player_name", wanted)
		Network.set_local_info(wanted, Network.local_info.classroom)
	lobby_name.text_submitted.connect(rename)
	lobby_name.focus_exited.connect(rename)
	var name_field := _field("YOUR NAME (ENTER TO SAVE)", lobby_name)
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	me_row.add_child(name_field)
	_room_picker = _make_room_picker()
	_room_picker.item_selected.connect(_on_room_changed)
	me_row.add_child(_field("YOUR CLASSROOM", _room_picker))
	box.add_child(me_row)

	_lobby_list = VBoxContainer.new()
	_lobby_list.add_theme_constant_override("separation", 6)
	box.add_child(_lobby_list)

	var hint := Label.new()
	if Network.is_host() and Network.session_name != "":
		hint.text = "ONLINE SESSION:  %s%s\nFriends click JOIN SESSION and type this name%s. Any number can join (up to %d)." \
				% [Network.session_name, "  (password protected)" if Network._pw_hash != "" else "",
				" and the password" if Network._pw_hash != "" else "", Network.MAX_PLAYERS]
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		hint.custom_minimum_size.x = 380
	elif Network.is_host() and Network.online:
		_build_invite_panel(box)
		hint.text = "Friends who connect show up above. You can invite more anytime."
	elif Network.is_host():
		hint.text = "Private round on this PC."
	else:
		hint.text = "Waiting for the host to start class..."
	hint.add_theme_color_override("font_color", Color("9fd8ff"))
	hint.add_theme_font_size_override("font_size", 13 if Network.is_host() else 15)
	box.add_child(hint)

	if Network.is_host():
		var length := OptionButton.new()
		for minutes in Network.ROUND_LENGTHS:
			length.add_item("%d minutes" % minutes)
		length.select(maxi(0, Network.ROUND_LENGTHS.find(int(Network.round_minutes))))
		length.item_selected.connect(func(i): Network.round_minutes = float(Network.ROUND_LENGTHS[i]))
		# Maps open in order (see Profile.map_unlocked); stars earned so far next to each.
		var maps := OptionButton.new()
		for i in Maps.LIST.size():
			var open := Profile.map_unlocked(i)
			maps.add_item("%s   %d/3 stars" % [Maps.LIST[i].name, Profile.star_count(i)] if open else "LOCKED: %s" % Maps.LIST[i].name)
			maps.set_item_disabled(i, not open)
		maps.add_item("Random map")
		maps.add_item("Daily challenge%s" % ("  (done)" if Profile.daily_done == Rules.today() else ""))
		maps.select(Maps.LIST.size() if Network.map_choice == Maps.RANDOM else (Maps.LIST.size() + 1 if Network.map_choice == Network.DAILY else Network.map_choice))
		maps.item_selected.connect(func(i: int):
			Network.set_map_choice(Maps.RANDOM if i == Maps.LIST.size() else (Network.DAILY if i > Maps.LIST.size() else i)))
		var mode := OptionButton.new()
		mode.add_item("Class: escape together")
		mode.add_item("Race: first out wins")
		mode.select(1 if Network.game_mode == "race" else 0)
		mode.item_selected.connect(func(i: int): Network.set_game_mode("race" if i == 1 else "class"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var map_field := _field("MAP", maps)
		map_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(map_field)
		row.add_child(_field("ROUND LENGTH", length))
		box.add_child(row)
		box.add_child(_field("MODE", mode))
	else:
		_map_name = Label.new()
		_map_name.add_theme_font_size_override("font_size", 17)
		_map_name.add_theme_color_override("font_color", GOLD)
		box.add_child(_map_name)
	_map_about = Label.new()
	_map_about.autowrap_mode = TextServer.AUTOWRAP_WORD
	_map_about.custom_minimum_size.x = 380
	_map_about.add_theme_font_size_override("font_size", 13)
	_map_about.add_theme_color_override("font_color", Color("e7d2aa"))
	box.add_child(_map_about)
	_on_lobby_map_changed()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_start_btn = null
	_ready_btn = null
	if Network.is_host():
		_start_btn = _button("START CLASS", Network.start_game, GOLD)
		buttons.add_child(_start_btn)
	else:
		_ready_btn = _button("I'M READY", func(): Network.set_ready(not Network.is_ready(multiplayer.get_unique_id())), Color("7fe0a0"))
		buttons.add_child(_ready_btn)
	buttons.add_child(_button("LEAVE", _on_leave_lobby, Color("e7d2aa")))
	box.add_child(buttons)

	_build_creator()
	_refresh_lobby()


## Level, rank, XP bar, saved-up Rs and what to go for next.
func _profile_strip() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var lv: Array = Profile.level_of(Profile.xp)
	var top := Label.new()
	top.text = "LEVEL %d  ·  %s        Bank: Rs %d" % [int(lv[0]), Profile.rank_title().to_upper(), Profile.bank]
	top.add_theme_font_size_override("font_size", 15)
	top.add_theme_color_override("font_color", Color("9fd8ff"))
	col.add_child(top)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.12)
	bar.custom_minimum_size = Vector2(380, 8)
	var fill := ColorRect.new()
	fill.color = Color("7fe0a0")
	fill.size = Vector2(380.0 * float(lv[1]) / float(lv[2]), 8)
	bar.add_child(fill)
	col.add_child(bar)
	var next := Label.new()
	next.text = "NEXT: " + Profile.next_goal()
	next.add_theme_font_size_override("font_size", 13)
	next.add_theme_color_override("font_color", Color("ffb37a"))
	col.add_child(next)
	return col


# --- Online sessions (name + optional password) ---------------------------------------------------

func _show_session_form(create: bool) -> void:
	_apply_local_info()
	var box := _new_screen()
	var heading := Label.new()
	heading.text = "CREATE SESSION" if create else "JOIN SESSION"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	box.add_child(heading)
	var name_edit := LineEdit.new()
	name_edit.max_length = 24
	name_edit.placeholder_text = "e.g. gauransh-gang" if create else "The name your friend created"
	name_edit.text = str(Settings.get_meta("last_session", "")) if Settings.has_meta("last_session") else ""
	box.add_child(_field("SESSION NAME", name_edit))
	var pw_edit := LineEdit.new()
	pw_edit.secret = true
	pw_edit.max_length = 32
	pw_edit.placeholder_text = "Optional: only friends with it can join" if create else "Leave empty if there isn't one"
	box.add_child(_field("PASSWORD (OPTIONAL)", pw_edit))
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size.x = 380
	status.add_theme_color_override("font_color", Color("ffd24a"))
	status.add_theme_font_size_override("font_size", 14)
	var go := _button("CREATE" if create else "JOIN", _submit_session.bind(create, name_edit, pw_edit, status),
		Color("ff9a3c") if create else Color("b07cff"))
	name_edit.text_submitted.connect(func(_t): go.pressed.emit())
	pw_edit.text_submitted.connect(func(_t): go.pressed.emit())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(go)
	row.add_child(_button("BACK", _show_menu.bind(""), Color("e7d2aa")))
	box.add_child(row)
	# Helpers in one row (keeps the form on a 720p screen): network test, firewall, codes.
	var helpers := HBoxContainer.new()
	helpers.add_theme_constant_override("separation", 6)
	box.add_child(helpers)
	var test := _chip("Test my network", func():
		status.text = "Testing your network (about 5 s)..."
		var report: String = await Network.test_network()
		if is_instance_valid(status):
			status.text = report, Color("9fd8ff"))
	test.tooltip_text = "Checks whether this Wi-Fi allows online play."
	helpers.add_child(test)
	if OS.get_name() == "Windows":
		var allow := _chip("Allow network", func():
			status.text = "Asking Windows for network access (press Yes on the popup)..."
			var result: String = await Network.request_firewall_access()
			if not is_instance_valid(status):
				return
			status.text = result + "\nTesting your network..."
			var report: String = await Network.test_network()
			if is_instance_valid(status):
				status.text = result + "\n" + report, Color("7fe0a0"))
		allow.tooltip_text = "Lets Bunk Master through the Windows firewall (asks for admin)."
		helpers.add_child(allow)
	var manual := _chip("Manual codes", _on_host_online_pressed if create else _show_join_online, Color(1, 1, 1, 0.12))
	manual.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	manual.tooltip_text = "Trouble connecting? Swap invite codes by hand instead."
	helpers.add_child(manual)
	for chip in helpers.get_children():
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(status)


func _submit_session(create: bool, name_edit: LineEdit, pw_edit: LineEdit, status: Label) -> void:
	var session := name_edit.text.strip_edges()
	Settings.set_meta("last_session", session)
	status.text = "Setting up the session..." if create else "Looking for \"%s\"..." % session
	var problem: String
	if create:
		problem = await Network.create_session(session, pw_edit.text)
	else:
		problem = await Network.join_session(session, pw_edit.text)
	if not is_instance_valid(status):
		return
	if problem != "":
		status.text = problem
		Network.leave()
		return
	if create:
		_show_lobby()
		return
	status.text = "Found it! Connecting directly to the host..."
	# Joined lobby appears via connected_ok; if that never happens, say why.
	await get_tree().create_timer(35.0).timeout
	if is_instance_valid(status) and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		status.text = Network.explain_failure()
		Network.leave()


# --- Online invite codes -------------------------------------------------------------------------

## Host lobby: the current invite code to send, and a box for the friend's reply.
func _build_invite_panel(box: VBoxContainer) -> void:
	var invite := LineEdit.new()
	invite.editable = false
	invite.text = Network.last_invite if Network.last_invite != "" else "Making an invite code..."
	var copy_invite := func():
		DisplayServer.clipboard_set(invite.text)
		_flash(box, "Invite copied! Send it to your friend.")
	var copy := _button("COPY", copy_invite, Color("ff9a3c"))
	copy.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(invite)
	row.add_child(copy)
	box.add_child(_field("1. SEND THIS INVITE CODE TO A FRIEND (WHATSAPP ETC.)", row))
	var on_invite := func(code: String):
		if is_instance_valid(invite):
			invite.text = code
	Network.invite_ready.connect(on_invite)
	invite.tree_exiting.connect(func(): Network.invite_ready.disconnect(on_invite))

	var reply := LineEdit.new()
	reply.placeholder_text = "Paste their reply code here"
	reply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var connect_reply := func():
		var text := reply.text if reply.text.strip_edges() != "" else DisplayServer.clipboard_get()
		var problem := Network.accept_reply(text)
		reply.text = ""
		_flash(box, problem if problem != "" else "Connecting... they'll appear in the student list. New invite ready for the next friend.")
	var add := _button("CONNECT", connect_reply, Color("7fe0a0"))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.add_child(reply)
	row2.add_child(add)
	box.add_child(_field("2. PASTE THE REPLY CODE THEY SEND BACK", row2))


func _flash(box: Control, text: String) -> void:
	var note := box.get_node_or_null("Flash") as Label
	if note == null:
		note = Label.new()
		note.name = "Flash"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		note.custom_minimum_size.x = 380
		note.add_theme_color_override("font_color", Color("ffd24a"))
		note.add_theme_font_size_override("font_size", 14)
		box.add_child(note)
	note.text = text


func _on_host_online_pressed() -> void:
	_apply_local_info()
	if not ClassDB.class_exists("WebRTCPeerConnectionExtension") and not ClassDB.can_instantiate("WebRTCPeerConnection"):
		_show_menu("Online play needs the WebRTC plugin, which is missing from this build.")
		return
	var err := Network.host_online()
	if err != OK:
		_show_menu("Couldn't start online hosting.")
		return
	_show_lobby()


func _show_join_online() -> void:
	_apply_local_info()
	var box := _new_screen()
	var heading := Label.new()
	heading.text = "JOIN ONLINE"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	box.add_child(heading)

	var invite := LineEdit.new()
	invite.placeholder_text = "Paste the host's invite code (BUNK-...)"
	box.add_child(_field("1. PASTE THE HOST'S INVITE CODE", invite))
	var reply := LineEdit.new()
	reply.editable = false
	reply.placeholder_text = "Your reply code appears here"
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size.x = 380
	status.add_theme_color_override("font_color", Color("ffd24a"))
	status.add_theme_font_size_override("font_size", 14)

	box.add_child(_button("MAKE MY REPLY", _make_reply.bind(invite, status), Color("b07cff")))

	var copy_reply := func():
		DisplayServer.clipboard_set(reply.text)
		status.text = "Reply copied! Send it to the host. You'll join as soon as they paste it."
	var copy := _button("COPY REPLY", copy_reply, Color("ff9a3c"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	reply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reply)
	row.add_child(copy)
	box.add_child(_field("2. SEND THIS REPLY CODE BACK TO THE HOST", row))
	box.add_child(status)
	var back := func():
		Network.leave()
		_show_menu("")
	box.add_child(_button("BACK", back, Color("e7d2aa")))

	var on_reply := func(code: String):
		if not is_instance_valid(reply):
			return
		reply.text = code
		DisplayServer.clipboard_set(code)
		status.text = "Reply code copied to your clipboard. Send it to the host, then wait here."
		# If nothing happens for a while, the networks probably can't meet directly.
		var mine := code
		await get_tree().create_timer(90.0).timeout
		if is_instance_valid(reply) and reply.text == mine and not Network.in_game \
				and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			status.text = "Still not connected. Make sure the host pasted your newest reply. If it keeps failing, one of your networks blocks direct connections: try the other person hosting, a phone hotspot, or Tailscale."
	var on_error := func(text: String):
		if is_instance_valid(status):
			status.text = text
	Network.reply_ready.connect(on_reply)
	Network.online_error.connect(on_error)
	reply.tree_exiting.connect(func():
		Network.reply_ready.disconnect(on_reply)
		Network.online_error.disconnect(on_error))


func _make_reply(invite: LineEdit, status: Label) -> void:
	var text := invite.text if invite.text.strip_edges() != "" else DisplayServer.clipboard_get()
	status.text = "Working out the best route to the host..."
	var problem: String = await Network.join_online(text)
	if problem != "":
		status.text = problem
		Network.leave()


# --- Character creator -------------------------------------------------------------------------
# Right-hand lobby panel: a live 3D preview (drag to spin, toggle face zoom) and
# tabs of options. Every colour has quick swatches plus a free colour picker.
# Choices live in Network.local_info.look (colours as "#rrggbb"), saved to disk.

var _preview_model: Node3D
var _preview_pivot: Node3D
var _preview_cam: Camera3D
var _preview_yaw := 0.0
var _preview_drag := false
var _preview_face := false
var _creator_panel: PanelContainer
var _creator_tab := 0
var _creator_msg: Label


func _build_creator() -> void:
	_creator_panel = PanelContainer.new()
	_creator_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_creator_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_creator_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_creator_panel.position.x -= 40
	_creator_panel.custom_minimum_size = Vector2(400, 0)
	_ui.add_child(_creator_panel)
	_fill_creator()


func _fill_creator() -> void:
	for child in _creator_panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_creator_panel.add_child(box)

	var head := HBoxContainer.new()
	var heading := Label.new()
	heading.text = "YOUR STUDENT"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var bank := Label.new()
	bank.text = "Rs %d  " % Profile.bank
	bank.tooltip_text = "Saved up from your rounds: buy locked items below"
	bank.add_theme_font_size_override("font_size", 15)
	bank.add_theme_color_override("font_color", GOLD)
	head.add_child(bank)
	head.add_child(_chip("RANDOM", _randomize_look, Color("b07cff")))
	head.add_child(_chip("RESET", _reset_look, Color("e7d2aa")))
	box.add_child(head)

	box.add_child(_build_preview())

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(380, 300)
	var tab_style := _style(Color(1, 1, 1, 0.06), 10, 10)
	tabs.add_theme_stylebox_override("panel", tab_style)
	tabs.add_theme_stylebox_override("tab_selected", _style(GOLD, 8, 6))
	tabs.add_theme_stylebox_override("tab_unselected", _style(Color(1, 1, 1, 0.1), 8, 6))
	tabs.add_theme_stylebox_override("tab_hovered", _style(Color(1, 1, 1, 0.2), 8, 6))
	tabs.add_theme_color_override("font_selected_color", INK)
	tabs.add_theme_color_override("font_unselected_color", Color.WHITE)
	tabs.add_theme_font_size_override("font_size", 14)
	box.add_child(tabs)

	var look := _current_look()
	var prefs: Dictionary = Network.local_info.look

	var body := _tab(tabs, "BODY")
	body.add_child(_field("SKIN", _color_row(P.SKIN, "skin", look.skin)))
	body.add_child(_field("EYES", _color_row(P.EYES, "eyes", look.get("eyes", P.EYES[0]))))
	body.add_child(_field("HEIGHT", _choice_row(P.HEIGHT_NAMES, int(prefs.get("height", 1)), "height", 3)))

	var hair := _tab(tabs, "HAIR")
	hair.add_child(_field("HAIR COLOUR", _color_row(P.HAIR, "hair", look.hair)))
	hair.add_child(_field("HAIRSTYLE", _choice_row(P.HAIR_STYLE_NAMES, int(look.get("hair_style", 0)), "hair_style", 4)))
	hair.add_child(_field("FACIAL HAIR", _choice_row(P.FACIAL_NAMES, int(prefs.get("facial", 0)), "facial", 4)))

	var outfit := _tab(tabs, "UNIFORM")
	var names := []
	for u in P.UNIFORMS:
		names.append(u[1])
	var uniform: String = look.get("uniform", "classic")
	outfit.add_child(_field("STYLE", _choice_row(names, P.uniform_index(uniform), "uniform", 4)))
	outfit.add_child(_field("SHIRT" if uniform != "kurta" else "KURTA", _color_row(P.CLOTH, "shirt", look.get("shirt", P.SHIRT))))
	outfit.add_child(_field("SKIRT" if uniform == "skirt" else "TROUSERS", _color_row(P.CLOTH, "trousers", look.get("trousers", P.TROUSERS))))
	var accent_name := {"blazer": "BLAZER", "sweater": "SWEATER VEST", "sports": "TRACK JACKET", "kurta": "TRIM", "labcoat": "COAT"}
	if accent_name.has(uniform):
		outfit.add_child(_field(accent_name[uniform], _color_row(P.CLOTH, "accent", look.get("accent", P.TROUSERS))))
	if uniform not in ["sports", "kurta"]:
		var tie_row := HBoxContainer.new()
		tie_row.add_theme_constant_override("separation", 6)
		tie_row.add_child(_chip("CLASS COLOUR", func(): _set_pref("tie", null), P.CLASS_COLORS[Network.local_info.classroom]))
		tie_row.add_child(_color_row(P.CLASS_COLORS + [Color("24315e"), Color("26262e")], "tie", look.get("tie", Color.BLACK), false))
		outfit.add_child(_field("TIE", tie_row))
	outfit.add_child(_field("SHOES", _color_row([Color("26262e"), Color("7a4a2a"), Color.WHITE, Color("e0524f"), Color("4f86e0")], "shoes", look.get("shoes", P.SHOES))))

	var extras := _tab(tabs, "EXTRAS")
	extras.add_child(_field("GLASSES", _choice_row(P.GLASSES_NAMES, int(look.get("glasses_style", 1 if look.get("glasses", false) else 0)), "glasses_style", 4)))
	extras.add_child(_field("HEADWEAR", _choice_row(P.HAT_NAMES, int(prefs.get("hat", 0)), "hat", 4)))
	if int(prefs.get("hat", 0)) > 0:
		extras.add_child(_field("HAT COLOUR", _color_row(P.CLOTH, "hat_color", look.get("hat_color", Color("e0524f")))))
	extras.add_child(_field("BAG", _choice_row(P.BAG_STYLE_NAMES, int(prefs.get("bag_style", 0)), "bag_style", 3)))
	var tag_names := []
	var tag_ids: Array = Profile.TAGS.keys()
	for t in tag_ids:
		tag_names.append(Profile.TAGS[t][0])
	var tag_row := _choice_row(tag_names, maxi(0, tag_ids.find(str(prefs.get("tag", "")))), "tag", 2)
	extras.add_child(_field("NAME TAG (what friends see over your head)", tag_row))
	if int(prefs.get("bag_style", 0)) != 2:
		extras.add_child(_field("BAG COLOUR", _color_row(P.BAGS, "bag", look.get("bag", P.BAGS[0]))))

	tabs.current_tab = _creator_tab
	tabs.tab_changed.connect(func(i): _creator_tab = i)
	_creator_msg = Label.new()
	_creator_msg.add_theme_font_size_override("font_size", 13)
	_creator_msg.add_theme_color_override("font_color", Color("ffb37a"))
	_creator_msg.text = "Gold items are locked: buy them with the Rs you save up in rounds."
	box.add_child(_creator_msg)


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(380, 250)
	container.stretch = true
	container.tooltip_text = "Drag to turn"
	container.gui_input.connect(_on_preview_input)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	_preview_cam = Camera3D.new()
	_preview_cam.fov = 38
	viewport.add_child(_preview_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("fff0dc")
	env.environment.ambient_light_energy = 0.8
	viewport.add_child(env)
	# A little round podium to stand on.
	var podium := preload("res://scripts/voxel.gd").new()
	podium.box(Vector3(0, -0.05, 0), Vector3(1.1, 0.1, 1.1), Color("3a3d47"))
	podium.box(Vector3(0, -0.02, 0), Vector3(0.9, 0.05, 0.9), GOLD.darkened(0.2))
	viewport.add_child(podium.to_instance())
	_preview_pivot = Node3D.new()
	viewport.add_child(_preview_pivot)
	_place_preview_camera()
	_rebuild_preview()

	var zoom := _chip("FACE", func():
		_preview_face = not _preview_face
		_place_preview_camera(), Color("7fd0ea"))
	zoom.position = Vector2(8, 8)
	container.add_child(zoom)
	return container


func _place_preview_camera() -> void:
	if _preview_face:
		_preview_cam.position = Vector3(0, 1.52, 1.05)
		_preview_cam.look_at_from_position(_preview_cam.position, Vector3(0, 1.48, 0))
	else:
		_preview_cam.position = Vector3(0, 1.15, 3.0)
		_preview_cam.look_at_from_position(_preview_cam.position, Vector3(0, 0.9, 0))


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_preview_drag = event.pressed
	elif event is InputEventMouseMotion and _preview_drag:
		_preview_yaw += event.relative.x * 0.012


## A row of preset swatches plus a free colour picker at the end.
func _color_row(colors: Array, key: String, current: Color, with_picker := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 26)
		b.focus_mode = Control.FOCUS_NONE
		var sb := _style(c, 7, 0)
		if (c as Color).is_equal_approx(current):
			sb.border_color = GOLD
			sb.set_border_width_all(3)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, sb)
		var html: String = "#" + (c as Color).to_html(false)
		b.pressed.connect(_set_pref.bind(key, html))
		row.add_child(b)
	if with_picker:
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(34, 26)
		picker.color = current
		picker.edit_alpha = false
		picker.tooltip_text = "Any colour"
		picker.focus_mode = Control.FOCUS_NONE
		var ring := _style(current, 7, 0)
		ring.border_color = Color.WHITE
		ring.set_border_width_all(2)
		picker.add_theme_stylebox_override("normal", ring)
		picker.text = "+"
		picker.add_theme_color_override("font_color", Color.WHITE if current.get_luminance() < 0.5 else INK)
		# Live preview while dragging; rebuild the panel when the picker closes.
		picker.color_changed.connect(func(c: Color):
			Network.local_info.look[key] = "#" + c.to_html(false)
			_rebuild_preview())
		picker.popup_closed.connect(func(): _set_pref(key, "#" + picker.color.to_html(false)))
		row.add_child(picker)
	return row


## Toggle-style buttons for a list of named options, laid out in a grid.
func _choice_row(names: Array, selected: int, key: String, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	for i in names.size():
		var value: Variant = P.UNIFORMS[i][0] if key == "uniform" else i
		if key == "tag":
			value = Profile.TAGS.keys()[i]
		var id := "%s:%s" % [key, str(value)]
		var locked := not Profile.owns(id)
		var text := str(names[i])
		if locked:
			text += ("  Rs %d" % Profile.price(id)) if Profile.COSMETICS.has(id) else "  (rank)"
		var b := _chip(text, _pick_or_buy.bind(key, value, id), GOLD if i == selected else (Color("5a4a2a") if locked else Color(1, 1, 1, 0.14)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if locked:
			b.tooltip_text = "Buy with Rs you saved up" if Profile.COSMETICS.has(id) else "Unlocked by ranking up"
		if i != selected:
			b.add_theme_color_override("font_color", Color("ffd24a") if locked else Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		grid.add_child(b)
	return grid


## A locked cosmetic: buy it with saved-up Rs, then wear it. Otherwise just wear it.
func _pick_or_buy(key: String, value: Variant, id: String) -> void:
	if not Profile.owns(id):
		var problem := Profile.buy(id)
		if problem != "":
			if is_instance_valid(_creator_msg):
				_creator_msg.text = problem
			Sfx.play("deny", -6.0)
			return
		Sfx.play("pickup", -4.0, 1.2)
	_set_pref(key, value)


## Random looks only use things you own.
func _strip_unowned(look: Dictionary) -> void:
	for key in ["hat", "glasses_style", "bag_style", "uniform", "tag"]:
		if look.has(key) and not Profile.owns("%s:%s" % [key, str(look[key])]):
			look.erase(key)


func _chip(text: String, handler: Callable, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	var sb := _style(color, 8, 6)
	var hover := _style(color.lightened(0.15), 8, 6)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(handler)
	return b


func _set_pref(key: String, value: Variant) -> void:
	if value == null:
		Network.local_info.look.erase(key)
	else:
		Network.local_info.look[key] = value
	if key == "uniform":
		# A new uniform starts from its own default colours.
		for k in ["shirt", "trousers", "accent"]:
			Network.local_info.look.erase(k)
	_save_look()
	Network.push_local_info()
	_rebuild_preview()
	if is_instance_valid(_creator_panel):
		_fill_creator.call_deferred()


func _current_look() -> Dictionary:
	return P.apply_prefs(P.make_look(7, Network.local_info.classroom), Network.local_info.look)


func _randomize_look() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	var pick := func(arr: Array) -> String: return "#" + (arr[r.randi() % arr.size()] as Color).to_html(false)
	var u: int = r.randi() % P.UNIFORMS.size()
	Network.local_info.look = {
		"skin": pick.call(P.SKIN), "hair": pick.call(P.HAIR), "eyes": pick.call(P.EYES),
		"hair_style": r.randi() % P.HAIR_STYLES, "uniform": P.UNIFORMS[u][0],
		"glasses_style": [0, 0, 1, 2, 3][r.randi() % 5], "facial": [0, 0, 0, 1, 2, 3][r.randi() % 6],
		"hat": [0, 0, 1, 2, 3][r.randi() % 5], "hat_color": pick.call(P.CLOTH),
		"bag_style": r.randi() % 3, "bag": pick.call(P.BAGS), "height": r.randi() % 3,
	}
	if r.randf() < 0.5:
		Network.local_info.look.accent = pick.call(P.CLOTH)
	var uniform: String = P.UNIFORMS[u][0]
	if not Profile.owns("uniform:" + uniform):
		uniform = "classic"
	_strip_unowned(Network.local_info.look)
	_set_pref("uniform", uniform)


func _reset_look() -> void:
	Network.local_info.look = {}
	_set_pref("uniform", "classic")


func _rebuild_preview() -> void:
	if not is_instance_valid(_preview_pivot):
		return
	if is_instance_valid(_preview_model):
		_preview_model.queue_free()
	_preview_model = StudentModel.new()
	_preview_model.build(_current_look())
	_preview_pivot.add_child(_preview_model)
	_preview_model.animate(0.016, 0.0, false, false, 0.0)


func _process(delta: float) -> void:
	if is_instance_valid(_preview_pivot):
		if not _preview_drag:
			_preview_yaw += delta * 0.6
		_preview_pivot.rotation.y = _preview_yaw


func _load_look() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(LOOK_PATH) != OK:
		return {}
	var out := {}
	for key in cfg.get_section_keys("look"):
		out[key] = cfg.get_value("look", key)
	return out


func _save_look() -> void:
	var cfg := ConfigFile.new()
	for key in Network.local_info.look:
		cfg.set_value("look", key, Network.local_info.look[key])
	cfg.save(LOOK_PATH)


func _refresh_lobby() -> void:
	# The host may have tweaked our name (two "Sam"s become "Sam" and "Sam 2").
	var mine: Dictionary = Network.players.get(multiplayer.get_unique_id(), {})
	if not mine.is_empty():
		Network.local_info.name = str(mine.name)
	if not is_instance_valid(_lobby_list):
		return
	for child in _lobby_list.get_children():
		child.queue_free()
	var ids: Array = Network.players.keys()
	ids.sort()
	var head := HBoxContainer.new()
	var count := Label.new()
	count.text = "STUDENTS  %d / %d" % [ids.size(), Network.MAX_PLAYERS]
	count.add_theme_font_size_override("font_size", 14)
	count.modulate = Color(1, 1, 1, 0.7)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(count)
	_ready_note = Label.new()
	_ready_note.add_theme_font_size_override("font_size", 13)
	head.add_child(_ready_note)
	_lobby_list.add_child(head)
	for id in ids:
		var info: Dictionary = Network.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var chip := ColorRect.new()
		chip.color = P.CLASS_COLORS[info.classroom]
		chip.custom_minimum_size = Vector2(14, 14)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var label := Label.new()
		label.text = "%s  ·  %s%s%s" % [info.name, Network.CLASSROOMS[info.classroom], "   (host)" if id == 1 else "",
			"   (you)" if id == multiplayer.get_unique_id() else ""]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if id != 1:
			var tag := Label.new()
			var on := Network.is_ready(id)
			tag.text = "READY" if on else "NOT READY"
			tag.add_theme_font_size_override("font_size", 14)
			tag.add_theme_color_override("font_color", Color("7fe0a0") if on else Color("ff8a6a"))
			row.add_child(tag)
		_lobby_list.add_child(row)
	# Start only once everybody has readied up.
	var waiting := 0
	for id in ids:
		if not Network.is_ready(id):
			waiting += 1
	if is_instance_valid(_start_btn):
		_start_btn.disabled = waiting > 0
		_start_btn.modulate = Color(1, 1, 1, 0.5 if waiting > 0 else 1.0)
	if is_instance_valid(_ready_btn):
		var me_ready := Network.is_ready(multiplayer.get_unique_id())
		_ready_btn.text = "READY!  (click to undo)" if me_ready else "I'M READY"
	if is_instance_valid(_ready_note):
		if waiting == 0:
			_ready_note.text = "Everyone's ready!" if Network.is_host() else "Ready! Waiting for the host"
			_ready_note.add_theme_color_override("font_color", Color("7fe0a0"))
		else:
			_ready_note.text = "%d not ready yet" % waiting
			_ready_note.add_theme_color_override("font_color", Color("ffb37a"))


func _start_world() -> void:
	_clear_ui()
	_load_world(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_to_menu(message: String) -> void:
	_close_pause()
	Sfx.set_music("")
	Sfx.set_ambience(false)
	Sfx.stop_loop("alarm")
	Network.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _world == null or not _world.preview or _world.preview_map != -1:
		_load_world(true)
	_show_menu(message)


# --- Button handlers -------------------------------------------------------------------------

func _on_room_changed(index: int) -> void:
	Network.set_local_info(Network.local_info.name, index)
	_rebuild_preview()


func _on_leave_lobby() -> void:
	Network.leave()
	if _world == null or _world.preview_map != -1:
		_load_world(true)
	_show_menu("")


func _apply_local_info() -> void:
	# The menu fields are gone once a session form replaced them: keep what we had.
	if not is_instance_valid(_name_edit) or not is_instance_valid(_room_picker):
		return
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "Student"
	Network.local_info.name = player_name
	Network.local_info.classroom = _room_picker.selected
	Settings.set_value("player_name", player_name)


# --- UI helpers ------------------------------------------------------------------------------

## Clears the UI and returns the content box of a fresh left-side panel with the logo.
func _new_screen() -> VBoxContainer:
	_clear_ui()
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = _make_theme()
	add_child(_ui)

	# Soft dark fade from the left so the panel reads over the bright campus.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.05, 0.04, 0.1, 0.55))
	gradient.set_color(1, Color(0.05, 0.04, 0.1, 0.0))
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = gradient
	fade_tex.fill_from = Vector2(0, 0)
	fade_tex.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = fade_tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	_ui.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var logo := Label.new()
	logo.text = "BUNK\nMASTER"
	logo.add_theme_font_size_override("font_size", 76)
	if get_viewport().get_visible_rect().size.y < WINDOW_SIZE.y - 20:  # short screen: one line leaves room
		logo.text = "BUNK MASTER"
		logo.add_theme_font_size_override("font_size", 46)
	logo.add_theme_color_override("font_color", GOLD)
	logo.add_theme_color_override("font_outline_color", INK)
	logo.add_theme_constant_override("outline_size", 22)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	logo.add_theme_constant_override("shadow_offset_y", 8)
	logo.add_theme_constant_override("line_spacing", -18)
	column.add_child(logo)

	var tagline := Label.new()
	tagline.text = "Sneak out of class. Don't get caught."
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_outline_color", INK)
	tagline.add_theme_constant_override("outline_size", 8)
	column.add_child(tagline)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box


func _clear_ui() -> void:
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = preload("res://scripts/fonts.gd").bold()
	th.default_font_size = 18

	th.set_stylebox("panel", "PanelContainer", _style(PANEL, 22, 26))
	th.set_color("font_color", "Label", Color.WHITE)

	var field := _style(Color("fffaf0"), 10, 10)
	field.border_color = Color("e7d2aa")
	field.set_border_width_all(3)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = GOLD
	th.set_stylebox("normal", "LineEdit", field)
	th.set_stylebox("focus", "LineEdit", field_focus)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("caret_color", "LineEdit", INK)
	th.set_color("selection_color", "LineEdit", Color(1, 0.8, 0.3, 0.5))

	th.set_stylebox("normal", "OptionButton", field)
	th.set_stylebox("hover", "OptionButton", field_focus)
	th.set_stylebox("pressed", "OptionButton", field_focus)
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(state, "OptionButton", INK)
	th.set_stylebox("panel", "PopupMenu", _style(Color("fffaf0"), 10, 8))
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", INK)
	th.set_stylebox("hover", "PopupMenu", _style(Color("ffe39a"), 6, 4))
	return th


## Chunky toy-style button with a darker "thickness" edge underneath.
func _button(text: String, handler: Callable, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 50)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := _style(color, 12, 10)
	normal.border_color = color.darkened(0.35)
	normal.border_width_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.border_width_bottom = 2
	pressed.content_margin_top = 14
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(handler)
	return button


func _field(caption: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(label)
	control.custom_minimum_size.y = 42
	box.add_child(control)
	return box


func _style(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _make_room_picker() -> OptionButton:
	var picker := OptionButton.new()
	for room in Network.CLASSROOMS:
		picker.add_item(room)
	picker.select(Network.local_info.classroom)
	return picker
