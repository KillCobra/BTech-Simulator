extends Node
## Player preferences (controls, audio, graphics), persisted to user://settings.cfg.
## Registered as the `Settings` autoload. Change values through set_value() so they
## are applied and saved in one go.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "settings"
## Keys that are saved/loaded, in file order.
const KEYS := [
	"mouse_sensitivity", "fov", "master_volume", "music_volume", "sfx_volume",
	"quality", "fullscreen", "player_name", "smooth_edges", "show_vision", "ui_size",
	"voice_mode", "mic_gate", "voice_volume", "mic_device",
]

enum Quality { LOW, MEDIUM, HIGH }

var mouse_sensitivity := 1.0 ## Look-speed multiplier, 0.2 - 3.0.
var fov := 75.0 ## Camera field of view in degrees, 60 - 100.
var master_volume := 0.9 ## Linear 0 - 1.
var music_volume := 0.6 ## Linear 0 - 1.
var sfx_volume := 0.9 ## Linear 0 - 1.
var quality := 2 ## 0 Low, 1 Medium, 2 High.
var fullscreen := false
var smooth_edges := false ## Temporal anti-aliasing: no edge shimmer, slightly softer in motion.
var ui_size := 2 ## In-game HUD size: 1 small, 2 normal, 3 large (HUD_SCALES).
const HUD_SCALES := [1.0, 1.0, 1.25, 1.5]  # index = ui_size
var show_vision := true ## Draw where staff can see: vision wedges on the minimap and the big map.
var player_name := "Student"
## Proximity voice (see the Voice autoload).
enum VoiceMode { OPEN_MIC, PUSH_TO_TALK, OFF }
var voice_mode := 0 ## 0 open mic (talks when it hears you), 1 push-to-talk, 2 mic off (you still hear others).
var mic_gate := 0.012 ## Open mic: how loud you must be to transmit (RMS, 0.002 - 0.08). Lower = more sensitive.
var voice_volume := 1.0 ## Friends' voices, linear 0 - 1.
var mic_device := "Default"


func _ready() -> void:
	load_settings()
	apply()


## At launch the window only goes fullscreen once the menu has been drawn: switching
## any earlier leaves the old splash in one corner and black around it until the
## first frame (a "black slab" while the menu scene loads).
var _window_ready := false


## Called by the menu once it's on screen: from now on the window follows `fullscreen`.
func window_ready() -> void:
	_window_ready = true
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in KEYS:
		if cfg.has_section_key(SECTION, key):
			_assign(key, cfg.get_value(SECTION, key))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])


## Updates one setting, applies it live and saves to disk.
func set_value(key: String, value: Variant) -> void:
	if not key in KEYS:
		push_warning("Settings: unknown key '%s'" % key)
		return
	_assign(key, value)
	apply()
	save_settings()


## Pushes audio + window settings to the engine and notifies listeners.
func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Voice", voice_volume)
	if mic_device in AudioServer.get_input_device_list() and AudioServer.input_device != mic_device:
		AudioServer.input_device = mic_device
	if DisplayServer.get_name() != "headless" and _window_ready:
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		var mode := DisplayServer.window_get_mode()
		var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if is_full != fullscreen:
			DisplayServer.window_set_mode(want)
	changed.emit()


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
		"smooth_edges":
			smooth_edges = bool(value)
		"show_vision":
			show_vision = bool(value)
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
		"player_name":
			var s := str(value).strip_edges()
			player_name = s if not s.is_empty() else "Student"


func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
