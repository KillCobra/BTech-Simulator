extends PanelContainer
## Surprise class test: a short mini-game per subject, scored 0-100. Each
## subject has three kinds of paper; one is picked at random each test.
##   0 Thermodynamics     stop the needle in the green · vent the boilers · which is hotter?
##   1 Engineering Maths  quick sums · finish the pattern · which is bigger?
##   2 Data Structures    click in ascending order · stacks and queues · binary search
##   3 Chemistry          repeat the recipe · element symbols · acid or base?
## First the paper is handed over and you look it over (a couple of seconds,
## the clock doesn't run). Emits `finished(score)` when done, when time runs
## out, or on Esc (hand in early).

signal finished(score: int)

const SUBJECTS := ["Thermodynamics", "Engineering Maths", "Data Structures", "Chemistry"]
const VARIANTS := [
	["Reactor Control", "Boiler Room", "Hot or Not?"],
	["Quick Sums", "Mind the Pattern", "Bigger or Smaller?"],
	["Sort It Out", "Stacks & Queues", "Binary Search"],
	["Mixing Lab", "Symbol Match", "Acid or Base?"],
]
const INK := Color("2a1a0e")
const GOLD := Color("ffc93c")
const LOOK_OVER := 2.4  # seconds to look the paper over before the clock starts

# [thing A, thing B, 0 if A is hotter else 1]
const HOTTER := [
	["Surface of the Sun", "Lightning bolt", 1], ["Boiling water", "Your forehead", 0],
	["Lava", "Candle flame", 0], ["Pizza oven", "Sauna", 0], ["Liquid nitrogen", "Dry ice", 1],
	["Toaster wires", "Hair dryer air", 0], ["Chai, fresh", "Chai, forgotten for 1 hour", 0],
	["Antarctica in winter", "Your freezer", 1], ["Car engine", "Laptop charger", 0],
	["Venus", "Mercury (night side)", 0], ["Bunsen burner", "Matchstick", 0],
	["Teacher's glare", "Microwave popcorn", 1],
]
# [symbol, right answer, wrong answers...]
const SYMBOLS := [
	["Fe", "Iron", "Fluorine", "Fermium"], ["Na", "Sodium", "Nitrogen", "Neon"], ["K", "Potassium", "Krypton", "Calcium"],
	["Au", "Gold", "Silver", "Aluminium"], ["Ag", "Silver", "Argon", "Gold"], ["Pb", "Lead", "Platinum", "Phosphorus"],
	["Hg", "Mercury", "Hydrogen", "Helium"], ["Sn", "Tin", "Sulfur", "Selenium"], ["Cu", "Copper", "Curium", "Carbon"],
	["W", "Tungsten", "Water", "Tellurium"], ["Cl", "Chlorine", "Calcium", "Carbon"], ["Zn", "Zinc", "Zirconium", "Sodium"],
]
# [substance, true if acid]
const ACIDS := [
	["Lemon juice", true], ["Soap", false], ["Vinegar", true], ["Baking soda", false], ["Toothpaste", false],
	["Cola", true], ["Bleach", false], ["Tomato", true], ["Antacid tablet", false], ["Car battery fluid", true],
	["Orange juice", true], ["Ammonia cleaner", false], ["Curd", true], ["Egg white", false],
]

var subject := 0
var variant := -1           # -1: pick one at random
var cheat := false          # holding a photo of the exam paper
var time_left := 25.0

var _score := 0.0
var _done := false
var _started := false
var _rng := RandomNumberGenerator.new()
var _body: VBoxContainer
var _clock: Label
var _status: Label
var _paper: Control

