extends VBoxContainer
## Settings form built in code. Every control writes straight through the `Settings`
## autoload (live apply + save). Emits `closed` when BACK is pressed.

signal closed

const INK := Color("2a1a0e")
const GOLD := Color("ffc93c")
const PANEL := Color(0.09, 0.09, 0.16, 0.84)
const TRACK := Color(1, 1, 1, 0.14)

var _s: Node ## The Settings autoload (looked up by path so this parses without it).


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
	right.add_child(_slider_row("MASTER VOLUME", "master_volume", 0, 100, 1, 100.0, "%d%%"))
	right.add_child(_slider_row("MUSIC VOLUME", "music_volume", 0, 100, 1, 100.0, "%d%%"))
	right.add_child(_slider_row("SFX VOLUME", "sfx_volume", 0, 100, 1, 100.0, "%d%%"))

	var quality := OptionButton.new()
	for item in ["Low", "Medium", "High"]:
		quality.add_item(item)
	quality.select(int(_s.quality))
	quality.item_selected.connect(func(i: int): _s.set_value("quality", i))
	_style_picker(quality)
	left.add_child(_field("GRAPHICS", quality))

	var hud_size := OptionButton.new()
	for item in ["1  Small", "2  Normal", "3  Large"]:
		hud_size.add_item(item)
	hud_size.select(int(_s.ui_size) - 1)
	hud_size.item_selected.connect(func(i: int): _s.set_value("ui_size", i + 1))
	_style_picker(hud_size)
	right.add_child(_field("HUD SIZE (IN GAME)", hud_size))

	var full := CheckButton.new()
	full.text = "FULLSCREEN"
	full.button_pressed = bool(_s.fullscreen)
	full.focus_mode = Control.FOCUS_NONE
	full.toggled.connect(func(on: bool): _s.set_value("fullscreen", on))
	_style_toggle(full)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 28)
	add_child(toggles)
	toggles.add_child(full)

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
	var vision_row := HBoxContainer.new()  # keeps the switch next to its label
	vision_row.add_child(vision)
	add_child(vision_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	buttons.add_child(_button("CONTROLS", _show_controls, Color("9fd8ff")))
	buttons.add_child(_button("VOICE", _show_voice, Color("b9e6a0")))
	buttons.add_child(_button("BACK", closed.emit, Color("e7d2aa")))


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
const METER_MAX := 0.12  # RMS at the right-hand end of the mic meter


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
	var about := _caption("Teachers hear HOW LOUD you are (never what you say): whisper when you hide. Friends: choose below whether their voices fade with distance or you hear everyone at full volume. Wear headphones so your mic doesn't pick up the game.")
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
	var gate := _slider_row("OPEN MIC STARTS AT", "mic_gate", 2, 80, 1, 1000.0, "%d")
	gate.custom_minimum_size.x = 300
	sliders.add_child(gate)
	var vol := _slider_row("FRIENDS' VOICES", "voice_volume", 0, 100, 1, 100.0, "%d%%")
	vol.custom_minimum_size.x = 300
	sliders.add_child(vol)
	_voice_page.add_child(_caption("SAY SOMETHING: the bar should cross the white line when you talk, not when you're quiet."))
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
	buttons.add_child(_button("DONE", _close_voice, Color("e7d2aa")))
	_voice_page.add_child(buttons)


func _process(_delta: float) -> void:
	if not is_instance_valid(_voice_page) or not is_instance_valid(_meter_fill):
		return
	var voice: Node = get_node_or_null("/root/Voice")
	if voice == null:
		return
	# The meter reads the mic even out of a session (the Voice autoload always listens).
	var lvl: float = voice.level
	_meter_fill.size.x = METER_W * clampf(lvl / METER_MAX, 0.0, 1.0)
	_meter_fill.color = Color("7fe0a0") if lvl >= float(_s.mic_gate) else Color(1, 1, 1, 0.35)
	_meter_gate.position.x = METER_W * clampf(float(_s.mic_gate) / METER_MAX, 0.0, 1.0)


func _exit_tree() -> void:
	var voice: Node = get_node_or_null("/root/Voice")
	if voice and is_instance_valid(_voice_page):
		voice.monitoring = false


func _close_voice() -> void:
	var voice: Node = get_node_or_null("/root/Voice")
	if voice:
		voice.monitoring = false
	if is_instance_valid(_voice_page):
		_voice_page.queue_free()
		remove_child(_voice_page)
	_voice_page = null
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
