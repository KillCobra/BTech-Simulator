extends Node
## Server-side game rules and NPC brains. Everything here runs on the host;
## the replicated vars below let every client's HUD show suspicion, items,
## quests, timers and events. Clients talk to it through `request()`.
##
## Rules in one breath: stay at your seat while your teacher watches and stay
## in your own classroom during class. Staff who see you breaking a rule fill
## your suspicion; at 100 they chase (or call someone who will). Caught =
## detention. Absent at attendance = +45. Get outside the university grounds
## (the map's outer walls) = escaped.

const CampusBuilder := preload("res://scenes/world/campus_builder.gd")
const Questions := preload("res://scripts/questions.gd")
const P := preload("res://scripts/palette.gd")

const DETENTION_TIME := 20.0
const DETENTION_STEP := 5.0   # every extra catch adds this much
const PASSING_TIME := 25.0    # class change: this long to walk to the next class
const RETURN_GRACE := 60.0    # after detention: this long to walk back to class
const GOOD_TIME := 45.0       # sit nicely this long and your teacher calms down a notch
const EXAM_TIME := 75.0      # the whole test window: papers handed out, then written
const EXAM_WRITE := 30.0     # each student's own time once they have the paper (look-over + 25 s)
const PASS_RETURN := 40.0    # a hall pass ran out: this long to walk back without trouble
const SETTLE_TIME := 7.0     # walking into your classroom: this long to reach your seat
const ASK_COOLDOWN := 25.0
const HAND_LINES := ["Here. No peeking at your neighbour.", "Name at the top. Neatly.", "Good luck. You'll need it.",
	"Eyes on your own paper.", "Phones away. I can see you.", "Read every question twice.", "Pens only. No pencils."]
const LATE_LINES := ["Late AND unprepared, hmm? Here.", "Nice of you to join us. Your paper.",
	"Tsk. Sit. Write. Quickly.", "Sit. Write. Don't make me regret this.", "Oh, you decided to come? Take it."]
const SUBJECTS := ["Thermodynamics", "Engineering Maths", "Data Structures", "Chemistry"]
const LINES := ["I will not bunk class.", "I will respect my teachers.", "Attendance is not optional.",
	"The canteen is not a classroom.", "I will stay in my seat.", "I will not pull the fire alarm.",
	"I will not climb out of windows.", "Lockers are for books, not students.", "I will not bribe staff with samosas.",
	"The service gate is not an exit.", "I will not answer attendance for my friends.", "Paper balls are not homework.",
	"The principal's car is not a selfie spot.", "I will raise my hand before I speak.", "I will not sprint in the corridors.",
	"A hall pass is not a holiday.", "I will not hide in the washroom.", "The library is a place of silence.",
	"I will copy my own notes.", "I will not ring the office bell for fun.", "Exams are not a group project.",
	"I will not play the drums during class.", "Detention is not a social club.", "My seat misses me when I leave it.",
	"I will not trade samosas during lectures."]
const CONTRABAND := ["canteen_key", "medical_note", "hall_pass"]
const CATCH_DIST := 1.5
const NOISE_RADIUS := 8.0
const HALL_PASS_TIME := 35.0
const ALARM_TIME := 25.0
const ALARM_COOLDOWN := 150.0
const GATE_OPEN_TIME := 12.0
const PICKUP_RESPAWN := 45.0
const MAX_ITEMS := 3
# [name, uses she/her-style look (no moustache, longer hair)]
const TEACHERS := [["Ms. Okafor", true], ["Mr. Tanaka", false], ["Dr. Alvarez", false], ["Mrs. Iyer", true]]
const SHOUTS := ["Hey! Stop right there!", "Where do you think you're going?!", "Come back here!", "You! Which class?!"]

const ITEMS := {
	"hall_pass": "Hall Pass", "samosa": "Samosa", "medical_note": "Medical Note",
	"canteen_key": "Canteen Key", "library_book": "Library Book", "detention_ticket": "Detention Skip",
}
# Canteen shop (Pappu Uncle's counter). Prices in rupees.
const SHOP := {"samosa": 10, "hall_pass": 40, "medical_note": 70, "detention_ticket": 90}
const SHOP_ABOUT := {
	"samosa": "Eat it, or bribe staff close by",
	"hall_pass": "Walk the corridors without trouble",
	"medical_note": "Show it to a gate guard to walk out",
	"detention_ticket": "Caught? Flash it and skip detention",
}
# Upgrades: [name, what it does, price per level].
const UPGRADES := {
	"pass": ["Signed passes", "+15 s on every hall pass", [50, 80, 120]],
	"shoes": ["Soft shoes", "Staff hear your sprinting from half as far", [100]],
}
const START_CASH := 30
const COIN_COUNT := 10
const COIN_RESPAWN := 20.0
const EXAM_GRACE := 8.0       # seconds to sit down once a test is announced
const BUMP_LINES := ["Oi, watch it!", "Bro, seriously?", "Careful!", "Excuse YOU.", "Ow! My foot!",
	"Walk much?", "Arre, dekh ke chalo!", "Hey! I'm walking here!", "Rude.", "Personal space, please!"]
const QUESTS := {
	"samosa": "Eat a samosa from the canteen",
	"exam": "Steal the exam paper from the staff room",
	"library": "Return the overdue library book",
	"selfie": "Selfie with the principal's car (unseen)",
	"register": "Sign the register while your teacher isn't looking",
	"hoop": "Score a basket on the court",
	"notice": "Stick a meme on a notice board",
	"bell": "Ring the staff room bell",
}
const QUEST_POINTS := 150

# Replicated (server -> everyone).
var status := {}  # peer_id -> see _new_status()
var rooms := []   # per classroom: {"attendance_in", "calling", "exam_at", "exam_until", "exam_id"}
var feed := []    # [{"t": elapsed, "text": String}]
var marks := []   # [{"pos": Vector3, "npc": String, "by": String, "until": float}]
var world := {"alarm_until": -100.0, "alarm_ready": 0.0, "gate_until": -100.0, "taken": {}, "stash": {},
	"period": 0, "periods": 3, "period_len": 160.0, "period_start": 0.0, "passing_until": -100.0, "coins": []}
var elapsed := 0.0
var round_time := 480.0
var round_over := false
var results := []

signal toasted(text: String, color: Color)
signal effect(kind: String, pos: Vector3, extra: String)

var campus: RefCounted
var players_root: Node3D
var npc_spawner: MultiplayerSpawner
var prop_spawner: MultiplayerSpawner

const GRAB_TIME := 0.9    # seconds a grabbed student has to shove free
const SHOVE_STUN := 2.2
const SHOVE_RANGE := 2.4

var _balls: Array[Node] = []

var _brains: Array[Dictionary] = []
var _extras: Array[Node] = []
var _adj: Array = []
var _graph_ready := false
var _seat := {}
var _departed := {}  # player name -> saved status, for rejoining
var _cool := {}  # peer_id -> {action: ready_time}
var _coin_spots: Array[Vector3] = []
var _coin_pools: Array = []  # [weight, spots, height, values, jitter]: where money tends to turn up
var _coin_due: Array[float] = []  # elapsed time when a picked-up coin comes back somewhere new
var _started := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in Network.CLASSROOMS.size():
		rooms.append({"attendance_in": 99999.0, "calling": false, "exam_at": 99999.0, "exam_until": -100.0, "exam_id": 0})
	# Big, nested state: reliable delta sync (too big for one unreliable packet).
	# _snapshot() swaps in deep copies each tick so change detection works on nested data.
	var big := MultiplayerSynchronizer.new()
	big.name = "Sync"
	big.delta_interval = 0.1
	var config := SceneReplicationConfig.new()
	for prop in [".:status", ".:rooms", ".:feed", ".:marks", ".:results"]:
		config.add_property(NodePath(prop))
		config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	big.replication_config = config
	Network.add_join_filter(big)
	add_child(big)
	# Small state sent continuously, so late joiners always get it.
	var small := MultiplayerSynchronizer.new()
	small.name = "SyncSmall"
	small.replication_interval = 0.2
	var small_config := SceneReplicationConfig.new()
	for prop in [".:world", ".:elapsed", ".:round_time", ".:round_over"]:
		small_config.add_property(NodePath(prop))
		small_config.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	small.replication_config = small_config
	Network.add_join_filter(small)
	add_child(small)


# --- Setup ---------------------------------------------------------------------------------

## Server: called once every player has been spawned. seats: peer_id -> Vector3.
func start(seats: Dictionary, minutes: float) -> void:
	_seat = seats
	round_time = minutes * 60.0
	_rng.randomize()
	for id in seats:
		status[id] = _new_status(id)
		_place_seat(id, seats[id])
	world.periods = clampi(roundi(round_time / 160.0), 2, 6)
	world.period_len = round_time / float(world.periods)
	world.passing_time = _passing_time()
	_schedule_period(0)

	for k in campus.ball_spawns.size():
		_balls.append(prop_spawner.spawn({"id": "Ball%d" % k, "pos": campus.ball_spawns[k]}))
	_setup_coins()
	if OS.get_cmdline_user_args().has("--no-staff"):  # dev: test routes without staff
		_log("Class has started (no staff).")
		_started = true
		return
	for i in campus.classes.size():
		var spots: Dictionary = campus.classes[i]
		var fem: bool = TEACHERS[i][1]
		_add_npc({"id": "Teacher%d" % i, "role": "teacher", "room": i, "name": TEACHERS[i][0],
			"pos": spots.board, "yaw": spots.yaw, "look": _staff_look(100 + i, fem), "voice": (1.15 if fem else 0.8) + i * 0.05},
			{"state": "write", "timer": 6.0, "range": 14.0, "fov": 100.0, "walk": 1.4, "chase_speed": 4.4, "alertness": 1.0, "chaser": true})
	_add_npc({"id": "Guard", "role": "gate", "room": -1, "name": "Sergei (Guard)",
		"pos": campus.gate_post, "yaw": campus.gate_yaw, "look": P.make_guard_look(7, true), "voice": 0.7},
		{"state": "post", "timer": 20.0, "range": 14.0, "fov": 110.0, "walk": 1.6, "chase_speed": 4.8, "alertness": 2.2, "chaser": true})
	_add_patrol("Peon", "Mr. Mendes (Caretaker)", campus.staff_loops.peon, P.make_guard_look(9, false), 1.9, 4.5, 1.4, 11.0, 0.75)
	var prefect := P.make_look(4242, 0)
	prefect.tie = Color("ffd24a")
	prefect.bag = null
	prefect.cap = Color("e0524f")
	prefect.mustache = false
	_add_patrol("Prefect", "Aisha (Prefect)", campus.staff_loops.prefect, prefect, 1.8, 4.6, 1.0, 10.0, 1.3)
	var vp := _staff_look(777, false)
	vp.shirt = Color("9a62d6")
	vp.glasses = true
	var proctor := _staff_look(888, false)
	proctor.shirt = Color("4f7fd9")
	_add_patrol("Proctor", "Mr. Kowalski (Proctor)", campus.staff_loops.proctor, proctor, 1.5, 4.6, 1.2, 12.0, 0.9)
	_add_patrol("VP", "Dr. Haddad (Vice Principal)", campus.staff_loops.vp, vp, 1.4, 5.0, 1.15, 11.0, 1.1)

	var ss: Dictionary = campus.staff_sit
	var ls: Dictionary = campus.librarian_sit
	var us: Dictionary = campus.uncle_spot
	_add_sitter("Staff", "Mrs. Lindqvist (on break)", ss.pos, ss.yaw, ss.away,
		_staff_look(55, true), ss.zone, "zone", true, "Reading the newspaper...", 1.2)
	_add_sitter("Librarian", "Ms. Nguyen (Librarian)", ls.pos, ls.yaw, ls.away,
		_staff_look(66, true), ls.zone, "sprint", false, "Shelving books...", 1.3)
	var uncle := P.make_guard_look(31, false)
	uncle.shirt = Color("f4f1e6")
	uncle.trousers = Color("3a3d47")
	_add_sitter("Uncle", "Pappu Uncle (Canteen)", us.pos, us.yaw, us.away,
		uncle, us.zone, "zone", false, "Making chai...", 0.75)
	_spawn_grounds_staff()

	_spawn_extras()
	_log("Class has started. Good luck bunking!")
	_fx_all("bell", Vector3.ZERO, "")
	_started = true


## Remembers which seat (by index) a player sits in, so it can follow them to
## the same place in every classroom after a class change.
func _place_seat(id: int, pos: Vector3) -> void:
	var room := current_room(id)
	var list: Array = campus.seats[room]
	var idx := 0
	var best := INF
	for k in list.size():
		var d: float = (list[k] as Vector3).distance_to(pos)
		if d < best:
			best = d
			idx = k
	status[id].seat_idx = idx
	status[id].seat = list[idx]
	_seat[id] = list[idx]


