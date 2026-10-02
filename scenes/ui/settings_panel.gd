extends VBoxContainer
## Settings form built in code. Every control writes straight through the `Settings`
## autoload (live apply + save). Emits `closed` when BACK is pressed.

signal closed

const INK := Color("2a1a0e")
const GOLD := Color("ffc93c")
const PANEL := Color(0.09, 0.09, 0.16, 0.84)
const TRACK := Color(1, 1, 1, 0.14)

var _s: Node ## The Settings autoload (looked up by path so this parses without it).
var _display: OptionButton ## DISPLAY: fullscreen / windowed (auto) / windowed at a size that fits this screen.


func _ready() -> void:
	_s = get_node_or_null("/root/Settings")
	if _s == null:
		push_error("SettingsPanel: /root/Settings autoload is missing.")
		return
	add_theme_constant_override("separation", 10)
	if not _has_inherited_theme():
		theme = _make_fallback_theme()

	var heading := Label.new()
	heading.text = "SETTINGS"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	add_child(heading)

	# Two columns so the whole form fits a 720p screen under the menu logo.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	add_child(cols)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for col in [left, right]:
		col.custom_minimum_size.x = 290
		col.add_theme_constant_override("separation", 10)
		cols.add_child(col)
	left.add_child(_slider_row("MOUSE SENSITIVITY", "mouse_sensitivity", 0.2, 3.0, 0.05, 1.0, "%.2fx"))
	left.add_child(_slider_row("FIELD OF VIEW", "fov", 60, 100, 1, 1.0, "%d°"))
	left.add_child(_slider_row("DANGER VIGNETTE", "vignette", 0, 200, 5, 100.0, "%d%%"))
	right.add_child(_slider_row("MASTER VOLUME", "master_volume", 0, 100, 1, 100.0, "%d%%"))
	right.add_child(_slider_row("MUSIC VOLUME", "music_volume", 0, 100, 1, 100.0, "%d%%"))
	right.add_child(_slider_row("SFX VOLUME", "sfx_volume", 0, 100, 1, 100.0, "%d%%"))

	# DISPLAY takes the left column's last slot; GRAPHICS and HUD SIZE share one row under the right column's
	# sliders, so the panel gains no height (the menu column is nearly full on a 1280 x 880 screen).
	_display = OptionButton.new()
	_display.add_item("Fullscreen", 0)
	_display.add_item("Windowed (auto size)", 1)
	var sizes: Array = _s.WINDOW_SIZES
	for k in sizes.size():
		var px: Vector2i = sizes[k]
		if _s.window_fits(px):
			_display.add_item("Windowed %d x %d" % [px.x, px.y], 2 + k)
	_sync_display()
	_display.item_selected.connect(func(i: int): _s.set_display(_display.get_item_id(i)))
	_style_picker(_display)
	left.add_child(_field("DISPLAY  (F11 OR ALT+ENTER)", _display))
	_s.changed.connect(_sync_display)  # a method, not a lambda: auto-disconnects when the panel is freed; stays right after F11

	var quality := OptionButton.new()
	for item in ["Low", "Medium", "High"]:
		quality.add_item(item)
	quality.select(int(_s.quality))
	quality.item_selected.connect(func(i: int): _s.set_value("quality", i))
	_style_picker(quality)

	var hud_size := OptionButton.new()
	for item in ["1  Small", "2  Normal", "3  Large"]:
		hud_size.add_item(item)
	hud_size.select(int(_s.ui_size) - 1)
	hud_size.item_selected.connect(func(i: int): _s.set_value("ui_size", i + 1))
	_style_picker(hud_size)

	var pickers := HBoxContainer.new()
	pickers.add_theme_constant_override("separation", 10)
	right.add_child(pickers)
	var quality_field := _field("GRAPHICS", quality)
	var hud_field := _field("HUD SIZE (IN GAME)", hud_size)
	quality_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pickers.add_child(quality_field)
	pickers.add_child(hud_field)

	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 28)
	add_child(toggles)

	var smooth := CheckButton.new()
	smooth.text = "SMOOTH EDGES (NO SHIMMER)"
	smooth.button_pressed = bool(_s.smooth_edges)
	smooth.focus_mode = Control.FOCUS_NONE
	smooth.toggled.connect(func(on: bool): _s.set_value("smooth_edges", on))
	_style_toggle(smooth)
	toggles.add_child(smooth)

	var vision := CheckButton.new()
	vision.text = "STAFF VISION ON MAP"
	vision.button_pressed = bool(_s.show_vision)
	vision.focus_mode = Control.FOCUS_NONE
	vision.toggled.connect(func(on: bool): _s.set_value("show_vision", on))
	_style_toggle(vision)
	toggles.add_child(vision)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	buttons.add_child(_button("CONTROLS", _show_controls, Color("9fd8ff")))
	buttons.add_child(_button("VOICE & MIC", _show_voice, Color("b9e6a0")))
	buttons.add_child(_button("BACK", closed.emit, Color("e7d2aa")))
	if voice_only:  # the lobby's MIC button: straight to the voice page
		_show_voice()