# Thermodynamics.
var _gauge: Control
var _needle := 0.0
var _needle_dir := 1.0
var _zone := 0.5
var _round := 0
var _rounds_score := 0.0
var _boilers: Array = []    # pressure 0..1 per boiler
var _boiler_speed: Array = []
var _boiler_view: Control
var _vented := 0
var _bursts := 0
var _boiler_t := 0.0
# Maths / multiple choice.
var _q := 0
var _answer := 0
var _mc: Array = []         # [prompt, [options], right index]
# Data structures.
var _numbers: Array = []
var _next := 0
var _mistakes := 0
var _secret := 0
var _tries := 0
var _lo := 1
var _hi := 100
var _guess_edit: SpinBox
# Chemistry.
var _recipe: Array = []
var _shown := 0
var _show_t := 0.0
var _input_i := 0
const BEAKERS := [Color("e0524f"), Color("48b06a"), Color("4f86e0"), Color("ffd24a")]
const BEAKER_NAMES := ["Red", "Green", "Blue", "Yellow"]


func _ready() -> void:
	_rng.randomize()
	if variant < 0:
		variant = _rng.randi() % 3
	add_to_group("modal_ui")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f4ecd8")
	sb.border_color = Color("8a5a3a")
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 380)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		set_anchor(side, 0.5)
	offset_left = -280
	offset_right = 280
	offset_top = -190
	offset_bottom = 190
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label("%s  ·  %s" % [SUBJECTS[subject].to_upper(), VARIANTS[subject][variant].to_upper()], 22, Color("8a2a3a"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_clock = _label("", 20, INK)
	head.add_child(_clock)
	_status = _label("", 15, Color("5a3a22"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	col.add_child(_label("Esc: hand in now", 12, Color(0.3, 0.2, 0.1, 0.7)))
	_look_over()


## The sheet you were just handed: a moment to read it before the clock starts.
func _look_over() -> void:
	_status.text = "The teacher hands you the question paper. Read it over..."
	_paper = PaperSheet.new()
	_paper.subject_name = SUBJECTS[subject]
	_paper.kind = VARIANTS[subject][variant]
	_paper.custom_minimum_size = Vector2(500, 230)
	_body.add_child(_paper)
	_paper.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_paper, "modulate:a", 1.0, 0.35)
	get_tree().create_timer(LOOK_OVER).timeout.connect(_begin)


func _begin() -> void:
	if _done or not is_inside_tree():
		return
	_body.remove_child(_paper)
	_paper.queue_free()
	_paper = null
	_started = true
	if cheat:
		_status.text = "You've seen this paper before... *writes every answer*"
		_score = 100.0
		get_tree().create_timer(2.5).timeout.connect(func(): _finish())
		return
	match [subject, variant]:
		[0, 0]: _start_thermo()
		[0, 1]: _start_boilers()
		[0, 2]: _start_hotter()
		[1, 0]: _next_sum()
		[1, 1]: _start_patterns()
		[1, 2]: _start_bigger()
		[2, 0]: _start_sort()
		[2, 1]: _start_stacks()
		[2, 2]: _start_search()
		[3, 0]: _start_recipe()
		[3, 1]: _start_symbols()
		_: _start_acids()


class PaperSheet extends Control:
	var subject_name := ""
	var kind := ""

	func _draw() -> void:
		var font := get_theme_default_font()
		var r := Rect2(Vector2(40, 0), Vector2(size.x - 80, size.y))
		draw_rect(Rect2(r.position + Vector2(5, 5), r.size), Color(0, 0, 0, 0.18))
		draw_rect(r, Color("fffdf6"))
		for k in 8:
			var y := r.position.y + 60 + k * 20
			draw_line(Vector2(r.position.x + 14, y), Vector2(r.end.x - 14, y), Color(0.55, 0.7, 0.9, 0.5), 1.0)
		draw_line(Vector2(r.position.x + 40, r.position.y), Vector2(r.position.x + 40, r.end.y), Color(0.9, 0.4, 0.4, 0.6), 1.5)
		draw_string(font, r.position + Vector2(52, 26), "SURPRISE TEST: " + subject_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("2a1a0e"))
		draw_string(font, r.position + Vector2(52, 48), "Section: " + kind + "     Max marks: 100", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("5a3a22"))
		draw_string(font, r.position + Vector2(52, 96), "Name: ____________    Roll no: ____", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("5a3a22"))
		draw_string(font, r.position + Vector2(52, 136), "Instructions: answer ALL questions. No talking.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("5a3a22"))
		draw_string(font, r.position + Vector2(52, 156), "Phones away. Eyes on your own paper.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("5a3a22"))
		draw_string(font, r.position + Vector2(r.size.x - 120, r.size.y - 16), "- Principal", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8a2a3a"))


func _process(delta: float) -> void:
	if _done or not _started:
		return
	time_left -= delta
	_clock.text = "%ds" % maxi(0, ceili(time_left))
	if time_left <= 0.0:
		_status.text = "Time's up! Pens down."
		_finish()
		return
	if subject == 0 and variant == 0 and _gauge:
		var speed := 0.9 + _round * 0.45
		_needle += _needle_dir * speed * delta
		if _needle > 1.0 or _needle < 0.0:
			_needle_dir = -_needle_dir
			_needle = clampf(_needle, 0.0, 1.0)
		_gauge.queue_redraw()
	if subject == 0 and variant == 1 and _boiler_view:
		_boiler_step(delta)
	if subject == 3 and variant == 0 and not cheat and _flask and _shown < _recipe.size() + 1:
		_show_t -= delta
		if _show_t <= 0.0:
			_show_recipe_step()


func _input(event: InputEvent) -> void:
	if _done:
		return
	# Esc with the pause menu open closes the menu, it doesn't hand the test in.
	for n in get_tree().get_nodes_in_group("pause_menu"):
		if is_instance_valid(n) and n.is_visible_in_tree():
			return
	if event.is_action_pressed("ui_cancel"):
		_status.text = "Handed in early."
		_finish()
		get_viewport().set_input_as_handled()
	elif subject == 0 and variant == 0 and _gauge and event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE:
		_lock_needle()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if _done:
		return
	_done = true
	var score := clampi(roundi(_score), 0, 100)
	_status.text += "   Score: %d/100" % score
	if score == 100:
		_status.text += "   FULL MARKS!"
	get_tree().create_timer(1.2).timeout.connect(func():
		finished.emit(score)
		queue_free())


func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


# --- Multiple choice (several papers use it) ---------------------------------------------------------

## Asks `_mc` one question at a time; each right answer is worth an equal share of 100.
func _next_mc() -> void:
	_clear_body()
	if _q >= _mc.size():
		_status.text = "All done!"
		_finish()
		return
	var item: Array = _mc[_q]
	_status.text = "Question %d of %d" % [_q + 1, _mc.size()]
	var prompt := _label(str(item[0]), 26, INK)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size.x = 500
	_body.add_child(prompt)
	var grid := GridContainer.new()
	grid.columns = 2 if (item[1] as Array).size() > 3 else (item[1] as Array).size()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for k in (item[1] as Array).size():
		var b := _button(str(item[1][k]), _pick_mc.bind(k))
		b.custom_minimum_size = Vector2(220, 46)
		b.add_theme_font_size_override("font_size", 17)
		grid.add_child(b)


func _pick_mc(k: int) -> void:
	if _done:
		return
	if k == int(_mc[_q][2]):
		_score += 100.0 / _mc.size()
	_q += 1
	_next_mc()


## Shuffles the options of [prompt, right answer, wrong answers...] into an _mc entry.
func _mc_item(prompt: String, right: Variant, wrong: Array) -> Array:
	var options := [right]
	options.append_array(wrong)
	options.shuffle()
	return [prompt, options, options.find(right)]


# --- Thermodynamics: keep the reactor in the green --------------------------------------------------

func _start_thermo() -> void:
	_status.text = "Keep the reactor stable! Press SPACE (or LOCK) when the needle is in the green. 3 tries."
	_gauge = Gauge.new()
	_gauge.game = self
	_gauge.custom_minimum_size = Vector2(500, 90)
	_body.add_child(_gauge)
	_body.add_child(_button("LOCK", _lock_needle))
	_zone = _rng.randf_range(0.2, 0.8)


func _lock_needle() -> void:
	var d := absf(_needle - _zone)
	var pts := clampf(1.0 - maxf(0.0, d - 0.02) / 0.23, 0.0, 1.0) * 100.0 / 3.0
	_rounds_score += pts
	_score = _rounds_score
	_round += 1
	_status.text = ["Way off!", "Close...", "Nice!", "Perfect!"][clampi(int(pts / 10.0), 0, 3)] + "   (%d/3)" % _round
	if _round >= 3:
		_finish()
	else:
		_zone = _rng.randf_range(0.15, 0.85)


class Gauge extends Control:
	var game: Node

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, h * 0.3, w, h * 0.4), Color("3a3d47"))
		draw_rect(Rect2(w * (game._zone - 0.08), h * 0.3, w * 0.16, h * 0.4), Color("48b06a"))
		draw_rect(Rect2(w * (game._zone - 0.02), h * 0.3, w * 0.04, h * 0.4), Color("7fe0a0"))
		var x: float = w * game._needle
		draw_rect(Rect2(x - 3, h * 0.1, 6, h * 0.8), Color("e0524f"))
		draw_string(get_theme_default_font(), Vector2(4, h * 0.25), "COLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("4f86e0"))
		draw_string(get_theme_default_font(), Vector2(w - 36, h * 0.25), "HOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e0524f"))


# --- Thermodynamics: vent the boilers before they burst ------------------------------------------------

func _start_boilers() -> void:
	_status.text = "Four boilers are heating up. Click a boiler to VENT it before its pressure hits the red line. Keep it up for 12 s!"
	for k in 4:
		_boilers.append(_rng.randf_range(0.0, 0.4))
		_boiler_speed.append(_rng.randf_range(0.08, 0.16))
	_boiler_view = Boilers.new()
	_boiler_view.game = self
	_boiler_view.custom_minimum_size = Vector2(500, 160)
	_body.add_child(_boiler_view)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	for k in 4:
		var b := _button("VENT %d" % (k + 1), _vent.bind(k))
		b.custom_minimum_size = Vector2(115, 44)
		row.add_child(b)
	_boiler_t = 12.0
	_score = 100.0


func _boiler_step(delta: float) -> void:
	_boiler_t -= delta
	for k in _boilers.size():
		_boilers[k] = float(_boilers[k]) + float(_boiler_speed[k]) * delta * (1.0 + (12.0 - _boiler_t) * 0.06)
		if float(_boilers[k]) >= 1.0:
			_boilers[k] = 0.1
			_bursts += 1
			_score = maxf(0.0, _score - 25.0)
			_status.text = "BOOM! Boiler %d burst. (%d burst)" % [k + 1, _bursts]
	_boiler_view.queue_redraw()
	if _boiler_t <= 0.0:
		_status.text = "Shift over! %d vents, %d bursts." % [_vented, _bursts]
		_boiler_view = null
		_finish()


func _vent(k: int) -> void:
	if _done or _boiler_view == null:
		return
	if float(_boilers[k]) < 0.25:
		_score = maxf(0.0, _score - 5.0)  # venting a cold boiler wastes steam
		_status.text = "Boiler %d was cold: wasted steam!" % [k + 1]
	else:
		_vented += 1
	_boilers[k] = 0.0
	_boiler_speed[k] = _rng.randf_range(0.08, 0.18)


class Boilers extends Control:
	var game: Node

	func _draw() -> void:
		var font := get_theme_default_font()
		var w := size.x / 4.0
		for k in 4:
			var x := k * w + 18
			var tank := Rect2(x, 10, w - 36, size.y - 36)
			draw_rect(tank, Color("3a3d47"))
			var p: float = clampf(game._boilers[k], 0.0, 1.0)
			var fill := Color("48b06a").lerp(Color("e0524f"), p)
			draw_rect(Rect2(tank.position.x + 4, tank.end.y - 4 - (tank.size.y - 8) * p, tank.size.x - 8, (tank.size.y - 8) * p), fill)
			var red_y := tank.position.y + 4 + (tank.size.y - 8) * 0.0
			draw_line(Vector2(tank.position.x, red_y), Vector2(tank.end.x, red_y), Color("ff2a2a"), 3.0)
			draw_string(font, Vector2(x + tank.size.x / 2.0 - 6, size.y - 8), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("2a1a0e"))


# --- Thermodynamics: which is hotter? -------------------------------------------------------------------

func _start_hotter() -> void:
	var pool := HOTTER.duplicate()
	pool.shuffle()
	for k in 4:
		var h: Array = pool[k]
		_mc.append(["Which is HOTTER?", [h[0], h[1]], h[2]])
	_next_mc()


# --- Maths: quick sums -------------------------------------------------------------------------------

func _next_sum() -> void:
	_clear_body()
	if _q >= 4:
		_finish()
		return
	var a := _rng.randi_range(3, 19)
	var b := _rng.randi_range(2, 12)
	var op: String = ["+", "-", "×"][_rng.randi() % 3]
	_answer = a + b if op == "+" else (a - b if op == "-" else a * b)
	_status.text = "Question %d of 4" % (_q + 1)
	_body.add_child(_label("%d %s %d = ?" % [a, op, b], 40, INK))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var options := [_answer, _answer + _rng.randi_range(1, 5), _answer - _rng.randi_range(1, 5)]
	options.shuffle()
	for o in options:
		row.add_child(_button(str(o), _pick_sum.bind(int(o))))


func _pick_sum(value: int) -> void:
	if _done:
		return
	if value == _answer:
		_score += 25.0
	_q += 1
	_next_sum()


# --- Maths: finish the pattern -------------------------------------------------------------------------

func _start_patterns() -> void:
	var kinds := [0, 1, 2, 3, 4]
	kinds.shuffle()
	for k in 4:
		var seq: Array = []
		var nxt := 0
		match kinds[k]:
			0:  # add a constant
				var a := _rng.randi_range(2, 20)
				var d := _rng.randi_range(3, 9)
				for i in 4:
					seq.append(a + d * i)
				nxt = a + d * 4
			1:  # doubling
				var a := _rng.randi_range(1, 6)
				for i in 4:
					seq.append(a * int(pow(2, i)))
				nxt = a * 16
			2:  # squares
				var a := _rng.randi_range(1, 5)
				for i in 4:
					seq.append((a + i) * (a + i))
				nxt = (a + 4) * (a + 4)
			3:  # Fibonacci-ish
				var x := _rng.randi_range(1, 4)
				var y := _rng.randi_range(2, 6)
				seq = [x, y, x + y, x + 2 * y]
				nxt = 2 * x + 3 * y
			_:  # triangular steps: +1, +2, +3...
				var a := _rng.randi_range(1, 10)
				seq = [a, a + 1, a + 3, a + 6]
				nxt = a + 10
		var wrong := [nxt + _rng.randi_range(1, 4), nxt - _rng.randi_range(1, 4), nxt + _rng.randi_range(5, 9)]
		_mc.append(_mc_item("%s, ?" % ", ".join(seq.map(func(v): return str(v))), nxt, wrong))
	_next_mc()


# --- Maths: which is bigger? ---------------------------------------------------------------------------

func _start_bigger() -> void:
	var pairs := []
	for k in 6:
		match _rng.randi() % 3:
			0:
				var a := _rng.randi_range(2, 5)
				var b := _rng.randi_range(2, 5)
				while b == a:
					b = _rng.randi_range(2, 5)
				pairs.append(["%d^%d" % [a, b], int(pow(a, b)), "%d^%d" % [b, a], int(pow(b, a))])
			1:
				var n1 := _rng.randi_range(1, 7)
				var d1 := _rng.randi_range(n1 + 1, 9)
				var n2 := _rng.randi_range(1, 7)
				var d2 := _rng.randi_range(n2 + 1, 9)
				pairs.append(["%d/%d" % [n1, d1], float(n1) / d1, "%d/%d" % [n2, d2], float(n2) / d2])
			_:
				var a := _rng.randi_range(11, 30)
				var b := _rng.randi_range(2, 9)
				var c := _rng.randi_range(40, 250)
				pairs.append(["%d × %d" % [a, b], a * b, "%d" % c, c])
	for p in pairs:
		if is_equal_approx(float(p[1]), float(p[3])):
			continue
		_mc.append(["Which is BIGGER?", [p[0], p[2]], 0 if float(p[1]) > float(p[3]) else 1])
		if _mc.size() >= 4:
			break
	_next_mc()


# --- Data structures: sort ---------------------------------------------------------------------------

func _start_sort() -> void:
	_status.text = "Click the numbers from SMALLEST to LARGEST."
	var pool := range(1, 100)
	pool.shuffle()
	_numbers = pool.slice(0, 6)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	for n in _numbers:
		grid.add_child(_button(str(n), _pick_number.bind(int(n))))
	_numbers.sort()


func _pick_number(n: int) -> void:
	if _done:
		return
	if n == int(_numbers[_next]):
		_next += 1
		for b in _body.get_child(0).get_children():
			if (b as Button).text == str(n):
				b.disabled = true
		_score = maxf(0.0, _next * 100.0 / 6.0 - _mistakes * 12.0)
		if _next >= _numbers.size():
			_status.text = "Sorted!"
			_finish()
	else:
		_mistakes += 1
		_score = maxf(0.0, _next * 100.0 / 6.0 - _mistakes * 12.0)
		_status.text = "Not that one! (%d mistakes)" % _mistakes


# --- Data structures: stacks and queues ------------------------------------------------------------------

func _start_stacks() -> void:
	for k in 4:
		var queue := _rng.randf() < 0.5
		var items: Array = []
		var ops: Array = []
		var letters := ["A", "B", "C", "D", "E", "F", "G"]
		letters.shuffle()
		var li := 0
		for step in 5:
			if items.size() < 2 or _rng.randf() < 0.65:
				items.append(letters[li])
				ops.append("push %s" % letters[li])
				li += 1
			else:
				ops.append("pop")
				if queue:
					items.pop_front()
				else:
					items.pop_back()
		if items.is_empty():
			items.append(letters[li])
			ops.append("push %s" % letters[li])
		var right: String = items[0] if queue else items[items.size() - 1]
		var wrong := []
		for l in letters.slice(0, 5):
			if l != right and wrong.size() < 3:
				wrong.append(l)
		var word := "QUEUE: what's at the FRONT?" if queue else "STACK: what's on TOP?"
		_mc.append(_mc_item("%s\n%s" % [word, ",  ".join(ops)], right, wrong))
	_next_mc()


# --- Data structures: binary search -------------------------------------------------------------------

func _start_search() -> void:
	_secret = _rng.randi_range(1, 100)
	_status.text = "I'm thinking of a number from 1 to 100. Find it! 7 guesses or fewer is full marks."
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	_guess_edit = SpinBox.new()
	_guess_edit.min_value = 1
	_guess_edit.max_value = 100
	_guess_edit.value = 50
	_guess_edit.custom_minimum_size = Vector2(160, 50)
	_guess_edit.get_line_edit().add_theme_font_size_override("font_size", 24)
	var field := StyleBoxFlat.new()
	field.bg_color = Color("fffdf6")
	field.border_color = Color("8a5a3a")
	field.set_border_width_all(2)
	field.set_corner_radius_all(8)
	field.set_content_margin_all(8)
	_guess_edit.get_line_edit().add_theme_stylebox_override("normal", field)
	_guess_edit.get_line_edit().add_theme_stylebox_override("focus", field)
	_guess_edit.get_line_edit().add_theme_color_override("font_color", INK)
	row.add_child(_guess_edit)
	row.add_child(_button("GUESS", func(): _guess(int(_guess_edit.value))))
	_body.add_child(_label("Range: 1 - 100", 18, INK))


func _guess(n: int) -> void:
	if _done:
		return
	_tries += 1
	var hint: Label = _body.get_child(1)
	if n == _secret:
		_score = clampf(100.0 - maxi(0, _tries - 7) * 15.0, 10.0, 100.0)
		_status.text = "Found it in %d guesses!" % _tries
		_finish()
		return
	if n < _secret:
		_lo = maxi(_lo, n + 1)
	else:
		_hi = mini(_hi, n - 1)
	hint.text = "%d is too %s.   Range: %d - %d   (guess %d)" % [n, "LOW" if n < _secret else "HIGH", _lo, _hi, _tries]
	_guess_edit.value = (_lo + _hi) / 2


# --- Chemistry: remember the recipe ---------------------------------------------------------------------

var _flask: ColorRect
var _flask_label: Label


func _start_recipe() -> void:
	_status.text = "Watch the recipe carefully..."
	for k in 4:
		_recipe.append(_rng.randi() % 4)
	_flask = ColorRect.new()
	_flask.custom_minimum_size = Vector2(120, 120)
	_flask.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(_flask)
	_flask_label = _label("", 20, INK)
	_flask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_flask_label)
	_show_t = 0.6
	time_left += 4.0  # time to watch


func _show_recipe_step() -> void:
	if _shown < _recipe.size():
		var c: int = _recipe[_shown]
		_flask.color = BEAKERS[c]
		_flask_label.text = "%d.  %s" % [_shown + 1, BEAKER_NAMES[c]]
		_shown += 1
		_show_t = 0.9
		return
	# Recipe shown: now the player repeats it.
	_shown += 1
	_flask.color = Color("dcdfe6")
	_flask_label.text = "Your turn: add them in the same order"
	_status.text = "Pour the chemicals in order."
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	for k in 4:
		var b := _button(BEAKER_NAMES[k], _pour.bind(k))
		b.custom_minimum_size = Vector2(115, 50)
		var sb := StyleBoxFlat.new()
		sb.bg_color = BEAKERS[k]
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override("normal", sb)
		row.add_child(b)


func _pour(k: int) -> void:
	if _done or _shown <= _recipe.size():
		return
	if k == int(_recipe[_input_i]):
		_input_i += 1
		_score = _input_i * 25.0
		_flask.color = BEAKERS[k]
		_flask_label.text = "%d/4 correct" % _input_i
		if _input_i >= _recipe.size():
			_status.text = "Perfect mixture!"
			_finish()
	else:
		_flask.color = Color("26262e")
		_status.text = "BOOM. Wrong chemical!"
		_finish()


# --- Chemistry: element symbols -------------------------------------------------------------------------

func _start_symbols() -> void:
	var pool := SYMBOLS.duplicate()
	pool.shuffle()
	for k in 4:
		var s: Array = pool[k]
		_mc.append(_mc_item("Which element is  %s ?" % s[0], s[1], s.slice(2)))
	_next_mc()


# --- Chemistry: acid or base? ---------------------------------------------------------------------------

func _start_acids() -> void:
	var pool := ACIDS.duplicate()
	pool.shuffle()
	for k in 5:
		var a: Array = pool[k]
		_mc.append([str(a[0]), ["ACID", "BASE"], 0 if a[1] else 1])
	_next_mc()


# --- UI helpers -------------------------------------------------------------------------------------------

func _label(text: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 50)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.set_corner_radius_all(10)
	sb.border_color = GOLD.darkened(0.35)
	sb.border_width_bottom = 5
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = GOLD.lightened(0.15)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(st, INK)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(handler)
	return b