## Seconds to walk between consecutive classrooms, with some slack: 25 s on the
## small school, more on big campuses with far-apart wings and tall towers.
func _passing_time() -> float:
	var worst := 0.0
	var n: int = campus.classes.size()
	for i in n:
		var a: Dictionary = campus.classes[i]
		var b: Dictionary = campus.classes[(i + 1) % n]
		var flat: float = (a.rect as Rect2).get_center().distance_to((b.rect as Rect2).get_center())
		var climb: float = absf(float(a.y) - float(b.y))
		worst = maxf(worst, (flat * 1.4 + climb * 4.0) / 3.4 + 8.0)
	return clampf(worst, PASSING_TIME, 75.0)


## The classroom a player should be in right now (their class moves every period).
func current_room(id: int) -> int:
	var n: int = maxi(1, campus.classes.size())
	return (int(Network.players.get(id, {}).get("classroom", 0)) + int(world.period)) % n


func _schedule_period(p: int) -> void:
	world.period = p
	world.period_start = elapsed
	world.passing_until = elapsed + (float(world.get("passing_time", PASSING_TIME)) if p > 0 else 0.0)
	var settle: float = float(world.passing_until) - elapsed
	var plen: float = world.period_len
	for i in rooms.size():
		rooms[i].calling = false
		rooms[i].attendance_in = settle + plen * 0.28 + i * 6.0  # once per period
		rooms[i].exam_at = minf(elapsed + settle + plen * 0.62 + i * 4.0, elapsed + plen - EXAM_TIME - 10.0)
		rooms[i].called = []  # who has answered the roll this period


## Bell: every class moves on to its next subject.
func _class_change() -> void:
	_schedule_period(int(world.period) + 1)
	_students_change_rooms()
	_fx_all("bell", Vector3.ZERO, "")
	_log("CLASS CHANGE! Period %d of %d. %ds to reach your next class." % [int(world.period) + 1, int(world.periods), int(world.get("passing_time", PASSING_TIME))])
	for b in _brains:
		if b.role == "teacher" and b.state == "attendance":
			b.state = "write"
			b.timer = 3.0
			_resume(b)
	for id in status:
		var st: Dictionary = status[id]
		var room := current_room(id)
		var list: Array = campus.seats[room]
		st.seat = list[mini(int(st.seat_idx), list.size() - 1)]
		_seat[id] = st.seat
		st.good_time = 0.0
		st.bunking = false
		if st.state in ["class", "chased"]:
			_tell(id, "CLASS CHANGE! Go to %s for %s." % [Network.CLASSROOMS[room], SUBJECTS[room]], Color("9fd8ff"))


## Bell: the NPC students in each classroom pack up, walk out and head to a
## free desk in the next classroom (a moment apart, like a real class).
func _students_change_rooms() -> void:
	var n: int = campus.classes.size()
	var taken := {}
	for b in _brains:
		if b.role == "extra" and int(b.get("class_room", -1)) >= 0:
			var to := (int(b.class_room) + 1) % n
			var seats: Array = (campus.seats[to] as Array).slice(8)
			var pick: Vector3 = b.seat
			for sp: Vector3 in seats:
				if not taken.has(sp):
					pick = sp
					break
			taken[pick] = true
			b.class_room = to
			b.seat = pick
			b.seat_yaw = campus.classes[to].yaw
			b.state = "leave"
			b.leave_at = elapsed + _rng.randf_range(0.3, 3.5)


func _add_npc(data: Dictionary, brain: Dictionary) -> Dictionary:
	var npc: Node = npc_spawner.spawn(data)
	brain.npc = npc
	brain.role = data.role
	brain.room = data.room
	brain.home = data.pos
	brain.home_yaw = data.yaw
	brain.target = -1
	brain.t = _rng.randf() * 10.0
	brain.distracted_until = -1.0
	brain.lost = 0.0
	_brains.append(brain)
	return brain


## Teacher look; `fem` = no moustache and longer hair.
func _staff_look(seed_value: int, fem: bool) -> Dictionary:
	var look := P.make_teacher_look(seed_value)
	if fem:
		look.mustache = false
		look.hair_style = [1, 3, 5][seed_value % 3]
	return look


## The map's own guards and patrols out in the university grounds.
func _spawn_grounds_staff() -> void:
	var n := 0
	for g in campus.posts:
		_add_npc({"id": g.id, "role": "gate", "room": -1, "name": g.name, "pos": g.pos, "yaw": g.yaw,
			"look": P.make_guard_look(int(g.seed) + 11, true), "voice": 0.75},
			{"state": "post", "timer": _rng.randf_range(20.0, 40.0), "range": 16.0, "fov": 110.0, "walk": 1.6,
			"chase_speed": 4.9, "alertness": 2.0, "chaser": true})
	for pt in campus.patrols:
		n += 1
		var look: Dictionary
		match str(pt.look):
			"teacher":
				look = _staff_look(500 + n * 13, pt.name.begins_with("Mrs.") or pt.name.begins_with("Ms."))
			"coach":
				look = _staff_look(600 + n, false)
				look.shirt = Color("e0524f")
				look.trousers = Color("24315e")
				look.cap = Color("24315e")
			"builder":
				look = P.make_guard_look(700 + n, true)
				look.shirt = Color("f2a93b")
				look.cap = Color("ffd24a")
			"ranger":
				look = P.make_guard_look(800 + n, true)
				look.shirt = Color("5a7a3a")
				look.trousers = Color("3a4a2a")
				look.cap = Color("3a4a2a")
			_:
				look = P.make_guard_look(900 + n, true)
		_add_patrol(pt.id, pt.name, pt.loop, look, pt.walk, pt.chase, 1.3, pt.view, 0.8 + (n % 4) * 0.12)


func _add_patrol(id: String, display: String, loop: Array, look: Dictionary, walk: float, chase: float, alertness: float, view: float, voice: float) -> void:
	_add_npc({"id": id, "role": "patrol", "room": -1, "name": display, "pos": loop[0], "yaw": 0.0, "look": look, "voice": voice},
		{"state": "patrol", "timer": 0.0, "range": view, "fov": 100.0, "walk": walk, "chase_speed": chase,
		"alertness": alertness, "loop": loop, "loop_i": 0, "chaser": true})


func _add_sitter(id: String, display: String, pos: Vector3, yaw: float, away_yaw: float, look: Dictionary,
		zone: Rect2, rule: String, chaser: bool, away_line: String, voice: float) -> void:
	_add_npc({"id": id, "role": "sitter", "room": -1, "name": display, "pos": pos, "yaw": yaw, "look": look, "voice": voice, "pose": 1},
		{"state": "sit", "timer": _rng.randf_range(10.0, 18.0), "range": 11.0, "fov": 110.0, "walk": 1.5, "chase_speed": 4.2,
		"alertness": 1.2, "zone": zone, "rule": rule, "chaser": chaser, "away_yaw": away_yaw, "away_line": away_line})


func _spawn_extras() -> void:
	var n := 0
	for room in campus.classes.size():
		# Seats 0-7 belong to players (in every room); students sit behind them.
		var free: Array = (campus.seats[room] as Array).slice(8)
		free.shuffle()
		for k in mini(3, free.size()):
			var b := _add_extra("Extra%d" % n, free[k], campus.classes[room].yaw, room, true, [])
			b.class_room = room
			b.seat = free[k]
			n += 1
	for k in campus.extra_seats.size():
		if k % 2 == 0:
			# Canteen chairs are on the near side of each table: face the table.
			_add_extra("Extra%d" % n, campus.extra_seats[k], float(campus.extra_yaws[k]) if k < campus.extra_yaws.size() else PI, _rng.randi() % 4, true, [])
			n += 1
	var walks: Array = campus.core_walks.duplicate()
	walks.append_array(campus.walkers)
	for w in walks:
		_add_extra("Extra%d" % n, w[0], 0.0, _rng.randi() % 4, false, w)
		n += 1


func _add_extra(id: String, pos: Vector3, yaw: float, room: int, sitting: bool, loop: Array) -> Dictionary:
	var b := _add_npc({"id": id, "role": "extra", "room": -1, "name": "", "pos": pos, "yaw": yaw,
		"look": P.make_look(_rng.randi(), room), "voice": 1.3, "pose": 1 if sitting else 0},
		{"state": "sit" if sitting else "walk", "timer": 0.0, "range": 0.0, "fov": 0.0, "walk": 1.3,
		"chase_speed": 0.0, "alertness": 0.0, "loop": loop, "loop_i": 0, "chaser": false})
	_extras.append(b.npc)
	return b


## Server: a player joined (or rejoined) a round in progress.
func add_player(id: int, seat: Vector3) -> void:
	var who := _name(id)
	if _departed.has(who):
		status[id] = _departed[who]
		_departed.erase(who)
		status[id].grabbed = false
		if status[id].state == "chased":
			status[id].state = "class"
		_log("%s is back!" % who)
	else:
		status[id] = _new_status(id)
		_log("%s joined the class late." % who)
	_place_seat(id, seat)


## Server: remember a leaving player's progress so they can rejoin by name.
func save_departed(id: int) -> void:
	if status.has(id):
		_departed[_name(id)] = status[id].duplicate(true)
	for b in _brains:
		if b.target == id:
			_end_chase(b)


## A free classroom seat for a late joiner (not a player's, not an NPC student's).
func free_seat(room: int) -> Vector3:
	for s in (campus.seats[room] as Array).slice(0, 8):
		if _seat.values().has(s):
			continue
		var taken := false
		for e in _extras:
			if e.global_position.distance_to(s) < 0.4:
				taken = true
		if not taken:
			return s
	return campus.seats[room][0] + Vector3(0, 0, -1.2)