## Shows the real window state (F11 or the macOS green button can change it behind the picker's back).
func _sync_display() -> void:
	if not is_instance_valid(_display):
		return
	var i: int = _display.get_item_index(int(_s.display_id()))
	_display.select(i if i >= 0 else 1)  # a saved size that doesn't fit this screen shows as Auto


# --- Controls (key bindings) -------------------------------------------------------------------

var _controls: VBoxContainer
var _waiting := ""          # action waiting for a new key
var _waiting_button: Button


func _show_controls() -> void:
	for child in get_children():
		child.visible = false
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 10)
	add_child(_controls)
	var heading := Label.new()
	heading.text = "CONTROLS"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	_controls.add_child(heading)
	var tip := _caption("Click a key, then press the new key (or a mouse button). Esc cancels.")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.custom_minimum_size.x = 380
	_controls.add_child(tip)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls.add_child(scroll)
	# Two columns of [action, key] pairs.
	var list := GridContainer.new()
	list.columns = 2
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation", 24)
	list.add_theme_constant_override("v_separation", 4)
	scroll.add_child(list)
	var input: Node = get_node("/root/GameInput")
	for b in input.BINDINGS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = b[1]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.clip_text = true
		name_label.custom_minimum_size.x = 150
		row.add_child(name_label)
		var key := Button.new()
		key.text = input.key_label(b[0])
		key.custom_minimum_size = Vector2(118, 30)
		key.focus_mode = Control.FOCUS_NONE
		key.add_theme_stylebox_override("normal", _style(Color(1, 1, 1, 0.12), 8, 4))
		key.add_theme_stylebox_override("hover", _style(Color(1, 1, 1, 0.22), 8, 4))
		key.add_theme_stylebox_override("pressed", _style(GOLD.darkened(0.3), 8, 4))
		key.pressed.connect(_start_rebind.bind(str(b[0]), key))
		row.add_child(key)
		list.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.add_child(_button("RESET", func():
		input.reset_defaults()
		_close_controls()
		_show_controls(), Color("ff8a7a")))
	buttons.add_child(_button("DONE", _close_controls, Color("e7d2aa")))
	_controls.add_child(buttons)


func _start_rebind(action: String, button: Button) -> void:
	if _waiting_button:
		_waiting_button.text = get_node("/root/GameInput").key_label(_waiting)
	_waiting = action
	_waiting_button = button
	button.text = "press a key..."


func _input(event: InputEvent) -> void:
	if _waiting == "" or not event.is_pressed() or event.is_echo():
		return
	var input: Node = get_node("/root/GameInput")
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_waiting_button.text = input.key_label(_waiting)
	elif event is InputEventKey or event is InputEventMouseButton:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		var ev: InputEvent
		if event is InputEventKey:
			ev = InputEventKey.new()
			ev.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		else:
			ev = InputEventMouseButton.new()
			ev.button_index = event.button_index
		input.rebind(_waiting, ev)
		# Other rows may have lost this key: refresh every label.
		_close_controls()
		_show_controls()
	else:
		return
	_waiting = ""
	_waiting_button = null
	get_viewport().set_input_as_handled()


