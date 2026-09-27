extends CanvasLayer
## In-game HUD. Reads the replicated Director state every frame: identity and
## bell timer, suspicion meter, attendance, side quests, inventory, big state
## banners, event feed, toasts, pings/phone markers, locker overlay, the Tab
## scoreboard and the end-of-round results.

const P := preload("res://scripts/palette.gd")
const CampusBuilder := preload("res://scenes/world/campus_builder.gd")
const Maps := preload("res://scenes/world/maps/maps.gd")
const ITEM_COLORS := {
	"hall_pass": Color("9fd8ff"), "samosa": Color("e0a050"), "medical_note": Color("fbf6e8"),
	"canteen_key": Color("ffd24a"), "library_book": Color("4f86e0"),
}
## Phone apps (index = --phone=N). _phone_app -1 is the home screen, which answers the
## four questions you have while sneaking: where's my class, where are my friends,
## what am I doing, how much money have I got. Everything else is one tap away.
const PHONE_APPS := [
	{"name": "Navigate", "icon": "route", "color": Color("b07cff")},
	{"name": "Help Out", "icon": "help", "color": Color("5fd3c5")},
]
const NAV_APP := 0
const HELP_APP := 1
const ROUTE_SHOW := 10.0  # seconds the Navigate trail stays on the floor and the minimap
const MAX_STAFF_TAGS := 6  # phone tracker: only the nearest few get a name tag


## A phone app's icon: a simple glyph drawn in ink on the tile.
class AppIcon extends Control:
	var kind := ""
	const INK := Color("2a1a0e")

	func _draw() -> void:
		var c := size / 2.0
		var w := 3.0
		match kind:
			"clock":
				draw_arc(c, 15, 0, TAU, 32, INK, w, true)
				draw_line(c, c + Vector2(0, -10), INK, w, true)
				draw_line(c, c + Vector2(7, 3), INK, w, true)
			"calendar":
				draw_rect(Rect2(c + Vector2(-15, -12), Vector2(30, 27)), INK, false, w)
				draw_rect(Rect2(c + Vector2(-15, -12), Vector2(30, 7)), INK)
				for i in 3:
					for j in 2:
						draw_rect(Rect2(c + Vector2(-10 + i * 8, j * 7), Vector2(4, 4)), INK)
			"wallet":
				draw_rect(Rect2(c + Vector2(-16, -10), Vector2(32, 22)), INK, false, w)
				draw_rect(Rect2(c + Vector2(4, -3), Vector2(12, 8)), INK)
				draw_line(c + Vector2(-14, -10), c + Vector2(8, -17), INK, w, true)
			"trade":
				draw_line(c + Vector2(-14, -6), c + Vector2(12, -6), INK, w, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(15, -6), c + Vector2(8, -12), c + Vector2(8, 0)]), INK)
				draw_line(c + Vector2(14, 7), c + Vector2(-12, 7), INK, w, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-15, 7), c + Vector2(-8, 1), c + Vector2(-8, 13)]), INK)
			"radar":
				draw_arc(c, 15, 0, TAU, 32, INK, w, true)
				draw_arc(c, 8, 0, TAU, 24, INK, 2.0, true)
				draw_line(c, c + Vector2(11, -11), INK, w, true)
				draw_circle(c + Vector2(-6, 6), 2.5, INK)
			"help":
				# A speech bubble with a heart: texting friends inside.
				draw_rect(Rect2(c + Vector2(-16, -14), Vector2(32, 22)), INK, false, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 8), c + Vector2(-2, 8), c + Vector2(-10, 15)]), INK)
				draw_circle(c + Vector2(-4, -5), 4.0, INK)
				draw_circle(c + Vector2(4, -5), 4.0, INK)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -4), c + Vector2(8, -4), c + Vector2(0, 5)]), INK)
			"route":
				var pts := PackedVector2Array([c + Vector2(-13, 13), c + Vector2(-13, 2), c + Vector2(4, 2), c + Vector2(4, -8)])
				draw_polyline(pts, INK, w, true)
				draw_circle(c + Vector2(-13, 13), 3.5, INK)
				# Map pin at the end.
				draw_circle(c + Vector2(10, -10), 6, INK)
				draw_colored_polygon(PackedVector2Array([c + Vector2(5, -7), c + Vector2(15, -7), c + Vector2(10, 1)]), INK)
				draw_circle(c + Vector2(10, -10), 2.2, Color.WHITE)

## Screen-space markers for pings and the phone's staff tracker.
class Markers extends Control:
	var items: Array = []  # {"at": Vector2, "text": String, "color": Color}

	func _draw() -> void:
		var font := get_theme_default_font()
		for m in items:
			var at: Vector2 = m.at
			var c: Color = m.color
			draw_circle(at, 9.0, Color(0, 0, 0, 0.55))
			draw_circle(at, 6.0, c)
			draw_string_outline(font, at + Vector2(12, 5), m.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.8))
			draw_string(font, at + Vector2(12, 5), m.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c)


const MapView := preload("res://scenes/ui/map_view.gd")
const Rules := preload("res://scripts/rules.gd")


## Screen-edge glow towards whoever is about to spot you (angle 0 = straight ahead).
class EdgePulse extends Control:
	var angle := 0.0
	var strength := 0.0
	var t := 0.0

	func _draw() -> void:
		if strength <= 0.01:
			return
		var c := size / 2.0
		var dir := Vector2(sin(angle), -cos(angle))
		# Where that direction leaves the screen (a slightly inset rectangle).
		var half := c - Vector2(30, 30)
		var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var at := c + dir * k
		var pulse := 0.55 + 0.45 * sin(t * (6.0 + 8.0 * strength))
		for i in 6:
			var r := 140.0 - i * 20.0
			draw_circle(at, r, Color(1.0, 0.15, 0.1, 0.05 * strength * pulse * (i + 1)))
		# A chevron pointing at them.
		var side := Vector2(-dir.y, dir.x)
		var tip := at + dir * 6.0
		var pts := PackedVector2Array([tip, tip - dir * 26.0 + side * 16.0, tip - dir * 18.0, tip - dir * 26.0 - side * 16.0])
		draw_colored_polygon(pts, Color(1.0, 0.3, 0.2, 0.9 * strength))


## A row of three stars (filled = earned, ringed = new this round).
class StarRow extends Control:
	var got: Array = [false, false, false]
	var fresh: Array = []

	func _draw() -> void:
		for k in 3:
			var at := Vector2(18 + k * 40, size.y / 2.0)
			var on: bool = got[k]
			if fresh.has(k):
				draw_circle(at, 17.0, Color(1.0, 0.85, 0.3, 0.35))
			MapView.draw_icon_star(self, at, 1.5, Color("ffd24a") if on else Color(1, 1, 1, 0.18))
const Icons := preload("res://scripts/icons.gd")
const Questions := preload("res://scripts/questions.gd")
const ExamGame := preload("res://scenes/ui/exam_game.gd")


## Key for the big map: marker icons and area colours.
class Legend extends Control:
	const ROWS := [
		["me", "You"], ["friend", "Friend"], ["staff", "Staff (seen or on your phone)"], ["staff_alert", "Staff chasing you"],
		["staff_floor", "Staff on another floor"], ["quest", "Side quest"], ["seat", "Your seat"], ["exit", "Way out of the university"],
		["", ""], ["area:5a5d68", "Road"], ["area:e8dcc0", "Path"], ["area:5cb6e0", "Water (you'll be washed back)"],
		["area:c9b48f", "Building"], ["class_now", "Your class right now"], ["area:9a9486", "Stairs"],
	]

	func _draw() -> void:
		var font := get_theme_default_font()
		var y := 10.0
		for row in ROWS:
			var kind: String = row[0]
			var at := Vector2(16, y + 8)
			if kind == "":
				y += 10
				continue
			if kind == "class_now":
				draw_rect(Rect2(at - Vector2(9, 7), Vector2(18, 14)), Color(1.0, 0.42, 0.36, 0.45))
				draw_rect(Rect2(at - Vector2(9, 7), Vector2(18, 14)), Color("ff5a4a"), false, 2.0)
			elif kind.begins_with("area:"):
				var c := Color(kind.trim_prefix("area:"))
				draw_rect(Rect2(at - Vector2(9, 7), Vector2(18, 14)), c)
				draw_rect(Rect2(at - Vector2(9, 7), Vector2(18, 14)), c.darkened(0.45), false, 1.5)
			else:
				match kind:
					"me": MapView.draw_icon_arrow(self, at, Vector2(0, -1), 0.8)
					"friend":
						draw_circle(at, 7.5, MapView.INK)
						draw_circle(at, 6.0, Color("7fd0ea"))
					"staff": MapView.draw_icon_staff(self, at, 0, false, 0.0)
					"staff_alert": MapView.draw_icon_staff(self, at, 2, false, 0.0)
					"staff_floor": MapView.draw_icon_staff(self, at, 0, true, 0.0)
					"quest": MapView.draw_icon_star(self, at, 0.9, Color("ffd24a"))
					"seat": MapView.draw_icon_seat(self, at + Vector2(0, 2), 0.8)
					"exit": MapView.draw_icon_exit(self, at, 0.8)
			draw_string(font, Vector2(34, y + 13), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e8e2d4"))
			y += 24
		custom_minimum_size.y = y + 4


const QUEST_TARGETS := {
	"samosa": "counter", "library": "return_book", "selfie": "car", "hoop": "hoop",
	"notice": "notice", "bell": "bell", "register": "register", "exam": "exam_paper",
}

var debug_camera := false
var _minimap: Control
var _mini_caption: Label
var _big: Control
var _big_map: Control
var _big_title: Label
var _big_floors: VBoxContainer
var _big_classes: Label
var _big_floor := -1  # -1 = follow the player
var _big_zoom := 1.0   # mouse wheel on the big map: 1 = whole map
var _campus: RefCounted

var _timer_label: Label
var _period_label: Label
var _mood_label: Label
var _chip: Label
var _seat_pin: Label3D
var _essay: PanelContainer
var _essay_line: Label
var _essay_edit: LineEdit
var _essay_time: Label
var _essay_shake: Tween
var _exam: Control
var _exam_key := ""
var _sus_fill: ColorRect
var _sus_value: Label
var _seen: Label
var _attendance: Label
var _pass: Label
var _banner: PanelContainer
var _banner_label: Label
var _objective: Label
var _quests: VBoxContainer
var _slots: Array[Label] = []
var _feed: VBoxContainer
var _hint: Label
var _charge: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _danger := 0.0      # smoothed vignette strength
var _beat := 0.0        # heartbeat phase
var _toast: Label
var _toast_time := 0.0
var _locker: Control
var _markers: Markers
var _board: PanelContainer
var _board_text: Label
var _end: PanelContainer
var _end_list: VBoxContainer
var _end_shown := false
var _dialog: PanelContainer
var _dialog_you: Label
var _dialog_who: Label
var _dialog_them: Label
var _dot: ColorRect
var _inv_row: Control
var _keys_line: Control
var _end_count := -1
var _style_cache := {}
var _cash_label: Label
var _slot_icons: Array[TextureRect] = []
var _ask: PanelContainer
var _mini_holder: Control
var _essay_dismissed := false  # closed the lines with Esc this detention: don't pop them up again
var _was_detention := false
# Phone (Q): a small screen on the right, the phone itself in your right hand.
var _phone: PanelContainer
var _phone_body: VBoxContainer
var _phone_scroll: ScrollContainer
var _phone_home: VBoxContainer
var _phone_header: HBoxContainer
var _phone_title: Label
var _phone_clock: Label
var _phone_sub: Label
var _phone_status: VBoxContainer  # home screen: class, what you're doing, money, friends
var _phone_time: Label
var _phone_app := -1  # -1: home screen
var _phone_tick := 0.0
# Navigate: the route to your seat, its map on the phone, and the glimpse on the floor / minimap.
var _nav_map: Control
var _nav_info: Label
var _nav_btn: Button
var _route: Array[Vector3] = []
var _route_at := -100.0      # when the route was worked out (s)
var _route_until := -100.0   # glimpse shown until (s)
var _trail: Node3D
var _floor_label: Label
var _frame: Control  # HUD panels go in here, scaled by the HUD size setting
var _floor_seen := -1
var _floor_flash := 0.0
# Heat, the round intro, style pop-ups, the spotted warning and the escape moment.
var _heat_label: Label
var _intro: PanelContainer
var _style_box: VBoxContainer
var _edge: EdgePulse
var _warn_beep := 0.0
var _escape_big: Label
var _profile_done := false
# Pappu Uncle's canteen shop.
var _shop: PanelContainer
var _shop_body: VBoxContainer
var _shop_tick := 0.0
var _dev_shop := false
# Voice: your mic's state, and the quick-shout menu (B) for anyone without one.
var _mic: Label
var _shout: PanelContainer
var _shout_until := 0.0


func _ready() -> void:
	add_to_group("hud")
	# HUD size setting: panels, cards, phone, tests... live in a frame that is scaled up.
	# Things tied to screen / 3D positions (vignette, ping markers, crosshair) stay outside.
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	get_viewport().size_changed.connect(_fit_frame)
	Settings.changed.connect(_fit_frame)
	_fit_frame()
	# Danger vignette first, so all HUD elements draw on top of it.
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = preload("res://shaders/vignette.gdshader")
	_vignette.material = _vignette_mat
	_vignette.visible = false
	add_child(_vignette)

	_markers = Markers.new()
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.85)
	dot.size = Vector2(6, 6)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = -dot.size / 2.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)
	_dot = dot

	_locker = _build_locker_overlay()
	_frame.add_child(_locker)

	_build_left_column()
	_build_meter()
	_build_banner()
	_build_inventory()

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-420, 214)
	_feed.custom_minimum_size = Vector2(400, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_feed)

	_hint = _outlined("", 22)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y -= 185  # above the item slots
	_hint.add_theme_color_override("font_color", Color("ffd24a"))
	_frame.add_child(_hint)

	var controls := _outlined("", 14)
	# The key line grows with experience: your first round only needs the basics
	# (the rest are explained when they're first useful).
	var keys_text := func():
		var k: Callable = GameInput.key_label
		var rounds := int(Network.local_info.get("rounds", 0))
		if rounds == 0:
			controls.text = "%s sprint   %s crouch   %s jump   %s interact   Click shove   %s map   Esc menu" \
					% [k.call("sprint"), k.call("crouch"), k.call("jump"), k.call("interact"), k.call("map")]
		elif rounds < 3:
			controls.text = "%s interact   Click shove   %s/%s/%s items   %s phone   %s throw paper   %s ping   %s map   Esc menu" \
					% [k.call("interact"), k.call("use_1"), k.call("use_2"), k.call("use_3"), k.call("phone"), k.call("throw"), k.call("ping"), k.call("map")]
		else:
			controls.text = "%s interact   %s/%s/%s items   %s phone   %s raise hand   %s throw paper   %s ping   %s answer for a friend   %s map   %s scores   Esc menu" \
					% [k.call("interact"), k.call("use_1"), k.call("use_2"), k.call("use_3"), k.call("phone"), k.call("raise_hand"), k.call("throw"),
					k.call("ping"), k.call("proxy"), k.call("map"), k.call("scoreboard")]
	keys_text.call()
	GameInput.rebound.connect(keys_text)
	controls.tree_exiting.connect(func(): GameInput.rebound.disconnect(keys_text))
	controls.modulate = Color(1, 1, 1, 0.75)
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	controls.position.y -= 30
	_frame.add_child(controls)
	_keys_line = controls

	_mic = _outlined("", 15)
	_mic.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_mic.position = Vector2(22, -180)
	_frame.add_child(_mic)

	_charge = _outlined("", 18)
	_charge.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_charge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_charge.position.y += 30
	_charge.add_theme_color_override("font_color", Color("ff9a3c"))
	_frame.add_child(_charge)

	_toast = _outlined("", 26)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y += 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_frame.add_child(_toast)

	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.9), 16, 20))
	_board_text = Label.new()
	_board_text.add_theme_font_size_override("font_size", 18)
	_board.add_child(_board_text)
	_board.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_board.grow_vertical = Control.GROW_DIRECTION_BOTH
	_board.visible = false
	_frame.add_child(_board)

	_edge = EdgePulse.new()
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_edge)  # screen effect: not scaled with the HUD
	move_child(_edge, 1)  # over the vignette, under everything else

	_style_box = VBoxContainer.new()
	_style_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_style_box.position += Vector2(90, -120)
	_style_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_box.add_theme_constant_override("separation", 2)
	_frame.add_child(_style_box)

	_escape_big = _outlined("", 64)
	_escape_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_escape_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_escape_big.grow_vertical = Control.GROW_DIRECTION_BOTH
	_escape_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_escape_big.position.y -= 150
	_escape_big.add_theme_color_override("font_color", Color("7fe0a0"))
	_escape_big.visible = false
	_frame.add_child(_escape_big)

	_build_dialog()
	_build_end_screen()