func _new_status(id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + int(Time.get_unix_time_from_system())
	var pool: Array = QUESTS.keys()
	var quests := []
	for k in 3:
		var q: String = pool[rng.randi() % pool.size()]
		pool.erase(q)
		quests.append({"id": q, "done": false})
	var items := []
	for q in quests:
		if q.id == "library":
			items.append("library_book")
	return {"sus": 0.0, "state": "class", "seen": false, "caught": 0, "spotted": 0, "time": 0.0, "timer": 0.0,
		"bunking": false, "items": items, "quests": quests, "pass_until": -1.0, "gate_pass_until": -1.0, "score": 0,
		"grabbed": false, "shoves": 0, "seat_idx": 0, "seat": Vector3.ZERO, "strikes": 0, "good_time": 0.0,
		"returning": false, "return_until": -1.0, "essay_line": 0, "exam_key": "", "exam_total": 0, "exams": 0,
		"exams_missed": 0, "exam_photo": false, "cash": START_CASH, "earned": 0, "upgrades": {"pass": 0, "shoes": 0},
		"exam_in_at": -1.0, "exam_paper": "", "exam_deadline": -1.0, "wait_since": -1.0, "badges": {},
		"settle_until": -1.0, "had_pass": false, "pass_late": false, "was_in_room": true}


func _log(text: String) -> void:
	print("[%.1f] %s" % [elapsed, text])
	feed.append({"t": elapsed, "text": text})
	if feed.size() > 6:
		feed.pop_front()


# --- Client -> server requests ------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request(action: String, args: Dictionary) -> void:
	if not multiplayer.is_server() or not _started or round_over:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	var p := players_root.get_node_or_null(str(id))
	if p == null or not status.has(id):
		return
	var st: Dictionary = status[id]
	if st.state == "detention" or st.state == "escaped":
		if action != "ping" and not (action == "essay" and st.state == "detention"):
			return
	match action:
		"interact": _on_interact(id, p, int(args.get("i", -1)))
		"talk": _on_talk(id, p, str(args.get("npc", "")))
		"sit": _on_sit(id, int(args.get("room", -1)), int(args.get("seat", -1)))
		"use": _on_use(id, p, int(args.get("slot", -1)))
		"throw": _on_throw(id, p, args.get("from", p.global_position + Vector3(0, 1.5, 0)), args.get("dir", Vector3.FORWARD))
		"note": _on_note(id, p, int(args.get("i", -1)), int(args.get("n", 1)))
		"exam": _on_exam(id, p, int(args.get("room", -1)), int(args.get("id", -1)), int(args.get("score", 0)))
		"essay": _on_essay(id, str(args.get("text", "")))
		"ping": _on_ping(id, p, args)
		"proxy": _on_proxy(id, p)
		"boost": _on_boost(id, p, int(args.get("friend", -1)))
		"shove": _on_shove(id, p)
		"ball_grab": _on_ball_grab(id, p, str(args.get("ball", "")))
		"ball_throw": _on_ball_throw(id, p, args.get("dir", Vector3.FORWARD), float(args.get("power", 0.5)))
		"ball_drop": _on_ball_throw(id, p, Vector3.ZERO, 0.0)
		"buy": _on_buy(id, p, str(args.get("what", "")))
		"ask": _on_ask(id, p, int(args.get("kind", 0)), str(args.get("q", "")))
		"give": _on_give(id, p, int(args.get("to", -1)), int(args.get("cash", 0)), int(args.get("slot", -1)))


@rpc("authority", "call_local", "reliable")
func _toast(text: String, color: Color) -> void:
	toasted.emit(text, color)


@rpc("authority", "call_local", "reliable")
func _fx(kind: String, pos: Vector3, extra: String) -> void:
	effect.emit(kind, pos, extra)


func _tell(id: int, text: String, color := Color.WHITE) -> void:
	print("[tell %s] %s" % [_name(id), text])
	_toast.rpc_id(id, text, color)


func _fx_all(kind: String, pos: Vector3, extra: String) -> void:
	_fx.rpc(kind, pos, extra)


func _cooldown(id: int, action: String, seconds: float) -> bool:
	var c: Dictionary = _cool.get_or_add(id, {})
	if elapsed < float(c.get(action, -1.0)):
		return false
	c[action] = elapsed + seconds
	return true


func _give(id: int, item: String) -> bool:
	var items: Array = status[id].items
	if items.size() >= MAX_ITEMS:
		_tell(id, "Your pockets are full!", Color("ffb37a"))
		return false
	items.append(item)
	_fx.rpc_id(id, "pickup", Vector3.ZERO, "")
	_tell(id, "Got: %s" % ITEMS.get(item, item), Color("ffd24a"))
	return true


## Raised hand: ask the teacher something (see scripts/questions.gd).
func _on_ask(id: int, p: Node3D, kind: int, question: String) -> void:
	var st: Dictionary = status[id]
	var room := current_room(id)
	var t := _brain_of_room(room)
	if st.state != "class" or campus.room_of(p.global_position) != room or t.is_empty():
		_tell(id, "Ask your questions in your own class.", Color("ffb37a"))
		return
	if t.state in ["chase", "attendance", "evacuate", "handout"] or _distracted(t) or _stunned(t):
		_tell(id, "Your teacher is busy right now.", Color("ffb37a"))
		return
	var reply := Questions.reply_for(kind, question, room)
	if reply == "":
		return
	if not _cooldown(id, "ask", ASK_COOLDOWN):
		t.npc.say("One question at a time, %s!" % _name(id), 2.0)
		return
	var npc: Node = t.npc
	_log("%s: \"%s\"" % [_name(id), question])
	match kind:
		0:  # intelligent: the teacher is pleased
			st.sus = maxf(0.0, float(st.sus) - 20.0)
			st.good_time = float(st.good_time) + 20.0
			npc.stop(npc.yaw_towards(p.global_position - npc.global_position))
			npc.say(reply, 4.0)
			_pay(id, 5, "for a smart question")
		1:  # quirky: laughs all round
			st.sus = maxf(0.0, float(st.sus) - 8.0)
			npc.stop(npc.yaw_towards(p.global_position - npc.global_position))
			npc.say(reply, 4.0)
			for e in _extras:
				if is_instance_valid(e) and campus.room_of(e.global_position) == room and _rng.randf() < 0.5:
					e.say(["Hahaha!", "LOL", "*snort*", "Good one!"][_rng.randi() % 4], 1.6)
		_:  # mischievous: a rant at the board (a sneak window!) or a strike
			if _rng.randf() < 0.3:
				st.strikes = mini(3, int(st.strikes) + 1)
				st.sus = minf(99.0, float(st.sus) + 20.0)
				npc.say("Very funny, %s. I'm watching you." % _name(id), 3.0)
				_tell(id, "The teacher saw through it (strictness %d/3)." % int(st.strikes), Color("ff9a4a"))
			else:
				npc.say(reply, 4.0)
				t.state = "write"
				t.timer = 9.0
				var spots: Dictionary = campus.classes[room]
				npc.go_to(_path(npc.global_position, spots.board), t.walk)
				_log("%s is ranting at the board! Now's your chance..." % npc.display_name)
	_tell(id, "%s: \"%s\"" % [npc.display_name, reply], Questions.KIND_COLORS[clampi(kind, 0, 2)])


## Pocket money: rupees for quests, tests, attendance and coins found around campus.
func _pay(id: int, amount: int, why: String) -> void:
	if not status.has(id) or amount == 0:
		return
	var st: Dictionary = status[id]
	st.cash = int(st.cash) + amount
	if amount > 0:
		st.earned = int(st.earned) + amount
		_tell(id, "+Rs %d %s" % [amount, why], Color("ffd24a"))
		_fx.rpc_id(id, "coin", Vector3.ZERO, "")


func _near_counter(p: Node3D) -> bool:
	var i := _find_interactable("counter")
	return i != -1 and p.global_position.distance_to(campus.interactables[i].pos) < 3.5


## Canteen shop: items go in your pocket, upgrades last the whole round.
func _on_buy(id: int, p: Node3D, what: String) -> void:
	var st: Dictionary = status[id]
	if not _near_counter(p):
		_tell(id, "Buy things at Pappu Uncle's canteen counter.", Color("ffb37a"))
		return
	var price := -1
	var level := 0
	if SHOP.has(what):
		price = SHOP[what]
	elif UPGRADES.has(what):
		level = int(st.upgrades.get(what, 0))
		var prices: Array = UPGRADES[what][2]
		if level >= prices.size():
			_tell(id, "Already maxed out.", Color("ffb37a"))
			return
		price = prices[level]
	else:
		return
	if int(st.cash) < price:
		_tell(id, "Not enough money (need Rs %d)." % price, Color("ffb37a"))
		return
	if SHOP.has(what):
		if not _give(id, what):
			return
	else:
		st.upgrades[what] = level + 1
		_fx.rpc_id(id, "pickup", Vector3.ZERO, "")
		_tell(id, "Upgrade: %s (level %d)" % [UPGRADES[what][0], level + 1], Color("7fe0a0"))
	st.cash = int(st.cash) - price
	_npc_say("Uncle", ["Shukriya, beta!", "Good choice!", "Come again!"][_rng.randi() % 3])


## Trade with a classmate standing next to you: hand over money or an item.
func _on_give(id: int, p: Node3D, to: int, cash: int, slot: int) -> void:
	var friend := players_root.get_node_or_null(str(to))
	if friend == null or to == id or not status.has(to) or friend.global_position.distance_to(p.global_position) > 3.5:
		_tell(id, "Stand next to your classmate to trade.", Color("ffb37a"))
		return
	var st: Dictionary = status[id]
	var ft: Dictionary = status[to]
	if ft.state in ["detention", "escaped"]:
		return
	if cash > 0:
		cash = mini(cash, int(st.cash))
		if cash <= 0:
			_tell(id, "You're broke!", Color("ffb37a"))
			return
		st.cash = int(st.cash) - cash
		ft.cash = int(ft.cash) + cash
		_tell(id, "Gave Rs %d to %s." % [cash, _name(to)], Color("9fd8ff"))
		_tell(to, "%s gave you Rs %d!" % [_name(id), cash], Color("ffd24a"))
		_fx.rpc_id(to, "coin", Vector3.ZERO, "")
	elif slot >= 0 and slot < st.items.size():
		if ft.items.size() >= MAX_ITEMS:
			_tell(id, "%s's pockets are full." % _name(to), Color("ffb37a"))
			return
		var item: String = st.items[slot]
		st.items.remove_at(slot)
		ft.items.append(item)
		_tell(id, "Gave the %s to %s." % [ITEMS.get(item, item), _name(to)], Color("9fd8ff"))
		_tell(to, "%s gave you a %s!" % [_name(id), ITEMS.get(item, item)], Color("ffd24a"))
		_fx.rpc_id(to, "pickup", Vector3.ZERO, "")


## Coins lying around campus: walk over one to pocket it; another turns up
## somewhere else a little later. Only spots staff can walk to (the nav graph).
func _setup_coins() -> void:
	# Money turns up where students drop or stash it: by the lockers, in the
	# washrooms, under the desks and canteen chairs; now and then anywhere.
	var lockers: Array[Vector3] = []
	var washroom: Array[Vector3] = []
	for l: Dictionary in campus.lockers:
		if "stall" in str(l.label).to_lower():
			washroom.append(l.out)
		else:
			lockers.append(l.out)
	for it: Dictionary in campus.interactables:
		if it.kind in ["toilet", "cistern"]:
			washroom.append(it.pos)
	var desks: Array[Vector3] = []
	for room: Array in campus.seats:
		desks.append_array(room)
	var canteen: Array[Vector3] = []
	canteen.append_array(campus.extra_seats)
	var open: Array[Vector3] = []
	for pt in campus.nav_points:
		if not campus.escaped(pt):
			open.append(pt)
	for pool: Array in [[0.3, lockers, 0.45, [10, 10, 15], 0.3], [0.2, washroom, 0.45, [10, 15, 20], 0.25],
			[0.25, desks, 0.2, [5, 5, 10], 0.0], [0.1, canteen, 0.2, [5, 10], 0.0], [0.15, open, 0.55, [5, 5, 10], 0.8]]:
		if not (pool[1] as Array).is_empty():
			_coin_pools.append(pool)
			_coin_spots.append_array(pool[1])
	if _coin_spots.is_empty():
		return
	var coins := []
	for k in COIN_COUNT:
		coins.append(_new_coin(coins))
	world.coins = coins
	if OS.get_cmdline_user_args().has("--trace"):
		for c: Dictionary in coins:
			print("[coin] Rs %d at %s h %.2f  (%s)" % [int(c.v), (c.p as Vector3).snapped(Vector3.ONE * 0.1), float(c.h), campus.place_name(c.p)])


func _new_coin(others: Array) -> Dictionary:
	var total := 0.0
	for pool: Array in _coin_pools:
		total += float(pool[0])
	var pos := Vector3.ZERO
	var pool: Array = _coin_pools[0]
	for attempt in 8:  # somewhere no other coin is lying
		var roll := _rng.randf() * total
		for p: Array in _coin_pools:
			roll -= float(p[0])
			if roll <= 0.0:
				pool = p
				break
		var spots: Array = pool[1]
		var j: float = pool[4]
		pos = (spots[_rng.randi() % spots.size()] as Vector3) + Vector3(_rng.randf_range(-j, j), 0, _rng.randf_range(-j, j))
		var clear := true
		for c: Dictionary in others:
			if (c.p as Vector3).distance_to(pos) < 3.0:
				clear = false
				break
		if clear:
			break
	var values: Array = pool[3]
	return {"p": pos, "h": float(pool[2]), "v": values[_rng.randi() % values.size()]}


func _coin_step(players: Dictionary) -> void:
	if _coin_spots.is_empty():
		return
	var coins: Array = world.coins
	for k in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[k]
		var pos: Vector3 = c.p
		for id in players:
			var p: Node3D = players[id]
			if status[id].state not in ["class", "chased"] or p.hidden:
				continue
			if absf(p.global_position.y - pos.y) < 1.2 and Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < 0.9:
				coins.remove_at(k)
				_coin_due.append(elapsed + COIN_RESPAWN)
				_pay(id, int(c.v), "found")
				break
	for k in range(_coin_due.size() - 1, -1, -1):
		if elapsed >= _coin_due[k]:
			_coin_due.remove_at(k)
			coins.append(_new_coin(coins))


func _complete(id: int, quest: String) -> void:
	for q in status[id].quests:
		if q.id == quest and not q.done:
			q.done = true
			_fx.rpc_id(id, "quest", Vector3.ZERO, "")
			_tell(id, "Quest complete: %s  +%d" % [QUESTS[quest], QUEST_POINTS], Color("7fe0a0"))
			_log("%s completed a side quest!" % _name(id))
			_pay(id, 40, "for the quest")
			return


func _on_interact(id: int, p: Node3D, index: int) -> void:
	if index < 0 or index >= campus.interactables.size():
		return
	var it: Dictionary = campus.interactables[index]
	if p.global_position.distance_to(it.pos) > 2.4:
		return
	var st: Dictionary = status[id]
	match it.kind:
		"pickup":
			if float(world.taken.get(index, -1.0)) > elapsed:
				_tell(id, "Someone already took it. Try again later.", Color("ffb37a"))
				return
			if it.item == "exam_paper":
				world.taken[index] = elapsed + PICKUP_RESPAWN
				st.exam_photo = true
				_fx.rpc_id(id, "pickup", Vector3.ZERO, "")
				_tell(id, "You snapped a photo of the exam paper! Your next test is in the bag.", Color("ffd24a"))
				_complete(id, "exam")
			elif _give(id, it.item):
				world.taken[index] = elapsed + PICKUP_RESPAWN
		"counter":
			_npc_say("Uncle", "Kya chahiye, beta?")
		"register":
			if int(it.room) != _own_room(id):
				_tell(id, "That's not your class register.", Color("ffb37a"))
				return
			var teacher := _brain_of_room(it.room)
			if teacher.is_empty() or teacher.state in ["write", "evacuate", "patrol", "chase", "return"] or _distracted(teacher):
				st.bunking = false
				_tell(id, "Signed yourself present. Smooth.", Color("7fe0a0"))
				_complete(id, "register")
			else:
				st.sus = minf(99.0, st.sus + 30.0)
				teacher.npc.say("What are you doing at my table?!", 2.5)
		"notice":
			_log("%s stuck a meme about the principal on the notice board." % _name(id))
			_complete(id, "notice")
		"hoop":
			if not _cooldown(id, "hoop", 2.0):
				return
			if _rng.randf() < 0.45:
				_tell(id, "SWISH! Nothing but net.", Color("7fe0a0"))
				_fx_all("swish", it.pos, "")
				_complete(id, "hoop")
			else:
				_tell(id, "Brick! Try again.", Color("ffb37a"))
		"car":
			if _seen_by_anyone(p):
				st.sus = minf(99.0, st.sus + 35.0)
				_tell(id, "Spotted posing with the principal's car!", Color("ff6a6a"))
			else:
				_fx.rpc_id(id, "camera", Vector3.ZERO, "")
				_tell(id, "Selfie taken. Instant classic.", Color("7fe0a0"))
				_complete(id, "selfie")
		"bell":
			if not _cooldown(id, "bell", 10.0):
				return
			_fx_all("office_bell", it.pos, "")
			_noise(it.pos, 16.0)
			_complete(id, "bell")
		"alarm":
			if elapsed < float(world.alarm_ready):
				_tell(id, "The alarm was just pulled. Wait %ds." % int(world.alarm_ready - elapsed), Color("ffb37a"))
				return
			_start_alarm()
			if _seen_by_anyone(p):
				st.sus = minf(99.0, st.sus + 40.0)
				_log("%s was seen pulling the fire alarm!" % _name(id))
			else:
				_log("Someone pulled the fire alarm! Everyone to the plaza!")
		"service_gate":
			if st.items.has("canteen_key"):
				_open_service_gate()
			else:
				_tell(id, "Locked. Pappu uncle keeps the key behind the counter.", Color("ffb37a"))
		"toilet":
			if not _cooldown(id, "toilet", 25.0):
				_tell(id, "You just went. Nobody needs to go THAT often.", Color("ffb37a"))
				return
			st.sus = maxf(0.0, st.sus - 25.0)
			st.pass_until = maxf(float(st.pass_until), elapsed + 20.0)
			_fx_all("flush", it.pos, "")
			_tell(id, "Ahh. Nobody questions a washroom break. (20s to wander back)", Color("7fe0a0"))
		"cistern":
			var key := str(index)
			if world.stash.has(key):
				if st.items.size() >= MAX_ITEMS:
					_tell(id, "Your pockets are full!", Color("ffb37a"))
					return
				var got: String = world.stash[key]
				world.stash.erase(key)
				st.items.append(got)
				_fx.rpc_id(id, "pickup", Vector3.ZERO, "")
				_tell(id, "Fished the %s out of the cistern. Ew." % ITEMS.get(got, got), Color("ffd24a"))
			elif st.items.is_empty():
				_tell(id, "Nothing to hide.", Color("ffb37a"))
			else:
				var item: String = st.items.pop_back()
				world.stash[key] = item
				_fx_all("stash", it.pos, "")
				_tell(id, "Hid the %s in the cistern. Nobody will find it here." % ITEMS.get(item, item), Color("9fd8ff"))
		"return_book":
			if st.items.has("library_book"):
				st.items.erase("library_book")
				_npc_say("Librarian", "Finally! Three months late!")
				_complete(id, "library")
			else:
				_tell(id, "You have no book to return.", Color("ffb37a"))


## Sitting in a free chair of your current class makes it your seat.
func _on_sit(id: int, room: int, seat: int) -> void:
	if room != current_room(id) or seat < 0 or seat >= mini(8, (campus.seats[room] as Array).size()):
		return
	var pos: Vector3 = campus.seats[room][seat]
	for other in status:
		if other != id and (status[other].seat as Vector3).distance_to(pos) < 0.1 and current_room(other) == room:
			return  # someone else's
	_place_seat(id, pos)


func _on_talk(id: int, p: Node3D, npc_name: String) -> void:
	var b := _brain_by_name(npc_name)
	if b.is_empty() or b.npc.global_position.distance_to(p.global_position) > 2.6 or b.state == "chase":
		return
	var st: Dictionary = status[id]
	# They stop what they're doing and turn to you while you talk.
	b.npc.stop(b.npc.yaw_towards(p.global_position - b.npc.global_position))
	st.talk_with = str(b.npc.name)
	st.talk_until = elapsed + 10.0  # the chat, plus time to walk back to your seat
	if b.state not in ["attendance", "evacuate", "chase", "investigate"]:
		if b.state != "stare":
			b.resume = b.state
		b.state = "stare"
		b.timer = 4.0
	if b.role == "teacher" and b.room == _own_room(id):
		if not _cooldown(id, "pass", 60.0):
			b.npc.say("I just said no. Sit down.", 2.0)
			return
		if _rng.randf() < 0.6:
			b.npc.say("Fine. Washroom, then straight back.", 2.5)
			_give(id, "hall_pass")
		else:
			b.npc.say("No! Wait till the bell.", 2.0)
			st.sus = minf(99.0, st.sus + 15.0)
	elif b.npc.name == "Uncle":
		_on_interact(id, p, _find_interactable("counter"))
	elif b.role != "extra":
		b.npc.say(["Shouldn't you be in class?", "Hmm? What is it?", "Go away, I'm busy."][_rng.randi() % 3], 2.0)


func _on_use(id: int, p: Node3D, slot: int) -> void:
	var st: Dictionary = status[id]
	if p.hidden:
		return
	var items: Array = st.items
	if slot < 0 or slot >= items.size():
		return
	var item: String = items[slot]
	match item:
		"hall_pass":
			items.remove_at(slot)
			var secs := HALL_PASS_TIME + 15.0 * int(st.upgrades.get("pass", 0))
			st.pass_until = elapsed + secs
			_tell(id, "Hall pass active for %ds. Walk, don't run." % int(secs), Color("9fd8ff"))
		"samosa":
			items.remove_at(slot)
			var near := _nearest_brain(p.global_position, 3.5, ["teacher", "gate", "patrol", "sitter"])
			if not near.is_empty() and near.target != id:
				near.distracted_until = elapsed + 12.0
				near.npc.say("Arre wah, samosa! *munch*", 3.0)
				if near.target != -1:
					_end_chase(near)
				_log("%s bribed %s with a samosa." % [_name(id), near.npc.display_name])
			else:
				_tell(id, "Crunchy, spicy, perfect.", Color("7fe0a0"))
				_complete(id, "samosa")
		"medical_note":
			var guard := _nearest_brain(p.global_position, 5.0, ["gate"])
			if not guard.is_empty() and guard.target != id:
				items.remove_at(slot)
				st.gate_pass_until = elapsed + 15.0
				guard.npc.say("Hmm... get well soon, beta. Go.", 3.0)
				_tell(id, "The guard bought it! Walk out now.", Color("7fe0a0"))
			else:
				_tell(id, "Show this to the gate guard up close.", Color("ffb37a"))
		"canteen_key":
			if p.global_position.distance_to(campus.service_gate_pos) < 3.5:
				_open_service_gate()
			else:
				_tell(id, "Use it at the service gate in the east wall.", Color("ffb37a"))
		"library_book":
			_tell(id, "Return it at the library desk.", Color("9fd8ff"))
		"detention_ticket":
			_tell(id, "Keep it in your pocket: it's used automatically if you get caught.", Color("9fd8ff"))


## Paper ball: flies along a real arc and stops at the first wall, floor or ceiling.
func _on_throw(id: int, p: Node3D, from: Vector3, dir: Vector3) -> void:
	if not _cooldown(id, "throw", 6.0):
		return
	if from.distance_to(p.global_position + Vector3(0, 1.4, 0)) > 1.5 or dir.length() < 0.1:
		from = p.global_position + Vector3(0, 1.5, 0)
	var v := dir.normalized() * 12.0 + Vector3.UP * 2.0
	var pos := from
	var t := 0.0
	var space := players_root.get_world_3d().direct_space_state
	var landed := false
	while t < 2.5:
		var nv := v + Vector3.DOWN * 9.8 * 0.02
		var next := pos + (v + nv) * 0.01
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, next, 1))
		t += 0.02
		if not hit.is_empty():
			pos = hit.position + (hit.normal as Vector3) * 0.06
			landed = true
			break
		pos = next
		v = nv
	if not landed:
		pos.y = maxf(pos.y, 0.06)
	var extra := "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%.2f" % [from.x, from.y, from.z, dir.normalized().x * 12.0, dir.normalized().y * 12.0 + 2.0, dir.normalized().z * 12.0, t]
	_fx_all("paper_arc", pos, extra)
	if OS.get_cmdline_user_args().has("--trace"):
		print("[paper] from %s landed %s after %.2fs" % [from, pos, t])
	get_tree().create_timer(t).timeout.connect(func(): _noise(pos, 11.0))


