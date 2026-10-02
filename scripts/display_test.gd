extends SceneTree
## Display settings check: `godot --headless --path . -s scripts/display_test.gd`.
## Fullscreen is the default, and the one-time migration is what moves existing players there: a settings.cfg from
## before the version key always says fullscreen=false (chosen or not), so the flip has to happen once and then stick.

const SettingsScript := preload("res://autoload/settings.gd")
const TMP := "user://display_test.cfg"


func _load(cfg: ConfigFile) -> Node:
	cfg.save(TMP)
	var s: Node = SettingsScript.new()  # never added to the tree: no _ready, no window calls
	s.load_settings(TMP)
	return s


func _init() -> void:
	var ok := true
	# 1. An old file (no version) saying windowed: flipped once, the version is stamped, other values are kept.
	var old := ConfigFile.new()
	old.set_value("settings", "fullscreen", false)
	old.set_value("settings", "fov", 80.0)
	var a := _load(old)
	ok = ok and a.fullscreen == true and is_equal_approx(a.fov, 80.0)
	var back := ConfigFile.new()
	back.load(TMP)
	ok = ok and int(back.get_value("settings", "settings_version", 0)) == SettingsScript.VERSION
	ok = ok and bool(back.get_value("settings", "fullscreen", false)) == true
	# 2. The same player later picks windowed: it sticks.
	a.fullscreen = false
	a.window_size = 3
	a.save_settings(TMP)
	var b: Node = SettingsScript.new()
	b.load_settings(TMP)
	ok = ok and b.fullscreen == false and b.window_size == 3
	# 3. No file at all (first launch): fullscreen, Auto size.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var c: Node = SettingsScript.new()
	c.load_settings(TMP)
	ok = ok and c.fullscreen == true and c.window_size == 0
	# 4. A size index from a newer or hand-edited file is clamped.
	var odd := ConfigFile.new()
	odd.set_value("settings", "settings_version", SettingsScript.VERSION)
	odd.set_value("settings", "fullscreen", false)
	odd.set_value("settings", "window_size", 99)
	var d := _load(odd)
	ok = ok and d.fullscreen == false and d.window_size == SettingsScript.WINDOW_SIZES.size()
	# 5. The picker ids line up: 0 fullscreen, 1 Auto, 2 + k = WINDOW_SIZES[k]; headless everything "fits".
	ok = ok and d.window_fits(Vector2i(2560, 1440)) == true
	for n in [a, b, c, d]:
		n.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	print("[display] %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
