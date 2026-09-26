extends Node
## Listen-server networking over WebRTC: one player creates an online session,
## friends join it by name (or with manual invite codes).
## The host (peer 1) owns the player list and decides when the game starts.

signal players_changed
signal connected_ok
signal connection_failed
signal server_closed
signal game_started
signal returned_to_lobby
signal all_loaded          # server only: every peer has the world scene ready
signal late_joined(id: int) # server only: someone loaded into a round already running
signal player_left(id: int) # server only
signal player_leaving(id: int) # server only: fired before their info is removed
signal invite_ready(code: String)      # online host: code to send the next friend
signal reply_ready(code: String)       # online joiner: code to send back to the host
signal online_error(text: String)
signal lobby_map_changed  # the host picked another map in the lobby

const InviteCode := preload("res://scripts/invite_code.gd")
const ICE_SERVERS := {"iceServers": [{"urls": [
	"stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478",
]}]}

var online := false        # true once in an online session or invite-code game
var last_invite := ""      # online host: newest invite code, for when the lobby is rebuilt
var _pending := {}         # online host: peer id -> WebRTCPeerConnection waiting for a reply
var _next_online_id := 2

const MAX_PLAYERS := 8
const CLASSROOMS := ["Class A", "Class B", "Class C", "Lab"]
const ROUND_LENGTHS := [5, 8, 12, 20]
const MAP_COUNT := 5  # scenes/world/maps/maps.gd LIST

var players := {}  # peer_id -> {"name": String, "classroom": int, "look": Dictionary, "ready": bool}
var local_info := {"name": "Student", "classroom": 0, "look": {}}
var in_game := false
var round_minutes := 8.0
var map_choice := 0   # host's pick in the lobby: a map id, or -1 for random
var current_map := 0  # the map this round is played on (same on every peer)

var loaded_peers: Array = []  # replicated: peers whose world is ready for replication

var _loaded := {}
var _all_loaded_sent := false


## Replication filter: only send world nodes to peers that have the world loaded,
## so people can join (or rejoin) a round that's already running.
func is_loaded(peer: int) -> bool:
	return peer == 1 or loaded_peers.has(peer)


func add_join_filter(sync: MultiplayerSynchronizer) -> void:
	sync.add_visibility_filter(is_loaded)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Dev/CI (`--host`): a private round on this PC that nobody else can join.
func host_local() -> Error:
	var peer := WebRTCMultiplayerPeer.new()
	var err := peer.create_server()
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_reset_session()
	_register(local_info)
	return OK


# --- Online sessions: name + optional password ------------------------------------
# The host announces the session on public MQTT brokers (topic derived from the
# name). Joiners find it there, prove the password, get a player id, and swap
# WebRTC offer/answer/candidates through the broker. Then play is direct P2P.

const MqttLink := preload("res://scripts/mqtt_link.gd")
const SESSION_FRESH := 45.0  # seconds: an announcement older than this is a dead session

var session_name := ""
var _mqtt: Node
var _base := ""
var _pw_hash := ""
var _cid := ""
var _seen := {}
var _info := {}            # latest session announcement (joiner) / our own (host)
var _cid_of := {}          # host: peer id -> joiner's client id
var _conn_by_cid := {}     # host: client id -> WebRTCPeerConnection
var _early_cands := {}     # host: candidates that arrived before the offer
var _my_conn: WebRTCPeerConnection
var _join_reply := {}      # joiner: welcome/deny from host
var _announce_time := 0.0
var _routes := {"mine": {}, "theirs": {}}  # joiner: kinds of connection routes found on each side


