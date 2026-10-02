extends SceneTree
## Open-mic gate check: `godot --headless --path . -s scripts/mic_gate_test.gd`.
## Feeds synthetic 20 ms frames to the Voice autoload (as host of an empty session, no network) and counts what it
## would send: a key click never opens the mic, speech opens it with the frames just before it, the hang tail holds,
## and push-to-talk / mode switches / being offline never send audio from before the key.

## A session host with nobody connected: Voice._online() is true, and nothing leaves the process.
class FakeHost extends MultiplayerPeerExtension:
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED
	func _get_unique_id() -> int:
		return 1
	func _is_server() -> bool:
		return true
	func _poll() -> void:
		pass
	func _get_available_packet_count() -> int:
		return 0
	func _get_max_packet_size() -> int:
		return 1024
	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()
	func _put_packet_script(_p: PackedByteArray) -> Error:
		return OK
	func _set_target_peer(_p: int) -> void:
		pass
	func _get_packet_peer() -> int:
		return 0
	func _get_packet_channel() -> int:
		return 0
	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _set_transfer_channel(_c: int) -> void:
		pass
	func _get_transfer_channel() -> int:
		return 0
	func _set_transfer_mode(_m: MultiplayerPeer.TransferMode) -> void:
		pass
	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _set_refuse_new_connections(_b: bool) -> void:
		pass
	func _is_refusing_new_connections() -> bool:
		return false
	func _is_server_relay_supported() -> bool:
		return false
	func _disconnect_peer(_p: int, _f: bool) -> void:
		pass
	func _close() -> void:
		pass


var _sent: Array = []  # loudness (as the header carries it) of every frame that would have been sent
var _fails := 0
var _voice: Node


func _frame_at(rms: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(480)
	for i in 480:
		f[i] = sin(TAU * 300.0 * i / 24000.0) * rms * 1.41421356
	return f


func _feed(rms: float, n := 1) -> void:
	for i in n:
		_voice._frame(_frame_at(rms), 0.02)


func _check(what: String, got: Variant, want: Variant) -> void:
	if str(got) != str(want):
		_fails += 1
		print("[mic-gate] FAIL %s: got %s, wanted %s" % [what, str(got), str(want)])


func _process(_delta: float) -> bool:  # the autoloads only exist once the loop runs
	_voice = root.get_node("Voice")
	var settings: Node = root.get_node("Settings")
	if not InputMap.has_action("push_to_talk"):
		InputMap.add_action("push_to_talk")
	var host := FakeHost.new()
	get_multiplayer().multiplayer_peer = host
	_voice.heard.connect(func(_id: int, rms: float): _sent.append(snappedf(rms, 0.001)))
	settings.voice_mode = 0
	settings.mic_gate = 0.012
	_check("online", _voice._online(), true)

	# Clicks and thumps: one or two loud frames, however loud, never open the mic.
	_feed(0.005, 10)
	_feed(0.1, 1)
	_feed(0.005, 20)
	_feed(0.1, 2)
	_feed(0.005, 20)
	_feed(0.1, 2)
	_feed(0.005, 1)
	_feed(0.1, 2)  # two clicks one frame apart are still not speech
	_feed(0.005, 20)
	_check("clicks send nothing", _sent.size(), 0)
	_check("clicks never show as talking", _voice.transmitting, false)

	# Speech: opens on the 3rd loud frame and first sends PREROLL frames (2 loud + 3 quiet), then the live one.
	_feed(0.0055, 3)  # the header carries milli-RMS, truncated: 0.0055 reads 0.005
	_feed(0.05, 2)
	_check("2 loud frames: still closed", _sent.size(), 0)
	_feed(0.05, 1)
	_check("opens with its pre-roll", _sent, [0.005, 0.005, 0.005, 0.05, 0.05, 0.05])
	_check("talking", _voice.transmitting, true)
	_feed(0.05, 7)
	_feed(0.005, 17)  # HANG 0.35 s = 17 more frames
	_check("hang tail", _sent.size(), 6 + 7 + 17)
	_check("still open on the last tail frame", _voice.transmitting, true)
	_feed(0.005, 1)
	_check("closed after the tail", _voice.transmitting, false)
	_check("nothing more sent", _sent.size(), 30)

	# One loud frame inside the tail keeps a mic that is already open open (no new 3-frame wait).
	_sent.clear()
	_feed(0.004, 30)
	_feed(0.05, 3)
	_feed(0.005, 10)
	_feed(0.05, 1)
	_feed(0.005, 17)
	_check("a lone frame refreshes the hang", _sent.size(), 6 + 10 + 1 + 17)
	_feed(0.005, 10)

	# Auto-gain follows speech only: pre-roll and tail noise below the gate leave it alone.
	_voice._gain = 1.0
	_feed(0.004, 5)
	_feed(0.011, 2)
	_feed(0.02, 3)
	_check("gain moved by 3 speech frames only", snappedf(_voice._gain, 0.01), 1.5)
	_feed(0.005, 30)

	# Push-to-talk never sends anything from before the key.
	settings.voice_mode = 1
	_sent.clear()
	_feed(0.05, 10)
	_check("push-to-talk without the key", _sent.size(), 0)
	Input.action_press("push_to_talk")
	_feed(0.05, 1)
	_check("key down sends just that frame", _sent.size(), 1)
	_feed(0.05, 4)
	Input.action_release("push_to_talk")
	_feed(0.05, 3)
	_check("key held for 5 frames", _sent.size(), 5)

	# Switching to push-to-talk with the key already down: the open mic's history is not sent.
	settings.voice_mode = 0
	_feed(0.005, 8)
	settings.voice_mode = 1
	_sent.clear()
	Input.action_press("push_to_talk")
	_feed(0.005, 1)
	Input.action_release("push_to_talk")
	_check("mode switch forgets the pre-roll", _sent.size(), 1)

	# Switching the mic off mid-sentence and back: no stale hang.
	settings.voice_mode = 0
	_feed(0.05, 5)
	settings.voice_mode = 2
	_feed(0.05, 1)
	_check("mic off closes at once", _voice.transmitting, false)
	settings.voice_mode = 0
	_sent.clear()
	_feed(0.005, 1)
	_check("no stale hang after switching back", _sent.size(), 0)

	# Offline (no session): nothing is sent and the history doesn't pile up.
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	_sent.clear()
	_feed(0.005, 6)
	_feed(0.05, 5)
	_check("offline sends nothing", _sent.size(), 0)
	_check("offline keeps no history after opening", _voice._pre.size(), 0)

	# The dev test voice (--voice-test) still talks at once on any signal, whatever the gate.
	get_multiplayer().multiplayer_peer = FakeHost.new()
	_voice._test_amp = 0.03
	_sent.clear()
	_feed(0.03, 3)
	_feed(0.0, 3)
	_check("test voice", _sent.size(), 3)
	_voice._test_amp = 0.0

	print("[mic-gate] %s" % ("OK" if _fails == 0 else "FAIL"))
	quit(_fails)
	return true