## Frame = the screen at 1/scale, drawn `scale` times bigger.
func _fit_frame() -> void:
	var size := int(Settings.ui_size)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hudsize="):  # dev: screenshots at a HUD size without saving it
			size = int(arg.trim_prefix("--hudsize="))
	var s: float = Settings.HUD_SCALES[clampi(size, 1, 3)]
	_frame.scale = Vector2(s, s)
	_frame.position = Vector2.ZERO
	_frame.size = get_viewport().get_visible_rect().size / s


func _build_left_column() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(20, 20)
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(column)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.72)))
	column.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var room: int = Network.local_info.classroom
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)
	var title := Label.new()
	title.text = Network.local_info.name
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	_chip = Label.new()
	_chip.text = " %s " % Network.CLASSROOMS[room]
	_chip.add_theme_stylebox_override("normal", _card(P.CLASS_COLORS[room], 6, 2))
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_chip)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_timer_label)
	_period_label = Label.new()
	_period_label.add_theme_font_size_override("font_size", 14)
	_period_label.add_theme_color_override("font_color", Color("9fd8ff"))
	box.add_child(_period_label)
	_mood_label = Label.new()
	_mood_label.add_theme_font_size_override("font_size", 14)
	_mood_label.add_theme_color_override("font_color", Color("ff9a4a"))
	box.add_child(_mood_label)
	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 15)
	_cash_label.add_theme_color_override("font_color", Color("ffd24a"))
	box.add_child(_cash_label)
	if multiplayer.is_server():
		var host := Label.new()
		if Network.online:
			host.text = "Hosting online · invite more friends from the lobby"
		else:
			host.text = "Hosting a private round"
		host.add_theme_font_size_override("font_size", 12)
		host.modulate = Color(1, 1, 1, 0.6)
		box.add_child(host)

	var qcard := PanelContainer.new()
	qcard.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.72)))
	column.add_child(qcard)
	_quests = VBoxContainer.new()
	_quests.add_theme_constant_override("separation", 4)
	qcard.add_child(_quests)


func _build_meter() -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.position = Vector2(-300, 20)
	card.custom_minimum_size = Vector2(280, 0)
	card.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.72)))
	_frame.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "SUSPICION"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_seen = Label.new()
	_seen.text = "SEEN!"
	_seen.add_theme_font_size_override("font_size", 14)
	_seen.add_theme_color_override("font_color", Color("ff5a5a"))
	head.add_child(_seen)
	_sus_value = Label.new()
	_sus_value.add_theme_font_size_override("font_size", 14)
	_sus_value.custom_minimum_size = Vector2(40, 0)
	_sus_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_sus_value)
	box.add_child(head)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.12)
	bar_bg.custom_minimum_size = Vector2(256, 14)
	box.add_child(bar_bg)
	_sus_fill = ColorRect.new()
	_sus_fill.size = Vector2(0, 14)
	bar_bg.add_child(_sus_fill)

	_attendance = Label.new()
	_attendance.add_theme_font_size_override("font_size", 15)
	box.add_child(_attendance)
	_pass = Label.new()
	_pass.add_theme_font_size_override("font_size", 15)
	_pass.add_theme_color_override("font_color", Color("9fd8ff"))
	box.add_child(_pass)
	_heat_label = Label.new()
	_heat_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_heat_label)


func _build_banner() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.position.y = 22
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(column)
	# Which floor you're on: faint, brightens for a moment when you change floors.
	_floor_label = _outlined("", 17)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.modulate.a = 0.45
	column.add_child(_floor_label)
	_banner = PanelContainer.new()
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 24)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Stay between the corner cards (they end ~410 px from each side at 1280 wide).
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_label.custom_minimum_size.x = 460
	_banner.add_child(_banner_label)
	column.add_child(_banner)
	_objective = _outlined("Sneak out of the university!", 15)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = 440
	column.add_child(_objective)


func _build_inventory() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.position = Vector2(20, -150)
	row.add_theme_constant_override("separation", 8)
	_frame.add_child(row)
	_inv_row = row
	for i in 3:
		var slot := Label.new()
		slot.custom_minimum_size = Vector2(150, 64)
		slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.autowrap_mode = TextServer.AUTOWRAP_WORD
		slot.add_theme_font_size_override("font_size", 14)
		row.add_child(slot)
		_slots.append(slot)
		var icon := TextureRect.new()
		icon.position = Vector2(6, 8)
		icon.size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		_slot_icons.append(icon)


func _build_locker_overlay() -> Control:
	# Just a line of text: the locker itself (its walls and the slotted door)
	# is real geometry you look out through, nothing is drawn over the view.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint := _outlined("Hiding...  staff who didn't see you get in will walk right past", 15)
	hint.name = "Hint"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y = 150
	hint.modulate = Color(1, 1, 1, 0.8)
	root.add_child(hint)
	return root


func _band(color: Color, l: float, r: float, t: float, b: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.anchor_left = l
	rect.anchor_right = r
	rect.anchor_top = t
	rect.anchor_bottom = b
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Subtitles while you talk to staff: your line, then their answer.
func _build_dialog() -> void:
	_dialog = PanelContainer.new()
	_dialog.add_theme_stylebox_override("panel", _card(Color(0.06, 0.06, 0.1, 0.88), 14, 18))
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialog.custom_minimum_size = Vector2(640, 0)
	_dialog.position.y -= 50  # item slots and key hints hide while it's up
	_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.visible = false
	_frame.add_child(_dialog)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_dialog.add_child(col)
	_dialog_you = Label.new()
	_dialog_you.add_theme_font_size_override("font_size", 17)
	_dialog_you.add_theme_color_override("font_color", Color("9fd8ff"))
	_dialog_you.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_dialog_you)
	_dialog_who = Label.new()
	_dialog_who.add_theme_font_size_override("font_size", 15)
	_dialog_who.add_theme_color_override("font_color", Color("ffd24a"))
	col.add_child(_dialog_who)
	_dialog_them = Label.new()
	_dialog_them.add_theme_font_size_override("font_size", 24)
	_dialog_them.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_dialog_them)
	var skip := Label.new()
	skip.add_theme_font_size_override("font_size", 12)
	skip.modulate = Color(1, 1, 1, 0.55)
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	skip.text = "[%s] or move to skip" % GameInput.key_label("interact")
	col.add_child(skip)


func _refresh_dialog(me: Node) -> void:
	var talk: Dictionary = me.talk_info() if me else {}
	_dialog.visible = not talk.is_empty()
	_dot.visible = talk.is_empty()
	_inv_row.visible = talk.is_empty()
	_keys_line.visible = talk.is_empty()
	if talk.is_empty():
		return
	_dialog_you.text = "YOU:  \"%s\"" % talk.line
	_dialog_who.text = str(talk.who).to_upper()
	_dialog_them.text = "\"%s\"" % talk.reply if talk.reply != "" else "..."


func _build_end_screen() -> void:
	_end = PanelContainer.new()
	_end.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.94), 22, 30))
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end.custom_minimum_size = Vector2(880, 0)
	_end.visible = false
	_frame.add_child(_end)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_end.add_child(box)
	var title := _outlined("FINAL BELL!", 48)
	title.add_theme_color_override("font_color", Color("ffc93c"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_end_list = VBoxContainer.new()
	_end_list.add_theme_constant_override("separation", 6)
	box.add_child(_end_list)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	if multiplayer.is_server():
		buttons.add_child(_end_button("BACK TO LOBBY", Color("ffc93c"), Network.back_to_lobby))
	else:
		var wait := Label.new()
		wait.text = "Waiting for the host..."
		buttons.add_child(wait)
	buttons.add_child(_end_button("LEAVE", Color("e7d2aa"), func(): get_tree().call_group("main", "leave_game")))


func _end_button(text: String, color: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # a stray Enter/Space mustn't end the session
	b.custom_minimum_size = Vector2(200, 50)
	var sb := _card(color, 12, 10)
	sb.border_color = color.darkened(0.35)
	sb.border_width_bottom = 6
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Color("2a1a0e"))
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	return b


# --- Maps ----------------------------------------------------------------------------------------

func setup_map(campus: RefCounted) -> void:
	_campus = campus
	_objective.text = campus.goal_text
	# Round minimap in the bottom-right corner, with a caption pill under it.
	var holder := Control.new()
	_mini_holder = holder
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.position = Vector2(-262, -292)
	holder.size = Vector2(240, 270)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(holder)
	var mask := MapView.RoundMask.new()
	mask.size = Vector2(240, 240)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(mask)
	_minimap = MapView.new()
	_minimap.size = Vector2(240, 240)
	_minimap.clip_contents = true
	_minimap.set_shapes(campus.map_shapes)
	_minimap.bounds = campus.bounds
	_minimap.outside = campus.map_outside
	_minimap.zoom = 2.6
	_minimap.label_size = 10
	_minimap.round_map = true
	_minimap.show_names = false
	_minimap.frame_color = Color(0, 0, 0, 0)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(_minimap)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.85), 10, 5))
	pill.position = Vector2(40, 238)
	pill.custom_minimum_size = Vector2(160, 0)
	holder.add_child(pill)
	_mini_caption = Label.new()
	_mini_caption.add_theme_font_size_override("font_size", 13)
	_mini_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(_mini_caption)

	# Big map: the map on the left, a side panel with floors, key and classes.
	_big = Control.new()
	_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big.visible = false
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_big)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.08, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big.add_child(shade)
	var map_frame := PanelContainer.new()
	map_frame.add_theme_stylebox_override("panel", _card(Color("2a2230"), 14, 6))
	map_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.offset_left = 32
	map_frame.offset_top = 32
	map_frame.offset_right = -312
	map_frame.offset_bottom = -32
	_big.add_child(map_frame)
	_big_map = MapView.new()
	_big_map.clip_contents = true
	_big_map.set_shapes(campus.map_shapes)
	_big_map.bounds = campus.bounds
	_big_map.outside = campus.map_outside
	_big_map.label_size = 13
	map_frame.add_child(_big_map)
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _card(Color(0.1, 0.09, 0.16, 0.96), 14, 16))
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -296
	side.offset_right = -24
	side.offset_top = 32
	side.offset_bottom = -32
	_big.add_child(side)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(col)
	_big_title = _outlined(Maps.title(campus.map_id).to_upper(), 24)
	_big_title.add_theme_color_override("font_color", Color("ffd24a"))
	col.add_child(_big_title)
	var hint := Label.new()
	var relabel := func(): hint.text = "[%s] change floor  ·  wheel to zoom  ·  [%s] close" % [GameInput.key_label("map_floor"), GameInput.key_label("map")]
	relabel.call()
	GameInput.rebound.connect(relabel)
	hint.tree_exiting.connect(func(): GameInput.rebound.disconnect(relabel))
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	col.add_child(hint)
	col.add_child(_section("FLOORS"))
	_big_floors = VBoxContainer.new()
	_big_floors.add_theme_constant_override("separation", 3)
	col.add_child(_big_floors)
	for k in campus.levels:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 14)
		_big_floors.add_child(row)
	col.add_child(_section("YOUR CLASSES"))
	_big_classes = Label.new()
	_big_classes.add_theme_font_size_override("font_size", 13)
	_big_classes.add_theme_color_override("font_color", Color("e8e2d4"))
	col.add_child(_big_classes)
	col.add_child(_section("KEY"))
	col.add_child(Legend.new())
	_big.visible = OS.get_cmdline_user_args().has("--bigmap")  # dev: screenshots
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--exam="):  # dev: --exam=0..3 opens that subject's test
			var game: Control = ExamGame.new()
			game.subject = int(arg.trim_prefix("--exam="))
			for v in OS.get_cmdline_user_args():
				if v.begins_with("--variant="):  # dev: which of the subject's papers
					game.variant = int(v.trim_prefix("--variant="))
			_frame.add_child(game)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if arg.begins_with("--phone="):  # dev: --phone=-1..6 opens the home screen / that phone app
			_phone_app = int(arg.trim_prefix("--phone="))
			toggle_phone.call_deferred()
		if arg == "--helpbot":  # dev: once escaped, send every kind of help to the other players
			get_tree().create_timer(14.0).timeout.connect(func():
				var director: Node = get_parent().get_node("Director")
				for pid in director.status:
					if int(pid) != multiplayer.get_unique_id():
						for action in ["help_answers", "prank_call", "deliver", "give"]:
							director.request.rpc_id(1, action, {"to": int(pid), "score": 80, "cash": 10})
							await get_tree().create_timer(0.5).timeout)
		if arg == "--stylepop":  # dev: style pop-ups for screenshots
			for k in 3:
				get_tree().create_timer(5.0 + k * 0.5).timeout.connect(on_effect.bind("style", Vector3.ZERO, ["CLOSE CALL|50", "SILENT|30", "SHOOK THEM OFF|60"][k]))
		if arg == "--nohud":  # dev: clean plates for trailers
			visible = false
		if arg == "--navshow":  # dev: the Navigate trail to your seat, a few seconds in
			get_tree().create_timer(5.0).timeout.connect(func(): _route_until = _now() + ROUTE_SHOW)
		if arg == "--scan":  # dev: staff tracker on, a few seconds in
			get_tree().create_timer(6.0).timeout.connect(func():
				var me: Node = get_parent().get_node("Players").get_node_or_null(str(multiplayer.get_unique_id()))
				if me:
					me.scan_staff())
		if arg == "--ask":  # dev: the raise-your-hand picker, a few seconds in
			get_tree().create_timer(6.0).timeout.connect(open_questions)
		if arg == "--shop":  # dev: the canteen shop, wherever you are
			_dev_shop = true
			open_shop.call_deferred()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("9fd8ff"))
	return l


