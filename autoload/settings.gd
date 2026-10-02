extends Node
## Player preferences (controls, audio, graphics), persisted to user://settings.cfg.
## Registered as the `Settings` autoload. Change values through set_value() so they
## are applied and saved in one go.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
## settings.cfg layout. 2 = fullscreen is the default (a v1 file always holds fullscreen=false, chosen or not).
const VERSION := 2
## Keys that are saved/loaded, in file order.
const KEYS := [
	"mouse_sensitivity", "fov", "master_volume", "music_volume", "sfx_volume",
	"quality", "fullscreen", "window_size", "player_name", "smooth_edges", "show_vision", "ui_size",
	"voice_mode", "mic_gate", "voice_volume", "mic_device", "proximity_voice", "vignette",
]

enum Quality { LOW, MEDIUM, HIGH }

var mouse_sensitivity := 1.0 ## Look-speed multiplier, 0.2 - 3.0.
var fov := 75.0 ## Camera field of view in degrees, 60 - 100.
var master_volume := 0.9 ## Linear 0 - 1.
var music_volume := 0.6 ## Linear 0 - 1.
var sfx_volume := 0.9 ## Linear 0 - 1.
var quality := 2 ## 0 Low, 1 Medium, 2 High.
var fullscreen := true ## What the player wants (saved). Dev runs ignore it at launch (see _launch_windowed) and leave the saved value alone.
var window_size := 0 ## Windowed size: 0 = Auto (the project's launch size, shrunk to fit the screen), else 1 + index into WINDOW_SIZES.
## Windowed sizes offered in Settings (16:9; only those that fit the screen are listed).
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const MIN_WINDOW := Vector2i(960, 600) ## Smallest window the player can drag to (clamped to the screen).
var smooth_edges := false ## Temporal anti-aliasing: no edge shimmer, slightly softer in motion.
var ui_size := 2 ## In-game HUD size: 1 small, 2 normal, 3 large (HUD_SCALES).
const HUD_SCALES := [1.0, 1.0, 1.25, 1.5]  # index = ui_size
var show_vision := true ## Draw where staff can see: vision wedges on the minimap and the big map.
var vignette := 1.0 ## Danger vignette strength: 0 off, 1.0 default (gentle), 1.5 about the old look, 2.0 strongest.
var player_name := "Student"
## Proximity voice (see the Voice autoload).
enum VoiceMode { OPEN_MIC, PUSH_TO_TALK, OFF }
var voice_mode := 0 ## 0 open mic (talks when it hears you), 1 push-to-talk, 2 mic off (you still hear others).
var mic_gate := 0.012 ## Open mic: how loud you must be to transmit (RMS, 0.002 - 0.08). Lower = more sensitive (the UI shows it as sensitivity 1-10, higher = more sensitive).
var voice_volume := 1.0 ## Friends' voices, linear 0 - 1.
var mic_device := "Default"
var proximity_voice := false ## On: friends' voices fade with distance (to nothing far away) and are muffled through walls. Off: everyone at full volume.

## Mic scale helpers, in one place so the slider, the meters and AUTO-SET agree. Players see sensitivity 1-10
## (10 hears a whisper); `mic_gate` (RMS) stays the stored truth so old settings.cfg files keep working.
## Each step is 3.55 dB: 10 -> 0.002, 6 -> 0.0102, 1 -> 0.079. Plain funcs, not static: a static called through
## the autoload instance raises STATIC_CALLED_ON_INSTANCE.
const GATE_STEP_DB := 3.55
const METER_DB_MIN := -60.0
const METER_DB_MAX := -12.0


func mic_db(rms: float) -> float:
	return 20.0 * log(maxf(rms, 0.00001)) / log(10.0)


## 0..1 on the dB scale every mic meter shares.
func mic_meter(rms: float) -> float:
	return clampf((mic_db(rms) - METER_DB_MIN) / (METER_DB_MAX - METER_DB_MIN), 0.0, 1.0)


func gate_for_sensitivity(s: float) -> float:
	return pow(10.0, (-54.0 + (10.0 - s) * GATE_STEP_DB) / 20.0)


func sensitivity_for_gate(g: float) -> float:
	return clampf(10.0 - (mic_db(g) + 54.0) / GATE_STEP_DB, 1.0, 10.0)


func _ready() -> void:
	load_settings()
	apply()
	_prepare_window()  # still before the first frame: Settings loads before the main scene


func load_settings(path := PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return  # first launch: the member defaults (fullscreen)
	for key in KEYS:
		if cfg.has_section_key(SECTION, key):
			_assign(key, cfg.get_value(SECTION, key))
	if int(cfg.get_value(SECTION, "settings_version", 1)) < VERSION:
		fullscreen = true  # one-time flip; windowed stays a choice from now on (the version is stored)
		save_settings(path)


func save_settings(path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "settings_version", VERSION)
	for key in KEYS:
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [path, err])