## Music room: play a note on the piano or the drums (loud: staff come to look).
func _on_note(id: int, p: Node3D, index: int, n: int) -> void:
	if index < 0 or index >= campus.interactables.size():
		return
	var it: Dictionary = campus.interactables[index]
	if not it.kind in ["piano", "drums"] or p.global_position.distance_to(it.pos) > 3.0:
		return
	if not _cooldown(id, "note", 0.08):
		return
	_fx_all("note", it.pos, "%s:%d" % [it.kind, clampi(n, 1, 8)])
	if _cooldown(id, "music_noise", 3.0):
		_noise(it.pos, 10.0)


## A finished class test (mini-game). Holding a photo of the exam paper = full marks.
func _on_exam(id: int, p: Node3D, room: int, exam_id: int, score: int) -> void:
	var st: Dictionary = status[id]
	if room != current_room(id) or room < 0 or room >= rooms.size() or campus.room_of(p.global_position) != room or not p.seated:
		return
	var r: Dictionary = rooms[room]
	var key := "%d:%d:%d" % [int(world.period), room, exam_id]
	if int(r.exam_id) != exam_id or st.exam_paper != key or elapsed > float(st.exam_deadline) + 5.0 or st.exam_key == key:
		return
	st.exam_key = key
	if st.exam_photo:
		score = 100
		st.exam_photo = false
	score = clampi(score, 0, 100)
	st.exam_total = int(st.exam_total) + score
	st.exams = int(st.exams) + 1
	_tell(id, "%s test: %d/100" % [SUBJECTS[room], score], Color("7fe0a0") if score >= 50 else Color("ffb37a"))
	_log("%s scored %d in the %s test." % [_name(id), score, SUBJECTS[room]])
	if score >= 20:
		_pay(id, score / 5, "for the test")
	if score == 100:
		var badges: Dictionary = st.badges
		badges[str(room)] = int(badges.get(str(room), 0)) + 1
		_fx.rpc_id(id, "badge", Vector3.ZERO, str(room))
		_tell(id, "MERIT BADGE: %s!  (x%d)" % [SUBJECTS[room], int(badges[str(room)])], Color("ffd24a"))
		_log("%s earned a %s merit badge!" % [_name(id), SUBJECTS[room]])


## Detention lines: copy the sentence exactly, get out sooner.
func _on_essay(id: int, text: String) -> void:
	var st: Dictionary = status[id]
	if st.state != "detention" or not _cooldown(id, "essay", 0.8):
		return
	var want: String = LINES[int(st.essay_line) % LINES.size()]
	if text.strip_edges().to_lower().replace("  ", " ") == want.to_lower():
		st.timer = maxf(2.0, float(st.timer) - 5.0)
		st.essay_line = (int(st.essay_line) + 1 + _rng.randi() % (LINES.size() - 1)) % LINES.size()
		_tell(id, "Line accepted. -5s", Color("7fe0a0"))
	else:
		_tell(id, "Copy it EXACTLY. The principal checks.", Color("ffb37a"))


func _on_ping(id: int, p: Node3D, args: Dictionary) -> void:
	if not _cooldown(id, "ping", 0.8):
		return
	var pos: Vector3 = args.get("pos", p.global_position)
	var kind := str(args.get("kind", "place"))
	if not kind in ["person", "object", "place"]:
		kind = "place"
	marks.append({"pos": pos, "npc": str(args.get("npc", "")), "player": int(args.get("player", 0)),
		"label": str(args.get("label", "")).left(40), "kind": kind, "by": _name(id), "until": elapsed + 7.0})
	print("[%.1f] ping by %s: %s '%s'" % [elapsed, _name(id), kind, marks[-1].label])
	while marks.size() > 8:
		marks.pop_front()
	_fx_all("ping", pos, "")