func _input(event: InputEvent) -> void:
	if _shout_input(event):
		get_viewport().set_input_as_handled()
		return
	if _essay != null and _essay.visible and event.is_action_pressed("ui_cancel"):
		_essay_dismissed = true
		close_essay()
		get_viewport().set_input_as_handled()
		return
	if _shop != null and _shop.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close_shop()
		get_viewport().set_input_as_handled()
		return
	if _ask != null and _ask.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("raise_hand")):
		close_questions()
		get_viewport().set_input_as_handled()
		return
	if phone_open() and event.is_action_pressed("ui_cancel") and _phone_app != -1:
		_show_app(-1)
		get_viewport().set_input_as_handled()
		return
	if phone_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("phone")):
		toggle_phone()
		get_viewport().set_input_as_handled()
		return
	if _big != null and _big.visible and event.is_action_pressed("ui_cancel"):
		_big.visible = false
		get_viewport().set_input_as_handled()
		return
	if _big == null or not _big.visible or not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_big_zoom = minf(_big_zoom * 1.25, 6.0)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_big_zoom = maxf(_big_zoom / 1.25, 1.0)


func _refresh_maps(director: Node, me: Node, players: Node, npcs: Node) -> void:
	if _minimap == null or me == null:
		return
	# Not while typing lines (they contain m and f) or sitting a test.
	var keys_free: bool = not (get_viewport().gui_get_focus_owner() is LineEdit) and _exam == null and not director.round_over \
			and not phone_open() and not (_shop != null and _shop.visible) and not (_ask != null and _ask.visible)
	if keys_free and Input.is_action_just_pressed("map"):
		_big.visible = not _big.visible
		_big_floor = -1
	var here: int = _campus.level_of(me.global_position)
	if keys_free and _big.visible and Input.is_action_just_pressed("map_floor"):
		var shown: int = here if _big_floor == -1 else _big_floor
		_big_floor = (shown + 1) % _campus.levels

	var me_xz := Vector2(me.global_position.x, me.global_position.z)
	_minimap.center = me_xz
	_minimap.rot = me.rotation.y
	_minimap.level = here
	_minimap.markers = _map_markers(director, me, players, npcs, here)
	_minimap.queue_redraw()
	_mini_caption.text = _floor_name(here) + "   ·   [%s] map" % GameInput.key_label("map")
	_floor_label.visible = _campus.levels > 1 and not debug_camera
	if here != _floor_seen:
		_floor_label.text = _floor_name(here)
		_floor_flash = 2.0 if _floor_seen != -1 else 0.0
		_floor_seen = here
	_floor_flash = maxf(0.0, _floor_flash - get_process_delta_time())
	_floor_label.modulate.a = 0.45 + 0.55 * clampf(_floor_flash, 0.0, 1.0)

	if not _big.visible:
		return
	var floor_shown: int = here if _big_floor == -1 else _big_floor
	var area: Rect2 = _campus.bounds.grow(20.0).intersection(_campus.world_rect)
	var fit := minf(_big_map.size.x / area.size.x, _big_map.size.y / area.size.y)
	_big_map.zoom = fit * _big_zoom
	# Zoomed in: follow the player, but never past the edge of the map.
	var half: Vector2 = _big_map.size / _big_map.zoom / 2.0
	var want := area.get_center().lerp(me_xz, clampf(_big_zoom - 1.0, 0.0, 1.0))
	var cx := area.get_center().x if half.x * 2.0 >= area.size.x else clampf(want.x, area.position.x + half.x, area.end.x - half.x)
	var cy := area.get_center().y if half.y * 2.0 >= area.size.y else clampf(want.y, area.position.y + half.y, area.end.y - half.y)
	_big_map.center = Vector2(cx, cy)
	_big_map.level = floor_shown
	_big_map.show_names = _big_zoom > 1.6
	_big_map.markers = _map_markers(director, me, players, npcs, floor_shown, true)
	_big_map.queue_redraw()
	for k in _big_floors.get_child_count():
		var row: Label = _big_floors.get_child(_campus.levels - 1 - k)
		var lvl: int = _campus.levels - 1 - k
		var marks := []
		if lvl == here:
			marks.append("you")
		for i in _campus.classes.size():
			if _campus.level_of(Vector3(0, float(_campus.classes[i].y), 0)) == lvl:
				marks.append(Network.CLASSROOMS[i])
		row.text = ("▶ " if lvl == floor_shown else "   ") + _floor_name(lvl).capitalize() + ("   (" + ", ".join(marks) + ")" if not marks.is_empty() else "")
		row.add_theme_color_override("font_color", Color("ffd24a") if lvl == floor_shown else Color(1, 1, 1, 0.75))
	var lines := []
	var now_room: int = director.current_room(multiplayer.get_unique_id())
	for i in _campus.classes.size():
		var mine := "  ← now" if i == now_room else ""
		lines.append("%s  ·  %s%s" % [Network.CLASSROOMS[i], _floor_name(_campus.level_of(Vector3(0, float(_campus.classes[i].y), 0))).capitalize(), mine])
	_big_classes.text = "\n".join(lines)


## Period, subject and room; the seat pin; the teacher's mood; exams.
func _refresh_timetable(director: Node, me: Node, st: Dictionary, room: int, now: float) -> void:
	if me == null:
		return  # our student hasn't spawned yet (joining)
	var w: Dictionary = director.world
	var period := int(w.get("period", 0))
	var periods := int(w.get("periods", 1))
	var subject: String = director.SUBJECTS[room] if room < director.SUBJECTS.size() else ""
	var floor_txt := _floor_name(_campus.level_of(Vector3(0, float(_campus.classes[room].y), 0))).capitalize()
	var next_in := float(w.get("period_start", 0.0)) + float(w.get("period_len", 0.0)) - now
	_period_label.text = "Period %d/%d  ·  %s
%s, %s" % [period + 1, periods, subject, Network.CLASSROOMS[room], floor_txt]
	if period < periods - 1:
		_period_label.text += "\nClass change in %s" % _clock(next_in)
	_chip.text = " %s " % Network.CLASSROOMS[room]
	_chip.add_theme_stylebox_override("normal", _cached_card(P.CLASS_COLORS[room], 6, 2))
	var strikes := int(st.get("strikes", 0))
	_mood_label.visible = strikes > 0 and st.get("state", "") in ["class", "chased"]
	if strikes > 0:
		_mood_label.text = "Teacher mood: %s  (sit nicely to calm them)" % ["", "annoyed", "ANGRY", "FURIOUS"][clampi(strikes, 0, 3)]
	# Pin over your seat while you're not in it.
	var seat: Vector3 = st.get("seat", Vector3.ZERO)
	if _seat_pin == null and get_parent() is Node3D:
		_seat_pin = Label3D.new()
		_seat_pin.text = "YOUR SEAT\n▼"
		_seat_pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_seat_pin.no_depth_test = true
		_seat_pin.fixed_size = true
		_seat_pin.pixel_size = 0.0022
		_seat_pin.font_size = 34
		_seat_pin.outline_size = 12
		_seat_pin.modulate = Color("7fd0ea")
		get_parent().add_child(_seat_pin)
	if _seat_pin:
		var dist: float = me.global_position.distance_to(seat)
		_seat_pin.visible = st.get("state", "") == "class" and seat != Vector3.ZERO and dist > 0.9 and not debug_camera
		_seat_pin.position = seat + Vector3(0, 1.6 + sin(now * 3.0) * 0.08, 0)
		# Big when you're nearly there, shrinking to a small marker from afar.
		_seat_pin.pixel_size = clampf(0.0022 * 3.0 / maxf(dist, 0.1), 0.0007, 0.0022)
	# Surprise test: sit it if you're in the room when it's on.
	var r: Dictionary = director.rooms[room]
	var key := "%d:%d:%d" % [period, room, int(r.get("exam_id", 0))]
	var seated: bool = me.seated and me.global_position.distance_to(st.get("seat", Vector3.ZERO)) < 1.3
	if _exam == null and st.get("state", "") == "class" and str(st.get("exam_paper", "")) == key \
			and float(st.get("exam_deadline", -1.0)) > now + 3.0 \
			and _campus.room_of(me.global_position) == room and seated and str(st.get("exam_key", "")) != key and _exam_key != key:
		_exam_key = key
		if phone_open():
			toggle_phone()
		close_shop()
		var game: Control = ExamGame.new()
		game.subject = room
		game.cheat = bool(st.get("exam_photo", false))
		game.time_left = clampf(float(st.exam_deadline) - now - ExamGame.LOOK_OVER - 0.5, 3.0, 25.0)
		game.finished.connect(func(score: int):
			director.request.rpc_id(1, "exam", {"room": room, "id": int(r.exam_id), "score": score})
			_exam = null
			game.remove_from_group("modal_ui")
			game.visible = false
			if should_capture():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
		_frame.add_child(game)
		_exam = game
		close_questions()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Detention lines: the paper comes up by itself, ready to type into.
	var in_detention: bool = st.get("state", "") == "detention"
	if in_detention and _exam != null:
		_exam.queue_free()  # dragged out of the test: no handing it in
		_exam = null
	if in_detention and not _was_detention:
		_essay_dismissed = false
		if phone_open():
			toggle_phone()
		close_shop()
	_was_detention = in_detention
	if in_detention and not _essay_dismissed and (_essay == null or not _essay.visible) and _exam == null:
		open_essay()
	if _essay and _essay.visible:
		if st.get("state", "") != "detention":
			close_essay()
		else:
			_essay_line.text = "\"%s\"" % director.LINES[int(st.get("essay_line", 0)) % director.LINES.size()]
			_essay_time.text = "Time left: %s" % _clock(float(st.get("timer", 0.0)))


## Whether the game may grab the mouse: nothing modal open, not paused, round on.
func should_capture() -> bool:
	var world := get_parent()
	var director: Node = world.get_node_or_null("Director") if world else null
	if director and director.round_over:
		return false
	for n in get_tree().get_nodes_in_group("pause_menu"):
		if is_instance_valid(n) and n.is_visible_in_tree():
			return false
	return not _modal_open()


func _modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("modal_ui"):
		if is_instance_valid(n) and n.is_visible_in_tree():
			return true
	return false


## Detention desk: copy the line exactly to knock 5 s off.
func open_essay() -> void:
	var world := get_parent()
	var director: Node = world.get_node_or_null("Director") if world else null
	if director == null or director.status.get(multiplayer.get_unique_id(), {}).get("state", "") != "detention":
		toast("Only for students in detention.", Color("ffb37a"))
		return
	if _essay == null:
		_essay = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("f4ecd8")
		sb.border_color = Color("8a5a3a")
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(22)
		_essay.add_theme_stylebox_override("panel", sb)
		_essay.custom_minimum_size = Vector2(560, 250)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_essay.set_anchor(side, 0.5)
		_essay.offset_left = -280
		_essay.offset_right = 280
		_essay.offset_top = -125
		_essay.offset_bottom = 125
		_essay.add_to_group("modal_ui")
		_frame.add_child(_essay)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		_essay.add_child(col)
		var title := Label.new()
		title.text = "WRITE YOUR LINES  ·  copy it exactly, press Enter"
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color("8a2a3a"))
		col.add_child(title)
		_essay_line = Label.new()
		_essay_line.add_theme_font_size_override("font_size", 26)
		_essay_line.add_theme_color_override("font_color", Color("2a1a0e"))
		col.add_child(_essay_line)
		_essay_edit = LineEdit.new()
		_essay_edit.custom_minimum_size = Vector2(500, 44)
		_essay_edit.add_theme_font_size_override("font_size", 20)
		_essay_edit.placeholder_text = "Start typing the line..."
		_essay_edit.keep_editing_on_text_submit = true  # Enter sends it, and you type the next one straight away
		_essay_edit.text_submitted.connect(func(text: String):
			if text.strip_edges() == "":
				return
			var st: Dictionary = director.status.get(multiplayer.get_unique_id(), {})
			var want: String = director.LINES[int(st.get("essay_line", 0)) % director.LINES.size()]
			if not director.essay_matches(text, want):
				_essay_wrong()
				return
			director.request.rpc_id(1, "essay", {"text": text})
			_essay_edit.clear()
			_essay_edit.edit())
		col.add_child(_essay_edit)
		_essay_time = Label.new()
		_essay_time.add_theme_font_size_override("font_size", 15)
		_essay_time.add_theme_color_override("font_color", Color("5a3a22"))
		col.add_child(_essay_time)
		var hint := Label.new()
		hint.text = "Just type, Enter to hand it in. Each correct line: -5 s.   Esc: stop writing"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1, 0.7))
		col.add_child(hint)
	_essay.visible = true
	_essay_dismissed = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_essay_edit.grab_focus()
	_essay_edit.edit()
	if OS.get_cmdline_user_args().has("--typebot") and not has_meta("typebot"):
		set_meta("typebot", true)
		_dev_type_lines(director)