## Updates one setting, applies it live and saves to disk.
func set_value(key: String, value: Variant) -> void:
	if not key in KEYS:
		push_warning("Settings: unknown key '%s'" % key)
		return
	if key == "fullscreen":  # the window and the wish must never diverge through the generic path
		set_fullscreen(bool(value))
		return
	_assign(key, value)
	apply()
	save_settings()


## Pushes the audio settings to the engine and notifies listeners. Never touches the window
## (see _show_mode): an unrelated slider must not undo F11 or the macOS green button.
func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)
	if mic_device in AudioServer.get_input_device_list() and AudioServer.input_device != mic_device:
		AudioServer.input_device = mic_device
	changed.emit()


# --- Window: fullscreen / windowed size ---------------------------------------------------------
# The window changes only here: once at launch (window_ready) and from explicit calls (F11, Alt+Enter,
# the DISPLAY picker). Everything below is a no-op headless, so bots and CI are unaffected.

## At launch the window only goes fullscreen once the menu has been drawn: switching
## any earlier leaves the old splash in one corner and black around it until the
## first frame (a "black slab" while the menu scene loads).
var _window_ready := false
var _switching := false


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Dev runs keep the window as it opens, so tests, screenshots, trailer plates and two instances on one
## screen don't all go fullscreen: the editor, anything after "--" (the rule profile.gd uses), --windowed / -w.
func _launch_windowed() -> bool:
	return OS.has_feature("editor") or not OS.get_cmdline_user_args().is_empty() or OS.get_cmdline_args().has("--windowed") or OS.get_cmdline_args().has("-w")


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## DISPLAY picker value: 0 fullscreen, 1 windowed Auto, 2 + k windowed WINDOW_SIZES[k].
func display_id() -> int:
	return 0 if is_fullscreen() else 1 + window_size


func _title_bar() -> int:
	return maxi(DisplayServer.window_get_size_with_decorations().y - DisplayServer.window_get_size().y, 40)


## Screen area a windowed size (title bar excluded) can use; huge when unknown (headless).
func _free_area() -> Vector2i:
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if area.size.x <= 0 or area.size.y <= 0:
		return Vector2i(100000, 100000)
	return Vector2i(area.size.x, area.size.y - _title_bar())


func window_fits(px: Vector2i) -> bool:
	var room := _free_area()
	return px.x <= room.x and px.y <= room.y


## The project's launch size (no third hard-coded copy).
func _auto_size() -> Vector2i:
	return Vector2i(int(ProjectSettings.get_setting("display/window/size/window_width_override", 1440)),
			int(ProjectSettings.get_setting("display/window/size/window_height_override", 990)))


## Before the first frame (replaces main's old _fit_window): the minimum size, and the window sized for this
## screen. Done even when fullscreen is wanted: this rect is what leaving fullscreen returns to.
func _prepare_window() -> void:
	if _headless() or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var room := _free_area()
	get_window().min_size = Vector2i(mini(MIN_WINDOW.x, room.x), mini(MIN_WINDOW.y, room.y))
	_size_window(true)


## Windowed only (window_set_size is ignored while fullscreen). At launch, Auto keeps the window as it
## opened and only shrinks it if it doesn't fit; dev runs always count as Auto.
func _size_window(launch := false) -> void:
	if _headless():
		return
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var room := _free_area()
	var keep := launch and (window_size == 0 or _launch_windowed())
	var want: Vector2i = DisplayServer.window_get_size() if keep else _chosen_size()
	var fit := minf(1.0, minf(float(room.x) / want.x, float(room.y) / want.y))
	if keep and fit >= 1.0:
		return
	want = Vector2i(Vector2(want) * fit)
	var outer := want + Vector2i(0, _title_bar())
	DisplayServer.window_set_size(want)
	DisplayServer.window_set_position(area.position + (area.size - outer) / 2 + Vector2i(0, _title_bar()))


func _chosen_size() -> Vector2i:
	if window_size <= 0:
		return _auto_size()
	var px: Vector2i = WINDOW_SIZES[window_size - 1]
	return px


## Called by the menu once it's on screen (the black-slab rule: never switch before the first drawn frame).
func window_ready() -> void:
	_window_ready = true
	if _headless():
		return
	print("[display] screen=%s usable=%s scale=%.1f window=%s mode=%d fullscreen_wanted=%s dev=%s" % [
			DisplayServer.screen_get_size(), DisplayServer.screen_get_usable_rect().size, DisplayServer.screen_get_scale(),
			DisplayServer.window_get_size(), DisplayServer.window_get_mode(), fullscreen, _launch_windowed()])
	if _launch_windowed():
		return
	await _show_mode()


