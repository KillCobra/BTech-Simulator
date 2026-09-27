extends Node
## Tiny MQTT 3.1.1 client over WebSocket, used only to find each other: session
## hosts and joiners swap short signaling messages through free public brokers.
## Connects to several brokers at once and uses all that answer, so one broker
## being down (or blocked on one side) doesn't matter. QoS 0 only.

signal connected                              # first broker connected
signal message(topic: String, text: String)

const BROKERS := [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
]

var brokers: Array = BROKERS.duplicate()  # set before start() to use fewer
var _socks: Array[WebSocketPeer] = []
var _state := {}       # socket -> 0 connecting, 1 sent CONNECT, 2 connected, -1 dead
var _topics: Array[String] = []
var _ping := 0.0
var _packet_id := 1
var is_ready := false


func start() -> void:
	for url in brokers:
		var ws := WebSocketPeer.new()
		ws.supported_protocols = PackedStringArray(["mqtt"])
		ws.inbound_buffer_size = 1 << 18
		if ws.connect_to_url(url) == OK:
			_socks.append(ws)
			_state[ws] = 0


func stop() -> void:
	for ws in _socks:
		if _state[ws] == 2:
			ws.send(PackedByteArray([0xE0, 0x00]))  # DISCONNECT
		ws.close()
	_socks.clear()
	_state.clear()
	_topics.clear()
	is_ready = false


func subscribe(topic: String) -> void:
	if not _topics.has(topic):
		_topics.append(topic)
	for ws in _socks:
		if _state[ws] == 2:
			_send_subscribe(ws, topic)


func publish(topic: String, text: String, retain := false) -> void:
	var body := _str(topic)
	body.append_array(text.to_utf8_buffer())
	var packet := _packet(0x31 if retain else 0x30, body)
	for ws in _socks:
		if _state[ws] == 2:
			ws.send(packet)


func _process(delta: float) -> void:
	_ping += delta
	for ws in _socks:
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if _state[ws] == 0:
					var body := _str("MQTT")
					body.append_array(PackedByteArray([4, 2, 0, 60]))  # v3.1.1, clean session, 60 s keepalive
					body.append_array(_str("bunk%08x" % randi()))
					ws.send(_packet(0x10, body))
					_state[ws] = 1
				while ws.get_available_packet_count() > 0:
					_handle(ws, ws.get_packet())
			WebSocketPeer.STATE_CLOSED:
				_state[ws] = -1
	if _ping > 30.0:
		_ping = 0.0
		for ws in _socks:
			if _state[ws] == 2:
				ws.send(PackedByteArray([0xC0, 0x00]))  # PINGREQ


func _handle(ws: WebSocketPeer, data: PackedByteArray) -> void:
	var at := 0
	while at < data.size():
		var kind := data[at] & 0xF0
		var length := 0
		var mult := 1
		var i := at + 1
		while i < data.size():
			var d := data[i]
			length += (d & 0x7F) * mult
			mult *= 128
			i += 1
			if d & 0x80 == 0:
				break
		var body := data.slice(i, i + length)
		at = i + length
		match kind:
			0x20:  # CONNACK
				if body.size() >= 2 and body[1] == 0:
					_state[ws] = 2
					for t in _topics:
						_send_subscribe(ws, t)
					if not is_ready:
						is_ready = true
						connected.emit()
			0x30:  # PUBLISH (QoS 0)
				if body.size() < 2:
					continue
				var tlen := (body[0] << 8) | body[1]
				var topic := body.slice(2, 2 + tlen).get_string_from_utf8()
				var text := body.slice(2 + tlen).get_string_from_utf8()
				message.emit(topic, text)


func _send_subscribe(ws: WebSocketPeer, topic: String) -> void:
	_packet_id = (_packet_id % 60000) + 1
	var body := PackedByteArray([_packet_id >> 8, _packet_id & 0xFF])
	body.append_array(_str(topic))
	body.append(0)
	ws.send(_packet(0x82, body))


static func _str(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	var out := PackedByteArray([b.size() >> 8, b.size() & 0xFF])
	out.append_array(b)
	return out


static func _packet(first: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([first])
	var n := body.size()
	while true:
		var d := n % 128
		n /= 128
		if n > 0:
			d |= 0x80
		out.append(d)
		if n == 0:
			break
	out.append_array(body)
	return out