func _close_controls() -> void:
	_waiting = ""
	_waiting_button = null
	if is_instance_valid(_controls):
		_controls.queue_free()
		remove_child(_controls)
	_controls = null
	for child in get_children():
		child.visible = true


# --- Voice chat ----------------------------------------------------------------------------------

var _voice_page: VBoxContainer
var _meter_fill: ColorRect
var _meter_gate: ColorRect
const METER_W := 380.0
const VOICE_HINT := "Stay quiet: the bar stays left of the white line. Talk: it goes past it. Jumpy with nobody talking? Use headphones or lower the sensitivity. Can't be heard? Raise it, or press AUTO-SET."
var voice_only := false  ## opened by the lobby's MIC button: straight to this page; DONE closes the whole panel
var _sens_slider: HSlider
var _sens_label: Label
var _voice_hint: Label
var _meter_v := 0.0            # the bar as drawn: jumps up with your voice, eases down
var _cal := 0                  # AUTO-SET: 0 idle, 1 listening to the room, 2 listening to you
var _cal_t := 0.0
var _cal_last := -1.0
var _cal_idle := 0.0           # seconds since the last reading counted
var _cal_peak := 0.0           # loudest reading of the whole run (all zero: the mic gives no sound at all)
var _cal_floor_db := -100.0
var _cal_samples: Array = []


func _show_voice() -> void:
	for child in get_children():
		child.visible = false
	var voice: Node = get_node_or_null("/root/Voice")
	if voice:
		voice.monitoring = true
	_voice_page = VBoxContainer.new()
	_voice_page.add_theme_constant_override("separation", 10)
	add_child(_voice_page)
	var heading := Label.new()
	heading.text = "VOICE CHAT"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	_voice_page.add_child(heading)
	var about := _caption("Teachers hear HOW LOUD you are (never what you say): whisper when you hide. Wear headphones.")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	about.custom_minimum_size.x = 600
	_voice_page.add_child(about)
	var input: Node = get_node("/root/GameInput")
	var mode := OptionButton.new()
	for item in ["Open mic (talks when it hears you)", "Push to talk [%s]" % input.key_label("push_to_talk"), "Mic off (still hear friends)"]:
		mode.add_item(item)
	mode.select(int(_s.voice_mode))
	mode.item_selected.connect(func(i: int): _s.set_value("voice_mode", i))
	_style_picker(mode)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_voice_page.add_child(row)
	var mode_field := _field("MIC", mode)
	mode_field.custom_minimum_size.x = 300
	row.add_child(mode_field)
	var device := OptionButton.new()
	var devices := AudioServer.get_input_device_list()
	for d in devices:
		device.add_item(d)
	device.select(maxi(0, devices.find(str(_s.mic_device))))
	device.item_selected.connect(func(i: int): _s.set_value("mic_device", devices[i]))
	_style_picker(device)
	var device_field := _field("MICROPHONE", device)
	device_field.custom_minimum_size.x = 300
	row.add_child(device_field)
	var hearing := OptionButton.new()
	hearing.add_item("Hear everyone at full volume, anywhere")
	hearing.add_item("Proximity: voices fade with distance, muffled through walls")
	hearing.select(1 if bool(_s.proximity_voice) else 0)
	hearing.item_selected.connect(func(i: int): _s.set_value("proximity_voice", i == 1))
	_style_picker(hearing)
	_voice_page.add_child(_field("HOW YOU HEAR FRIENDS", hearing))
	var sliders := HBoxContainer.new()
	sliders.add_theme_constant_override("separation", 20)
	_voice_page.add_child(sliders)
	var gate := _sensitivity_row()
	gate.custom_minimum_size.x = 300
	sliders.add_child(gate)
	var vol := _slider_row("FRIENDS' VOICES", "voice_volume", 0, 100, 1, 100.0, "%d%%")
	vol.custom_minimum_size.x = 300
	sliders.add_child(vol)
	_voice_hint = _caption(VOICE_HINT)
	_voice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_voice_hint.custom_minimum_size = Vector2(600, 81)  # 2 lines (Jersey 10 at 13 px): every AUTO-SET message fits, so the page doesn't jump
	_voice_page.add_child(_voice_hint)
	var meter := ColorRect.new()
	meter.color = TRACK
	meter.custom_minimum_size = Vector2(METER_W, 16)
	meter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # exactly METER_W wide, so the white line sits right
	_voice_page.add_child(meter)
	_meter_fill = ColorRect.new()
	_meter_fill.color = Color("7fe0a0")
	_meter_fill.size = Vector2(0, 16)
	meter.add_child(_meter_fill)
	_meter_gate = ColorRect.new()
	_meter_gate.color = Color.WHITE
	_meter_gate.size = Vector2(3, 22)
	_meter_gate.position.y = -3
	meter.add_child(_meter_gate)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(_button("AUTO-SET", _start_calibration, Color("9fd8ff")))
	buttons.add_child(_button("DONE", _close_voice, Color("e7d2aa")))
	_voice_page.add_child(buttons)