func _on_proxy(id: int, p: Node3D) -> void:
	if p.hidden:
		return
	var b := _brain_of_room(_own_room(id))
	if b.is_empty() or b.state != "attendance" or int(b.get("waiting", -1)) == -1 or b.waiting == id:
		return
	if campus.room_of(p.global_position) != b.room or b.get("proxied", false):
		return
	if _rng.randf() < 0.7:
		b.proxied = true
		b.proxied_by = id
		_tell(id, "Nailed the voice!", Color("7fe0a0"))
	else:
		var friend: int = b.waiting
		b.npc.say("Nice try, %s! I know your voice!" % _name(id), 2.5)
		status[id].sus = minf(99.0, status[id].sus + 25.0)
		if status.has(friend):
			status[friend].sus = minf(99.0, status[friend].sus + 25.0)
		b.waiting = -1
		b.timer = 1.5


func _on_boost(id: int, p: Node3D, friend_id: int) -> void:
	var friend := players_root.get_node_or_null(str(friend_id))
	if friend == null or not friend.crouching or friend.global_position.distance_to(p.global_position) > 1.8:
		return
	p.launch.rpc_id(id, Vector3(0, 8.2, 0))
	_fx_all("boost", p.global_position, "")


## Shove whoever is right in front of you: they stagger and fall for a moment.
## It breaks a grab, but staff don't forget it (longer detention, lower score).
func _on_shove(id: int, p: Node3D) -> void:
	var fwd: Vector3 = -p.get_node("Head").global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var target := {}
	var best := SHOVE_RANGE
	for b in _brains:
		if b.role == "extra" or _stunned(b):
			continue
		var to: Vector3 = b.npc.global_position - p.global_position
		to.y = 0.0
		if to.length() < best and (to.length() < 0.8 or fwd.dot(to.normalized()) > 0.35):
			best = to.length()
			target = b
	if target.is_empty():
		return
	if not _cooldown(id, "shove", 4.0):
		_tell(id, "Catch your breath first!", Color("ffb37a"))
		return
	var st: Dictionary = status[id]
	var npc: Node = target.npc
	target.stunned_until = elapsed + SHOVE_STUN
	target.grab_until = -1.0
	if status.has(target.target):
		status[target.target].grabbed = false  # shoving a friend's captor frees them too
	npc.stun(fwd * 5.5)
	npc.say(["Arre!", "Oof!", "How DARE you?!", "Aaah!"][_rng.randi() % 4], 1.8)
	st.shoves += 1
	st.grabbed = false
	_fx_all("shove", npc.global_position, "")
	if target.target == id:
		_tell(id, "Shoved free! RUN!", Color("7fe0a0"))
	elif target.role != "extra":
		st.sus = minf(100.0, st.sus + 55.0)  # now they're definitely suspicious
	_log("%s shoved %s!" % [_name(id), npc.display_name])


func _stunned(b: Dictionary) -> bool:
	return elapsed < float(b.get("stunned_until", -1.0))


func _held_ball(id: int) -> Node:
	for ball in _balls:
		if is_instance_valid(ball) and ball.holder == id:
			return ball
	return null


func _on_ball_grab(id: int, p: Node3D, ball_name: String) -> void:
	if _held_ball(id):
		return
	for ball in _balls:
		if is_instance_valid(ball) and str(ball.name) == ball_name and ball.holder == -1 \
				and ball.global_position.distance_to(p.global_position + Vector3(0, 0.5, 0)) < 2.4:
			ball.grab(id)
			_fx.rpc_id(id, "pickup", Vector3.ZERO, "")
			return


## Throw (dir/power) or just drop (zero dir) the ball you're holding.
func _on_ball_throw(id: int, p: Node3D, dir: Vector3, power: float) -> void:
	var ball := _held_ball(id)
	if ball == null:
		return
	var from: Vector3 = ball.hand_position(p)
	var velocity := Vector3.ZERO
	if dir.length() > 0.1:
		# Aim where you look; a natural shooting arc is added on top, and the
		# charged power decides how far it flies.
		dir = dir.normalized()
		power = clampf(power, 0.0, 1.0)
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var elev := clampf(asin(clampf(dir.y, -1.0, 1.0)) + 0.55, 0.25, 1.35)
		var speed := 5.0 + power * 5.5
		# Gentle assist when roughly facing a hoop: straighten the aim and pull
		# the speed toward the perfect shot, so decent timing is rewarded.
		for rim in campus.rims:
			var to_rim: Vector3 = rim - from
			var d := Vector2(to_rim.x, to_rim.z).length()
			var to_flat := Vector3(to_rim.x, 0, to_rim.z).normalized()
			if d < 10.0 and flat.dot(to_flat) > cos(0.3):
				var h: float = to_rim.y + 0.1
				var denom := 2.0 * pow(cos(elev), 2) * (d * tan(elev) - h)
				if denom > 0.0:
					flat = to_flat
					speed = lerpf(speed, sqrt(9.8 * d * d / denom), 0.82)
				break
		velocity = (flat * cos(elev) + Vector3.UP * sin(elev)) * speed
	else:
		velocity = -p.get_node("Head").global_transform.basis.z * 1.5
	ball.last_thrower = id
	ball.release(from, velocity)
	_fx_all("throw", from, "")


func _release_balls_of(id: int) -> void:
	var ball := _held_ball(id)
	if ball:
		ball.release(ball.global_position, Vector3.ZERO)


func _update_balls() -> void:
	for k in _balls.size():
		var ball: Node = _balls[k]
		if not is_instance_valid(ball):
			continue
		if ball.check_basket(campus.rims):
			_fx_all("swish", ball.global_position, "")
			var thrower: int = ball.last_thrower
			if status.has(thrower):
				_log("%s scored a basket! SWISH!" % _name(thrower))
				_complete(thrower, "hoop")
		# Lost balls (over the wall, stuck somewhere odd) go back to the court.
		if ball.holder == -1 and (ball.global_position.y < -3.0 or ball.global_position.distance_to(campus.ball_spawns[k]) > 45.0):
			ball.release(campus.ball_spawns[k], Vector3.ZERO)


func _start_alarm() -> void:
	world.alarm_until = elapsed + ALARM_TIME
	world.alarm_ready = elapsed + ALARM_COOLDOWN
	var k := 0
	for b in _brains:
		if b.role in ["teacher", "patrol", "sitter"] and b.npc.name != "Uncle":
			if b.state == "chase":
				_end_chase(b)
			b.state = "evacuate"
			b.npc.pose = 0
			var spot: Vector3 = campus.assembly + Vector3((k % 5) * 1.3 - 2.6, 0, (k / 5) * 1.3)
			b.npc.go_to(_path(b.npc.global_position, spot), b.walk * 1.8)
			b.npc.say("Fire drill! Everyone out!", 2.0)
			k += 1
	for r in rooms:
		r.calling = false


func _open_service_gate() -> void:
	world.gate_until = elapsed + GATE_OPEN_TIME
	_fx_all("gate", campus.service_gate_pos, "")
	_log("The service gate is open!")


func _noise(pos: Vector3, radius: float) -> void:
	for b in _brains:
		if b.role in ["extra"] or b.state in ["chase", "evacuate", "attendance"] or _distracted(b):
			continue
		if b.npc.global_position.distance_to(pos) > radius:
			continue
		if b.role == "sitter" and b.npc.name == "Uncle":
			continue
		b.resume = b.state
		b.state = "investigate"
		b.timer = 3.0
		b.npc.alert = 1
		b.npc.pose = 0
		b.npc.say("What was that?!", 1.5)
		b.npc.go_to(_path(b.npc.global_position, pos), b.walk * 1.5)


# --- Main loop -------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _started or not multiplayer.is_server() or round_over:
		return
	if not _graph_ready:
		_build_graph()
		_graph_ready = true
		if OS.get_cmdline_user_args().has("--trace"):
			var nodes: PackedVector3Array = campus.nav_points
			for i in nodes.size():
				if nodes[i].x < -21.0 and nodes[i].x > -23.0:
					var nb := []
					for j in _adj[i]:
						nb.append(nodes[j])
					print("[nav] %s -> %s" % [nodes[i], nb])
			for probe in [campus.classes[2].board, campus.assembly]:
				var st := _nearest_node(probe)
				var seen := {st: true}
				var q := [st]
				while not q.is_empty():
					var cur: int = q.pop_back()
					for nx in _adj[cur]:
						if not seen.has(nx):
							seen[nx] = true
							q.append(nx)
				print("[nav] from %s: reach %d of %d nodes" % [probe, seen.size(), nodes.size()])
			print("[nav] path top class->assembly: %s" % [_path(campus.classes[2].board, campus.assembly)])
	elapsed += delta

	var players := {}
	for p in players_root.get_children():
		players[int(str(p.name))] = p
	for id in players:
		if not status.has(id):
			status[id] = _new_status(id)
		status[id].seen = false
	for id in status.keys():
		if not players.has(id):
			status.erase(id)

	if int(world.period) < int(world.periods) - 1 and elapsed >= float(world.period_start) + float(world.period_len):
		_class_change()
	_exam_step(players)
	var alarm_on: bool = elapsed < float(world.alarm_until)
	for r in rooms:
		if not r.calling and not alarm_on:
			r.attendance_in -= delta
	if not alarm_on:
		for b in _brains:
			if b.state == "evacuate":
				b.state = "return"
				_resume(b)
	for brain in _brains:
		if is_instance_valid(brain.npc):
			_think(brain, delta, players)
	_cctv_step(delta, players)
	_update_balls()
	_coin_step(players)
	for id in players:
		_update_player(id, players[id], delta)
		if status[id].state != "class" or players[id].hidden:
			_release_balls_of(id)
	var now := elapsed
	marks = marks.filter(func(m): return float(m.until) > now)

	var all_done := not players.is_empty()
	for id in players:
		if status[id].state != "escaped":
			all_done = false
	if elapsed >= round_time or all_done:
		_end_round()
	_snapshot()


func _exam_step(players: Dictionary) -> void:
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		if elapsed < float(r.exam_until):
			_exam_watch(i, r, players)
		if elapsed >= float(r.exam_at):
			r.exam_at = 99999.0
			r.exam_until = elapsed + EXAM_TIME
			r.exam_id = int(r.exam_id) + 1
			r.exam_period = int(world.period)
			var t := _brain_of_room(i)
			if not t.is_empty() and t.state != "chase":
				t.npc.say("Surprise test! Pens out, eyes down!", 3.0)
			# Only the class it concerns hears about it (no feed spam for every room).
			for id in players:
				if current_room(id) == i and status[id].state != "escaped":
					_tell(id, "Surprise %s test in %s! Sit in your seat: the teacher hands out the papers." % [SUBJECTS[i], Network.CLASSROOMS[i]], Color("ffd24a"))
		elif float(r.exam_until) > 0.0 and elapsed > float(r.exam_until) + 5.0 and int(r.get("exam_period", -1)) == int(world.period):
			r.exam_period = -1
			for id in players:
				var st: Dictionary = status[id]
				# Detention, or walking back from it, excuses you.
				if current_room(id) == i and st.exam_key != "%d:%d:%d" % [int(world.period), i, int(r.exam_id)] \
						and st.state not in ["escaped", "detention"] and elapsed > float(st.get("return_until", -1.0)):
					st.exams_missed = int(st.exams_missed) + 1
					_tell(id, "You missed the %s test! -50" % SUBJECTS[i], Color("ff6a6a"))


## During a test everyone in the room must be at their desk. A few seconds to
## sit down (from the start of the test, or from walking in late); after that,
## a teacher who sees you on your feet sends you straight to detention.
func _exam_watch(room: int, r: Dictionary, players: Dictionary) -> void:
	var t := _brain_of_room(room)
	var start: float = float(r.exam_until) - EXAM_TIME
	for id in players:
		var p: Node3D = players[id]
		var st: Dictionary = status[id]
		if current_room(id) != room or st.state != "class" or p.hidden:
			continue
		if st.exam_key == "%d:%d:%d" % [int(world.period), room, int(r.exam_id)]:
			continue  # handed in already
		if campus.room_of(p.global_position) != room:
			st.exam_in_at = -1.0
			continue
		if float(st.exam_in_at) < start:
			st.exam_in_at = elapsed
		var at_desk: bool = p.seated and p.global_position.distance_to(st.seat) < 1.3
		if at_desk:
			_want_paper(room, r, t, id, st)
			continue
		st.wait_since = -1.0
		if elapsed < maxf(start + EXAM_GRACE, float(st.exam_in_at) + 5.0):
			continue
		if elapsed < float(st.pass_until) or t.is_empty() or t.state == "chase" or _distracted(t) or _stunned(t):
			continue
		if _can_see(t.npc, p, 16.0, 200.0):
			_tell(id, "Standing during the test! Straight to detention.", Color("ff6a6a"))
			_catch(t, id, "On your FEET during my test?! Principal's office!")


