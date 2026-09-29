extends Node
## Procedural audio: every sound and music loop is synthesized at startup
## (no asset files). Short SFX are built in _ready; the longer music loops
## are rendered on a worker thread so startup stays snappy.

const RATE := 22050
const MUSIC_DB := -4.0
const FADE_TIME := 0.5

enum { SINE, SQUARE, TRIANGLE, SAW }

var streams := {}  # name -> AudioStreamWAV

var _loops := {}  # key -> AudioStreamPlayer
var _warned := {}
var _music_player: AudioStreamPlayer
var _music_track := ""
var _pending_music := ""
var _music_task := -1
var _music_result := {}
var _ambience_timer: Timer
var gen_time_ms := 0.0
var music_gen_time_ms := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	var t0 := Time.get_ticks_usec()
	_build_sfx()
	gen_time_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_music_task = WorkerThreadPool.add_task(_build_music)
	_ambience_timer = Timer.new()
	_ambience_timer.one_shot = true
	_ambience_timer.timeout.connect(_on_ambience_timeout)
	add_child(_ambience_timer)


func _process(_delta: float) -> void:
	if _music_task >= 0 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		streams.merge(_music_result)
		_music_result = {}
		if _pending_music != "":
			var track := _pending_music
			_pending_music = ""
			set_music(track)
	if _music_task < 0:
		set_process(false)


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


## True once the music loops have finished rendering.
func is_ready() -> bool:
	return _music_task < 0


# --- Public API ---------------------------------------------------------------

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null or not scene.is_inside_tree():
		play(sound, volume_db, pitch)
		return
	var stream := _stream(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 40.0
	p.finished.connect(p.queue_free)
	scene.add_child(p)
	p.global_position = pos
	p.play()


## Animal-Crossing-style gibberish: a quick run of blips at pos.
func voice(text: String, pos: Vector3, pitch := 1.0) -> void:
	var count := clampi(ceili(text.strip_edges().length() / 2.0), 1, 14)
	for i in count:
		play_at("blip", pos, -4.0, pitch * randf_range(0.88, 1.18))
		await get_tree().create_timer(0.07, true).timeout
		if not is_inside_tree():
			return


func start_loop(sound: String, key: String, volume_db := 0.0) -> void:
	if _loops.has(key) and is_instance_valid(_loops[key]):
		return
	var stream := _stream(sound)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	add_child(p)
	p.play()
	_loops[key] = p


func stop_loop(key: String) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	_loops.erase(key)
	if is_instance_valid(p):
		p.queue_free()


## "" fades music out; otherwise crossfades to the named looping track.
func set_music(track: String) -> void:
	if _music_task >= 0 and track != "":
		_pending_music = track  # still rendering; start when ready
		return
	_pending_music = ""
	if track == _music_track and (track == "" or is_instance_valid(_music_player)):
		return
	_music_track = track
	if is_instance_valid(_music_player):
		var old := _music_player
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, FADE_TIME)
		tw.tween_callback(old.queue_free)
	_music_player = null
	if track == "":
		return
	var stream := _stream(track)
	if stream == null:
		_music_track = ""
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Music"
	p.volume_db = -40.0
	add_child(p)
	p.play()
	create_tween().tween_property(p, "volume_db", MUSIC_DB, FADE_TIME)
	_music_player = p


## Random bird chirps every few seconds while enabled.
func set_ambience(enabled: bool) -> void:
	if enabled:
		if _ambience_timer.is_stopped():
			_ambience_timer.start(randf_range(4.0, 9.0))
	else:
		_ambience_timer.stop()


func _on_ambience_timeout() -> void:
	play("bird", -18.0, randf_range(0.9, 1.3))
	_ambience_timer.start(randf_range(4.0, 9.0))


func _stream(sound: String) -> AudioStream:
	var s: AudioStream = streams.get(sound)
	if s == null and not _warned.has(sound):
		_warned[sound] = true
		push_warning("Sfx: unknown sound '%s'" % sound)
	return s


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