## Dev: types the detention lines with real key presses (no clicks, no extra Enter).
func _dev_type_lines(director: Node) -> void:
	for n in 3:
		await get_tree().create_timer(0.5).timeout
		if _essay == null or not _essay.visible:
			return
		var st: Dictionary = director.status.get(multiplayer.get_unique_id(), {})
		var line: String = director.LINES[int(st.get("essay_line", 0)) % director.LINES.size()]
		if n == 0 and OS.get_cmdline_user_args().has("--typebot-wrong"):
			line = "I will bunk every class"  # dev: a wrong line first (red flash + shake)
		for ch in line:
			var ev := InputEventKey.new()
			ev.pressed = true
			ev.unicode = ch.unicode_at(0)
			Input.parse_input_event(ev)
			await get_tree().process_frame
		print("[typebot] typed: %s | field: %s" % [line, _essay_edit.text])
		var enter := InputEventKey.new()
		enter.pressed = true
		enter.keycode = KEY_ENTER
		enter.physical_keycode = KEY_ENTER
		Input.parse_input_event(enter)
		await get_tree().create_timer(1.0).timeout


## Wrong line: the text flashes red, the paper shakes, then the line is wiped.
func _essay_wrong() -> void:
	if _essay_shake and _essay_shake.is_valid():
		_essay_shake.kill()
	Sfx.play("deny", -6.0)
	if OS.get_cmdline_user_args().has("--typebot"):
		print("[typebot] wrong line: %s" % _essay_edit.text)
	_essay_edit.add_theme_color_override("font_color", Color("d42a2a"))
	var shift := func(v: float) -> void:
		_essay.offset_left = -280.0 + v
		_essay.offset_right = 280.0 + v
	_essay_shake = create_tween()
	for k in 6:
		_essay_shake.tween_method(shift, 0.0 if k == 0 else (10.0 if k % 2 == 1 else -10.0), 10.0 if k % 2 == 0 else -10.0, 0.04)
	_essay_shake.tween_method(shift, -10.0, 0.0, 0.04)
	_essay_shake.tween_callback(func():
		_essay_edit.clear()
		_essay_edit.remove_theme_color_override("font_color")
		_essay_edit.edit())


func close_essay() -> void:
	if _essay:
		_essay.visible = false
	if should_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Raise your hand ---------------------------------------------------------------------------

func open_questions() -> void:
	var world := get_parent()
	var director: Node = world.get_node_or_null("Director") if world else null
	var me: Node = world.get_node("Players").get_node_or_null(str(multiplayer.get_unique_id())) if world else null
	if director == null or me == null or director.round_over or _exam != null:
		return
	var st: Dictionary = director.status.get(multiplayer.get_unique_id(), {})
	var room: int = director.current_room(multiplayer.get_unique_id())
	if st.get("state", "") != "class" or _campus.room_of(me.global_position) != room:
		toast("Raise your hand in your own class.", Color("ffb37a"))
		return
	if _ask == null:
		_ask = PanelContainer.new()
		_ask.add_theme_stylebox_override("panel", _card(Color(0.07, 0.07, 0.12, 0.95), 16, 18))
		_ask.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_ask.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_ask.grow_vertical = Control.GROW_DIRECTION_BOTH
		_ask.custom_minimum_size = Vector2(640, 0)
		# A little right of centre: clear of the side-quest card on the left.
		_ask.offset_left = 72
		_ask.offset_right = 72
		_ask.add_to_group("modal_ui")
		_frame.add_child(_ask)
	for c in _ask.get_children():
		_ask.remove_child(c)
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_ask.add_child(col)
	var title := _outlined("RAISE YOUR HAND  ·  %s" % str(director.SUBJECTS[room]).to_upper(), 22)
	title.add_theme_color_override("font_color", Color("ffd24a"))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Smart questions win the teacher over. Mischievous ones send them ranting at the board (everyone's chance to sneak out!), but they might see through it."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 600
	sub.add_theme_font_size_override("font_size", 13)
	sub.modulate = Color(1, 1, 1, 0.7)
	col.add_child(sub)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for q in Questions.pick(room, rng):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var tag := Label.new()
		tag.text = Questions.KINDS[q.kind]
		tag.custom_minimum_size = Vector2(118, 0)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", Color("2a1a0e"))
		tag.add_theme_stylebox_override("normal", _cached_card(Questions.KIND_COLORS[q.kind], 8, 4))
		row.add_child(tag)
		var b := Button.new()
		b.text = str(q.q)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", _cached_card(Color(1, 1, 1, 0.08), 8, 8))
		b.add_theme_stylebox_override("hover", _cached_card(Color(1, 1, 1, 0.2), 8, 8))
		b.add_theme_stylebox_override("pressed", _cached_card(Color(1, 1, 1, 0.25), 8, 8))
		var kind: int = q.kind
		var text: String = q.q
		b.pressed.connect(func():
			close_questions()
			me.ask(kind, text))
		row.add_child(b)
	var hint := Label.new()
	hint.text = "[%s] or Esc: put your hand down" % GameInput.key_label("raise_hand")
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.55)
	col.add_child(hint)
	if phone_open():
		toggle_phone()
	_ask.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_questions() -> void:
	if _ask == null or not _ask.visible:
		return
	_ask.visible = false
	if should_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Voice --------------------------------------------------------------------------------------

## Bottom-left: is your mic live, and how far could a teacher hear you right now?
func _refresh_mic(st: Dictionary) -> void:
	var mode := int(Settings.voice_mode)
	var hear := bool(Network.round_rules.get("hear", true)) and str(st.get("state", "")) in ["class", "chased"]
	var shout_key := GameInput.key_label("shout")
	if mode == Settings.VoiceMode.OFF or not Voice.mic_ok:
		_mic.text = "%s   [%s] quick shout" % ["Mic off" if Voice.mic_ok else "No mic", shout_key]
		_mic.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		return
	if Voice.transmitting:
		var r: float = preload("res://scenes/world/director.gd").voice_radius(Voice.level)
		var bars := clampi(int(r / 2.0), 1, 8)
		var warn := ""
		if hear:
			warn = "   staff hear you ~%d m" % int(round(r)) if r >= 4.0 else "   whisper: safe"
		_mic.text = "● TALKING  %s%s" % ["|".repeat(bars), warn]
		_mic.add_theme_color_override("font_color", Color("ff6a5a") if hear and r >= 4.0 else Color("7fe0a0"))
	elif mode == Settings.VoiceMode.PUSH_TO_TALK:
		_mic.text = "[%s] push to talk   [%s] quick shout" % [GameInput.key_label("push_to_talk"), shout_key]
		_mic.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	else:
		_mic.text = "Mic on (open)   [%s] quick shout" % shout_key
		_mic.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))


## Quick shout (B, then 1-4): no mic needed. Returns true if it used the event.
func _shout_input(event: InputEvent) -> bool:
	var open := _shout != null and _shout.visible
	if open and _now() > _shout_until:
		_shout.visible = false
		open = false
	if not open:
		if event.is_action_pressed("shout") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and not (get_viewport().gui_get_focus_owner() is LineEdit):
			_open_shout()
			return true
		return false
	if event.is_action_pressed("shout") or event.is_action_pressed("ui_cancel"):
		_shout.visible = false
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode - KEY_1
		if k >= 0 and k < 4:
			var director: Node = get_parent().get_node_or_null("Director")
			if director:
				director.request.rpc_id(1, "shout", {"k": k})
			_shout.visible = false
			return true
	return false


func _open_shout() -> void:
	if _shout == null:
		_shout = PanelContainer.new()
		_shout.add_theme_stylebox_override("panel", _card(Color(0.07, 0.07, 0.12, 0.92), 14, 12))
		_shout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_shout.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_shout.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_shout.position.y -= 230
		_shout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(_shout)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_shout.add_child(row)
		var list: Array = preload("res://scenes/world/director.gd").SHOUT_LIST
		for k in list.size():
			var l := Label.new()
			l.text = "[%d] %s" % [k + 1, list[k][0]]
			l.add_theme_font_size_override("font_size", 20)
			l.add_theme_color_override("font_color", Color("ffd24a") if k > 0 else Color("9fd8ff"))
			row.add_child(l)
	_shout.visible = true
	_shout_until = _now() + 3.0


# --- Phone ---------------------------------------------------------------------------------

func phone_open() -> bool:
	return _phone != null and _phone.visible


## Phone out / away. While it's out the mouse taps its screen; you can still walk.
func toggle_phone() -> void:
	var world := get_parent()
	var director: Node = world.get_node_or_null("Director") if world else null
	if _phone == null:
		_build_phone()
	if _phone.visible:
		_phone.visible = false
		if _mini_holder:
			_mini_holder.visible = true
		if should_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if director == null or director.round_over or _exam != null:
		return
	_phone.visible = true
	if _mini_holder:
		_mini_holder.visible = false
	_show_app(_phone_app)
	Sfx.play("click", -6.0, 1.3)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_phone() -> void:
	_phone = PanelContainer.new()
	var bezel := _card(Color("15161c"), 26, 12)
	bezel.border_color = Color("3a3d4a")
	bezel.set_border_width_all(4)
	_phone.add_theme_stylebox_override("panel", bezel)
	_phone.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_phone.offset_left = -348
	_phone.offset_right = -28
	_phone.offset_top = -560
	_phone.offset_bottom = -40
	_phone.add_to_group("modal_ui")
	_phone.visible = false
	_frame.add_child(_phone)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _card(Color("1f2a3a"), 16, 12))
	_phone.add_child(screen)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	screen.add_child(col)
	var status_bar := HBoxContainer.new()
	var carrier := Label.new()
	carrier.text = "BunkFone"
	carrier.add_theme_font_size_override("font_size", 12)
	carrier.modulate = Color(1, 1, 1, 0.6)
	carrier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(carrier)
	_phone_time = Label.new()
	_phone_time.add_theme_font_size_override("font_size", 12)
	_phone_time.modulate = Color(1, 1, 1, 0.8)
	_phone_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_bar.add_child(_phone_time)
	var close := Label.new()
	close.text = "[%s] put away" % GameInput.key_label("phone")
	close.add_theme_font_size_override("font_size", 12)
	close.modulate = Color(1, 1, 1, 0.6)
	status_bar.add_child(close)
	col.add_child(status_bar)

	# Home screen: the time left, then a grid of app tiles.
	_phone_home = VBoxContainer.new()
	_phone_home.add_theme_constant_override("separation", 6)
	_phone_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_phone_home)
	_phone_clock = Label.new()
	_phone_clock.add_theme_font_size_override("font_size", 34)
	_phone_clock.add_theme_color_override("font_color", Color("ffd24a"))
	_phone_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_home.add_child(_phone_clock)
	_phone_sub = Label.new()
	_phone_sub.add_theme_font_size_override("font_size", 12)
	_phone_sub.modulate = Color(1, 1, 1, 0.65)
	_phone_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phone_sub.custom_minimum_size.x = 260
	_phone_home.add_child(_phone_sub)
	_phone_status = VBoxContainer.new()
	_phone_status.add_theme_constant_override("separation", 2)
	_phone_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_phone_home.add_child(_phone_status)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	_phone_home.add_child(grid)
	for k in PHONE_APPS.size():
		grid.add_child(_app_tile(k))

	# An open app: a title bar with a back arrow, then its page.
	_phone_header = HBoxContainer.new()
	_phone_header.add_theme_constant_override("separation", 8)
	col.add_child(_phone_header)
	var back := _phone_button("◀ Home", _show_app.bind(-1), Color(1, 1, 1, 0.85))
	back.add_theme_font_size_override("font_size", 12)
	_phone_header.add_child(back)
	_phone_title = Label.new()
	_phone_title.add_theme_font_size_override("font_size", 16)
	_phone_title.add_theme_color_override("font_color", Color("ffd24a"))
	_phone_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_phone_header.add_child(_phone_title)
	_phone_scroll = ScrollContainer.new()
	_phone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_phone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_phone_scroll)
	_phone_body = VBoxContainer.new()
	_phone_body.add_theme_constant_override("separation", 6)
	_phone_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_scroll.add_child(_phone_body)