## A seated student without a paper yet: the teacher walks over and hands one
## out (one desk at a time). If the teacher is tied up (a chase, the fire
## drill...), the paper gets passed back along the row after a while.
func _want_paper(room: int, r: Dictionary, t: Dictionary, id: int, st: Dictionary) -> void:
	var key := "%d:%d:%d" % [int(world.period), room, int(r.exam_id)]
	if st.exam_paper == key or elapsed > float(r.exam_until) - EXAM_WRITE:
		return
	if float(st.wait_since) < 0.0:
		st.wait_since = elapsed
	var free: bool = not t.is_empty() and t.state in ["write", "watch", "patrol", "return", "stare", "handout"] \
			and not _distracted(t) and not _stunned(t)
	if free and int(t.get("hand_to", -1)) == -1:
		t.state = "handout"
		t.hand_to = id
		t.hand_key = key
		t.hand_t = 0.0
		t.muttered = false
		var seat: Vector3 = st.seat
		var aisle: Array = campus.classes[room].get("aisle", [])
		var side := seat + Vector3(0.9, 0, 0)
		var best := INF
		for a: Vector3 in aisle:
			if a.distance_to(seat) < best:
				best = a.distance_to(seat)
				side = seat + (a - seat).limit_length(1.1)
		t.npc.pose = 0
		t.npc.go_to(_path(t.npc.global_position, side), t.walk * 1.3)
	elif elapsed - float(st.wait_since) > 12.0 and (t.is_empty() or int(t.get("hand_to", -1)) != id):
		if not t.is_empty():
			t.npc.say("Pass that paper back to %s!" % _name(id), 2.5)
		_give_paper(id, key)


func _give_paper(id: int, key: String) -> void:
	var st: Dictionary = status[id]
	st.exam_paper = key
	st.exam_deadline = elapsed + EXAM_WRITE
	print("[%.1f] exam paper %s -> %s" % [elapsed, key, _name(id)])
	st.wait_since = -1.0
	_fx.rpc_id(id, "paper", Vector3.ZERO, "")


## Teacher at a desk handing out a paper: face the student, mutter, hand it over.
func _handout_step(b: Dictionary, delta: float, players: Dictionary) -> void:
	var npc: Node = b.npc
	var id: int = int(b.get("hand_to", -1))
	var st: Dictionary = status.get(id, {})
	var p: Node3D = players.get(id)
	if p == null or st.is_empty() or st.state != "class" or not p.seated or current_room(id) != b.room:
		b.hand_to = -1
		b.state = "watch"
		b.timer = 2.0
		return
	b.hand_t = float(b.hand_t) + delta
	if not npc.is_idle() and b.hand_t < 8.0:
		return
	npc.stop(npc.yaw_towards(p.global_position - npc.global_position))
	if not b.muttered:
		b.muttered = true
		b.give_at = b.hand_t + 1.2
		var r: Dictionary = rooms[b.room]
		var late: bool = float(st.exam_in_at) > float(r.exam_until) - EXAM_TIME + EXAM_GRACE
		var lines: Array = LATE_LINES if late else HAND_LINES
		npc.say(lines[_rng.randi() % lines.size()], 2.2)
	elif b.hand_t >= float(b.give_at):
		_give_paper(id, str(b.hand_key))
		b.hand_to = -1
		b.state = "watch"
		b.timer = 1.0


func _snapshot() -> void:
	status = status.duplicate(true)
	rooms = rooms.duplicate(true)
	world = world.duplicate(true)
	feed = feed.duplicate(true)
	marks = marks.duplicate(true)


func _update_player(id: int, p: Node3D, delta: float) -> void:
	var st: Dictionary = status[id]
	match st.state:
		"detention":
			st.timer -= delta
			if st.timer <= 0.0:
				st.state = "class"
				st.sus = 10.0
				st.returning = true
				st.return_until = elapsed + RETURN_GRACE
				_teleport(id, campus.detention_exit, p.rotation.y)
				var room := current_room(id)
				_tell(id, "Detention's over. Walk back to %s. Your teacher is waiting..." % Network.CLASSROOMS[room], Color("ffb37a"))
				_log("%s is out of detention." % _name(id))
		"escaped":
			pass
		_:
			if not st.seen:
				# Hiding in a locker or stall calms things down twice as fast.
				st.sus = maxf(0.0, st.sus - (14.0 if p.hidden else 7.0) * delta)
			_behaviour(id, p, st, delta)
			if p.global_position.y < -0.9:
				_washed_back(id, p)
			elif campus.escaped(p.global_position):
				st.state = "escaped"
				st.time = elapsed
				_fx.rpc_id(id, "win", Vector3.ZERO, "")
				_log("%s ESCAPED the university!" % _name(id))
				for b in _brains:
					if b.target == id:
						_end_chase(b)


## Back from detention: the teacher scolds you and gets stricter. Sitting
## nicely for a while calms them down again, one notch at a time.
func _behaviour(id: int, p: Node3D, st: Dictionary, delta: float) -> void:
	var room := current_room(id)
	var in_room: bool = campus.room_of(p.global_position) == room
	# Walking into your classroom: a few seconds to reach your seat.
	if in_room and not bool(st.get("was_in_room", true)):
		st.settle_until = elapsed + SETTLE_TIME
	st.was_in_room = in_room
	# A hall pass ran out while you're out: walk back without being hunted,
	# though coming back late puts your teacher in a worse mood.
	if elapsed < float(st.pass_until):
		st.had_pass = true
	elif st.get("had_pass", false):
		st.had_pass = false
		if not in_room and st.state == "class":
			st.pass_late = true
			st.return_until = maxf(float(st.return_until), elapsed + PASS_RETURN)
			_tell(id, "Your pass ran out! Walk back to %s." % Network.CLASSROOMS[room], Color("ffb37a"))
	if in_room and st.get("pass_late", false):
		st.pass_late = false
		st.return_until = -1.0
		st.settle_until = elapsed + SETTLE_TIME
		st.strikes = mini(3, int(st.strikes) + 1)
		st.good_time = 0.0
		var tp := _brain_of_room(room)
		if not tp.is_empty():
			tp.npc.say(["Took your time, didn't you, %s? Sit.", "Long washroom queue, %s? Hmm. Sit down.",
				"%s. The pass said 35 seconds, not 35 minutes."][_rng.randi() % 3] % _name(id), 3.0)
		_tell(id, "Back late from your pass: your teacher is annoyed (strictness %d/3)." % int(st.strikes), Color("ff9a4a"))
	if st.returning and in_room:
		st.returning = false
		st.return_until = -1.0
		st.strikes = mini(3, int(st.strikes) + 1)
		st.good_time = 0.0
		var t := _brain_of_room(room)
		if not t.is_empty():
			t.npc.say(["Back from detention, %s? Sit. I'm watching YOU.", "Well well, %s. One more stunt and you're done.",
				"%s! Seat. Now. Not a word."][mini(int(st.strikes) - 1, 2)] % _name(id), 3.5)
		_tell(id, "Your teacher is angry with you (strictness %d/3). Behave to calm them down." % int(st.strikes), Color("ff9a4a"))
		_log("%s got an earful from the teacher." % _name(id))
	if int(st.strikes) <= 0:
		return
	var seated: bool = in_room and p.seated and p.global_position.distance_to(st.seat) < 1.3 and not st.seen
	st.good_time = float(st.good_time) + delta if seated else 0.0
	if float(st.good_time) >= GOOD_TIME:
		st.good_time = 0.0
		st.strikes = int(st.strikes) - 1
		var t := _brain_of_room(room)
		if not t.is_empty():
			t.npc.say("Hmm. Better, %s. Keep it up." % _name(id), 2.5)
		_tell(id, "Good behaviour! Your teacher calms down (strictness %d/3)." % int(st.strikes), Color("7fe0a0"))


## Fell in the water: the current carries you back to the bank.
func _washed_back(id: int, p: Node3D) -> void:
	var w: Dictionary = campus.water_at(p.global_position)
	var bank: Vector3 = campus.bank_for(w, p.global_position) if not w.is_empty() else _seat.get(id, Vector3.ZERO)
	_teleport(id, bank + Vector3(0, 0.1, 0), p.rotation.y)
	_tell(id, "SPLASH!  The water carried you back to the bank.", Color("7fd0ea"))
	_fx_all("splash", p.global_position, "")
	for b in _brains:
		if b.target == id:
			_end_chase(b)


func _end_round() -> void:
	round_over = true
	var list := []
	for id in status:
		var st: Dictionary = status[id]
		var done := 0
		for q in st.quests:
			if q.done:
				done += 1
		var score := done * QUEST_POINTS - int(st.caught) * 100 - int(st.spotted) * 25 - int(st.get("shoves", 0)) * 40 \
				+ int(st.get("exam_total", 0)) - int(st.get("exams_missed", 0)) * 50
		if st.state == "escaped":
			score += 500 + int(maxf(0.0, round_time - float(st.time)))
		st.score = score
		list.append({"name": _name(id), "score": score, "escaped": st.state == "escaped", "time": st.time,
			"quests": done, "caught": st.caught, "spotted": st.spotted, "tests": int(st.get("exam_total", 0))})
	list.sort_custom(func(a, b): return a.score > b.score)
	results = list
	for b in _brains:
		b.npc.stop(b.npc.rotation.y)
		b.npc.alert = 0
	_fx_all("bell", Vector3.ZERO, "end")
	_log("The final bell rang!")
	if OS.get_cmdline_user_args().has("--quit-at-end"):  # dev/CI: stop once the round is over
		get_tree().create_timer(1.0).timeout.connect(get_tree().quit)


func _name(id: int) -> String:
	return str(Network.players.get(id, {}).get("name", "Someone"))


func _own_room(id: int) -> int:
	return current_room(id)


# --- Brains ------------------------------------------------------------------------------------

func _think(b: Dictionary, delta: float, players: Dictionary) -> void:
	var npc: Node = b.npc
	b.t += delta
	if b.role == "extra":
		_extra(b, delta, players)
		return
	if _stunned(b):
		return  # on the floor after a shove
	if b.state == "chase":
		_chase_step(b, delta, players)
		return
	if _distracted(b):
		npc.alert = 0
		npc.stop(npc.rotation.y)
		return

	# Watch for rule-breakers.
	var watching: bool = not (b.role == "sitter" and b.state == "away")
	var spotted := -1
	var spotted_sus := -1.0
	if watching:
		for id in players:
			var p: Node3D = players[id]
			var st: Dictionary = status[id]
			if st.state == "detention" or st.state == "escaped":
				continue
			if not _suspicious(id, p, b) or not _can_see(npc, p, b.range, b.fov):
				continue
			st.seen = true
			var dist: float = npc.global_position.distance_to(p.global_position)
			var rate: float = 34.0 * b.alertness * clampf(1.25 - dist / b.range, 0.3, 1.25) * (0.6 if p.crouching else 1.0)
			if b.role == "teacher" and b.room == current_room(id):
				rate *= 1.0 + 0.6 * int(st.strikes)  # an angry teacher misses nothing
			if dist < 4.0:
				rate *= 2.5  # right under their nose
			if b.state == "evacuate":
				rate *= 0.5  # chatting at the assembly point
			if _in_crowd(p):
				rate *= 0.45
			st.sus = minf(100.0, st.sus + rate * delta)
			if st.sus > spotted_sus:
				spotted_sus = st.sus
				spotted = id
	if spotted != -1:
		npc.alert = 1
		if spotted_sus >= 100.0 and status[spotted].state != "chased":
			if b.chaser:
				_start_chase(b, spotted, players[spotted].global_position)
			else:
				npc.say(["Chor! Chor! Somebody catch them!", "Shhh! PRINCIPAL MA'AM!"][0 if npc.name == "Uncle" else 1], 2.5)
				_call_help(spotted, players[spotted].global_position, npc.display_name)
			return
		if b.state not in ["attendance", "evacuate"]:
			if b.state != "stare":
				b.resume = b.state
				npc.say("Hmm?", 1.2)
			b.state = "stare"
			b.timer = 1.4
			npc.stop(npc.yaw_towards(players[spotted].global_position - npc.global_position))
	elif b.state != "investigate":
		npc.alert = 0

	# Hear sprinting nearby.
	if b.state in ["write", "watch", "patrol", "post", "return", "sit"]:
		var ears: float = NOISE_RADIUS * (1.6 if npc.name == "Librarian" else 1.0)
		for id in players:
			var p: Node3D = players[id]
			var heard: float = ears * (0.5 if int(status[id].upgrades.get("shoes", 0)) > 0 else 1.0)
			if p.sprinting and status[id].state in ["class", "chased"] \
					and p.global_position.distance_to(npc.global_position) < heard:
				b.resume = b.state
				b.state = "investigate"
				b.timer = 3.0
				npc.alert = 1
				npc.pose = 0
				npc.say("Shhh!" if npc.name == "Librarian" else "Who's running?!")
				npc.go_to(_path(npc.global_position, p.global_position), b.walk * 1.5)
				break

	if b.role == "teacher" and b.state in ["write", "watch", "patrol", "return"] \
			and rooms[b.room].attendance_in <= 0.0:
		_start_attendance(b)

	match b.state:
		"stare":
			b.timer -= delta
			if b.timer <= 0.0:
				b.state = b.get("resume", "return")
				if b.state in ["patrol", "stare", "investigate"] and b.role == "teacher":
					b.state = "return"
				_resume(b)
		"investigate":
			if npc.is_idle():
				npc.stop(npc.rotation.y + sin(b.t * 2.0) * 1.2)
				b.timer -= delta
				if b.timer <= 0.0:
					npc.say("Hmph. Kids these days.", 2.0)
					b.state = "return"
					_resume(b)
		"evacuate":
			if npc.is_idle():
				npc.stop(sin(b.t * 0.4 + b.home.x) * 2.0)
		"return":
			if npc.is_idle():
				b.state = {"teacher": "write", "gate": "post", "patrol": "patrol", "sitter": "sit"}[b.role]
				b.timer = _rng.randf_range(4.0, 7.0) if b.role != "sitter" else _rng.randf_range(10.0, 18.0)
				_resume(b)
		_:
			match b.role:
				"teacher": _teacher(b, delta, players)
				"gate": _gate_guard(b, delta)
				"patrol": _patroller(b, delta)
				"sitter": _sitter(b, delta)