## Makes the window match `fullscreen`. Borderless FULLSCREEN on both OSes (a native Space on macOS; on
## Windows it keeps alt-tab, Discord and the firewall prompt working). Not EXCLUSIVE.
func _show_mode() -> void:
	if _headless() or not _window_ready or is_fullscreen() == fullscreen:
		return
	_switching = true
	var recapture := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if recapture:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # no cursor jump or camera whip mid-switch
	var before := get_window().size
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	# Wait for the new size to arrive (macOS animates a Space change), then for it to settle.
	var t := Time.get_ticks_msec()
	while get_window().size == before and Time.get_ticks_msec() - t < 1000:
		await get_tree().process_frame
	var last := get_window().size
	var calm := 0
	t = Time.get_ticks_msec()
	while calm < 8 and Time.get_ticks_msec() - t < 1000:
		await get_tree().process_frame
		var now := get_window().size
		calm = calm + 1 if now == last else 0
		last = now
	if recapture:  # only if nothing else wants the mouse (pause menu, a test, results): the HUD knows
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.should_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_switching = false


## F11 / Alt+Enter / the DISPLAY picker: remembers the choice, then switches. Leaving fullscreen returns to
## the previous window rect (the OS does that).
func set_fullscreen(on: bool) -> void:
	if _switching:
		return
	fullscreen = on
	save_settings()
	await _show_mode()
	changed.emit()


## DISPLAY picker: 0 fullscreen, 1 windowed Auto, 2 + k windowed WINDOW_SIZES[k].
func set_display(id: int) -> void:
	if _switching:
		return
	if id > 0:
		window_size = clampi(id - 1, 0, WINDOW_SIZES.size())
	await set_fullscreen(id == 0)
	if id > 0 and not _headless():
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_size_window()  # best effort right after leaving fullscreen; picking again while windowed always works


## An autoload's _input runs after the scene's and before the GUI: this works in the menu, lobby, game,
## pause menu and over a focused LineEdit. The settings screen's key rebinding sees the key first.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var alt_enter := key.alt_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)
	var mac_fs := key.meta_pressed and key.ctrl_pressed and key.keycode == KEY_F  # F11 is Show Desktop on Macs
	if key.keycode == KEY_F11 or alt_enter or mac_fs:
		get_viewport().set_input_as_handled()  # also stops Alt+Enter submitting a focused LineEdit
		set_fullscreen(not is_fullscreen())  # toggle from what the window REALLY is


## Applies the quality preset to a world's environment and sun (call again on `changed`).
func apply_graphics(env: Environment, sun: DirectionalLight3D) -> void:
	if env:
		# Remember the scene's own fog setting so leaving Low restores it.
		if not env.has_meta("base_fog"):
			env.set_meta("base_fog", env.fog_enabled)
		env.ssao_enabled = quality >= Quality.MEDIUM
		env.ssil_enabled = quality >= Quality.HIGH
		env.glow_enabled = quality >= Quality.MEDIUM
		env.fog_enabled = env.get_meta("base_fog") if quality >= Quality.MEDIUM else false
	if sun:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = [45.0, 70.0, 90.0][quality]
	get_tree().root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	get_tree().root.use_taa = smooth_edges
	# FXAA softens everything, text included; MSAA already smooths edges above Low.
	get_tree().root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == Quality.LOW else Viewport.SCREEN_SPACE_AA_DISABLED


func _assign(key: String, value: Variant) -> void:
	match key:
		"mouse_sensitivity":
			mouse_sensitivity = clampf(float(value), 0.2, 3.0)
		"fov":
			fov = clampf(float(value), 60.0, 100.0)
		"master_volume":
			master_volume = clampf(float(value), 0.0, 1.0)
		"music_volume":
			music_volume = clampf(float(value), 0.0, 1.0)
		"sfx_volume":
			sfx_volume = clampf(float(value), 0.0, 1.0)
		"quality":
			quality = clampi(int(value), Quality.LOW, Quality.HIGH)
		"fullscreen":
			fullscreen = bool(value)
		"window_size":
			window_size = clampi(int(value), 0, WINDOW_SIZES.size())
		"smooth_edges":
			smooth_edges = bool(value)
		"show_vision":
			show_vision = bool(value)
		"vignette":
			vignette = clampf(float(value), 0.0, 2.0)
		"ui_size":
			ui_size = clampi(int(value), 1, 3)
		"voice_mode":
			voice_mode = clampi(int(value), 0, 2)
		"mic_gate":
			mic_gate = clampf(float(value), 0.002, 0.08)
		"voice_volume":
			voice_volume = clampf(float(value), 0.0, 1.0)
		"mic_device":
			mic_device = str(value) if str(value) != "" else "Default"
		"proximity_voice":
			proximity_voice = bool(value)
		"player_name":
			var s := str(value).strip_edges()
			player_name = s if not s.is_empty() else "Student"


func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