## Players see sensitivity 1-10 (10 hears a whisper); the stored `mic_gate` is the RMS behind it.
func _sensitivity_row() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var label := _caption("MIC SENSITIVITY")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)
	_sens_label = Label.new()
	_sens_label.add_theme_font_size_override("font_size", 15)
	_sens_label.add_theme_color_override("font_color", GOLD)
	top.add_child(_sens_label)
	box.add_child(top)
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 1
	_sens_slider.max_value = 10
	_sens_slider.step = 1
	_sens_slider.custom_minimum_size = Vector2(0, 30)
	_sens_slider.focus_mode = Control.FOCUS_NONE
	_style_slider(_sens_slider)
	_sens_slider.value = _s.sensitivity_for_gate(float(_s.mic_gate))  # snaps to a whole step
	_sens_label.text = "%d / 10" % int(_sens_slider.value)
	_sens_slider.value_changed.connect(func(v: float):
		_sens_label.text = "%d / 10" % int(v)
		_s.set_value("mic_gate", _s.gate_for_sensitivity(v)))
	box.add_child(_sens_slider)
	return box


func _process(delta: float) -> void:
	if not is_instance_valid(_voice_page) or not is_instance_valid(_meter_fill):
		return
	var voice: Node = get_node_or_null("/root/Voice")
	if voice == null:
		return
	# The meter reads the mic even out of a session (the Voice autoload always listens).
	var lvl: float = voice.level
	var target: float = _s.mic_meter(lvl)
	_meter_v = target if target > _meter_v else lerpf(_meter_v, target, minf(1.0, delta * 8.0))  # up at once, down in ~0.15 s: readable, not jittery
	_meter_fill.size.x = METER_W * _meter_v
	_meter_fill.color = Color("7fe0a0") if lvl >= float(_s.mic_gate) else Color(1, 1, 1, 0.35)
	var gate_x: float = _s.mic_meter(float(_s.mic_gate))
	_meter_gate.position.x = METER_W * gate_x - 1.5
	if _cal != 0:
		_calibrate(delta, lvl)


# --- AUTO-SET: stay quiet for 2 s, then talk for 4 s; the gate goes between the room and your voice. ---
# The music and every bus are left alone on purpose: calibrating with the speakers on teaches the gate about their bleed.

func _percentile(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var sorted := a.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(sorted.size() * p), 0, sorted.size() - 1)])


func _start_calibration() -> void:
	var voice: Node = get_node_or_null("/root/Voice")
	if _cal != 0 or voice == null:
		return
	if not voice.mic_ok:
		_voice_hint.text = "No microphone found. Plug one in and pick it under MICROPHONE."
		return
	_cal = 1
	_cal_t = 0.0
	_cal_last = -1.0
	_cal_idle = 0.0
	_cal_peak = 0.0
	_cal_samples.clear()
	_voice_hint.text = "Step 1 of 2: stay quiet for a moment..."