## A home-screen tile: a coloured rounded square with the app's glyph, its name under it.
func _app_tile(k: int) -> Button:
	var app: Dictionary = PHONE_APPS[k]
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = Vector2(82, 86)
	tile.tooltip_text = app.name
	tile.add_theme_stylebox_override("normal", _cached_card(Color(1, 1, 1, 0.0), 14, 4))
	tile.add_theme_stylebox_override("hover", _cached_card(Color(1, 1, 1, 0.1), 14, 4))
	tile.add_theme_stylebox_override("pressed", _cached_card(Color(1, 1, 1, 0.18), 14, 4))
	tile.pressed.connect(func():
		Sfx.play("click", -8.0, 1.5)
		_show_app(k))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var square := PanelContainer.new()
	square.add_theme_stylebox_override("panel", _cached_card(app.color, 14, 0))
	square.custom_minimum_size = Vector2(54, 54)
	square.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(square)
	var icon := AppIcon.new()
	icon.kind = app.icon
	icon.custom_minimum_size = Vector2(54, 54)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square.add_child(icon)
	var caption := Label.new()
	caption.text = app.name
	caption.add_theme_font_size_override("font_size", 12)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(caption)
	return tile


## Opens an app (-1: the home screen).
func _show_app(k: int) -> void:
	_phone_app = clampi(k, -1, PHONE_APPS.size() - 1)
	var home := _phone_app == -1
	_phone_home.visible = home
	_phone_header.visible = not home
	_phone_scroll.visible = not home
	for child in _phone_body.get_children():
		_phone_body.remove_child(child)
		child.queue_free()
	_nav_map = null
	if not home:
		_phone_title.text = str(PHONE_APPS[_phone_app].name).to_upper()
		_phone_title.add_theme_color_override("font_color", PHONE_APPS[_phone_app].color)
		_phone_scroll.scroll_vertical = 0
		if _phone_app == NAV_APP:
			_build_navigate()
	_phone_tick = 0.0  # redraw now


## Rebuilds the open app a few times a second (it shows live timers and money).
func _refresh_phone(director: Node, me: Node, st: Dictionary, delta: float) -> void:
	if not phone_open():
		return
	if director.round_over:
		toggle_phone()
		return
	_phone_tick -= delta
	if _phone_tick > 0.0:
		return
	_phone_tick = 0.25
	var left: float = director.round_time - director.elapsed
	_phone_time.text = _clock(left)
	if _phone_app == -1:
		_phone_clock.text = _clock(left)
		_phone_sub.text = "until the final bell"
		_fill_home(director, st)
		return
	if _phone_app == NAV_APP:
		_refresh_navigate(director, me, st)
		return
	for child in _phone_body.get_children():
		_phone_body.remove_child(child)
		child.queue_free()
	if _phone_app == HELP_APP:
		_app_help(director, me, st)


func _phone_text(text: String, size_px := 14, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 250
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	_phone_body.add_child(l)
	return l


func _phone_button(text: String, handler: Callable, color := Color("7fd0ea"), enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", _cached_card(color if enabled else Color(1, 1, 1, 0.12), 8, 6))
	b.add_theme_stylebox_override("hover", _cached_card(color.lightened(0.2), 8, 6))
	b.add_theme_stylebox_override("pressed", _cached_card(color.lightened(0.2), 8, 6))
	b.add_theme_stylebox_override("disabled", _cached_card(Color(1, 1, 1, 0.12), 8, 6))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Color("2a1a0e"))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.pressed.connect(handler)
	return b


func _home_line(text: String, size_px := 14, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 262
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	_phone_status.add_child(l)


## The home screen, at a glance: where's my class, what am I doing, my money, my friends.
func _fill_home(director: Node, st: Dictionary) -> void:
	for c in _phone_status.get_children():
		_phone_status.remove_child(c)
		c.queue_free()
	var id := multiplayer.get_unique_id()
	var now: float = director.elapsed
	var room: int = director.current_room(id)
	var floor_txt := _floor_name(_campus.level_of(Vector3(0, float(_campus.classes[room].y), 0))).capitalize()
	var r: Dictionary = director.rooms[room] if room < director.rooms.size() else {}
	_home_line("CLASS", 11, Color("9fd8ff"))
	match str(st.get("state", "")):
		"escaped":
			_home_line("You're OUT! Open Help Out and be mission control.", 14, Color("7fe0a0"))
		"detention":
			_home_line("In detention: %s left. Friends can get you out." % _clock(float(st.get("timer", 0.0))), 14, Color("ff9a4a"))
		_:
			_home_line("%s  ·  %s, %s" % [director.SUBJECTS[room], Network.CLASSROOMS[room], floor_txt], 15)
			var teacher: String = director.teacher_line(room)
			if teacher != "":
				_home_line(teacher, 12, Color("ffb37a"))
			var when := []
			if r.get("calling", false):
				when.append("ATTENDANCE NOW")
			elif float(r.get("attendance_in", 99999.0)) < 9000.0:
				when.append("attendance in %s" % _clock(maxf(0.0, float(r.attendance_in))))
			if float(r.get("exam_until", -100.0)) > now:
				when.append("TEST NOW")
			elif float(r.get("exam_at", 99999.0)) < 90000.0:
				when.append("test in %s" % _clock(float(r.exam_at) - now))
			if not when.is_empty():
				_home_line(" · ".join(when), 12, Color("ffd24a"))
	_home_line("DOING", 11, Color("9fd8ff"))
	var doing := "Quest chain done: walk out a gate!"
	for q in st.get("quests", []):
		if not q.done:
			doing = str(preload("res://scenes/world/director.gd").QUESTS.get(q.id, q.id))
			break
	_home_line(doing, 13)
	var items := []
	for item in st.get("items", []):
		items.append(str(director.ITEMS.get(item, item)))
	_home_line("Rs %d%s" % [int(st.get("cash", 0)), ("  ·  " + ", ".join(items)) if not items.is_empty() else ""], 14, Color("ffd24a"))
	var players := get_parent().get_node_or_null("Players")
	var friends := []
	for pid in director.status:
		if int(pid) == id:
			continue
		var ft: Dictionary = director.status[pid]
		var who := str(Network.players.get(int(pid), {}).get("name", "Friend"))
		var node: Node3D = players.get_node_or_null(str(pid)) if players else null
		var where := ""
		match str(ft.state):
			"escaped": where = "OUT"
			"detention": where = "in DETENTION"
			"chased": where = "being CHASED"
			_:
				if node:
					where = _floor_name(_campus.level_of(node.global_position)).capitalize()
					var place: String = _campus.place_name(node.global_position)
					if place != "":
						where = "%s, %s" % [place, where]
		friends.append("%s: %s" % [who, where])
	if not friends.is_empty():
		_home_line("FRIENDS", 11, Color("9fd8ff"))
		for f in friends.slice(0, 5):
			_home_line(f, 12, Color("7fd0ea"))


# --- Phone: Help Out (after you escape) ----------------------------------------------------------

func _app_help(director: Node, me_node: Node, st: Dictionary) -> void:
	_phone_text("MISSION CONTROL", 15, Color("5fd3c5"))
	if st.get("state", "") != "escaped":
		_phone_text("Escape the university first. From outside you run mission control: text friends their test answers, prank-call the staff chasing them, send money and samosas, and track the staff.", 12, Color(1, 1, 1, 0.65))
		return
	_phone_text("Each help: +%d points. Answers: once per friend per period." % director.ASSIST_POINTS, 12, Color(1, 1, 1, 0.6))
	_phone_body.add_child(_phone_button("Ring the bell at the gate", func(): director.request.rpc_id(1, "outside_bell", {}), Color("ffd24a")))
	_phone_text("Calls the nearest staff out to the gate, away from their posts.", 11, Color(1, 1, 1, 0.55))
	if me_node:
		var now_s := _now()
		var scan_txt := "Track the staff (5 s)"
		if now_s < me_node.phone_until:
			scan_txt = "Tracking staff...  %ds" % int(ceil(me_node.phone_until - now_s))
		elif now_s < me_node.phone_ready:
			scan_txt = "Tracker recharging  %ds" % int(ceil(me_node.phone_ready - now_s))
		_phone_body.add_child(_phone_button(scan_txt, func(): me_node.scan_staff(), Color("ff8aa8"), now_s >= me_node.phone_ready))
	var me := multiplayer.get_unique_id()
	var any := false
	for pid in director.status:
		var id := int(pid)
		if id == me:
			continue
		any = true
		var ft: Dictionary = director.status[pid]
		var who := str(Network.players.get(id, {}).get("name", "Friend"))
		var room: int = director.current_room(id)
		var r: Dictionary = director.rooms[room] if room < director.rooms.size() else {}
		var now: float = director.elapsed
		var line := ""
		match str(ft.state):
			"escaped": line = "Out already. Legend."
			"detention": line = "In DETENTION (%s)" % _clock(float(ft.timer))
			"chased": line = "Being CHASED!"
			_:
				var key := "%d:%d:%d" % [int(director.world.period), room, int(r.get("exam_id", 0))]
				if str(ft.get("exam_key", "")) == key:
					line = "%s · test done" % Network.CLASSROOMS[room]
				elif float(r.get("exam_until", -100.0)) > now:
					line = "%s · TEST NOW!" % Network.CLASSROOMS[room]
				elif float(r.get("exam_at", 99999.0)) < 90000.0:
					line = "%s · test in %s" % [Network.CLASSROOMS[room], _clock(float(r.exam_at) - now)]
				else:
					line = "%s · in class" % Network.CLASSROOMS[room]
		_phone_text("\n%s" % who, 16, Color("7fd0ea"))
		_phone_text(line, 12, Color("ff6a6a") if ft.state == "chased" else Color(1, 1, 1, 0.75))
		var inside: bool = str(ft.state) in ["class", "chased"]
		if not inside:
			continue
		var sent: bool = (st.get("helped", {}) as Dictionary).has("%d:%d" % [id, int(director.world.period)])
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_phone_body.add_child(grid)
		grid.add_child(_phone_button("Answers sent" if sent else "Text answers", _open_help_exam.bind(director, id, room),
			Color("5fd3c5"), not sent and _exam == null))
		grid.add_child(_phone_button("Prank call", func(): director.request.rpc_id(1, "prank_call", {"to": id}), Color("ff8aa8")))
		grid.add_child(_phone_button("Send Rs 10", func(): director.request.rpc_id(1, "give", {"to": id, "cash": 10}),
			Color("ffd24a"), int(st.get("cash", 0)) >= 10))
		grid.add_child(_phone_button("Samosa Rs %d" % director.DELIVERY_PRICE, func(): director.request.rpc_id(1, "deliver", {"to": id}),
			Color("e0a050"), int(st.get("cash", 0)) >= director.DELIVERY_PRICE))
		var watching: bool = me_node != null and int(me_node.get("spectating")) == id
		_phone_body.add_child(_phone_button("Stop watching" if watching else "Watch %s" % who,
			func(): if me_node: me_node.spectate(-1 if watching else id), Color("b07cff")))
	if not any:
		_phone_text("\nNobody else in this session.", 13, Color(1, 1, 1, 0.5))


## Texting answers: you sit your friend's test on the phone; they get your score as a safety net.
func _open_help_exam(director: Node, to: int, room: int) -> void:
	if _exam != null:
		return
	if phone_open():
		toggle_phone()
	var game: Control = ExamGame.new()
	game.subject = room
	game.time_left = 25.0
	game.finished.connect(func(score: int):
		director.request.rpc_id(1, "help_answers", {"to": to, "score": score})
		_exam = null
		game.remove_from_group("modal_ui")
		game.visible = false
		game.queue_free()
		if should_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_frame.add_child(game)
	_exam = game
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Phone: Navigate --------------------------------------------------------------------------------

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Where Navigate leads: your seat in this period's classroom (or the room itself).
func _nav_target(director: Node, st: Dictionary) -> Vector3:
	var seat: Vector3 = st.get("seat", Vector3.ZERO)
	if seat != Vector3.ZERO:
		return seat
	var room: int = director.current_room(multiplayer.get_unique_id())
	if room < _campus.classes.size():
		var r: Rect2 = _campus.classes[room].rect
		return Vector3(r.get_center().x, float(_campus.classes[room].y), r.get_center().y)
	return Vector3.ZERO


func _build_navigate() -> void:
	_nav_info = _phone_text("Finding the way...", 13)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _cached_card(Color("0f1520"), 10, 3))
	_phone_body.add_child(frame)
	_nav_map = MapView.new()
	_nav_map.custom_minimum_size = Vector2(262, 220)
	_nav_map.clip_contents = true
	_nav_map.set_shapes(_campus.map_shapes)
	_nav_map.bounds = _campus.bounds
	_nav_map.outside = _campus.map_outside
	_nav_map.label_size = 9
	_nav_map.show_names = false
	_nav_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_nav_map)
	_nav_btn = _phone_button("SHOW ME THE WAY", func():
		_route_at = -100.0  # work it out again from where you stand now
		_route_until = _now() + ROUTE_SHOW
		_phone_tick = 0.0
		Sfx.play("click", -6.0, 1.8), Color("b07cff"))
	_phone_body.add_child(_nav_btn)
	_phone_text("Lights the way on the floor and on your minimap for %d s." % int(ROUTE_SHOW), 11, Color(1, 1, 1, 0.55))
	_route_at = -100.0


func _refresh_navigate(director: Node, me: Node, st: Dictionary) -> void:
	if _nav_map == null or me == null:
		return
	if st.get("state", "") in ["detention", "escaped"]:
		_nav_info.text = "You're in detention. Finish it first!" if st.state == "detention" \
				else "You're OUT! No seat to get back to.\nTrack the staff, ping, or throw paper balls over the wall to help friends still inside."
		_nav_map.route = []
		_nav_map.queue_redraw()
		return
	var target := _nav_target(director, st)
	var room: int = director.current_room(multiplayer.get_unique_id())
	var here: int = _campus.level_of(me.global_position)
	var there: int = _campus.level_of(target)
	var length := 0.0
	for i in _route.size() - 1:
		length += _route[i].distance_to(_route[i + 1])
	var where := "%s, %s" % [Network.CLASSROOMS[room], _floor_name(there).capitalize()]
	if me.seated and me.global_position.distance_to(target) < 1.3:
		_nav_info.text = "YOUR SEAT: %s\nYou're sitting in it. Nice." % where
	else:
		var how := "Follow the purple line."
		if there > here:
			how = "Take the stairs UP to the %s." % _floor_name(there).capitalize()
		elif there < here:
			how = "Take the stairs DOWN to the %s." % _floor_name(there).capitalize()
		_nav_info.text = "YOUR SEAT: %s\nAbout %d m.  %s" % [where, int(round(length)), how]
	# Fit the whole route on the little map.
	var box := Rect2(Vector2(me.global_position.x, me.global_position.z), Vector2.ZERO)
	for p in _route:
		box = box.expand(Vector2(p.x, p.z))
	box = box.expand(Vector2(target.x, target.z)).grow(8.0)
	var map_size: Vector2 = _nav_map.size if _nav_map.size.x > 10.0 else _nav_map.custom_minimum_size
	_nav_map.center = box.get_center()
	_nav_map.zoom = clampf(minf(map_size.x / box.size.x, map_size.y / box.size.y), 0.6, 5.0)
	_nav_map.level = here
	_nav_map.route = _route_segments(here)
	_nav_map.markers = [
		{"at": Vector2(target.x, target.z), "kind": "seat", "text": ""},
		{"at": Vector2(me.global_position.x, me.global_position.z), "kind": "me", "yaw": me.rotation.y},
	]
	_nav_map.queue_redraw()
	var left := _route_until - _now()
	_nav_btn.text = "SHOWING THE WAY  %ds" % int(ceil(left)) if left > 0.0 else "SHOW ME THE WAY"


## Route as map segments: [from, to, on floor `level`].
func _route_segments(level: int) -> Array:
	var out := []
	for i in _route.size() - 1:
		var a := _route[i]
		var b := _route[i + 1]
		out.append([Vector2(a.x, a.z), Vector2(b.x, b.z), _campus.level_of(a) == level and _campus.level_of(b) == level])
	return out


## Every frame: keeps the route fresh while Navigate is open, and shows the
## glimpse (a trail of glowing arrows on the floor + the line on the minimap).
func _update_route(director: Node, me: Node, st: Dictionary) -> void:
	var now := _now()
	var nav_open := phone_open() and _phone_app == NAV_APP
	var showing := now < _route_until
	if me == null or (not nav_open and not showing) or st.get("state", "") in ["escaped", "detention"]:
		if _trail:
			_trail.queue_free()
			_trail = null
		if not _route.is_empty():
			_route = []
			_minimap.route = []
			_big_map.route = []
		return
	# Recompute every 2 s while the app is open; the glimpse keeps the route it started with.
	var fresh := now - _route_at > 2.0 and (nav_open or _trail == null)
	if fresh:
		var target := _nav_target(director, st)
		_route = [] if target == Vector3.ZERO else director.route_to(me.global_position, target)
		_route_at = now
		_phone_tick = 0.0
	if showing and (_trail == null or fresh):
		_build_trail()
	if not showing and _trail:
		_trail.queue_free()
		_trail = null
	var here: int = _campus.level_of(me.global_position)
	_minimap.route = _route_segments(here) if showing else []
	_big_map.route = _route_segments(_big_map.level) if showing else []
	if _trail:
		var mm: MultiMesh = (_trail.get_child(0) as MultiMeshInstance3D).multimesh
		var age: float = now - float(_trail.get_meta("born"))
		mm.visible_instance_count = mini(mm.instance_count, int(age * 70.0) + 1)  # sweeps out from you
		var mat: StandardMaterial3D = _trail.get_meta("mat")
		mat.albedo_color.a = clampf(age / 0.3, 0.0, 1.0) * clampf((_route_until - now) / 1.5, 0.0, 1.0) * 0.9


## Arrows every metre along the route, just above the floor, pointing the way.
func _build_trail() -> void:
	if _trail:
		_trail.queue_free()
		_trail = null
	if _route.size() < 2 or not (get_parent() is Node3D):
		return
	var xforms: Array[Transform3D] = []
	var carry := 0.6  # start a little ahead of your feet
	for i in _route.size() - 1:
		var a := _route[i]
		var b := _route[i + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		var flat := Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.RIGHT, PI / 2.0)
		var d := carry
		while d < length:
			xforms.append(Transform3D(flat, a + dir * d + Vector3(0, 0.1, 0)))
			d += 1.0
		carry = d - length
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.36, 0.42, 0.04)  # a flat triangle: its tip points along the route
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(MapView.ROUTE, 0.0)
	mat.no_depth_test = false
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail = Node3D.new()
	_trail.name = "RouteTrail"
	_trail.set_meta("born", _now())
	_trail.set_meta("mat", mat)
	_trail.add_child(inst)
	(get_parent() as Node3D).add_child(_trail)