## Re-issue movement for the brain's current state.
func _resume(b: Dictionary) -> void:
	var npc: Node = b.npc
	match b.state:
		"return":
			var home: Vector3 = b.home
			if b.role == "patrol":
				home = b.loop[b.loop_i]
			npc.pose = 0
			npc.go_to(_path(npc.global_position, home), b.walk)
		"write":
			var spots: Dictionary = campus.classes[b.room]
			var spot: Vector3 = spots.board + (spots.side as Vector3) * _rng.randf_range(-1.3, 1.3)
			npc.go_to(_path(npc.global_position, spot), b.walk)
		"post", "sit":
			npc.go_to(_path(npc.global_position, b.home), b.walk)
		"patrol":
			npc.go_to(_path(npc.global_position, b.loop[b.loop_i]), b.walk)


func _teacher(b: Dictionary, delta: float, players: Dictionary) -> void:
	var npc: Node = b.npc
	match b.state:
		"write":
			# Back to the class, writing on the board: the window to sneak out.
			if npc.is_idle():
				npc.stop(campus.classes[b.room].yaw)
				b.timer -= delta
				if b.timer <= 0.0:
					if _rng.randf() < 0.3:
						b.state = "patrol"
						var spots: Dictionary = campus.classes[b.room]
						var route: Array[Vector3] = []
						route.append_array(spots.aisle)
						route.append(spots.aisle[0])
						route.append(spots.board)
						npc.go_to(route, b.walk)
						npc.say(["Everyone copy this down.", "No talking!", "Page 42, everyone."][_rng.randi() % 3])
					else:
						b.state = "watch"
						b.timer = _rng.randf_range(3.0, 5.5)
						npc.say(["Any questions?", "Are you all listening?", "Hmm...", "Eyes on the board!"][_rng.randi() % 4], 2.0)
		"watch":
			npc.stop(float(campus.classes[b.room].yaw) + PI + sin(b.t * 1.2) * 0.55)
			b.timer -= delta
			if b.timer <= 0.0:
				b.state = "write"
				b.timer = _rng.randf_range(5.0, 9.0)
				_resume(b)
		"patrol":
			if npc.is_idle():
				b.state = "write"
				b.timer = _rng.randf_range(5.0, 8.0)
		"attendance":
			_attendance_step(b, delta, players)
		"handout":
			_handout_step(b, delta, players)


func _start_attendance(b: Dictionary) -> void:
	var queue := []
	var ids: Array = Network.players.keys()
	ids.sort()
	var called: Array = rooms[b.room].get("called", [])
	for id in ids:
		if current_room(id) == b.room and not called.has(id):
			queue.append(id)
	if queue.is_empty():
		rooms[b.room].attendance_in = 99999.0
		return
	b.queue = queue
	b.waiting = -1
	b.state = "attendance"
	b.timer = 2.0
	rooms[b.room].calling = true
	var spots: Dictionary = campus.classes[b.room]
	b.npc.go_to(_path(b.npc.global_position, spots.table), b.walk * 1.3)
	b.npc.say("Attendance time!", 2.0)


func _attendance_step(b: Dictionary, delta: float, players: Dictionary) -> void:
	var npc: Node = b.npc
	if not npc.is_idle():
		return
	npc.stop(float(campus.classes[b.room].yaw) + PI)
	b.timer -= delta
	if b.timer > 0.0:
		return
	# Resolve the name we called: silence means absent, unless a friend faked it.
	if int(b.waiting) != -1:
		var id: int = b.waiting
		b.waiting = -1
		rooms[b.room].called.append(id)
		if b.get("proxied", false):
			npc.say("...Present!  (Hmm, you sound different.)", 1.8)
			_log("%s answered attendance for %s!" % [_name(b.proxied_by), _name(id)])
		elif status.has(id) and (elapsed < float(status[id].get("return_until", -1.0)) or elapsed < float(status[id].pass_until)):
			npc.say("%s? ...On a pass, fine." % _name(id), 1.8)
		elif status.has(id) and status[id].state in ["class", "chased"]:
			npc.say("%s?!  ABSENT!" % _name(id), 1.8)
			status[id].sus = minf(99.0, status[id].sus + 45.0)
			status[id].bunking = true
			_log("%s was marked ABSENT by %s!" % [_name(id), npc.display_name])
		b.proxied = false
		b.timer = 1.4
		return
	var queue: Array = b.queue
	if queue.is_empty():
		rooms[b.room].calling = false
		rooms[b.room].attendance_in = 99999.0  # once per period
		b.state = "watch"
		b.timer = 3.0
		return
	var next: int = queue.pop_front()
	b.timer = 1.9
	if not players.has(next):
		return
	var st: Dictionary = status[next]
	var present: bool = st.state in ["class", "chased"] and not players[next].hidden \
			and campus.room_of(players[next].global_position) == b.room
	if present:
		npc.say("%s?   ...Present!" % _name(next), 1.8)
		rooms[b.room].called.append(next)
		_pay(next, 5, "for being present")
	else:
		npc.say("%s?  ...%s?" % [_name(next), _name(next)], 2.0)
		b.waiting = next
		b.proxied = false
		b.timer = 2.2  # window for a friend to answer (R)


func _gate_guard(b: Dictionary, delta: float) -> void:
	var npc: Node = b.npc
	if not npc.is_idle():
		return
	b.timer -= delta
	match b.state:
		"post":
			npc.holding = false
			npc.stop(float(b.home_yaw) + sin(b.t * 0.7) * 0.9)
			if b.timer <= 0.0:
				b.state = "break"
				b.timer = 8.0
				npc.stop(float(b.home_yaw) + PI / 2.0)
				npc.holding = true
				npc.say("Chai break... ahh.", 3.0)
		"break":
			npc.stop(float(b.home_yaw) + PI / 2.0)
			if b.timer <= 0.0:
				b.state = "post"
				b.timer = _rng.randf_range(18.0, 28.0)
				npc.holding = false
				npc.say("Back on duty.", 1.5)


func _patroller(b: Dictionary, delta: float) -> void:
	var npc: Node = b.npc
	if not npc.is_idle():
		return
	npc.stop(npc.rotation.y + sin(b.t * 1.5) * 0.8)
	b.timer -= delta
	if b.timer <= 0.0:
		b.loop_i = (b.loop_i + 1) % b.loop.size()
		b.timer = 1.8
		npc.go_to(_path(npc.global_position, b.loop[b.loop_i]), b.walk)


func _sitter(b: Dictionary, delta: float) -> void:
	var npc: Node = b.npc
	if not npc.is_idle():
		return
	npc.pose = 1
	b.timer -= delta
	match b.state:
		"sit":
			npc.holding = npc.name == "Staff"
			npc.stop(b.home_yaw)
			if b.timer <= 0.0:
				b.state = "away"
				b.timer = _rng.randf_range(6.0, 9.0)
				npc.say(b.away_line, 2.5)
		"away":
			npc.stop(b.away_yaw)
			if b.timer <= 0.0:
				b.state = "sit"
				b.timer = _rng.randf_range(12.0, 20.0)


func _extra(b: Dictionary, _delta: float, players: Dictionary) -> void:
	var npc: Node = b.npc
	if round_over or b.state == "sit":
		return
	if b.state == "leave":
		if elapsed >= float(b.leave_at):
			b.state = "move"
			b.move_until = elapsed + float(world.get("passing_time", PASSING_TIME)) * 2.0 + 40.0  # safety net: then just sit down
			npc.pose = 0
			if _rng.randf() < 0.3:
				npc.say(["Finally!", "Next class...", "Ugh, stairs.", "Wait for me!", "Did anyone get the notes?"][_rng.randi() % 5], 1.5)
			npc.go_to(_path(npc.global_position, b.seat), 3.0)
		return
	# Walk into a student and they stumble out of your way (with a word or two).
	for id in players:
		var p: Node3D = players[id]
		var to: Vector3 = npc.global_position - p.global_position
		if absf(to.y) > 1.0:
			continue
		to.y = 0.0
		var d := to.length()
		if d > 0.75:
			continue
		var push := maxf(float(p.net_speed), 2.2) * 1.3
		var away := to.normalized() if d > 0.01 else Vector3(1, 0, 0)
		npc.nudge(away * push)
		if elapsed > float(b.get("bump_ready", 0.0)):
			b.bump_ready = elapsed + 4.0
			npc.say(BUMP_LINES[_rng.randi() % BUMP_LINES.size()], 1.8)
	if b.state == "move":
		var gap: float = Vector2(npc.global_position.x - b.seat.x, npc.global_position.z - b.seat.z).length()
		# Desks are in the way of the chair itself: close enough, then slide in.
		var arrived: bool = gap < 0.5 or (npc.is_idle() and gap < 1.8)
		if npc.is_idle() and not arrived and elapsed < float(b.move_until):
			npc.go_to(_path(npc.global_position, b.seat), 3.0)  # got pushed off course
		elif arrived or elapsed >= float(b.move_until):
			npc.global_position = b.seat
			npc.stop(float(b.seat_yaw))
			npc.pose = 1
			b.state = "sit"
			if OS.get_cmdline_user_args().has("--trace"):
				print("[npc] %s sat down in room %d (%s) gap %.1f at %s seat %s" % [npc.name, int(b.class_room), "walked" if gap < 1.8 else "timed out", gap, npc.global_position, b.seat])
		return
	if npc.is_idle():
		b.loop_i = (b.loop_i + 1) % b.loop.size()
		npc.go_to(_path(npc.global_position, b.loop[b.loop_i]), b.walk)


func _distracted(b: Dictionary) -> bool:
	return elapsed < float(b.distracted_until)


# --- CCTV --------------------------------------------------------------------------------------

func cctv_yaw(cam: Dictionary, t: float) -> float:
	return float(cam.base_yaw) + sin(t * float(cam.speed)) * float(cam.sweep)


func _cctv_step(delta: float, players: Dictionary) -> void:
	for cam in campus.cctv:
		var yaw := cctv_yaw(cam, elapsed)
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		for id in players:
			var p: Node3D = players[id]
			var st: Dictionary = status[id]
			if st.state != "class" or not _suspicious_generic(id, p):
				continue
			if not _can_see_from(cam.pos, fwd, p, 16.0, 55.0):
				continue
			st.seen = true
			st.sus = minf(100.0, st.sus + 22.0 * delta * (0.45 if _in_crowd(p) else 1.0))
			if st.sus >= 100.0:
				_log("CCTV caught %s on camera!" % _name(id))
				_call_help(id, p.global_position, "CCTV")


# --- Chase, catch ------------------------------------------------------------------------------

func _call_help(id: int, pos: Vector3, caller: String) -> void:
	var best := {}
	var best_d := INF
	for b in _brains:
		if not b.chaser or b.role in ["teacher", "sitter"] or b.state == "chase" or _distracted(b):
			continue
		var d: float = b.npc.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		status[id].sus = 90.0
		return
	_start_chase(best, id, pos)
	best.lost = -8.0  # time to arrive before giving up
	_log("%s called %s!" % [caller, best.npc.display_name])


func _start_chase(b: Dictionary, id: int, pos: Vector3) -> void:
	if b.state == "attendance":
		rooms[b.room].calling = false  # picked up again after the chase, where it stopped
	b.state = "chase"
	b.target = id
	b.lost = 0.0
	b.repath = 0.0
	b.saw_hide = false
	b.last_seen = pos
	status[id].state = "chased"
	status[id].spotted += 1
	b.npc.alert = 2
	b.npc.pose = 0
	b.npc.holding = false
	b.npc.say(SHOUTS[_rng.randi() % SHOUTS.size()], 2.5)
	_fx_all("whistle", b.npc.global_position, str(id))
	_log("%s spotted %s!" % [b.npc.display_name, _name(id)])