func _calibrate(delta: float, lvl: float) -> void:
	_cal_t += delta
	_cal_peak = maxf(_cal_peak, lvl)
	# The level changes every 20 ms: count each reading once at any frame rate (a digitally silent mic never changes: every 40 ms then).
	_cal_idle += delta
	var fresh := lvl != _cal_last or _cal_idle >= 0.04
	_cal_last = lvl
	if fresh:
		_cal_idle = 0.0
	if _cal == 1:
		if fresh and _cal_t > 0.5:  # skip the click on the button
			_cal_samples.append(lvl)
		if _cal_t >= 2.5:
			_cal_floor_db = maxf(float(_s.mic_db(_percentile(_cal_samples, 0.9))), float(_s.METER_DB_MIN))  # a noise-gated mic reads dead silence: floor it
			_cal_samples.clear()
			_cal = 2
			_cal_t = 0.0
			_voice_hint.text = "Step 2 of 2: now say it like you would in class:  \"Sir, may I go to the washroom?\""
	elif _cal == 2:
		if fresh and _cal_t > 0.7:  # reaction time
			_cal_samples.append(lvl)
		if _cal_t >= 4.5:
			_finish_calibration()


func _finish_calibration() -> void:
	_cal = 0
	var voiced: Array = []
	for v in _cal_samples:
		if float(_s.mic_db(float(v))) > _cal_floor_db + 6.0:
			voiced.append(v)
	_cal_samples.clear()
	if _cal_peak < 0.0002:  # not a whisper of signal in 6 s: nothing reaches the game
		_voice_hint.text = "The mic isn't sending any sound. Check MICROPHONE above, and your computer's microphone permission."
		return
	if voiced.size() < 15:  # under ~0.3 s of voice
		_voice_hint.text = "Couldn't hear you. Press AUTO-SET again and talk as soon as step 2 starts, or raise your mic volume in your computer's sound settings."
		return
	var speech_db: float = _s.mic_db(_percentile(voiced, 0.5))
	var gap: float = speech_db - _cal_floor_db
	if gap < 10.0:
		_voice_hint.text = "Your voice is only %d dB above the room noise. Move closer, raise your mic volume in your computer's sound settings, use a headset or push to talk. Sensitivity left as it was." % int(gap)
		return
	# Halfway between the room and your voice (in dB), at least 6 dB over the room and 4 dB under your voice.
	var gate_db := clampf(_cal_floor_db + clampf(gap * 0.5, 6.0, gap - 4.0), -54.0, -22.0)
	_s.set_value("mic_gate", pow(10.0, gate_db / 20.0))
	var steps: float = _s.sensitivity_for_gate(float(_s.mic_gate))
	if is_instance_valid(_sens_slider):
		_sens_slider.set_value_no_signal(steps)
		_sens_label.text = "%d / 10" % int(_sens_slider.value)
	_voice_hint.text = "Done! Sensitivity set to %d / 10: the bar now passes the white line only when you talk. On speakers? Do this at the volume you'll play at." % int(round(steps))


func _exit_tree() -> void:
	_cal = 0
	var voice: Node = get_node_or_null("/root/Voice")
	if voice and is_instance_valid(_voice_page):
		voice.monitoring = false


func _close_voice() -> void:
	_cal = 0
	var voice: Node = get_node_or_null("/root/Voice")
	if voice:
		voice.monitoring = false
	if is_instance_valid(_voice_page):
		_voice_page.queue_free()
		remove_child(_voice_page)
	_voice_page = null
	if voice_only:  # opened from the lobby: DONE leaves the settings altogether
		closed.emit()
		return
	for child in get_children():
		child.visible = true


# --- Rows ----------------------------------------------------------------------------------