# --- Canteen shop ----------------------------------------------------------------------------

func open_shop() -> void:
	var world := get_parent()
	var director: Node = world.get_node_or_null("Director") if world else null
	if director == null or director.round_over:
		return
	if phone_open():
		toggle_phone()
	if _shop == null:
		_shop = PanelContainer.new()
		var sb := _card(Color("fbf1dc"), 18, 20)
		sb.border_color = Color("c4492f")
		sb.set_border_width_all(6)
		_shop.add_theme_stylebox_override("panel", sb)
		_shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_shop.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_shop.grow_vertical = Control.GROW_DIRECTION_BOTH
		_shop.custom_minimum_size = Vector2(560, 0)
		_shop.add_to_group("modal_ui")
		_frame.add_child(_shop)
		_shop_body = VBoxContainer.new()
		_shop_body.add_theme_constant_override("separation", 8)
		_shop.add_child(_shop_body)
	_shop.visible = true
	_shop_tick = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_shop() -> void:
	if _shop == null or not _shop.visible:
		return
	_shop.visible = false
	if should_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_shop(director: Node, me: Node, st: Dictionary, delta: float) -> void:
	if _shop == null or not _shop.visible:
		return
	# Walked off (or got dragged off to detention): the shop closes.
	var counter := {}
	for it in _campus.interactables:
		if it.kind == "counter":
			counter = it
	var far: bool = me == null or counter.is_empty() or me.global_position.distance_to(counter.pos) > 4.0
	if (far and not _dev_shop) or st.get("state", "") not in ["class", "chased"]:
		close_shop()
		return
	_shop_tick -= delta
	if _shop_tick > 0.0:
		return
	_shop_tick = 0.3
	for child in _shop_body.get_children():
		_shop_body.remove_child(child)
		child.queue_free()
	var ink := Color("2a1a0e")
	var title := Label.new()
	title.text = "PAPPU UNCLE'S CANTEEN"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("c4492f"))
	_shop_body.add_child(title)
	var cash := int(st.get("cash", 0))
	var wallet := Label.new()
	wallet.text = "Your pocket money: Rs %d      (%d/%d items in your pockets)" % [cash, (st.get("items", []) as Array).size(), director.MAX_ITEMS]
	wallet.add_theme_font_size_override("font_size", 15)
	wallet.add_theme_color_override("font_color", ink)
	_shop_body.add_child(wallet)
	for key in director.SHOP:
		var price: int = director.SHOP[key]
		_shop_row(str(director.ITEMS[key]), str(director.SHOP_ABOUT[key]), "Rs %d" % price, cash >= price,
			func(): director.request.rpc_id(1, "buy", {"what": key}), ITEM_COLORS.get(key, Color("ffd24a")))
	var ups: Dictionary = st.get("upgrades", {})
	var head := Label.new()
	head.text = "UPGRADES (last all round)"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color("8a5a3a"))
	_shop_body.add_child(head)
	for key in director.UPGRADES:
		var u: Array = director.UPGRADES[key]
		var lvl := int(ups.get(key, 0))
		var prices: Array = u[2]
		var maxed := lvl >= prices.size()
		var name_txt := "%s  (Lv %d/%d)" % [u[0], lvl, prices.size()]
		_shop_row(name_txt, str(u[1]), "MAX" if maxed else "Rs %d" % int(prices[lvl]), not maxed and cash >= int(prices[mini(lvl, prices.size() - 1)]),
			func(): director.request.rpc_id(1, "buy", {"what": key}), Color("7fe0a0"))
	var hint := Label.new()
	hint.text = "[%s] or Esc: close" % GameInput.key_label("interact")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1, 0.7))
	_shop_body.add_child(hint)


func _shop_row(title: String, about: String, price: String, can_buy: bool, buy: Callable, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_shop_body.add_child(row)
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(12, 40)
	row.add_child(chip)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", Color("2a1a0e"))
	col.add_child(t)
	var a := Label.new()
	a.text = about
	a.add_theme_font_size_override("font_size", 12)
	a.add_theme_color_override("font_color", Color("6a4a32"))
	col.add_child(a)
	var b := Button.new()
	b.text = "BUY  " + price if price != "MAX" else "MAX"
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not can_buy
	b.custom_minimum_size = Vector2(120, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _cached_card(Color("ffc93c"), 10, 6))
	b.add_theme_stylebox_override("hover", _cached_card(Color("ffe39a"), 10, 6))
	b.add_theme_stylebox_override("pressed", _cached_card(Color("ffe39a"), 10, 6))
	b.add_theme_stylebox_override("disabled", _cached_card(Color(0, 0, 0, 0.12), 10, 6))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Color("2a1a0e"))
	b.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0.35))
	b.pressed.connect(buy)
	row.add_child(b)


static func _floor_name(level: int) -> String:
	if level == 0:
		return "GROUND FLOOR"
	return ["FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "SIXTH", "SEVENTH"][mini(level - 1, 6)] + " FLOOR"


func _map_markers(director: Node, me: Node, players: Node, npcs: Node, floor_shown: int, big := false) -> Array:
	var out := []
	var now_s := Time.get_ticks_msec() / 1000.0
	# Goal and quest targets.
	for e in _campus.exits:
		out.append({"at": e.at, "text": e.name if big else "", "kind": "exit"})
	var st: Dictionary = director.status.get(multiplayer.get_unique_id(), {})
	for q in st.get("quests", []):
		if q.done or not QUEST_TARGETS.has(q.id):
			continue
		if q.id == "hoop":
			for rim in _campus.rims:
				out.append({"at": Vector2(rim.x, rim.z), "kind": "quest"})
			continue
		var want: String = QUEST_TARGETS[q.id]
		for it in _campus.interactables:
			var hit: bool = it.kind == want or (it.kind == "pickup" and it.get("item", "") == want)
			if want == "register" and it.kind == "register" and int(it.room) != director.current_room(multiplayer.get_unique_id()):
				hit = false
			if hit and (_campus.level_of(it.pos) == floor_shown or not big):
				out.append({"at": Vector2(it.pos.x, it.pos.z), "kind": "quest"})
	# Pings.
	for m in director.marks:
		var pos: Vector3 = m.pos
		if str(m.npc) != "" and npcs.has_node(str(m.npc)):
			pos = npcs.get_node(str(m.npc)).global_position
		out.append({"at": Vector2(pos.x, pos.z), "kind": "ping"})
	# Staff: only when close by, or while checking your phone.
	var phone: bool = now_s < me.phone_until
	for npc in npcs.get_children():
		if npc.role == "extra":
			continue
		var close: bool = npc.global_position.distance_to(me.global_position) < 14.0
		if not (close or phone):
			continue
		var other_floor: bool = _campus.level_of(npc.global_position) != floor_shown
		out.append({"at": Vector2(npc.global_position.x, npc.global_position.z), "alert": npc.alert, "other_floor": other_floor,
			"text": npc.display_name.get_slice(" (", 0), "kind": "staff",
			"yaw": npc.rotation.y, "fov": float(npc.view_fov) if Settings.show_vision else 0.0, "reach": float(npc.view_range)})
	# Friends, then you on top.
	for p in players.get_children():
		if p == me:
			continue
		out.append({"at": Vector2(p.global_position.x, p.global_position.z), "color": Color("7fd0ea"),
			"text": p.display_name, "kind": "friend"})
	# Your current classroom, outlined (it moves every period).
	var now_room: int = director.current_room(multiplayer.get_unique_id())
	if now_room < _campus.classes.size():
		var cr: Dictionary = _campus.classes[now_room]
		out.append({"at": (cr.rect as Rect2).get_center(), "kind": "room", "rect": cr.rect,
			"level": _campus.level_of(Vector3(0, float(cr.y), 0))})
	var seat: Vector3 = st.get("seat", Vector3.ZERO)
	if st.get("state", "") == "class" and seat != Vector3.ZERO and (_campus.level_of(seat) == floor_shown or not big):
		out.append({"at": Vector2(seat.x, seat.z), "kind": "seat", "text": "Your seat" if big else ""})
	out.append({"at": Vector2(me.global_position.x, me.global_position.z), "kind": "me", "yaw": me.rotation.y})
	return out


# --- Per-frame -----------------------------------------------------------------------------

## Round effects the HUD reacts to (forwarded by the world).
func on_effect(kind: String, _pos: Vector3, extra: String) -> void:
	match kind:
		"style":
			var parts := extra.split("|")
			if parts.size() >= 2:
				_pop_style(parts[0], int(parts[1]))
		"heat":
			var h := int(extra)
			toast("HEAT %d!  %s" % [h, Rules.HEAT_NAMES[clampi(h, 1, 4)].get_slice(": ", 1)], Color("ff9a4a"))
			Sfx.play("alarm_spotted", -10.0, 0.7 + 0.1 * h)
		"round_intro":
			_show_intro.call_deferred()
		"hint_proxy":
			toast("%s is missing! [%s] answer \"Present!\" for them" % [extra, GameInput.key_label("proxy")], Color("7fe0a0"))
		"win":
			_show_escape_moment()


## "CLOSE CALL +50", rising and fading next to the crosshair.
func _pop_style(title: String, points: int) -> void:
	var l := _outlined("%s  +%d" % [title, points], 26)
	l.add_theme_color_override("font_color", Color("ffd24a"))
	_style_box.add_child(l)
	Sfx.play("pickup", -6.0, 1.3)
	var tw := create_tween()
	l.scale = Vector2(1.4, 1.4)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


## Start of the round: the map's trick, today's event and rules, the first quest.
func _show_intro() -> void:
	if is_instance_valid(_intro):
		_intro.queue_free()
	var rules: Dictionary = Network.round_rules
	_intro = PanelContainer.new()
	_intro.add_theme_stylebox_override("panel", _card(Color(0.08, 0.08, 0.14, 0.9), 16, 18))
	_intro.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_intro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_intro.grow_vertical = Control.GROW_DIRECTION_BOTH
	_intro.position.y += 150
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_intro)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_intro.add_child(box)
	var add := func(text: String, size_px: int, color: Color):
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", size_px)
		l.add_theme_color_override("font_color", color)
		box.add_child(l)
	if rules.get("daily", false):
		add.call("DAILY CHALLENGE", 26, Color("ff9a4a"))
		add.call(str(Rules.DAILY_RULES.get(str(rules.rule), "")), 15, Color("ffb37a"))
	if str(rules.get("mode", "")) == "race":
		add.call("RACE: FIRST ONE OUT WINS", 24, Color("ff6a8a"))
		add.call("Paper balls that land on rivals make the staff look their way.", 14, Color(1, 1, 1, 0.75))
	add.call(Rules.map_tip(Network.current_map), 15, Color("9fd8ff"))
	var ev := str(rules.get("event", ""))
	if ev != "":
		add.call("TODAY: " + Rules.event_name(ev), 20, Color("ffd24a"))
		add.call(Rules.event_about(ev), 14, Color(1, 1, 1, 0.8))
	add.call("FIRST QUEST: " + str(preload("res://scenes/world/director.gd").QUESTS[Rules.OPENING]), 16, Color("7fe0a0"))
	var tw := create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(_intro, "modulate:a", 0.0, 1.0)
	tw.tween_callback(_intro.queue_free)