static func _hash(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _session_topic(name: String) -> String:
	return "bunkmaster/v1/" + _hash(name.strip_edges().to_lower()).left(24)


func _start_mqtt() -> void:
	_stop_mqtt()
	_mqtt = MqttLink.new()
	add_child(_mqtt)
	_mqtt.message.connect(_on_mqtt_message)
	_mqtt.start()
	_seen.clear()
	_info = {}


func _stop_mqtt() -> void:
	if _mqtt:
		_mqtt.stop()
		_mqtt.queue_free()
		_mqtt = null


func _send(topic: String, data: Dictionary, retain := false) -> void:
	if _mqtt == null:
		return
	data.m = "%08x%08x" % [randi(), randi()]
	data.from = _cid
	_mqtt.publish(topic, JSON.stringify(data), retain)


## Waits (without blocking) until check.call() is true or the timeout passes.
func _wait_for(check: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if check.call():
			return true
		await get_tree().process_frame
	return check.call()


## False when the WebRTC library (libwebrtc_native dll next to the game) didn't
## load, e.g. the exe was run from inside the zip or antivirus removed the dll.
func webrtc_ok() -> bool:
	return WebRTCPeerConnection.new().initialize(ICE_SERVERS) == OK


const NO_WEBRTC := "Online play files are missing: extract the WHOLE zip into a folder and run BunkMaster.exe from there (the .dll file must sit next to it; don't open it from inside the zip). If the .dll keeps vanishing, your antivirus removed it."


## Host: create a session friends can join by name. Returns "" or a problem.
func create_session(name: String, password: String) -> String:
	if not webrtc_ok():
		return NO_WEBRTC
	name = name.strip_edges()
	if name.length() < 3:
		return "Pick a session name with at least 3 letters."
	_cid = "h%08x" % randi()
	_base = _session_topic(name)
	_pw_hash = _hash(name.to_lower() + "|" + password) if password != "" else ""
	_start_mqtt()
	_mqtt.subscribe(_base + "/info")
	if not await _wait_for(func(): return _mqtt != null and _mqtt.is_ready, 8.0):
		_stop_mqtt()
		return "Couldn't reach the matchmaking servers. Check your internet, or use manual codes."
	await _wait_for(func(): return not _info.is_empty(), 1.5)  # a live session with this name?
	if _session_alive(_info) and _info.get("from", "") != _cid:
		_stop_mqtt()
		return "A session called \"%s\" is already running. Pick another name." % name
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_server() != OK:
		_stop_mqtt()
		return "Couldn't start online play."
	multiplayer.multiplayer_peer = peer
	_reset_session()
	online = true
	session_name = name
	_mqtt.subscribe(_base + "/host")
	_announce()
	_register(local_info)
	return ""


func _session_alive(info: Dictionary) -> bool:
	return not info.is_empty() and Time.get_unix_time_from_system() - float(info.get("t", 0.0)) < SESSION_FRESH


func _announce() -> void:
	_announce_time = 0.0
	_info = {"t": Time.get_unix_time_from_system(), "name": session_name, "locked": _pw_hash != "",
		"players": players.size(), "in_game": in_game}
	_send(_base + "/info", _info.duplicate(), true)


## Joiner: find a session by name and connect. Returns "" once connecting, or a problem.
func join_session(name: String, password: String) -> String:
	if not webrtc_ok():
		return NO_WEBRTC
	name = name.strip_edges()
	if name == "":
		return "Type the session name your friend created."
	_cid = "c%08x" % randi()
	_base = _session_topic(name)
	_start_mqtt()
	_mqtt.subscribe(_base + "/info")
	_mqtt.subscribe(_base + "/c/" + _cid)
	if not await _wait_for(func(): return _mqtt != null and _mqtt.is_ready, 8.0):
		_stop_mqtt()
		return "Couldn't reach the matchmaking servers. Check your internet, or use manual codes."
	await _wait_for(func(): return _session_alive(_info), 4.0)
	if not _session_alive(_info):
		_stop_mqtt()
		return "No session called \"%s\" is running right now. Check the spelling, and that the host is in the lobby." % name
	if _info.get("locked", false) and password == "":
		_stop_mqtt()
		return "\"%s\" is password protected. Enter the password." % name
	_join_reply = {}
	_send(_base + "/host", {"kind": "join", "pw": _hash(name.to_lower() + "|" + password) if password != "" else "",
		"name": str(local_info.name)})
	if not await _wait_for(func(): return not _join_reply.is_empty(), 8.0):
		_stop_mqtt()
		return "The host didn't answer. Ask them to check they're still in the lobby."
	if _join_reply.kind == "deny":
		_stop_mqtt()
		return str(_join_reply.get("reason", "The host refused the connection."))
	# Welcome: become a WebRTC client with the id the host gave us, and offer.
	_routes = {"mine": {}, "theirs": {}}
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_client(int(_join_reply.id)) != OK:
		_stop_mqtt()
		return "Couldn't start online play."
	multiplayer.multiplayer_peer = peer
	_reset_session()
	online = true
	session_name = name
	_my_conn = _new_connection()
	var to_host := _base + "/host"
	_my_conn.session_description_created.connect(func(type: String, sdp: String):
		_my_conn.set_local_description(type, sdp)
		_send(to_host, {"kind": "offer", "sdp": sdp}))
	_my_conn.ice_candidate_created.connect(func(media: String, index: int, cand: String):
		if _share_candidate(cand):
			_send(to_host, {"kind": "cand", "media": media, "index": index, "cand": cand}))
	peer.add_peer(_my_conn, 1)
	_my_conn.create_offer()
	return ""


func _on_mqtt_message(topic: String, text: String) -> void:
	if text == "":
		if topic.ends_with("/info"):
			_info = {}  # host cleared the announcement
		return
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return
	var m := str(data.get("m", ""))
	if m != "" and _seen.has(m):
		return  # same message via another broker
	_seen[m] = true
	if topic.ends_with("/info"):
		_info = data
	elif topic.ends_with("/host") and multiplayer.is_server() and online:
		_host_message(data)
	elif topic.contains("/c/"):
		_joiner_message(data)


func _host_message(data: Dictionary) -> void:
	var cid := str(data.get("from", ""))
	var reply_to := _base + "/c/" + cid
	match str(data.get("kind", "")):
		"join":
			if _pw_hash != "" and str(data.get("pw", "")) != _pw_hash:
				_send(reply_to, {"kind": "deny", "reason": "Wrong password."})
				return
			if players.size() >= MAX_PLAYERS:
				_send(reply_to, {"kind": "deny", "reason": "The session is full (%d players)." % MAX_PLAYERS})
				return
			var id := _next_online_id
			_next_online_id += 1
			_cid_of[id] = cid
			_send(reply_to, {"kind": "welcome", "id": id})
		"offer":
			var id := -1
			for pid in _cid_of:
				if _cid_of[pid] == cid:
					id = pid
			var peer := multiplayer.multiplayer_peer as WebRTCMultiplayerPeer
			if id == -1 or peer == null or _conn_by_cid.has(cid):
				return
			var conn := _new_connection()
			conn.session_description_created.connect(func(type: String, sdp: String):
				conn.set_local_description(type, sdp)
				_send(reply_to, {"kind": "answer", "sdp": sdp}))
			conn.ice_candidate_created.connect(func(media: String, index: int, cand: String):
				if _share_candidate(cand):
					_send(reply_to, {"kind": "cand", "media": media, "index": index, "cand": cand}))
			peer.add_peer(conn, id)
			_conn_by_cid[cid] = conn
			conn.set_remote_description("offer", str(data.sdp))
			for c in _early_cands.get(cid, []):
				conn.add_ice_candidate(c[0], c[1], c[2])
			_early_cands.erase(cid)
		"cand":
			var c := [str(data.media), int(data.index), str(data.cand)]
			if _conn_by_cid.has(cid):
				_conn_by_cid[cid].add_ice_candidate(c[0], c[1], c[2])
			else:
				_early_cands.get_or_add(cid, []).append(c)


func _joiner_message(data: Dictionary) -> void:
	match str(data.get("kind", "")):
		"welcome", "deny":
			_join_reply = data
		"answer":
			if _my_conn:
				_my_conn.set_remote_description("answer", str(data.sdp))
		"cand":
			_routes.theirs[str(data.cand).get_slice(" ", 7)] = true
			if _my_conn:
				_my_conn.add_ice_candidate(str(data.media), int(data.index), str(data.cand))


func _leave_session() -> void:
	if _mqtt and multiplayer.is_server() and session_name != "":
		_mqtt.publish(_base + "/info", "", true)  # clear the announcement
	_stop_mqtt()
	session_name = ""
	_cid_of.clear()
	_conn_by_cid.clear()
	_early_cands.clear()
	_my_conn = null


func _process(delta: float) -> void:
	if _mqtt == null:
		return
	if session_name != "" and multiplayer.is_server():
		_announce_time += delta
		if _announce_time > 15.0:
			_announce()  # keep the session "fresh" for joiners
	elif session_name != "" and not multiplayer.is_server() \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_stop_mqtt()  # joined: the broker isn't needed any more


# --- Online play with invite codes (WebRTC, peer to peer, no accounts) ---------------
# Host: host_online() -> invite_ready(code) -> friend's reply -> accept_reply(code).
# Friend: join_online(code) -> reply_ready(code) -> connects when the host accepts.

func host_online() -> Error:
	var peer := WebRTCMultiplayerPeer.new()
	var err := peer.create_server()
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_reset_session()
	online = true
	_pending.clear()
	_register(local_info)
	new_invite()
	return OK


## Online host: prepare an invite code for the next friend.
func new_invite() -> void:
	var peer := multiplayer.multiplayer_peer as WebRTCMultiplayerPeer
	if peer == null or not multiplayer.is_server():
		return
	var id := _next_online_id
	_next_online_id += 1
	var conn := _new_connection()
	peer.add_peer(conn, id)
	_pending[id] = conn
	var offer := await _describe(conn, "")
	if offer.is_empty():
		online_error.emit("Couldn't create an invite. Is the internet connected?")
		return
	offer.i = id
	last_invite = InviteCode.encode(offer)
	invite_ready.emit(last_invite)


## Online host: the friend sent back their reply code.
func accept_reply(code: String) -> String:
	var data := InviteCode.decode(code)
	if data.is_empty() or not data.has("i") or not data.has("s"):
		return "That doesn't look like a reply code. Ask your friend to copy the whole thing."
	var id := int(data.i)
	if not _pending.has(id):
		return "That reply is for an old invite. Send your friend the newest invite code."
	var conn: WebRTCPeerConnection = _pending[id]
	_pending.erase(id)
	conn.set_remote_description("answer", data.s)
	for c in data.get("c", []):
		conn.add_ice_candidate(c[0], int(c[1]), c[2])
	new_invite()  # ready for the next friend
	return ""


## Friend: paste the host's invite; produces a reply code to send back.
func join_online(code: String) -> String:
	var data := InviteCode.decode(code)
	if data.is_empty() or not data.has("i") or not data.has("s"):
		return "That doesn't look like an invite code. Ask the host to copy the whole thing."
	var peer := WebRTCMultiplayerPeer.new()
	if peer.create_client(int(data.i)) != OK:
		return "Couldn't start online play."
	multiplayer.multiplayer_peer = peer
	_reset_session()
	online = true
	var conn := _new_connection()
	peer.add_peer(conn, 1)
	var answer := await _describe(conn, data.s, data.get("c", []))
	if answer.is_empty():
		online_error.emit("Couldn't create a reply code. Is the internet connected?")
		return ""
	answer.i = int(data.i)
	reply_ready.emit(InviteCode.encode(answer))
	return ""


## Dev: --share=srflx only offers that kind of route (tests the internet path
## between two games on one PC).
func _share_candidate(cand: String) -> bool:
	_routes.mine[cand.get_slice(" ", 7)] = true
	if OS.get_cmdline_user_args().has("--net-trace"):
		print("[net] local candidate: %s" % cand.get_slice(" ", 7))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--share="):
			return (" typ %s " % arg.trim_prefix("--share=")) in (cand + " ")
	return true


func _new_connection() -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize(ICE_SERVERS)
	return conn


## Menu check: can this network carry game traffic (UDP), and how strict is
## its NAT? Asks public STUN servers what address they see us at, from one
## socket: no answer = UDP blocked; different ports = strict (symmetric) NAT.
func test_network() -> String:
	var udp := PacketPeerUDP.new()
	if udp.bind(0) != OK:
		return "Couldn't open a network socket on this PC."
	var sent := {}  # transaction id (hex) -> server
	for srv: Array in [["stun.l.google.com", 19302], ["stun.cloudflare.com", 3478], ["stun1.l.google.com", 19302]]:
		var ip := IP.resolve_hostname(srv[0], IP.TYPE_IPV4)
		if ip == "":
			continue
		var tid := Crypto.new().generate_random_bytes(12)
		var msg := PackedByteArray([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42])  # binding request
		msg.append_array(tid)
		udp.set_dest_address(ip, srv[1])
		udp.put_packet(msg)
		sent[tid.hex_encode()] = srv[0]
	if sent.is_empty():
		return "No internet (couldn't look up any servers)."
	var seen := {}  # server -> mapped port
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000 and seen.size() < sent.size():
		await get_tree().process_frame
		while udp.get_available_packet_count() > 0:
			var p := udp.get_packet()
			var tid := p.slice(8, 20).hex_encode() if p.size() >= 20 else ""
			if sent.has(tid):
				var port := _stun_port(p)
				if port > 0:
					seen[sent[tid]] = port
	udp.close()
	var lines := []
	if not webrtc_ok():
		lines.append("ONLINE PLAY FILES: MISSING. " + NO_WEBRTC)
	if seen.is_empty():
		lines.append("GAME TRAFFIC (UDP): BLOCKED on this network. Online play can't work here: switch to a phone hotspot or mobile data.")
	else:
		var ports := {}
		for s in seen.values():
			ports[s] = true
		lines.append("GAME TRAFFIC (UDP): OK.")
		if ports.size() == 1:
			lines.append("NAT: easy. Direct connections should work.")
		else:
			lines.append("NAT: strict. Direct connections can fail on this network; a phone hotspot on one side usually helps.")
	var link := MqttLink.new()
	add_child(link)
	link.start()
	await _wait_for(func(): return link.is_ready, 6.0)
	lines.append("Matchmaking servers: %s." % ("reachable" if link.is_ready else "NOT reachable (sessions can't be found; use manual codes)"))
	link.stop()
	link.queue_free()
	return "\n".join(lines)


## Menu button: let the game through the Windows firewall. Asks for admin
## (UAC) and adds allow rules for this exe, dropping any block rules Windows
## made when an earlier firewall popup was dismissed. If admin is declined,
## listens on a port so Windows shows its own "allow access" popup instead.
func request_firewall_access() -> String:
	if OS.get_name() != "Windows":
		return "Only needed on Windows. On Mac: System Settings > Network > Firewall > Options, allow Bunk Master."
	var exe := OS.get_executable_path().replace("/", "\\")
	var dir := ProjectSettings.globalize_path("user://").replace("/", "\\")
	var script := dir + "allow_network.cmd"
	var done := dir + "allow_network.done"
	DirAccess.remove_absolute(done)
	var f := FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		return "Couldn't write the firewall helper."
	f.store_string("@echo off\r\n"
		+ "netsh advfirewall firewall delete rule name=all program=\"%s\" >nul\r\n" % exe
		+ "netsh advfirewall firewall add rule name=\"Bunk Master\" dir=in action=allow program=\"%s\" enable=yes profile=any >nul\r\n" % exe
		+ "netsh advfirewall firewall add rule name=\"Bunk Master\" dir=out action=allow program=\"%s\" enable=yes profile=any >nul\r\n" % exe
		+ "echo ok> \"%s\"\r\n" % done)
	f.close()
	var cmd := "Start-Process -FilePath '%s' -Verb RunAs -WindowStyle Hidden -Wait" % script.replace("'", "''")
	var pid := OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", cmd])
	if pid > 0:
		var start := Time.get_ticks_msec()
		while OS.is_process_running(pid) and Time.get_ticks_msec() - start < 60000:
			await get_tree().create_timer(0.25).timeout
	if FileAccess.file_exists(done):
		return "Network access allowed in Windows Firewall."
	# No admin: listening makes Windows pop its own firewall question (only if no rule exists yet).
	var server := TCPServer.new()
	var udp := PacketPeerUDP.new()
	var port := randi_range(20000, 60000)
	server.listen(port)
	udp.bind(port)
	await get_tree().create_timer(8.0).timeout
	server.stop()
	udp.close()
	return "Admin access was declined. If Windows asked to allow Bunk Master, tick both boxes and press Allow. No popup? Windows Security > Firewall > Allow an app, and tick Bunk Master."


## Port from a STUN binding response (XOR-MAPPED-ADDRESS, or MAPPED-ADDRESS).
static func _stun_port(p: PackedByteArray) -> int:
	var at := 20
	while at + 4 <= p.size():
		var kind := (p[at] << 8) | p[at + 1]
		var length := (p[at + 2] << 8) | p[at + 3]
		if at + 4 + length > p.size():
			break
		if kind == 0x0020 and length >= 8:
			return ((p[at + 6] << 8) | p[at + 7]) ^ 0x2112
		if kind == 0x0001 and length >= 8:
			return (p[at + 6] << 8) | p[at + 7]
		at += 4 + ((length + 3) & ~3)
	return 0


## Joiner, after a failed connection: which side's network is the problem.
## (host = local address, srflx = internet address via UDP.)
func explain_failure() -> String:
	var mine: Dictionary = _routes.mine
	var theirs: Dictionary = _routes.theirs
	var line := "Routes: you %s, host %s." % ["+".join(mine.keys()) if mine else "none", "+".join(theirs.keys()) if theirs else "none"]
	if theirs.is_empty():
		return "No connection details arrived from the host (the matchmaking servers dropped them). Just try JOIN again.\n" + line
	if not mine.has("srflx"):
		return "YOUR network blocks game traffic (UDP), common on college/office Wi-Fi. Switch to a phone hotspot or mobile data.\n" + line
	if not theirs.has("srflx"):
		return "The HOST's network blocks game traffic (UDP), common on college/office Wi-Fi. The host should switch to a phone hotspot or mobile data.\n" + line
	return "Your networks block a direct connection (strict NAT, common on mobile data). Try a different network on one side, e.g. home Wi-Fi or another phone's hotspot.\n" + line


## Creates our side's description (offer, or answer to remote_sdp) and gathers
## network candidates, so everything fits in one code. Returns {"s", "c"}.
func _describe(conn: WebRTCPeerConnection, remote_sdp: String, remote_candidates := []) -> Dictionary:
	var result := {"s": "", "c": []}
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		result.s = sdp)
	conn.ice_candidate_created.connect(func(media: String, index: int, cand_name: String):
		result.c.append([media, index, cand_name]))
	if remote_sdp == "":
		conn.create_offer()
	else:
		conn.set_remote_description("offer", remote_sdp)  # answer is created automatically
		for c in remote_candidates:
			conn.add_ice_candidate(c[0], int(c[1]), c[2])
	# Wait for candidate gathering (STUN lookups) to finish, up to 5 s.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		await get_tree().process_frame
		conn.poll()
		if result.s != "" and conn.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE:
			break
	return result if result.s != "" else {}


func leave() -> void:
	_leave_session()
	online = false
	last_invite = ""
	_pending.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_session()


func is_host() -> bool:
	return multiplayer.is_server()


func set_local_info(player_name: String, classroom: int) -> void:
	local_info.name = player_name
	local_info.classroom = classroom
	push_local_info()


## Sends local_info (name, classroom, look) to the host.
func push_local_info() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.is_server():
		_register(local_info)
	else:
		_register.rpc_id(1, local_info)


## Everyone in the lobby has pressed READY (the host counts as ready: they press START).
func all_ready() -> bool:
	for id in players:
		if id != 1 and not bool(players[id].get("ready", false)):
			return false
	return true


func is_ready(id: int) -> bool:
	return id == 1 or bool(players.get(id, {}).get("ready", false))


## Lobby: this player is (or is no longer) ready to start.
func set_ready(value: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.is_server():
		_set_ready(value)
	else:
		_set_ready.rpc_id(1, value)


@rpc("any_peer", "reliable")
func _set_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not players.has(id) or in_game:
		return
	players[id].ready = value or id == 1
	_sync_players.rpc(players)
	players_changed.emit()


func start_game() -> void:
	if multiplayer.is_server() and not in_game and all_ready():
		current_map = map_choice if map_choice >= 0 else randi() % MAP_COUNT
		_start.rpc(round_minutes, current_map)


## Host: end the round screen and bring everyone back to the lobby.
func back_to_lobby() -> void:
	if multiplayer.is_server():
		_back_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	in_game = false
	_loaded.clear()
	loaded_peers.clear()
	_all_loaded_sent = false
	if multiplayer.is_server():
		for id in players:
			players[id].ready = id == 1  # everyone readies up again for the next round
		_sync_players.rpc(players)
	returned_to_lobby.emit()


@rpc("authority", "call_local", "reliable")
func _set_loaded_peers(list: Array) -> void:
	loaded_peers = list


func report_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(1)
	else:
		_client_loaded.rpc_id(1)


func local_ipv4_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for addr in IP.get_local_addresses():
		if addr.count(".") == 3 and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			out.append(addr)
	return out


func _reset_session() -> void:
	players.clear()
	_loaded.clear()
	loaded_peers.clear()
	_all_loaded_sent = false
	in_game = false


# --- RPCs -------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var look_in: Variant = info.get("look", {})
	var was_ready: bool = bool(players.get(id, {}).get("ready", false))
	players[id] = {
		"name": _unique_name(id, str(info.get("name", "Student")).strip_edges().left(16)),
		"classroom": clampi(int(info.get("classroom", 0)), 0, CLASSROOMS.size() - 1),
		"look": look_in if look_in is Dictionary else {},
		"ready": was_ready or id == 1,  # newcomers start NOT ready
	}
	_sync_players.rpc(players)
	if id != 1:
		_lobby_map.rpc_id(id, map_choice)
	players_changed.emit()


## Two students can't share a name (it's how everyone tells them apart): "Sam" -> "Sam 2".
func _unique_name(id: int, wanted: String) -> String:
	if wanted == "":
		wanted = "Student"
	var taken := {}
	for other in players:
		if other != id:
			taken[str(players[other].name).to_lower()] = true
	var out := wanted
	var n := 2
	while taken.has(out.to_lower()):
		out = "%s %d" % [wanted.left(13), n]
		n += 1
	return out


## Host: pick the lobby map (a map id or -1 for random); everyone's lobby shows it.
func set_map_choice(choice: int) -> void:
	map_choice = choice
	lobby_map_changed.emit()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_lobby_map.rpc(choice)


@rpc("authority", "reliable")
func _lobby_map(choice: int) -> void:
	map_choice = clampi(choice, -1, MAP_COUNT - 1)
	lobby_map_changed.emit()


@rpc("authority", "reliable")
func _sync_players(all_players: Dictionary) -> void:
	players = all_players
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start(minutes: float, map_id := 0) -> void:
	round_minutes = minutes
	current_map = clampi(map_id, 0, MAP_COUNT - 1)
	in_game = true
	if multiplayer.is_server():
		_loaded.clear()
		loaded_peers.clear()
		_all_loaded_sent = false
	game_started.emit()


@rpc("any_peer", "reliable")
func _client_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	_loaded[id] = true
	if not loaded_peers.has(id):
		loaded_peers.append(id)
		_set_loaded_peers.rpc(loaded_peers)
	if _all_loaded_sent and in_game:
		late_joined.emit(id)
	_check_all_loaded()


func _check_all_loaded() -> void:
	if not in_game or _all_loaded_sent:
		return
	for id in players:
		if not _loaded.has(id):
			return
	_all_loaded_sent = true
	all_loaded.emit()


# --- Connection events --------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# Joining mid-round: tell them to load the world; they spawn once it's ready.
	if multiplayer.is_server() and in_game:
		_start.rpc_id(id, round_minutes, current_map)
		_set_loaded_peers.rpc_id(id, loaded_peers)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	player_leaving.emit(id)
	players.erase(id)
	_loaded.erase(id)
	loaded_peers.erase(id)
	_set_loaded_peers.rpc(loaded_peers)
	_sync_players.rpc(players)
	players_changed.emit()
	player_left.emit(id)
	_check_all_loaded()


func _on_connected_to_server() -> void:
	_register.rpc_id(1, local_info)
	connected_ok.emit()
	if OS.get_cmdline_user_args().has("--autoready"):  # dev: test bots ready up by themselves
		set_ready.call_deferred(true)


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	server_closed.emit()