## Caption + live value on one line, slider underneath. `mult` maps the stored
## value to the slider (100 for 0-1 volumes shown as percent).
func _slider_row(caption: String, key: String, lo: float, hi: float, step: float,
		mult: float, fmt: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var top := HBoxContainer.new()
	var label := _caption(caption)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", GOLD)
	top.add_child(value_label)
	box.add_child(top)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 30)
	slider.focus_mode = Control.FOCUS_NONE
	_style_slider(slider)
	slider.value = float(_s.get(key)) * mult
	value_label.text = fmt % slider.value
	slider.value_changed.connect(func(v: float):
		value_label.text = fmt % v
		_s.set_value(key, v / mult))
	box.add_child(slider)
	return box


func _field(caption: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_caption(caption))
	control.custom_minimum_size.y = 42
	box.add_child(control)
	return box


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


# --- Styling -------------------------------------------------------------------------------

func _style_slider(slider: HSlider) -> void:
	var track := _style(TRACK, 6, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := _style(GOLD, 6, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	var fill_hot := fill.duplicate() as StyleBoxFlat
	fill_hot.bg_color = GOLD.lightened(0.2)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hot)
	slider.add_theme_icon_override("grabber", _knob(Color("fffaf0")))
	slider.add_theme_icon_override("grabber_highlight", _knob(Color.WHITE))


## Cream field look from main.gd, applied locally so it holds under any theme.
func _style_picker(picker: OptionButton) -> void:
	var field := _style(Color("fffaf0"), 10, 10)
	field.border_color = Color("e7d2aa")
	field.set_border_width_all(3)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = GOLD
	picker.add_theme_stylebox_override("normal", field)
	picker.add_theme_stylebox_override("hover", field_focus)
	picker.add_theme_stylebox_override("pressed", field_focus)
	picker.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		picker.add_theme_color_override(state, INK)
	var popup := picker.get_popup()
	popup.add_theme_stylebox_override("panel", _style(Color("fffaf0"), 10, 8))
	popup.add_theme_stylebox_override("hover", _style(Color("ffe39a"), 6, 4))
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", INK)


## Caption-styled label on the left, chunky gold pill switch on the right.
func _style_toggle(toggle: CheckButton) -> void:
	toggle.add_theme_font_size_override("font_size", 13)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(state, Color(1, 1, 1, 0.7))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var on := _pill(true)
	var off := _pill(false)
	for icon in ["checked", "checked_mirrored"]:
		toggle.add_theme_icon_override(icon, on)
	for icon in ["unchecked", "unchecked_mirrored"]:
		toggle.add_theme_icon_override(icon, off)
	toggle.custom_minimum_size.y = 36


## 52x28 switch: gold track + knob right when on, dim track + knob left when off.
func _pill(on: bool) -> ImageTexture:
	var w := 52
	var h := 28
	var r := h / 2.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := GOLD if on else Color(0.3, 0.3, 0.4)
	var knob := Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distance to the pill's centre segment gives a rounded rectangle.
			var d := p.distance_to(Vector2(clampf(p.x, r, w - r), r))
			var col := Color(0, 0, 0, 0)
			if d <= r:
				col = INK if d > r - 2.5 else track
				var kd := p.distance_to(knob)
				if kd <= r - 5.0:
					col = Color("fffaf0")
				col.a = clampf(r - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Round knob with a thick ink outline, drawn once into a texture.
func _knob(fill: Color) -> ImageTexture:
	var px := 22
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := Vector2(px, px) / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d <= 10.5:
				col = INK if d > 7.0 else fill
				col.a = clampf(10.5 - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Chunky toy-style button with a darker "thickness" edge underneath (as in main.gd).
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


func _style(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _has_inherited_theme() -> bool:
	var node := get_parent()
	while node:
		if node is Control and (node as Control).theme:
			return true
		if node is Window and (node as Window).theme:
			return true
		node = node.get_parent()
	return false


## Used only when no ancestor provides a theme: gives the menu's chunky font.
func _make_fallback_theme() -> Theme:
	var th := Theme.new()
	th.default_font = preload("res://scripts/fonts.gd").bold()
	th.default_font_size = 18
	th.set_color("font_color", "Label", Color.WHITE)
	return th