## You're out: the time, big.
func _show_escape_moment() -> void:
	var director: Node = get_parent().get_node_or_null("Director")
	var st: Dictionary = director.status.get(multiplayer.get_unique_id(), {}) if director else {}
	if st.get("state", "") != "escaped":
		return
	_escape_big.text = "ESCAPED!\n%s" % _clock(float(st.get("time", 0.0)))
	_escape_big.visible = true
	_escape_big.modulate.a = 1.0
	_escape_big.pivot_offset = _escape_big.size / 2.0
	_escape_big.scale = Vector2(2.2, 2.2)
	var tw := create_tween()
	tw.tween_property(_escape_big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.4)
	tw.tween_property(_escape_big, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): _escape_big.visible = false)


## About to be spotted: a pulsing glow at the screen edge towards the watcher, and a
## blip that speeds up as the meter fills.
func _update_warning(cam: Camera3D, st: Dictionary, delta: float) -> void:
	var on: bool = st.get("state", "") == "class" and bool(st.get("seen", false)) and float(st.get("sus", 0.0)) >= 70.0 and cam != null
	if OS.get_cmdline_user_args().has("--warn") and cam != null:  # dev: screenshot the warning
		st = {"sus": 90.0, "watch_pos": cam.global_position + cam.global_transform.basis.x * 5.0 - cam.global_transform.basis.z * 2.0}
		on = true
	_edge.t += delta
	if not on:
		_edge.strength = move_toward(_edge.strength, 0.0, delta * 3.0)
		_edge.queue_redraw()
		return
	var to: Vector3 = (st.get("watch_pos", Vector3.ZERO) as Vector3) - cam.global_position
	var basis := cam.global_transform.basis
	_edge.angle = atan2(to.dot(basis.x), to.dot(-basis.z))
	var k := clampf((float(st.sus) - 70.0) / 30.0, 0.0, 1.0)
	_edge.strength = move_toward(_edge.strength, 0.4 + 0.6 * k, delta * 4.0)
	_edge.queue_redraw()
	_warn_beep -= delta
	if _warn_beep <= 0.0:
		_warn_beep = lerpf(0.55, 0.15, k)
		Sfx.play("blip", -8.0, 1.0 + k)


func toast(text: String, color := Color.WHITE) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 3.0


func refresh(director: Node, me: Node, cam: Camera3D, npcs: Node, players: Node) -> void:
	_refresh_maps(director, me, players, npcs)
	var delta := get_process_delta_time()
	_toast_time -= delta
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	_locker.visible = me != null and me.hidden and not debug_camera
	_refresh_dialog(me)
	_hint.text = me.interact_hint if me else ""
	var power: float = me.charge if me else 0.0
	_charge.visible = power > 0.0
	if power > 0.0:
		var bars := int(round(power * 10.0))
		_charge.text = "SHOT POWER  [" + "|".repeat(bars * 2) + " ".repeat((10 - bars) * 2) + "]"

	var now: float = director.elapsed
	_timer_label.text = "Final bell in %s" % _clock(director.round_time - now)

	var id := multiplayer.get_unique_id()
	var st: Dictionary = director.status.get(id, {})
	if st.is_empty():
		_banner.visible = false
		return

	_cash_label.text = "Pocket money: Rs %d" % int(st.get("cash", 0))
	if _ask and _ask.visible and (st.get("state", "") != "class" or director.round_over):
		close_questions()
	_refresh_phone(director, me, st, delta)
	_refresh_mic(st)
	_update_route(director, me, st)
	_update_warning(cam, st, delta)
	var heat := int(director.world.get("heat", 1))
	var ev := str(Network.round_rules.get("event", ""))
	_heat_label.text = "HEAT %d/4%s" % [heat, "   " + Rules.event_name(ev) if ev != "" else ""]
	_heat_label.add_theme_color_override("font_color", [Color("7fe0a0"), Color("ffd24a"), Color("ff9a4a"), Color("ff5a5a")][clampi(heat - 1, 0, 3)])
	_refresh_shop(director, me, st, delta)
	var sus: float = st.sus
	_update_danger(delta, st)
	_sus_fill.size.x = 256.0 * sus / 100.0
	_sus_fill.color = Color("ffd24a").lerp(Color("ff3b3b"), sus / 100.0)
	_sus_value.text = "%d%%" % int(sus)
	_seen.visible = st.seen and int(Time.get_ticks_msec() / 250) % 2 == 0

	var room: int = director.current_room(id)
	var r: Dictionary = director.rooms[room] if room < director.rooms.size() else {}
	_refresh_timetable(director, me, st, room, now)
	if st.state == "escaped":
		_attendance.text = "Out! Phone > Help Out"
		_attendance.add_theme_color_override("font_color", Color("7fe0a0"))
	elif st.state != "class" or r.is_empty():
		_attendance.text = ""
	elif r.calling:
		_attendance.text = "ATTENDANCE NOW! Be in your seat!"
		_attendance.add_theme_color_override("font_color", Color("ff6a6a"))
	elif r.attendance_in <= 0.0:  # the teacher is busy (chasing, fire drill...): it's coming
		_attendance.text = "Attendance any moment!"
		_attendance.add_theme_color_override("font_color", Color("ffd24a"))
	elif r.attendance_in > 9000.0:  # already taken this period (director parks it at 99999)
		_attendance.text = "Attendance: done for this period"
		_attendance.add_theme_color_override("font_color", Color("7fe0a0"))
	else:
		_attendance.text = "Attendance in %s" % _clock(r.attendance_in)
		_attendance.add_theme_color_override("font_color", Color("ffd24a") if r.attendance_in < 15.0 else Color(1, 1, 1, 0.85))
	var pass_left: float = float(st.pass_until) - now
	var gate_left: float = float(st.gate_pass_until) - now
	if gate_left > 0.0:
		_pass.text = "Gate pass: walk out! %s" % _clock(gate_left)
	elif pass_left > 0.0:
		_pass.text = "Hall pass %s" % _clock(pass_left)
	else:
		_pass.text = ""

	_refresh_quests(st)
	_refresh_inventory(st)

	var alarm_left: float = float(director.world.alarm_until) - now
	_objective.visible = st.state == "class"
	match st.state:
		"chased":
			if st.get("grabbed", false):
				_show_banner("GRABBED!  CLICK TO SHOVE FREE!", Color("ff2a2a"))
			else:
				_show_banner("RUN!  You've been spotted!   (Click: shove if they get close)", Color("ff4a4a"))
		"detention":
			_show_banner("DETENTION   %s\nType your lines to get out sooner (-5s each)" % _clock(st.timer), Color("f2a93b"))
		"escaped":
			if now - float(st.time) < 8.0:
				_show_banner("YOU ESCAPED THE UNIVERSITY!   %s
%s" % [_clock(st.time), _campus.win_text], Color("48b06a"))
			else:  # smaller, so helpers can see what they're doing
				_show_banner("OUT OF CAMPUS  ·  escaped in %s" % _clock(st.time), Color("48b06a"))
		_:
			var passing: float = float(director.world.passing_until) - now
			var test_left: float = float(r.get("exam_until", -100.0)) - now
			var handed_in: bool = str(st.get("exam_key", "")) == "%d:%d:%d" % [int(director.world.period), room, int(r.get("exam_id", 0))]
			var exam_key := "%d:%d:%d" % [int(director.world.period), room, int(r.get("exam_id", 0))]
			if test_left > 0.0 and _exam == null and not handed_in and me != null and _campus.room_of(me.global_position) == room:
				if me.seated and str(st.get("exam_paper", "")) != exam_key:
					_show_banner("TEST!  Stay in your seat: the teacher is bringing your paper.", Color("c9703a"))
				elif not me.seated:
					_show_banner("TEST NOW!  Sit in your seat to get a paper.  Standing = detention!   %s" % _clock(test_left), Color("c23a3a"))
				else:
					_banner.visible = false
			elif alarm_left > 0.0:
				_show_banner("FIRE ALARM!  Staff at the plaza  %s" % _clock(alarm_left), Color("e0524f"))
			elif float(director.world.get("party_until", -100.0)) > now:
				_show_banner("CAKE TIME!  Staff are at the canteen  %s" % _clock(float(director.world.party_until) - now), Color("d65ba0"))
			elif passing > 0.0 and me != null and _campus.room_of(me.global_position) != room:
				_show_banner("CLASS CHANGE!  Go to %s  (%s)   %s" % [Network.CLASSROOMS[room], _floor_name(_campus.level_of(Vector3(0, float(_campus.classes[room].y), 0))).capitalize(), _clock(passing)], Color("3f86a8"))
			elif st.get("returning", false):
				var left: float = float(st.return_until) - now
				_show_banner("Walk back to %s%s" % [Network.CLASSROOMS[room], ("   %s" % _clock(left)) if left > 0.0 else "  (you're late!)"], Color("c9703a"))
			elif st.bunking:
				_show_banner("Marked ABSENT. Don't get caught!", Color("9a62d6"))
			else:
				_banner.visible = false

	var fresh := []
	for entry in director.feed:
		if now - float(entry.t) < 9.0:
			fresh.append(str(entry.text))
	while _feed.get_child_count() < fresh.size():
		var line := _outlined("", 16)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 400
		_feed.add_child(line)
	for k in _feed.get_child_count():
		var line: Label = _feed.get_child(k)
		line.visible = k < fresh.size()
		if line.visible:
			line.text = fresh[k]

	_refresh_markers(director, me, cam, npcs, players)
	_board.visible = Input.is_action_pressed("scoreboard") and not director.round_over
	if _board.visible:
		_board_text.text = _scoreboard(director)
	# Results can land a moment after round_over on a guest: redraw when they do.
	if director.round_over and (not _end_shown or director.results.size() != _end_count):
		_end_shown = true
		_end_count = director.results.size()
		_show_results(director.results)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Vignette strength follows how close you are to being caught: it creeps in
## with suspicion, jumps when you're chased, peaks when grabbed, and fades
## slowly as suspicion drops. A heartbeat pulse (and thump) speeds up with it.
func _update_danger(delta: float, st: Dictionary) -> void:
	var target := clampf((float(st.sus) - 25.0) / 75.0, 0.0, 1.0) * 0.6
	match st.state:
		"chased":
			target = maxf(target, 0.8)
			if st.get("grabbed", false):
				target = 1.0
		"detention", "escaped":
			target = 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--danger="):  # dev: force a strength for screenshots
			target = float(arg.trim_prefix("--danger="))
	var rate := 6.0 if target > _danger else 0.8  # quick to rise, slow to fade
	_danger = move_toward(_danger, target, rate * delta)

	var bpm := lerpf(70.0, 150.0, _danger)
	var before := _beat
	_beat = fmod(_beat + delta * bpm / 60.0, 1.0)
	# Double-thump heartbeat shape: lub (at 0) ... dub (at 0.3).
	var pulse := maxf(exp(-pow(_beat * 9.0, 2.0)), 0.6 * exp(-pow((_beat - 0.3) * 9.0, 2.0)))
	if _beat < before and _danger > 0.55:
		Sfx.play("footstep", lerpf(-16.0, -4.0, _danger), 0.45)

	_vignette.visible = _danger > 0.01 and not debug_camera
	_vignette_mat.set_shader_parameter("intensity", _danger)
	_vignette_mat.set_shader_parameter("pulse", pulse)


func _refresh_quests(st: Dictionary) -> void:
	var quests: Array = st.quests
	while _quests.get_child_count() < quests.size() + 1:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 14)
		_quests.add_child(l)
	var head: Label = _quests.get_child(0)
	var done := 0
	for q in quests:
		if q.done:
			done += 1
	head.text = "QUEST CHAIN  %d/%d%s" % [done, quests.size(), "   DONE! Walk out a gate" if done == quests.size() else ""]
	head.modulate = Color(1, 1, 1, 0.7) if done < quests.size() else Color(1, 0.85, 0.3)
	var current := done  # quests are done in order
	for i in quests.size():
		var q: Dictionary = quests[i]
		var l: Label = _quests.get_child(i + 1)
		var text: String = preload("res://scenes/world/director.gd").QUESTS.get(q.id, q.id)
		if q.done:
			l.text = "[x]  " + text
			l.add_theme_color_override("font_color", Color("7fe0a0"))
		elif i == current:
			l.text = "> %d.  %s" % [i + 1, text]
			l.add_theme_color_override("font_color", Color("ffd24a"))
		else:
			l.text = "   %d.  %s" % [i + 1, "(locked: finish the one above)"]
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))