func _chase_step(b: Dictionary, delta: float, players: Dictionary) -> void:
	var npc: Node = b.npc
	var id: int = b.target
	if not players.has(id) or status[id].state != "chased":
		_end_chase(b)
		return
	var p: Node3D = players[id]
	var st: Dictionary = status[id]
	var seen := _can_see(npc, p, b.range * 1.4, 200.0)
	var dist: float = npc.global_position.distance_to(p.global_position)
	# Safety net: a chase that goes nowhere for too long ends (never a
	# "RUN!" banner that lasts all round).
	b.chase_t = float(b.get("chase_t", 0.0)) + delta
	if b.chase_t > 45.0:
		b.lost = 99.0
	if p.hidden:
		# In a locker: they lose track of you and wander off, no camping outside,
		# unless they were right behind you (or holding you) when you got in.
		if not b.get("hide_judged", false):
			b.hide_judged = true
			b.saw_hide = bool(st.get("grabbed", false)) or (bool(b.get("seen_prev", false)) and dist < 2.5)
			if b.saw_hide:
				npc.say("I SAW that. Out you come!", 2.0)
		if not b.saw_hide:
			b.lost = maxf(b.lost, 0.0) + delta * 2.0
	elif seen:
		b.lost = minf(b.lost, 0.0) if b.lost < 0.0 else 0.0
		b.last_seen = p.global_position
	else:
		b.lost += delta
	if not p.hidden:
		b.hide_judged = false
		b.saw_hide = false
	b.seen_prev = seen
	if b.lost > 4.0:
		st.state = "class"
		st.sus = 60.0
		npc.say("Hmph. Lost them.", 2.0)
		_log("%s escaped %s." % [_name(id), npc.display_name])
		_end_chase(b)
		return
	# Catching takes a moment: the student is grabbed and can shove free.
	if dist < CATCH_DIST and (not p.hidden or b.saw_hide):
		if float(b.get("grab_until", -1.0)) < 0.0:
			b.grab_until = elapsed + GRAB_TIME
			st.grabbed = true
			npc.say("Got you now—!", 1.2)
			_tell(id, "GRABBED!  Left-click to SHOVE free!", Color("ff6a6a"))
		elif elapsed >= float(b.grab_until):
			_catch(b, id)
			return
	elif float(b.get("grab_until", -1.0)) >= 0.0 and dist > 2.2:
		b.grab_until = -1.0
		st.grabbed = false
	b.repath -= delta
	if b.repath <= 0.0:
		b.repath = 0.35
		var goal: Vector3 = p.global_position if (seen or b.saw_hide or b.lost < 0.0) else b.last_seen
		if OS.get_cmdline_user_args().has("--trace") and int(elapsed * 3.0) % 6 == 0:
			print("[chase] %s at %s -> %s dist %.1f seen %s lost %.1f path %s" % [npc.display_name, npc.global_position.snapped(Vector3.ONE * 0.1), goal.snapped(Vector3.ONE * 0.1), dist, seen, b.lost, _path(npc.global_position, goal)])
		# Close and in sight: straight at them (a path round the desks would
		# step out of grabbing range and back, over and over).
		var route: Array[Vector3] = []
		if seen and dist < 3.0:
			route.append(goal)
		else:
			route = _path(npc.global_position, goal)
		npc.go_to(route, b.chase_speed)


func _end_chase(b: Dictionary) -> void:
	var id: int = b.target
	if status.has(id):
		status[id].grabbed = false
		# Fire drill, samosa bribe, washed back...: nobody else after them = free again.
		var others := false
		for o in _brains:
			if o != b and o.state == "chase" and o.target == id:
				others = true
		if status[id].state == "chased" and not others:
			status[id].state = "class"
			status[id].sus = maxf(float(status[id].sus), 60.0)
	b.grab_until = -1.0
	b.chase_t = 0.0
	b.target = -1
	b.npc.alert = 0
	b.state = "return"
	_resume(b)


func _catch(b: Dictionary, id: int, reason := "") -> void:
	var st: Dictionary = status[id]
	if st.items.has("detention_ticket"):
		st.items.erase("detention_ticket")
		st.state = "class"
		st.grabbed = false
		st.sus = 40.0
		b.npc.say("A Detention Skip... signed by the principal?! Hmph. Go.", 3.0)
		_tell(id, "You flashed your Detention Skip ticket. Off the hook!", Color("7fe0a0"))
		_log("%s used a Detention Skip on %s!" % [_name(id), b.npc.display_name])
		_end_chase(b)
		return
	st.state = "detention"
	st.caught += 1
	# Every catch adds 5 s; shoving staff makes it worse.
	st.timer = minf(DETENTION_TIME + DETENTION_STEP * (st.caught - 1) + 8.0 * st.shoves, 90.0)
	st.returning = false
	st.essay_line = _rng.randi() % LINES.size()
	var taken := []
	for item in CONTRABAND:
		while st.items.has(item):
			st.items.erase(item)
			taken.append(ITEMS.get(item, item))
	if not taken.is_empty():
		_tell(id, "Confiscated: %s" % ", ".join(taken), Color("ff6a6a"))
	st.grabbed = false
	st.sus = 0.0
	st.bunking = false
	st.pass_until = -1.0
	b.npc.say(reason if reason != "" else "Gotcha! Principal's office. NOW.", 3.0)
	_fx.rpc_id(id, "caught", Vector3.ZERO, "")
	_log("%s was caught by %s! Detention." % [_name(id), b.npc.display_name])
	_teleport(id, campus.detention_spot, 0.0)
	_end_chase(b)


func _teleport(id: int, pos: Vector3, yaw: float) -> void:
	var p := players_root.get_node_or_null(str(id))
	if p:
		p.teleport.rpc_id(id, pos, yaw)


# --- Perception ----------------------------------------------------------------------------------

func _suspicious(id: int, p: Node3D, b: Dictionary) -> bool:
	var pos := p.global_position
	# Standing in front of someone to talk to them isn't sneaking.
	if str(status[id].get("talk_with", "")) == str(b.npc.name) and elapsed < float(status[id].get("talk_until", -1.0)):
		return false
	if b.role == "sitter":
		if not (b.zone as Rect2).has_point(Vector2(pos.x, pos.z)):
			return false
		return b.rule != "sprint" or p.sprinting
	var own_room := _own_room(id)
	if b.role == "teacher" and b.room == own_room and campus.room_of(pos) == own_room:
		if elapsed < float(world.passing_until) or elapsed < float(status[id].get("settle_until", -1.0)):
			return false  # still settling in after the bell, or just walked in
		var tolerance := 1.3 - 0.1 * int(status[id].strikes)
		return pos.distance_to(_seat.get(id, pos)) > tolerance or p.sprinting
	if b.role == "gate" and _in_gate_zone(pos):
		return elapsed > float(status[id].gate_pass_until)
	return _suspicious_generic(id, p)


## Out of their own classroom during class, without a hall pass.
func _suspicious_generic(id: int, p: Node3D) -> bool:
	if campus.room_of(p.global_position) == _own_room(id):
		return false
	# Class change, or walking back from detention: the corridors are fair game.
	if elapsed < float(world.passing_until) or elapsed < float(status[id].return_until):
		return _in_gate_zone(p.global_position)
	return elapsed > float(status[id].pass_until) or _in_gate_zone(p.global_position)


func _in_gate_zone(pos: Vector3) -> bool:
	for z: Rect2 in campus.gate_zones:
		if z.has_point(Vector2(pos.x, pos.z)):
			return true
	return false


func _in_crowd(p: Node3D) -> bool:
	if p.sprinting:
		return false
	for e in _extras:
		if e.global_position.distance_to(p.global_position) < 1.8:
			return true
	return false


func _seen_by_anyone(p: Node3D) -> bool:
	for b in _brains:
		if b.role == "extra" or _distracted(b) or (b.role == "sitter" and b.state == "away"):
			continue
		if _can_see(b.npc, p, b.range, b.fov):
			return true
	return false


func _can_see(npc: Node, p: Node3D, view_range: float, fov_deg: float) -> bool:
	return _can_see_from(npc.eye_position(), npc.forward(), p, view_range, fov_deg)


func _can_see_from(eye: Vector3, fwd: Vector3, p: Node3D, view_range: float, fov_deg: float) -> bool:
	if p.hidden:
		return false
	var target := p.global_position + Vector3(0, 0.55 if p.crouching else 1.35, 0)
	var to := target - eye
	var dist := to.length()
	if dist > view_range:
		return false
	if dist > 1.6:
		var flat := Vector3(to.x, 0, to.z).normalized()
		if fwd.dot(flat) < cos(deg_to_rad(fov_deg * 0.5)):
			return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, 1)
	return players_root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Lookups -----------------------------------------------------------------------------------------

func _brain_of_room(room: int) -> Dictionary:
	for b in _brains:
		if b.role == "teacher" and b.room == room:
			return b
	return {}


func _brain_by_name(node_name: String) -> Dictionary:
	for b in _brains:
		if is_instance_valid(b.npc) and b.npc.name == node_name:
			return b
	return {}


func _nearest_brain(pos: Vector3, radius: float, roles: Array) -> Dictionary:
	var best := {}
	var best_d := radius
	for b in _brains:
		if not roles.has(b.role):
			continue
		var d: float = b.npc.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


func _npc_say(node_name: String, text: String) -> void:
	var b := _brain_by_name(node_name)
	if not b.is_empty():
		b.npc.say(text, 2.5)


func _find_interactable(kind: String) -> int:
	for i in campus.interactables.size():
		if campus.interactables[i].kind == kind:
			return i
	return -1


# --- Navigation: waypoint graph + line-of-sight shortcuts ------------------------------------------

func _clear(a: Vector3, b: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = players_root.get_world_3d().direct_space_state
	var dir := b - a
	dir.y = 0
	# Too steep to walk (e.g. straight through a floor slab): only ramps connect storeys.
	if absf(a.y - b.y) > dir.length() * 0.6 + 0.3:
		return false
	if dir.length() < 0.01:
		return true
	var side := Vector3(-dir.z, 0, dir.x).normalized() * 0.36
	# Rays follow the endpoints' heights, so ramps link up but floors/slabs block.
	var ay := maxf(a.y, 0.0)
	var by := maxf(b.y, 0.0)
	for offset in [Vector3(0, 0.4, 0), Vector3(0, 1.2, 0), side + Vector3(0, 0.4, 0), -side + Vector3(0, 0.4, 0)]:
		var from: Vector3 = Vector3(a.x, ay, a.z) + offset
		var to: Vector3 = Vector3(b.x, by, b.z) + offset
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | CampusBuilder.NPC_WALL_LAYER)).is_empty():
			return false
	return true


func _build_graph() -> void:
	var nodes: PackedVector3Array = campus.nav_points
	_adj.clear()
	for i in nodes.size():
		_adj.append([])
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if nodes[i].distance_to(nodes[j]) <= 16.0 and _clear(nodes[i], nodes[j]):
				_adj[i].append(j)
				_adj[j].append(i)


func _nearest_node(pos: Vector3) -> int:
	var nodes: PackedVector3Array = campus.nav_points
	var order := range(nodes.size())
	order.sort_custom(func(a, b): return nodes[a].distance_squared_to(pos) < nodes[b].distance_squared_to(pos))
	for k in mini(10, order.size()):
		if _clear(pos, nodes[order[k]]):
			return order[k]
	return order[0] if not order.is_empty() else -1


## Walking route from `from` to `to` (both included) over the waypoint graph.
## Works on any peer: the phone's Navigate app uses it; builds the graph on first use.
func route_to(from: Vector3, to: Vector3) -> Array[Vector3]:
	if _adj.is_empty():
		_build_graph()
		_graph_ready = true
	var out: Array[Vector3] = [from]
	out.append_array(_path(from, to))
	return out


func _path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _clear(from, to) or _adj.is_empty():
		out.append(to)
		return out
	var start := _nearest_node(from)
	var goal := _nearest_node(to)
	var nodes: PackedVector3Array = campus.nav_points
	var dist := {start: 0.0}
	var prev := {}
	var open := [start]
	while not open.is_empty():
		var best := 0
		for k in open.size():
			if dist[open[k]] < dist[open[best]]:
				best = k
		var cur: int = open.pop_at(best)
		if cur == goal:
			break
		for nxt in _adj[cur]:
			var d: float = dist[cur] + nodes[cur].distance_to(nodes[nxt])
			if d < dist.get(nxt, INF):
				dist[nxt] = d
				prev[nxt] = cur
				if not open.has(nxt):
					open.append(nxt)
	var chain := []
	var node := goal
	while node != start and prev.has(node):
		chain.push_front(node)
		node = prev[node]
	chain.push_front(start)
	for n in chain:
		out.append(nodes[n])
	out.append(to)
	# Skip nodes you can walk past in a straight line. Without this, the nearest
	# node can lie behind you, and a chaser that repaths often walks back and
	# forth to it forever.
	while out.size() > 1 and _clear(from, out[1]):
		out.pop_front()
	while out.size() > 2 and _clear(out[out.size() - 3], to):
		out.remove_at(out.size() - 2)
	return out