# --- Sound design -------------------------------------------------------------

func _build_sfx() -> void:
	streams["bell"] = _wav(_make_bell())
	streams["siren"] = _wav(_make_siren(), true)

	# Police whistle: bright tone with a fast pea-rattle trill.
	var b := _buf(0.9)
	_tone(b, 0.0, 0.9, 2600, 2550, 0.32, SINE, 0.0, 1.0, 28.0, 0.035)
	_tone(b, 0.0, 0.9, 5200, 5100, 0.05, SINE, 0.0, 1.0, 28.0, 0.035)
	_noise(b, 0.0, 0.9, 0.04, 0.5, 0.0)
	_trem(b, 28.0, 0.35)
	streams["whistle"] = _wav(b)

	b = _buf(0.055)
	_tone(b, 0.0, 0.055, 440, 400, 0.4, SQUARE, 35.0, 0.35)
	streams["blip"] = _wav(b)

	b = _buf(0.09)
	_noise(b, 0.0, 0.09, 0.9, 0.06, 45.0)
	_tone(b, 0.0, 0.09, 110, 55, 0.35, SINE, 40.0)
	streams["footstep"] = _wav(b)

	b = _buf(0.35)
	_tone(b, 0.0, 0.12, 1318.5, 1318.5, 0.3, TRIANGLE, 12.0)
	_tone(b, 0.08, 0.27, 1975.5, 1975.5, 0.3, TRIANGLE, 9.0)
	_tone(b, 0.08, 0.27, 3951.0, 3951.0, 0.05, SINE, 14.0)
	streams["pickup"] = _wav(b)

	b = _buf(0.25)
	_tone(b, 0.0, 0.1, 155, 150, 0.3, SQUARE, 4.0, 0.2)
	_tone(b, 0.12, 0.13, 125, 120, 0.3, SQUARE, 4.0, 0.2)
	streams["deny"] = _wav(b)

	# Sad trombone "wah wah wah waaah".
	b = _buf(1.2)
	var wah := [[0.0, 392.0], [0.22, 370.0], [0.44, 349.2]]
	for w in wah:
		_tone(b, w[0], 0.21, w[1], w[1] * 0.97, 0.3, SAW, 3.0, 0.12)
	_tone(b, 0.66, 0.54, 329.6, 311.1, 0.3, SAW, 1.5, 0.12, 6.0, 0.02)
	streams["caught"] = _wav(b)

	b = _buf(1.6)
	var arp := [72, 76, 79, 84, 79, 84]
	for i in arp.size():
		_tone(b, i * 0.1, 0.16, _hz(arp[i]), _hz(arp[i]), 0.22, SQUARE, 8.0, 0.3)
	for m in [72, 76, 79, 88]:
		_tone(b, 0.62, 0.98, _hz(m), _hz(m), 0.12, TRIANGLE, 2.5, 1.0, 5.0, 0.004)
	streams["win"] = _wav(b)

	b = _buf(0.3)
	_noise(b, 0.0, 0.3, 0.5, 0.35, 6.0)
	_crackle(b, 0.08)
	streams["paper"] = _wav(b)

	b = _buf(0.35)
	_tone(b, 0.0, 0.14, 520, 1300, 0.28, SQUARE, 0.0, 0.3)
	_tone(b, 0.13, 0.22, 1568, 1568, 0.25, TRIANGLE, 10.0)
	_tone(b, 0.13, 0.22, 3136, 3136, 0.06, SINE, 14.0)
	streams["alarm_spotted"] = _wav(b)

	b = _buf(0.3)
	_tone(b, 0.0, 0.13, 1318.5, 1318.5, 0.28, SINE, 14.0)
	_tone(b, 0.12, 0.18, 1760.0, 1760.0, 0.28, SINE, 12.0)
	streams["phone"] = _wav(b)

	b = _buf(0.25)
	_tone(b, 0.0, 0.08, 2600, 4200, 0.22, SINE, 8.0, 1.0, 45.0, 0.05)
	_tone(b, 0.11, 0.12, 3000, 4800, 0.2, SINE, 8.0, 1.0, 45.0, 0.05)
	streams["bird"] = _wav(b)

	b = _buf(0.04)
	_tone(b, 0.0, 0.04, 1800, 1200, 0.25, TRIANGLE, 90.0)
	_noise(b, 0.0, 0.01, 0.15, 0.7, 200.0)
	streams["click"] = _wav(b)

	# Toilet flush: a rushing gurgle that fades.
	b = _buf(1.8)
	_noise(b, 0.0, 1.8, 0.55, 0.12, 1.6)
	_noise(b, 0.05, 1.2, 0.25, 0.4, 2.5)
	_tone(b, 0.1, 1.4, 180, 90, 0.08, SINE, 1.5, 1.0, 9.0, 0.2)
	streams["flush"] = _wav(b)

	# Piano (middle C); other notes are played by pitching it.
	b = _buf(1.3)
	_tone(b, 0.0, 1.3, 261.63, 261.63, 0.3, SINE, 3.2)
	_tone(b, 0.0, 1.0, 523.25, 523.25, 0.1, SINE, 4.5)
	_tone(b, 0.0, 0.6, 784.9, 784.9, 0.05, TRIANGLE, 7.0)
	_noise(b, 0.0, 0.02, 0.08, 0.5, 120.0)
	streams["piano"] = _wav(b)

	# Drum kit.
	b = _buf(0.4)
	_tone(b, 0.0, 0.4, 140, 45, 0.7, SINE, 9.0)
	streams["kick"] = _wav(b)
	b = _buf(0.25)
	_noise(b, 0.0, 0.25, 0.5, 0.6, 14.0)
	_tone(b, 0.0, 0.12, 220, 180, 0.25, TRIANGLE, 20.0)
	streams["snare"] = _wav(b)
	b = _buf(0.09)
	_noise(b, 0.0, 0.09, 0.3, 0.95, 45.0)
	streams["hat"] = _wav(b)
	b = _buf(0.45)
	_tone(b, 0.0, 0.45, 160, 110, 0.5, SINE, 7.0)
	_noise(b, 0.0, 0.05, 0.1, 0.4, 60.0)
	streams["tom"] = _wav(b)
	b = _buf(1.2)
	_noise(b, 0.0, 1.2, 0.35, 0.9, 3.0)
	streams["crash"] = _wav(b)


func _make_bell() -> PackedFloat32Array:
	# Electric bell: clapper hammering a gong at ~22 Hz.
	var dur := 2.5
	var b := _buf(dur)
	var n := b.size()
	var partials := [[1100.0, 0.5], [2200.0, 0.18], [3036.0, 0.12], [4410.0, 0.05]]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1]
		# Each strike decays quickly, like the hammer hitting.
		var strike := fposmod(t * 22.0, 1.0)
		var trem := 0.35 + 0.65 * exp(-strike * 5.0)
		var fade := clampf((dur - t) / 0.4, 0.0, 1.0) * minf(t / 0.01, 1.0)
		b[i] = s * trem * fade * 0.55
	return b


func _make_siren() -> PackedFloat32Array:
	# Mean frequency 850 Hz * 1.2 s = 1020 whole cycles, so it loops click-free.
	var dur := 1.2
	var b := _buf(dur)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 600.0 + 500.0 * (0.5 - 0.5 * cos(TAU * t / dur))
		b[i] = tanh(2.5 * sin(TAU * phase)) * 0.3
		phase = fposmod(phase + f / RATE, 1.0)
	return b


# --- Music (runs on a worker thread) -----------------------------------------

func _build_music() -> void:
	var t0 := Time.get_ticks_usec()
	var out := {}
	out["chase"] = _wav(_make_chase(), true)
	out["calm"] = _wav(_make_calm(), true)
	out["menu"] = _wav(_make_menu(), true)
	music_gen_time_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_music_result = out


func _make_chase() -> PackedFloat32Array:
	# A minor, 150 BPM, 4 bars: Am - F - G - E.
	var spb := 60.0 / 150.0
	var b := _buf(16 * spb)
	var roots := [45, 41, 43, 40]
	var chords := [[0, 3, 7, 12], [0, 4, 7, 12], [0, 4, 7, 12], [0, 4, 7, 11]]
	for bar in 4:
		var root: int = roots[bar]
		for e in 8:  # bass in bouncing 8ths
			var m := root + (12 if e % 2 == 1 else 0)
			_note(b, spb, bar * 4 + e * 0.5, 0.45, m, 0.2, SQUARE, 3.0, 0.15)
		var ch: Array = chords[bar]
		for s in 16:  # 16th-note arpeggio lead
			var idx := s % 4 if bar % 2 == 0 else 3 - s % 4
			var m2: int = root + 24 + ch[idx]
			_note(b, spb, bar * 4 + s * 0.25, 0.22, m2, 0.09, SQUARE, 9.0, 0.35)
		for beat in 4:  # kick / snare / hats
			var t := (bar * 4 + beat) * spb
			if beat % 2 == 0:
				_tone(b, t, 0.14, 150, 45, 0.45, SINE, 18.0)
			else:
				_noise(b, t, 0.12, 0.22, 0.45, 28.0)
			_noise(b, t + spb * 0.5, 0.03, 0.08, 0.9, 90.0)
	return b


func _make_calm() -> PackedFloat32Array:
	# C major, 120 BPM, 4 bars: Cmaj7 - Am7 - Fmaj7 - G7.
	var spb := 0.5
	var b := _buf(16 * spb)
	var roots := [48, 45, 41, 43]
	var chords := [[4, 7, 11], [3, 7, 10], [4, 7, 11], [4, 7, 10]]
	for bar in 4:
		var root: int = roots[bar]
		_note(b, spb, bar * 4, 1.9, root - 12, 0.2, TRIANGLE, 0.6)
		_note(b, spb, bar * 4 + 2, 1.9, root - 5, 0.14, TRIANGLE, 0.8)
		for c in chords[bar]:  # soft keys on beats 1 and 3
			_note(b, spb, bar * 4, 1.8, root + 12 + c, 0.04, SINE, 1.8)
			_note(b, spb, bar * 4 + 2, 1.8, root + 12 + c, 0.03, SINE, 2.2)
	var melody := [
		[0, 1, 76], [1, 1, 79], [2, 1.5, 81], [3.5, 0.5, 79],
		[4, 1, 76], [5, 1, 72], [6, 2, 74],
		[8, 1, 72], [9, 1, 69], [10, 1, 72], [11, 1, 74],
		[12, 1.5, 76], [13.5, 0.5, 74], [14, 2, 71],
	]
	for n in melody:
		_note(b, spb, n[0], n[1] * 0.95, n[2], 0.1, TRIANGLE, 1.6, 1.0, 5.0, 0.004)
	for i in b.size():
		b[i] *= 0.8
	return b


func _make_menu() -> PackedFloat32Array:
	# Sneaky-but-friendly title theme: B minor, 104 BPM, 8 bars: Bm - G - D - A, twice.
	var spb := 60.0 / 104.0
	var b := _buf(32 * spb)
	var roots := [47, 43, 50, 45]
	var chords := [[0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]]
	var tops := [[66, 69, 74, 71], [67, 71, 74, 79], [66, 69, 74, 78], [64, 69, 73, 76]]
	for bar in 8:
		var k := bar % 4
		var root: int = roots[k]
		_note(b, spb, bar * 4, 3.8, root - 12, 0.16, TRIANGLE, 0.5)  # long bass
		for c in chords[k]:  # warm pad
			_note(b, spb, bar * 4, 3.9, root + c, 0.035, TRIANGLE, 0.3, 0.5)
		for e in 8:  # bouncy plucked bass on the off-beats
			if e % 2 == 1:
				_note(b, spb, bar * 4 + e * 0.5, 0.3, root + (7 if e % 4 == 3 else 0), 0.09, SQUARE, 7.0, 0.2)
		for e in 8:  # tiptoe pluck arpeggio
			var top: Array = tops[k]
			_note(b, spb, bar * 4 + e * 0.5, 0.45, top[e % 4] + (12 if bar >= 4 and e == 6 else 0),
				0.06, TRIANGLE, 5.0, 0.6)
		for beat in 4:  # soft kick, finger-snap hats
			var t := (bar * 4 + beat) * spb
			if beat % 2 == 0:
				_tone(b, t, 0.16, 120, 45, 0.3, SINE, 16.0)
			else:
				_noise(b, t, 0.08, 0.1, 0.5, 40.0)
			_noise(b, t + spb * 0.5, 0.025, 0.04, 0.9, 100.0)
	for i in b.size():
		b[i] *= 0.85
	return b


func _note(b: PackedFloat32Array, spb: float, beat: float, beats: float, midi: int,
		amp: float, wave: int, decay: float, lp := 1.0, vib_hz := 0.0, vib := 0.0) -> void:
	var f := _hz(midi)
	_tone(b, beat * spb, beats * spb, f, f, amp, wave, decay, lp, vib_hz, vib)


# --- Synth primitives ---------------------------------------------------------

func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Adds a tone into b: linear pitch glide f0->f1, exponential decay, optional
## one-pole low-pass (lp in 0..1, 1 = off) and vibrato. Short attack/release
## ramps keep it click-free.
func _tone(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float,
		amp: float, wave := SINE, decay := 0.0, lp := 1.0, vib_hz := 0.0, vib := 0.0) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	if n <= 0:
		return
	var att := 0.004 * RATE
	var rel := minf(0.02, dur * 0.3) * RATE
	var phase := 0.0
	var y := 0.0
	var inv := 1.0 / RATE
	for i in n:
		var k := float(i) / n
		var f := lerpf(f0, f1, k)
		if vib > 0.0:
			f *= 1.0 + vib * sin(TAU * vib_hz * i * inv)
		phase = fposmod(phase + f * inv, 1.0)
		var x: float
		match wave:
			SQUARE:
				x = 1.0 if phase < 0.5 else -1.0
			TRIANGLE:
				x = 4.0 * absf(phase - 0.5) - 1.0
			SAW:
				x = 2.0 * phase - 1.0
			_:
				x = sin(TAU * phase)
		y += lp * (x - y)
		var env := minf(i / att, 1.0) * minf((n - i) / rel, 1.0)
		if decay > 0.0:
			env *= exp(-decay * i * inv)
		b[i0 + i] += y * env * amp


## Adds low-passed white noise (lp 0..1) with exponential decay.
func _noise(b: PackedFloat32Array, start: float, dur: float, amp: float, lp: float, decay: float) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	if n <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + i0
	var y := 0.0
	var rel := minf(0.01, dur * 0.3) * RATE
	for i in n:
		y += lp * (rng.randf_range(-1.0, 1.0) - y)
		var env := minf(i / 20.0, 1.0) * minf((n - i) / rel, 1.0) * exp(-decay * i / float(RATE))
		b[i0 + i] += y * env * amp


## Amplitude tremolo over the whole buffer.
func _trem(b: PackedFloat32Array, hz: float, depth: float) -> void:
	for i in b.size():
		b[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * hz * i / RATE))


## Random gating that makes noise sound like crinkling paper.
func _crackle(b: PackedFloat32Array, grain: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var g := 1.0
	var step := int(grain * RATE / 10.0)
	for i in b.size():
		if i % step == 0:
			g = rng.randf_range(0.2, 1.4)
		b[i] *= g


func _wav(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var n := b.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