func _refresh_inventory(st: Dictionary) -> void:
	var items: Array = st.items
	for i in 3:
		var slot := _slots[i]
		if i < items.size():
			var item: String = items[i]
			var names: Dictionary = preload("res://scenes/world/director.gd").ITEMS
			slot.text = "[%s]\n%s" % [GameInput.key_label("use_%d" % (i + 1)), names.get(item, item)]
			var c: Color = ITEM_COLORS.get(item, Color.WHITE)
			var tex := Icons.item(item, 48)
			_slot_icons[i].texture = tex
			_slot_icons[i].visible = tex != null
			slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if tex else HORIZONTAL_ALIGNMENT_CENTER
			var key := "slot|%s|%s" % [c.to_html(), tex != null]
			if not _style_cache.has(key):
				var sb := _card(Color(c, 0.85), 10, 8)
				if tex:
					sb.content_margin_left = 60
				_style_cache[key] = sb
			slot.add_theme_stylebox_override("normal", _style_cache[key])
			slot.add_theme_color_override("font_color", Color("2a1a0e"))
		else:
			_slot_icons[i].visible = false
			slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot.text = "[%s]\n-" % GameInput.key_label("use_%d" % (i + 1))
			slot.add_theme_stylebox_override("normal", _cached_card(Color(0.08, 0.08, 0.14, 0.6)))
			slot.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))


func _refresh_markers(director: Node, me: Node, cam: Camera3D, npcs: Node, players: Node) -> void:
	_markers.items.clear()
	if cam == null:
		_markers.queue_redraw()
		return
	# Pings: people (they follow them around), objects by name, places as locations.
	for m in director.marks:
		var pos: Vector3 = m.pos
		var name_txt := str(m.get("label", ""))
		var kind := str(m.get("kind", "place"))
		if str(m.npc) != "" and npcs.has_node(str(m.npc)):
			var npc: Node3D = npcs.get_node(str(m.npc))
			pos = npc.global_position + Vector3(0, 2.2, 0)
			if name_txt == "":
				name_txt = npc.display_name if npc.display_name != "" else "Student"
		elif int(m.get("player", 0)) != 0 and players.has_node(str(m.player)):
			pos = (players.get_node(str(m.player)) as Node3D).global_position + Vector3(0, 2.2, 0)
		var text := "%s  (%s)" % [name_txt, m.by] if kind != "place" else "Location: %s  (%s)" % [name_txt if name_txt != "" else "here", m.by]
		var color := Color("ffd24a") if kind == "person" else (Color("7fd0ea") if kind == "object" else Color("7fe0a0"))
		_add_marker(cam, pos, text, color)
	if me and Time.get_ticks_msec() / 1000.0 < me.phone_until:
		# Nearest staff first, only a few named at a time: walk around and the
		# tags follow whoever is closest, instead of a pile of unreadable names.
		var staff: Array = npcs.get_children().filter(func(n): return n.role != "extra")
		var here: Vector3 = me.global_position
		staff.sort_custom(func(a, b): return a.global_position.distance_squared_to(here) < b.global_position.distance_squared_to(here))
		for k in staff.size():
			var npc: Node3D = staff[k]
			var c := Color("ff4a4a") if npc.alert == 2 else (Color("ffb37a") if npc.alert == 1 else Color("9fd8ff"))
			var dist := int(npc.global_position.distance_to(here))
			_add_marker(cam, npc.global_position + Vector3(0, 2.0, 0), "%s  %dm" % [npc.display_name.get_slice(" (", 0), dist] if k < MAX_STAFF_TAGS else "", c)
	_declutter_markers()
	_markers.queue_redraw()


## Tags that would overlap one already placed lose their text (the dot stays).
func _declutter_markers() -> void:
	var taken: Array[Rect2] = []
	var font := _markers.get_theme_default_font()
	for m in _markers.items:
		if str(m.text) == "":
			continue
		var w := font.get_string_size(str(m.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var box := Rect2((m.at as Vector2) + Vector2(-10, -12), Vector2(w + 26, 24))
		var clash := false
		for r in taken:
			if r.intersects(box):
				clash = true
				break
		if clash:
			m.text = ""
		else:
			taken.append(box)


func _add_marker(cam: Camera3D, pos: Vector3, text: String, color: Color) -> void:
	if cam.is_position_behind(pos):
		return
	var at := cam.unproject_position(pos)
	var size := _markers.size
	var text_w := _markers.get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	at = at.clamp(Vector2(20, 20), size - Vector2(text_w + 30, 20))  # keep the whole name on screen
	_markers.items.append({"at": at, "text": text, "color": color})


func _scoreboard(director: Node) -> String:
	var lines := ["STUDENT            STATE        QUESTS   CAUGHT   MONEY"]
	for id in director.status:
		var st: Dictionary = director.status[id]
		var done := 0
		for q in st.quests:
			if q.done:
				done += 1
		var who: String = str(Network.players.get(id, {}).get("name", "?"))
		lines.append("%-18s %-12s %d/3      %d        Rs %d" % [who.left(18), str(st.state).to_upper(), done, int(st.caught), int(st.get("cash", 0))])
	return "\n".join(lines)


func _show_results(results: Array) -> void:
	for child in _end_list.get_children():
		child.queue_free()
	var rank := 1
	for r in results:
		var line := Label.new()
		var fate := "ESCAPED in %s" % _clock(r.time) if r.escaped else "still on campus"
		var helped := ", helped %d×" % int(r.assists) if int(r.get("assists", 0)) > 0 else ""
		var extras := ""
		if bool(r.get("won", false)):
			extras += "  RACE WINNER!"
		if bool(r.get("chain", false)):
			extras += "  chain done"
		line.text = "%d.  %s   —   %d pts   (%s, %d quests, style %d, caught %d×%s)%s" % [rank, r.name, r.score, fate, r.quests, int(r.get("style", 0)), r.caught, helped, extras]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 820
		line.add_theme_font_size_override("font_size", 20 if rank == 1 else 17)
		line.add_theme_color_override("font_color", Color("ffc93c") if rank == 1 else Color.WHITE)
		_end_list.add_child(line)
		rank += 1
	if not results.is_empty() and bool(results[0].get("class_bonus", false)):
		var bonus := _outlined("THE WHOLE CLASS ESCAPED!  +50% for everyone", 20)
		bonus.add_theme_color_override("font_color", Color("7fe0a0"))
		_end_list.add_child(bonus)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_end_list.add_child(row)
	row.add_child(_results_progress(results))
	row.add_child(_results_highlights(results))
	_end.visible = true
	if is_instance_valid(_intro):
		_intro.queue_free()
	_escape_big.visible = false
	# Nothing may cover the results or eat their clicks.
	if _big:
		_big.visible = false
	if _essay:
		_essay.visible = false
	if _phone:
		_phone.visible = false
	if _shop:
		_shop.visible = false
	if _ask:
		_ask.visible = false
	if _exam:
		_exam.queue_free()
		_exam = null
	_frame.move_child(_end, _frame.get_child_count() - 1)


## Your progress this round (applied to the saved profile once): XP, stars, best time, Rs saved.
func _results_progress(results: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size.x = 430
	var mine := {}
	for r in results:
		if int(r.get("id", -1)) == multiplayer.get_unique_id():
			mine = r
	if mine.is_empty():
		return col
	var sum: Dictionary = Profile.last_summary
	if not _profile_done:
		_profile_done = true
		sum = Profile.apply_round(mine, Network.current_map, Network.round_rules)
	var head := _outlined("YOUR PROGRESS", 18)
	head.add_theme_color_override("font_color", Color("9fd8ff"))
	col.add_child(head)
	var after: Array = sum.get("after", Profile.level_of(Profile.xp))
	var before: Array = sum.get("before", after)
	var lvl := Label.new()
	lvl.add_theme_font_size_override("font_size", 17)
	lvl.text = "Level %d  ·  %s   (+%d XP)" % [int(after[0]), Profile.rank_title(), int(sum.get("xp", 0))]
	col.add_child(lvl)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.12)
	bar_bg.custom_minimum_size = Vector2(400, 14)
	col.add_child(bar_bg)
	var fill := ColorRect.new()
	fill.color = Color("7fe0a0")
	fill.size = Vector2(400.0 * float(before[1]) / float(before[2]), 14)
	bar_bg.add_child(fill)
	var tw := create_tween()
	if int(after[0]) > int(before[0]):
		tw.tween_property(fill, "size:x", 400.0, 0.7)
		tw.tween_callback(func(): fill.size.x = 0.0)
	tw.tween_property(fill, "size:x", 400.0 * float(after[1]) / float(after[2]), 0.9)
	if int(after[0]) > int(before[0]):
		var up := _outlined("LEVEL UP!  Level %d" % int(after[0]), 20)
		up.add_theme_color_override("font_color", Color("ffd24a"))
		col.add_child(up)
	if str(sum.get("rank_up", "")) != "":
		var ru := _outlined("NEW RANK: %s  (new name tag in the lobby!)" % str(sum.rank_up), 18)
		ru.add_theme_color_override("font_color", Color("ff9a4a"))
		col.add_child(ru)
	for line: Array in sum.get("lines", []):
		var l := Label.new()
		l.text = "+%d XP   %s" % [int(line[1]), str(line[0])]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color("ffd24a") if "STAR" in str(line[0]) or "DAILY" in str(line[0]) else Color(1, 1, 1, 0.8))
		col.add_child(l)
	var stars := StarRow.new()
	stars.custom_minimum_size = Vector2(130, 36)
	stars.got = Profile.stars(Network.current_map)
	stars.fresh = sum.get("new_stars", [])
	var star_row := HBoxContainer.new()
	star_row.add_child(stars)
	var best := Label.new()
	var bt := Profile.best_time(Network.current_map)
	best.text = ("Best escape %s%s" % [_clock(bt), "   NEW RECORD!" if sum.get("record", false) else ""]) if bt >= 0.0 else "No escape here yet"
	best.add_theme_font_size_override("font_size", 14)
	best.add_theme_color_override("font_color", Color("7fe0a0") if sum.get("record", false) else Color(1, 1, 1, 0.75))
	star_row.add_child(best)
	col.add_child(star_row)
	var bank := Label.new()
	bank.text = "+Rs %d saved  ·  bank Rs %d (spend it in the lobby)" % [int(sum.get("bank", 0)), Profile.bank]
	bank.add_theme_font_size_override("font_size", 14)
	bank.add_theme_color_override("font_color", Color("ffd24a"))
	col.add_child(bank)
	for id in sum.get("unlocked", []):
		var un := _outlined("NEW MAP UNLOCKED: %s!" % Maps.title(int(id)), 18)
		un.add_theme_color_override("font_color", Color("7fe0a0"))
		col.add_child(un)
	var next := Label.new()
	next.text = "NEXT: " + Profile.next_goal()
	next.add_theme_font_size_override("font_size", 15)
	next.add_theme_color_override("font_color", Color("ff9a4a"))
	col.add_child(next)
	return col


## Fun facts from the round, for comparing with friends.
func _results_highlights(results: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size.x = 380
	var head := _outlined("HIGHLIGHTS", 18)
	head.add_theme_color_override("font_color", Color("9fd8ff"))
	col.add_child(head)
	var lines := []
	var best := func(key: String, lowest: bool) -> Dictionary:
		var pick := {}
		for r in results:
			if pick.is_empty() or (float(r.get(key, 0)) < float(pick.get(key, 0)) if lowest else float(r.get(key, 0)) > float(pick.get(key, 0))):
				pick = r
		return pick
	var close: Dictionary = best.call("closest", true)
	if not close.is_empty() and float(close.closest) < 50.0:
		lines.append("Closest call: %s slipped away from %s at %.1f m" % [close.name, close.closest_who, float(close.closest)])
	var ghost: Dictionary = best.call("longest_unseen", false)
	if not ghost.is_empty() and float(ghost.longest_unseen) >= 10.0:
		lines.append("Ghost: %s, %d s out of class unseen" % [ghost.name, int(ghost.longest_unseen)])
	var paper: Dictionary = best.call("best_distraction", false)
	if not paper.is_empty() and int(paper.best_distraction) >= 1:
		lines.append("Best distraction: %s's paper ball pulled %d staff" % [paper.name, int(paper.best_distraction)])
	var regular: Dictionary = best.call("caught", false)
	if not regular.is_empty() and int(regular.caught) >= 1:
		lines.append("Detention regular: %s (%d×)" % [regular.name, int(regular.caught)])
	for r in results:
		if bool(r.get("speedy", false)):
			lines.append("Speed bonus: %s escaped under 3:00" % r.name)
	if lines.is_empty():
		lines.append("A quiet day at the academy.")
	for text in lines:
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 380
		l.add_theme_font_size_override("font_size", 14)
		col.add_child(l)
	return col


func _show_banner(text: String, color: Color) -> void:
	_banner.visible = true
	_banner_label.text = text
	_banner.add_theme_stylebox_override("panel", _cached_card(Color(color, 0.9), 14, 16))


func _clock(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]


func _outlined(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _cached_card(color: Color, radius := 10, margin := 8) -> StyleBoxFlat:
	var key := "%s|%d|%d" % [color.to_html(), radius, margin]
	if not _style_cache.has(key):
		_style_cache[key] = _card(color, radius, margin)
	return _style_cache[key]


func _card(color: Color, radius := 12, margin := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb
