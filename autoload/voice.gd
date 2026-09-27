extends Node
## Proximity voice chat, registered as the `Voice` autoload.
##
## Your mic is captured on a muted "Mic" bus, averaged down to 16 kHz mono, cut into
## 20 ms frames and squeezed 4:1 with IMA ADPCM (8 kB/s while you talk, nothing while
## you don't). Frames go to the host, which relays them to everyone close enough to
## hear. Each friend's voice plays from their head: clear next to you, fading down the
## corridor, muffled through walls and heavily muffled through floors.
##
## The host also hands every frame's loudness to the Director (`heard`), so staff can
## hear you too: whisper and they won't notice, laugh and the teacher turns around.

signal heard(peer_id: int, rms: float)  # host only: someone's mic frame (for staff hearing)

const RATE := 16000
const FRAME := 320            # samples per packet (20 ms)
const HANG := 0.35            # open mic: keep sending this long after you stop talking
const RELAY_RANGE := 48.0     # host: don't relay voices to players further away than this
const HEADER := 6             # see scripts/adpcm.gd

const Adpcm := preload("res://scripts/adpcm.gd")

var transmitting := false  # local: your mic is live right now (HUD shows it)
var level := 0.0           # local: loudness of your last 20 ms (RMS, 0..1), for the meter
var mic_ok := false        # a microphone can be captured
var monitoring := false    # the settings page's mic meter is open: listen even outside a session

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _src_rate := 44100.0
var _step := 1.0           # output samples per input sample
var _phase := 0.0
var _acc := 0.0
var _acc_n := 0
var _pcm := PackedFloat32Array()
var _seq := 0
var _hang := 0.0
var _peers := {}           # peer id -> {"player", "playback", "last", "seq", "rms", "occl_t"}
var _test_amp := 0.0       # dev: --voice-test=AMP talks a synthetic voice instead of the mic
var _test_t := 0.0
var _echo := false         # dev: --voice-echo plays your own voice back to you
var _world: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Voice", false)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--voice-test="):
			_test_amp = float(arg.trim_prefix("--voice-test="))
		elif arg == "--voice-echo":
			_echo = true
	if DisplayServer.get_name() != "headless":
		_start_mic()


func _apply_settings() -> void:
	var idx := AudioServer.get_bus_index("Voice")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(Settings.voice_volume), 0.0001)))
		AudioServer.set_bus_mute(idx, float(Settings.voice_volume) <= 0.0)


func _ensure_bus(bus_name: String, muted: bool) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_mute(idx, muted)
	return idx


## Starts capturing the microphone (needs audio/driver/enable_input in the project).
func _start_mic() -> void:
	var idx := _ensure_bus("Mic", true)  # we only want the samples, never to hear ourselves
	for k in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, k) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(idx, k)
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, _capture)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)
	_src_rate = AudioServer.get_mix_rate()
	_step = float(RATE) / _src_rate
	mic_ok = true


## Friends and staff can only hear you once there's a session.
func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	_world = get_tree().get_first_node_in_group("world")
	_read_mic(delta)
	while _pcm.size() >= FRAME:
		var frame := _pcm.slice(0, FRAME)
		_pcm = _pcm.slice(FRAME)
		_frame(frame, float(FRAME) / RATE)
	_update_voices(delta)


## Mic (or the dev test voice) -> 16 kHz samples in _pcm. The mic is only open in a
## session (or while the settings meter is up) and never when it's switched off.
func _read_mic(delta: float) -> void:
	if _mic_player:
		var want := (monitoring or _online()) and int(Settings.voice_mode) != Settings.VoiceMode.OFF
		if monitoring:
			want = true
		if want != _mic_player.playing:
			if want:
				_mic_player.play()
			else:
				_mic_player.stop()
				_capture.clear_buffer()
				level = 0.0
				transmitting = false
	if _test_amp > 0.0:
		# Dev: a buzzy "voice" that talks for 1.5 s, then pauses for 1.5 s.
		var n := int(delta * RATE)
		for i in n:
			_test_t += 1.0 / RATE
			var on := fmod(_test_t, 3.0) < 1.5
			_pcm.append(sin(TAU * 180.0 * _test_t) * _test_amp * 1.41 if on else 0.0)
		return
	if _capture == null:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var buf := _capture.get_buffer(avail)
	# Box-filter down to 16 kHz: average the input samples that fall in each output sample.
	for v in buf:
		_acc += (v.x + v.y) * 0.5
		_acc_n += 1
		_phase += _step
		if _phase >= 1.0:
			_phase -= 1.0
			_pcm.append(_acc / _acc_n)
			_acc = 0.0
			_acc_n = 0
	if _pcm.size() > RATE:  # fell far behind (window dragged, breakpoint): drop the backlog
		_pcm = _pcm.slice(_pcm.size() - FRAME * 2)


## One 20 ms frame of your voice: decide whether it goes out, then send it.
func _frame(frame: PackedFloat32Array, seconds: float) -> void:
	var sum := 0.0
	for x in frame:
		sum += x * x
	level = sqrt(sum / frame.size())
	var mode := int(Settings.voice_mode)
	var want := false
	if _test_amp > 0.0:
		want = level > 0.001
	elif mode == Settings.VoiceMode.OPEN_MIC:
		if level >= float(Settings.mic_gate):
			_hang = HANG
		else:
			_hang -= seconds
		want = _hang > 0.0
	elif mode == Settings.VoiceMode.PUSH_TO_TALK:
		want = _ptt_held()
	transmitting = want
	if not want or not _online():
		return
	_seq = (_seq + 1) & 0xffff
	var packet := Adpcm.encode(frame, level, _seq)
	var me := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_received(me, packet)
		for peer in multiplayer.get_peers():
			if _audible(me, peer):
				_down.rpc_id(peer, me, packet)
	else:
		_up.rpc_id(1, packet)
		if _echo:
			_received(me, packet)


func _ptt_held() -> bool:
	if not InputMap.has_action("push_to_talk") or not Input.is_action_pressed("push_to_talk"):
		return false
	return not (get_viewport().gui_get_focus_owner() is LineEdit)  # typing detention lines, a name...


# --- Network ---------------------------------------------------------------------------------------

## Client -> host: one frame of my voice. The host plays it and relays it.
@rpc("any_peer", "unreliable_ordered")
func _up(packet: PackedByteArray) -> void:
	if not multiplayer.is_server() or packet.size() < HEADER:
		return
	var from := multiplayer.get_remote_sender_id()
	_received(from, packet)
	for peer in multiplayer.get_peers():
		if peer != from and _audible(from, peer):
			_down.rpc_id(peer, from, packet)


## Host -> client: a frame of someone's voice.
@rpc("authority", "unreliable_ordered")
func _down(from: int, packet: PackedByteArray) -> void:
	if packet.size() >= HEADER:
		_received(from, packet)


## Host: is `listener` close enough to `speaker` to be worth sending the frame to?
func _audible(speaker: int, listener: int) -> bool:
	if _world == null or not Network.in_game:
		return true  # the lobby: everyone hears everyone
	if linked(speaker, listener):
		return true
	var players: Node = _world.get_node_or_null("Players")
	var a: Node3D = players.get_node_or_null(str(speaker)) if players else null
	var b: Node3D = players.get_node_or_null(str(listener)) if players else null
	return a == null or b == null or a.global_position.distance_to(b.global_position) < RELAY_RANGE


func _received(from: int, packet: PackedByteArray) -> void:
	var rms := packet[2] / 1000.0
	if multiplayer.is_server():
		heard.emit(from, rms)
	if from == multiplayer.get_unique_id() and not _echo:
		return
	var out := _out(from)
	var seq := packet[0] | (packet[1] << 8)
	out.last = Time.get_ticks_msec() / 1000.0
	out.rms = rms
	if ((seq - int(out.seq)) & 0xffff) > 0x8000:
		return  # older than one we already played
	out.seq = seq
	var pb: AudioStreamGeneratorPlayback = out.playback
	if pb == null:
		return
	var samples := Adpcm.decode(packet)
	if pb.get_frames_available() < samples.size():
		return  # the buffer is full (their clock runs fast): skip a frame rather than lag
	var frames := PackedVector2Array()
	frames.resize(samples.size())
	for i in samples.size():
		frames[i] = Vector2(samples[i], samples[i])
	pb.push_buffer(frames)


## The speaker for a friend's voice (made on their first frame).
func _out(from: int) -> Dictionary:
	if _peers.has(from) and is_instance_valid(_peers[from].player):
		return _peers[from]
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	var p := AudioStreamPlayer3D.new()
	p.stream = gen
	p.bus = "Voice"
	p.unit_size = 3.5
	p.max_distance = 42.0
	p.attenuation_filter_cutoff_hz = 20500.0
	add_child(p)
	p.play()
	var out := {"player": p, "playback": p.get_stream_playback(), "last": -10.0, "seq": -1, "rms": 0.0, "occl_t": 0.0}
	_peers[from] = out
	print("[voice] hearing peer %d" % from)
	return out


## Every frame: each voice sits on its speaker's head (or everywhere, in the lobby),
## muffled when there's a wall or a floor between you.
func _update_voices(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var players: Node = _world.get_node_or_null("Players") if _world else null
	for id in _peers.keys():
		var out: Dictionary = _peers[id]
		var p: AudioStreamPlayer3D = out.player
		if not is_instance_valid(p):
			_peers.erase(id)
			continue
		var who: Node3D = players.get_node_or_null(str(id)) if players else null
		var phone := linked(int(id), me)
		if who == null or cam == null or phone:
			# Lobby, or a phone call: straight in your ear.
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			p.panning_strength = 0.0
			p.global_position = cam.global_position if cam else Vector3.ZERO
			p.attenuation_filter_cutoff_hz = 3200.0 if phone else 20500.0
			p.volume_db = 0.0
			continue
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.0
		var head: Vector3 = who.global_position + Vector3(0, 1.5 if not who.crouching else 1.0, 0)
		p.global_position = head
		out.occl_t = float(out.occl_t) - delta
		if float(out.occl_t) > 0.0:
			continue
		out.occl_t = 0.15
		var dy := absf(head.y - cam.global_position.y)
		var cutoff := 20500.0
		var vol := 0.0
		if dy > 2.6:
			cutoff = 450.0  # through a floor: a rumble
			vol = -14.0
		else:
			var query := PhysicsRayQueryParameters3D.create(cam.global_position, head, 1)
			if not cam.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				cutoff = 900.0  # through a wall
				vol = -7.0
		p.attenuation_filter_cutoff_hz = lerpf(p.attenuation_filter_cutoff_hz, cutoff, 0.6)
		p.volume_db = lerpf(p.volume_db, vol, 0.6)


## Is this peer talking right now? (Their name tag shows it.)
func is_speaking(id: int) -> bool:
	if id == multiplayer.get_unique_id():
		return transmitting
	return _peers.has(id) and Time.get_ticks_msec() / 1000.0 - float(_peers[id].last) < 0.3


## Two players on a phone call hear each other anywhere (Help Out: call a friend).
func linked(a: int, b: int) -> bool:
	if _world == null:
		return false
	var director: Node = _world.get_node_or_null("Director")
	if director == null:
		return false
	for c in director.things.get("calls", []):
		if float(c[2]) > float(director.elapsed) and ((int(c[0]) == a and int(c[1]) == b) or (int(c[0]) == b and int(c[1]) == a)):
			return true
	return false


## Forget voices when a session ends (new peers reuse ids).
func reset() -> void:
	for id in _peers:
		if is_instance_valid(_peers[id].player):
			_peers[id].player.queue_free()
	_peers.clear()
