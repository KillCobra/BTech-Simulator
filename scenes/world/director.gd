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
const Rules := preload("res://scripts/rules.gd")
const Lines := preload("res://scripts/lines.gd")

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
const LINES := ["I will not bunk class", "I will respect my teachers", "Attendance is not optional",
	"The canteen is not a classroom", "I will stay in my seat", "I will not pull the fire alarm",
	"I will not climb out of windows", "Lockers are for books, not students", "I will not bribe staff with samosas",
	"The service gate is not an exit", "I will not answer attendance for my friends", "Paper balls are not homework",
	"The principal's car is not a selfie spot", "I will raise my hand before I speak", "I will not sprint in the corridors",
	"A hall pass is not a holiday", "I will not hide in the washroom", "The library is a place of silence",
	"I will copy my own notes", "I will not ring the office bell for fun", "Exams are not a group project",
	"I will not play the drums during class", "Detention is not a social club", "My seat misses me when I leave it",
	"I will not trade samosas during lectures"]
const CONTRABAND := ["canteen_key", "medical_note", "hall_pass"]
const CATCH_DIST := 1.5
const NOISE_RADIUS := 8.0
## Staff and cameras only notice students on (about) their own floor: storeys are 3.6 m
## apart, so this blocks spotting or hearing through ceilings, stair openings and windows
## across a courtyard, but still covers stair landings and bleachers.
const FLOOR_REACH := 2.4
const HALL_PASS_TIME := 35.0
const ALARM_TIME := 25.0
const ALARM_COOLDOWN := 150.0
const GATE_OPEN_TIME := 12.0
const PICKUP_RESPAWN := 45.0
const MAX_ITEMS := 3
# [name, uses she/her-style look (no moustache, longer hair), what everyone learns about them]
# Index = classroom. Each one plays differently (see TEACHER_BRAINS and the excuses).
const TEACHERS := [
	["Ms. Okafor", true, "hard to fool, soft on good marks"],
	["Mr. Tanaka", false, "eagle eyes, never leaves his room"],
	["Dr. Alvarez", false, "loves questions, hears nothing"],
	["Mrs. Iyer", true, "hears everything, believes you once"],
]
## How each teacher plays (index = classroom). range/fov: eyes; ears: how far they hear
## voices; gullible: how well excuses work on them; leash: gives up a chase this far
## from their board; remembers: believes one excuse, then never again.
const TEACHER_BRAINS := [
	{"range": 14.0, "fov": 100.0, "alertness": 1.15, "ears": 1.0, "gullible": 0.45, "chase_speed": 4.4, "likes_marks": true},
	{"range": 22.0, "fov": 70.0, "alertness": 1.0, "ears": 1.0, "gullible": 1.0, "chase_speed": 4.1, "leash": 15.0},
	{"range": 12.0, "fov": 100.0, "alertness": 0.8, "ears": 0.6, "gullible": 1.3, "chase_speed": 4.2, "lectures": true},
	{"range": 14.0, "fov": 100.0, "alertness": 1.0, "ears": 1.6, "gullible": 1.8, "chase_speed": 4.4, "remembers": true},
]
## Dr. Alvarez, asked a smart question: a lecture at the board (everyone's chance to sneak out).
const LECTURE := ["Ah! An EXCELLENT question. You see...", "...a linked list is really just a treasure hunt...",
	"...and each node points to the next, like gossip in a canteen...", "...which is why, in 1962, a man named Hoare...",
	"...no, no, this is the fascinating part...", "...where was I? Ah yes, the stack!", "...any questions? No? Good. Where were we..."]

const ITEMS := {
	"hall_pass": "Hall Pass", "samosa": "Samosa", "medical_note": "Medical Note",
	"canteen_key": "Canteen Key", "library_book": "Library Book", "extinguisher": "Fire Extinguisher",
}
# Canteen shop (Pappu Uncle's counter). Prices in rupees.
const SHOP := {"samosa": 10, "hall_pass": 40, "medical_note": 70}
const SHOP_ABOUT := {
	"samosa": "Eat it, or bribe staff close by",
	"hall_pass": "Walk the corridors without trouble",
	"medical_note": "Show it to a gate guard to walk out",
}
# Upgrades: [name, what it does, price per level].
const UPGRADES := {
	"pass": ["Signed passes", "+15 s on every hall pass", [50, 80, 120]],
}
const START_CASH := 30
const COIN_COUNT := 10
const COIN_RESPAWN := 20.0
const EXAM_GRACE := 8.0       # seconds to sit down once a test is announced
const BUMP_LINES := ["Oi, watch it!", "Bro, seriously?", "Careful!", "Excuse YOU.", "Ow! My foot!",
	"Walk much?", "Eyes UP, genius!", "Hey! I'm walking here!", "Rude.", "Personal space, please!"]
const QUESTS := {
	"samosa": "Eat a samosa from the canteen",
	"exam": "Steal the exam paper from the staff room",
	"library": "Return the overdue library book",
	"selfie": "Selfie with the principal's car (unseen)",
	"register": "Sign the register while your teacher isn't looking",
	"hoop": "Score a basket on the court",
	"notice": "Stick a meme on a notice board",
	"bell": "Ring the staff room bell",
	"slip": "Answer the register, then slip out of class",
	"boost": "Give or get a boost from a friend (crouch + E)",
	"proxy": "Answer the register for a friend (R)",
}
const QUEST_POINTS := 150

# Replicated (server -> everyone).
var status := {}  # peer_id -> see _new_status()
var rooms := []   # per classroom: {"attendance_in", "calling", "exam_at", "exam_until", "exam_id"}
var feed := []    # [{"t": elapsed, "text": String}]
var marks := []   # [{"pos": Vector3, "npc": String, "by": String, "until": float}]
var world := {"alarm_until": -100.0, "alarm_ready": 0.0, "gate_until": -100.0, "taken": {}, "stash": {},
	"puddles": [], "clouds": [], "calls": [], "bucket_ready": {}, "held": {},
	"period": 0, "periods": 3, "period_len": 160.0, "period_start": 0.0, "passing_until": -100.0, "coins": [],
	"heat": 1, "heat_bumps": 0, "party_at": -1.0, "party_until": -100.0, "race_winner": -1, "race_end_at": -1.0}
var elapsed := 0.0
var round_time := 480.0
var round_over := false
var results := []
var awards := []   # end of round: [{"title", "name", "line"}] (see _awards)
var replay := {}   # end of round: the best CCTV clip of the round (see _clip_*)

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
var _pending_staff: Array = []  # [heat, Callable]: patrols that come on duty as the heat rises
var _rules: Dictionary = {}     # this round's rules (Network.round_rules)
## Moments: everything notable that happened to someone ({t, id, kind, other}). They
## feed the end-of-round awards, and a dev report of stretches where nothing happened.
var _moments: Array = []
var _stats := {}  # player name -> counters for the awards (host only; kept across a rejoin)


func _ready() -> void:
	for i in Network.CLASSROOMS.size():
		rooms.append({"attendance_in": 99999.0, "calling": false, "exam_at": 99999.0, "exam_until": -100.0, "exam_id": 0})
	# Big, nested state: reliable delta sync (too big for one unreliable packet).
	# _snapshot() swaps in deep copies each tick so change detection works on nested data.
	var big := MultiplayerSynchronizer.new()
	big.name = "Sync"
	big.delta_interval = 0.1
	var config := SceneReplicationConfig.new()
	for prop in [".:status", ".:rooms", ".:feed", ".:marks", ".:results", ".:awards", ".:replay"]:
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
	if multiplayer.is_server():
		Voice.heard.connect(_on_voice)


# --- Setup ---------------------------------------------------------------------------------

## Server: called once every player has been spawned. seats: peer_id -> Vector3.
func start(seats: Dictionary, minutes: float) -> void:
	_seat = seats
	round_time = minutes * 60.0
	_rng.randomize()
	_rules = Network.round_rules.duplicate()
	if _event() == "birthday":
		world.party_at = round_time * 0.45
	for id in seats:
		status[id] = _new_status(id)
		_place_seat(id, seats[id])
	world.periods = clampi(roundi(round_time / 160.0), 2, 6)
	world.period_len = round_time / float(world.periods)
	world.passing_time = _passing_time()
	_schedule_period(0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--question="):  # dev: the nearest staff grabs and questions the host after N s
			get_tree().create_timer(float(arg.trim_prefix("--question="))).timeout.connect(func():
				var me: Node3D = players_root.get_node_or_null("1")
				var b := _nearest_brain(me.global_position, 999.0, ["teacher", "patrol", "gate"]) if me else {}
				if not b.is_empty():
					_start_chase(b, 1, me.global_position)
					b.npc.global_position = me.global_position + Vector3(0.8, 0, 0)
					print("[dev] %s grabs the host" % b.npc.display_name))
		if arg.begins_with("--jail="):  # dev: the host is sent to detention after N s
			get_tree().create_timer(float(arg.trim_prefix("--jail="))).timeout.connect(func():
				for b in _brains:
					if b.role == "teacher" and status.has(1):
						_catch(b, 1, "Straight to detention (dev).")
						return)

	for k in campus.ball_spawns.size():
		_balls.append(prop_spawner.spawn({"id": "Ball%d" % k, "pos": campus.ball_spawns[k]}))
	# A couple of canteen trolleys out on the assembly ground.
	for k in 2:
		var at: Vector3 = campus.assembly + Vector3(-3.5 + k * 7.0, 0.1, 3.5)
		_trolleys.append(prop_spawner.spawn({"id": "Trolley%d" % k, "kind": "trolley", "pos": at, "yaw": 0.0}))
	_setup_coins()
	if OS.get_cmdline_user_args().has("--no-staff"):  # dev: test routes without staff
		_log("Class has started (no staff).")
		_started = true
		return
	for i in campus.classes.size():
		var spots: Dictionary = campus.classes[i]
		var fem: bool = TEACHERS[i][1]
		var brain := {"state": "write", "timer": 6.0, "walk": 1.4, "chaser": true}
		brain.merge(TEACHER_BRAINS[i % TEACHER_BRAINS.size()])
		_add_npc({"id": "Teacher%d" % i, "role": "teacher", "room": i, "name": TEACHERS[i % TEACHERS.size()][0],
			"pos": spots.board, "yaw": spots.yaw, "look": _staff_look(100 + i, fem), "voice": (1.15 if fem else 0.8) + i * 0.05}, brain)
	_add_npc({"id": "Guard", "role": "gate", "room": -1, "name": "Sergei (Guard)",
		"pos": campus.gate_post, "yaw": campus.gate_yaw, "look": P.make_guard_look(7, true), "voice": 0.7},
		{"state": "post", "timer": 20.0, "range": 14.0, "fov": 110.0, "walk": 1.6, "chase_speed": 4.8, "alertness": 2.2, "chaser": true, "gullible": 0.7})
	# School patrols come on duty as the heat rises (see Rules.HEAT_STAFF).
	_pending_staff.append([Rules.HEAT_STAFF.Peon, func():
		_add_patrol("Peon", "Mr. Mendes (Caretaker)", campus.staff_loops.peon, P.make_guard_look(9, false), 1.9, 4.5, 1.4, 11.0, 0.75)])
	_pending_staff.append([Rules.HEAT_STAFF.Prefect, func():
		var prefect := P.make_look(4242, 0)
		prefect.tie = Color("ffd24a")
		prefect.bag = null
		prefect.cap = Color("e0524f")
		prefect.mustache = false
		_add_patrol("Prefect", "Aisha (Prefect)", campus.staff_loops.prefect, prefect, 1.8, 4.6, 1.0, 10.0, 1.3)
		_brains[-1].chaser = false  # she doesn't chase you: she runs to tell your teacher
		_brains[-1].tells = true])
	_pending_staff.append([Rules.HEAT_STAFF.Proctor, func():
		var proctor := _staff_look(888, false)
		proctor.shirt = Color("4f7fd9")
		_add_patrol("Proctor", "Mr. Kowalski (Proctor)", campus.staff_loops.proctor, proctor, 1.5, 4.6, 1.2, 12.0, 0.9)])
	_pending_staff.append([Rules.HEAT_STAFF.VP, func():
		var vp := _staff_look(777, false)
		vp.shirt = Color("9a62d6")
		vp.glasses = true
		_add_patrol("VP", "Dr. Haddad (Vice Principal)", campus.staff_loops.vp, vp, 1.4, 5.0, 1.15, 11.0, 1.1)
		_brains[-1].gullible = 0.5])
	_update_heat(true)

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
	if _event() != "":
		_log("TODAY: %s. %s" % [Rules.event_name(_event()), Rules.event_about(_event())])
	_fx_all("bell", Vector3.ZERO, "")
	_fx_all("round_intro", Vector3.ZERO, "")
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
	for id in status:
		status[id].helper_answers = -1
	world.period_start = elapsed
	world.passing_until = elapsed + (float(world.get("passing_time", PASSING_TIME)) if p > 0 else 0.0)
	var settle: float = float(world.passing_until) - elapsed
	var plen: float = world.period_len
	for i in rooms.size():
		rooms[i].calling = false
		rooms[i].attendance_in = settle + plen * 0.28 + i * 6.0  # once per period
		var test_at := 0.42 if _event() == "exam_week" else 0.62  # exam week: tests come sooner
		rooms[i].exam_at = minf(elapsed + settle + plen * test_at + i * 4.0, elapsed + plen - EXAM_TIME - 10.0)
		if _fresh():
			rooms[i].exam_at = 99999.0  # someone's very first round: no surprise tests yet
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
	data.view = [float(brain.get("range", 0.0)), float(brain.get("fov", 0.0))]  # for the players' vision cones
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
	brain.look = data.look  # for the end-of-round replay
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
			"chase_speed": 4.9, "alertness": 2.0, "chaser": true, "outdoor": true})
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
		_brains[-1].outdoor = true


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
	# A chain: the opening quest, then a medium one (a co-op one with friends about),
	# then a risky one. Only the current step can be done.
	var tier2: Array = Rules.TIER_2.duplicate()
	if Network.players.size() > 1:
		tier2.append_array(Rules.TIER_2_COOP)
	var quests := [{"id": Rules.OPENING, "done": false},
		{"id": tier2[rng.randi() % tier2.size()], "done": false},
		{"id": Rules.TIER_3[rng.randi() % Rules.TIER_3.size()], "done": false}]
	var items := []
	return {"sus": 0.0, "state": "class", "seen": false, "caught": 0, "spotted": 0, "time": 0.0, "timer": 0.0,
		"bunking": false, "items": items, "quests": quests, "pass_until": -1.0, "gate_pass_until": -1.0, "score": 0,
		"catches": 0, "warnings": 0, "chain": false, "style": 0, "peak": false, "calm_t": 0.0,
		"silent_m": 0.0, "last_pos": Vector3.ZERO, "unseen_run": 0.0, "longest_unseen": 0.0, "closest": 99.0,
		"closest_who": "", "best_distraction": 0, "present_period": -1, "watch_pos": Vector3.ZERO,
		"grabbed": false, "shoves": 0, "seat_idx": 0, "seat": Vector3.ZERO, "strikes": 0, "good_time": 0.0,
		"returning": false, "return_until": -1.0, "essay_line": 0, "exam_key": "", "exam_total": 0, "exams": 0,
		"exams_missed": 0, "exam_photo": false, "cash": 0 if _rule() == "broke" else START_CASH, "earned": 0,
		"upgrades": {"pass": 0},
		"exam_in_at": -1.0, "exam_paper": "", "exam_deadline": -1.0, "wait_since": -1.0,
		"settle_until": -1.0, "had_pass": false, "pass_late": false, "was_in_room": true,
		"helper_answers": -1, "helper_from": "", "assists": 0, "helped": {}}


## Something happened to `id` (with `other` involved, a peer id or -1).
func _moment(kind: String, id: int, other := -1) -> void:
	_moments.append({"t": elapsed, "id": id, "kind": kind, "other": other})
	_clip_moment(kind, id, other)


## Adds `by` to one of `id`'s award counters (see _awards). "max:" keys keep the biggest value.
func _stat(id: int, key: String, by := 1.0) -> void:
	if not status.has(id):
		return
	var s: Dictionary = _stats.get_or_add(_name(id), {})
	if key.begins_with("max:"):
		s[key] = maxf(float(s.get(key, 0.0)), by)
	else:
		s[key] = float(s.get(key, 0.0)) + by


## "with Mrs. Iyer: hears everything, believes you once" (HUD period card, phone).
func teacher_line(room: int) -> String:
	if room < 0 or room >= TEACHERS.size():
		return ""
	return "with %s: %s" % [TEACHERS[room][0], TEACHERS[room][2]]


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
	if st.state == "detention" and action not in ["ping", "essay", "shout"]:
		return
	# Out of the university: you can still ping, trade, boost a friend and throw paper
	# balls back over the wall to pull staff away from friends still inside.
	if st.state == "escaped" and action not in ["ping", "give", "throw", "boost", "help_answers", "prank_call", "deliver", "outside_bell", "shout",
			"call_office", "announce", "open_gate", "call"]:
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
		"help_answers": _on_help_answers(id, int(args.get("to", -1)), int(args.get("score", 0)))
		"prank_call": _on_prank_call(id, int(args.get("to", -1)))
		"deliver": _on_deliver(id, int(args.get("to", -1)))
		"outside_bell": _on_outside_bell(id, p)
		"give": _on_give(id, p, int(args.get("to", -1)), int(args.get("cash", 0)), int(args.get("slot", -1)))
		"shout": _on_shout(id, p, int(args.get("k", 0)))
		"trolley": _on_trolley(id, p, str(args.get("name", "")))
		"hold_door": _on_hold_door(id, p, int(args.get("i", -1)), int(args.get("friend", -1)))
		"announce": _on_announce(id, int(args.get("k", 0)))
		"open_gate": _on_remote_gate(id)
		"call": _on_call(id, int(args.get("to", -1)))
		"trolley_off": _off_trolley(id)
		"excuse": _on_excuse(id, p, int(args.get("k", -1)))
		"vouch": _on_vouch(id, p, int(args.get("friend", -1)))
		"call_office": _on_call_office(id, int(args.get("to", -1)))


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
	if kind in CLIP_FX:
		_clip_events.append({"t": elapsed, "fx": kind, "pos": pos, "extra": extra})


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
			_pay(id, 5, "for a smart question")
			if t.get("lectures", false):
				# Dr. Alvarez can't help himself: 20 s at the board, back to the class.
				t.state = "write"
				t.timer = 20.0
				t.lecture_until = elapsed + 20.0
				t.lecture_i = 0
				var spots: Dictionary = campus.classes[room]
				npc.go_to(_path(npc.global_position, spots.board), t.walk)
				npc.say(LECTURE[0], 3.5)
				_log("%s asked Dr. Alvarez a smart question. He's LECTURING. Everyone, GO!" % _name(id))
				_moment("lecture", id)
			else:
				npc.stop(npc.yaw_towards(p.global_position - npc.global_position))
				npc.say(reply, 4.0)
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


## A stylish move: a few points and a pop-up by the crosshair.
func _style(id: int, kind: String) -> void:
	if not status.has(id) or not Rules.STYLE.has(kind):
		return
	var st: Dictionary = status[id]
	var pts: int = int(Rules.STYLE[kind][1])
	st.style = int(st.style) + pts
	_fx.rpc_id(id, "style", Vector3.ZERO, "%s|%d" % [Rules.STYLE[kind][0], pts])


## A player's first round (see Network.start_game): the basics only, no tests,
## no round event, the school never gets stricter than heat 2.
func _fresh() -> bool:
	return bool(_rules.get("fresh", false))


func _event() -> String:
	return str(_rules.get("event", ""))


func _rule() -> String:
	return str(_rules.get("rule", ""))


## What Pappu Uncle says when you come to the counter: he notices your wallet, your
## detentions and the mood of the school.
func _uncle_greeting(id: int) -> String:
	var st: Dictionary = status.get(id, {})
	if int(st.get("cash", 0)) < 10:
		return Lines.uncle(_rng, "broke")
	if int(st.get("caught", 0)) > 0 and _rng.randf() < 0.5:
		return Lines.uncle(_rng, "caught")
	if int(world.heat) >= 4 and _rng.randf() < 0.5:
		return Lines.uncle(_rng, "heat")
	return Lines.uncle(_rng, "greet")


var _uncle_next := 12.0


## Hang around the canteen and Uncle talks to you (tips included).
func _uncle_chatter(players: Dictionary) -> void:
	if elapsed < _uncle_next:
		return
	_uncle_next = elapsed + _rng.randf_range(10.0, 16.0)
	var b := _brain_by_name("Uncle")
	if b.is_empty() or str(b.npc.speech) != "":
		return
	for id in players:
		if status[id].state in ["class", "chased"] and (players[id] as Node3D).global_position.distance_to(b.npc.global_position) < 6.0:
			b.npc.say(Lines.uncle(_rng, "idle"), 3.5)
			return


func _near_counter(p: Node3D) -> bool:
	var i := _find_interactable("counter")
	return i != -1 and p.global_position.distance_to(campus.interactables[i].pos) < 3.5


## Canteen shop: items go in your pocket, upgrades last the whole round.
func _on_buy(id: int, p: Node3D, what: String) -> void:
	var st: Dictionary = status[id]
	if not _near_counter(p):
		_tell(id, "Buy things at Pappu Uncle's canteen counter.", Color("ffb37a"))
		return
	if what.begins_with("bail:"):
		_on_bail(id, int(what.trim_prefix("bail:")))
		return
	var price := -1
	var level := 0
	if what == "hall_pass" and _rule() == "no_pass":
		_tell(id, "No hall passes today. Uncle's sold out.", Color("ffb37a"))
		return
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
	_npc_say("Uncle", Lines.uncle(_rng, "buy"))


## Pappu Uncle sends the principal a plate of samosas "from the canteen"... and a
## friend in detention gets let off. Rs 40.
func _on_bail(id: int, to: int) -> void:
	var st: Dictionary = status[id]
	if not status.has(to) or status[to].state != "detention" or to == id:
		_tell(id, "Nobody to bail out.", Color("ffb37a"))
		return
	if int(st.cash) < BAIL_PRICE:
		_tell(id, "The principal's samosas cost Rs %d." % BAIL_PRICE, Color("ffb37a"))
		return
	st.cash = int(st.cash) - BAIL_PRICE
	_npc_say("Uncle", "One plate for the principal... with your compliments. Heh heh.")
	_release(to, "%s bribed the principal with Uncle's samosas. You're FREE!" % _name(id))
	_tell(id, "Samosas sent. %s walks free!" % _name(to), Color("7fe0a0"))
	_log("%s bribed %s out of detention with samosas!" % [_name(id), _name(to)])
	_stat(id, "rescues")
	_moment("rescue", id, to)
	_moment("rescued", to, id)


## Trade with a classmate standing next to you: hand over money or an item.
func _on_give(id: int, p: Node3D, to: int, cash: int, slot: int) -> void:
	var friend := players_root.get_node_or_null(str(to))
	var remote: bool = status[id].state == "escaped"  # sent by phone from outside
	if friend == null or to == id or not status.has(to) or (not remote and friend.global_position.distance_to(p.global_position) > 3.5):
		_tell(id, "Stand next to your classmate to trade.", Color("ffb37a"))
		return
	var st: Dictionary = status[id]
	var ft: Dictionary = status[to]
	if ft.state == "detention":
		_tell(id, "%s is in detention: wait till they're out." % _name(to), Color("ffb37a"))
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


# --- Helping from outside (escaped players, from their phone) ------------------------------------

const ASSIST_POINTS := 40
const PRANK_COOLDOWN := 45.0
const DELIVERY_PRICE := 15
const PRANK_LINES := ["Hello? Principal's office? ...Who is this?", "WHAT? My car is being towed?!",
	"Wrong number. Again. Who keeps calling?!", "Yes, this is staff. No, I did NOT order 40 pizzas."]


## `to` is a friend still inside who can take help (not escaped, not in detention); else tells `id` why not.
func _inside_friend(id: int, to: int) -> bool:
	if status[id].state != "escaped":
		return false
	if to == id or not status.has(to) or not players_root.has_node(str(to)):
		return false
	if status[to].state in ["escaped", "detention"]:
		_tell(id, "%s can't use help right now." % _name(to), Color("ffb37a"))
		return false
	return true


## The helper sat the friend's paper on their phone: the friend's test this
## period scores at least that. Once per friend per period.
func _on_help_answers(id: int, to: int, score: int) -> void:
	if not _inside_friend(id, to):
		return
	var key := "%d:%d" % [to, int(world.period)]
	var helped: Dictionary = status[id].helped
	if helped.has(key):
		_tell(id, "You already texted %s this period's answers." % _name(to), Color("ffb37a"))
		return
	helped[key] = true
	score = clampi(score, 0, 100)
	var ft: Dictionary = status[to]
	ft.helper_answers = maxi(int(ft.helper_answers), score)
	ft.helper_from = _name(id)
	status[id].assists = int(status[id].assists) + 1
	_tell(id, "Answers sent to %s (%d/100). +%d" % [_name(to), score, ASSIST_POINTS], Color("7fe0a0"))
	_tell(to, "%s texted you the answers: your %s test scores at least %d/100!" % [_name(id), SUBJECTS[current_room(to)], score], Color("ffd24a"))
	_fx.rpc_id(to, "pickup", Vector3.ZERO, "")
	_log("%s texted %s the answers." % [_name(id), _name(to)])


## A prank call pulls away whoever is chasing the friend (or the staff nearest to them) for 10 s.
func _on_prank_call(id: int, to: int) -> void:
	if not _inside_friend(id, to):
		return
	var friend: Node3D = players_root.get_node(str(to))
	var pick := {}
	for b in _brains:
		if b.state == "chase" and b.target == to:
			pick = b
	if pick.is_empty():
		pick = _nearest_brain(friend.global_position, 30.0, ["teacher", "gate", "patrol", "sitter"])
	if pick.is_empty():
		_tell(id, "No staff near %s to prank-call." % _name(to), Color("ffb37a"))
		return
	if not _cooldown(id, "prank", PRANK_COOLDOWN):
		_tell(id, "Your number's been flagged. Wait a bit before calling again.", Color("ffb37a"))
		return
	pick.distracted_until = elapsed + 10.0
	pick.npc.stop(pick.npc.rotation.y)
	pick.npc.say(PRANK_LINES[_rng.randi() % PRANK_LINES.size()], 3.5)
	if pick.target != -1:
		_end_chase(pick)
	status[id].assists = int(status[id].assists) + 1
	_tell(id, "Prank call! %s is busy for 10 s. +%d" % [pick.npc.display_name, ASSIST_POINTS], Color("7fe0a0"))
	_tell(to, "%s prank-called %s. GO!" % [_name(id), pick.npc.display_name], Color("ffd24a"))
	_log("%s prank-called %s." % [_name(id), pick.npc.display_name])
	_moment("prank", id, to)
	_moment("saved", to, id)


## Samosa delivery to a friend inside, paid by the helper.
func _on_deliver(id: int, to: int) -> void:
	if not _inside_friend(id, to):
		return
	var st: Dictionary = status[id]
	var ft: Dictionary = status[to]
	if (ft.items as Array).size() >= MAX_ITEMS:
		_tell(id, "%s's pockets are full." % _name(to), Color("ffb37a"))
		return
	if int(st.cash) < DELIVERY_PRICE:
		_tell(id, "Delivery costs Rs %d. You're broke!" % DELIVERY_PRICE, Color("ffb37a"))
		return
	if not _cooldown(id, "deliver", 15.0):
		return
	st.cash = int(st.cash) - DELIVERY_PRICE
	ft.items.append("samosa")
	st.assists = int(st.assists) + 1
	_tell(id, "Samosa delivered to %s. +%d" % [_name(to), ASSIST_POINTS], Color("7fe0a0"))
	_tell(to, "Delivery! %s sent you a samosa." % _name(id), Color("ffd24a"))
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
	if not status.has(id):
		return
	var st: Dictionary = status[id]
	for q in st.quests:
		if q.done:
			continue
		if q.id != quest:
			return  # not the current step of the chain
		q.done = true
		_fx.rpc_id(id, "quest", Vector3.ZERO, "")
		_tell(id, "Quest complete: %s  +%d" % [QUESTS[quest], QUEST_POINTS], Color("7fe0a0"))
		_log("%s completed a side quest!" % _name(id))
		_pay(id, 40, "for the quest")
		_style(id, "quest")
		var next := ""
		for n in st.quests:
			if not n.done:
				next = n.id
				break
		if next == "library" and not (st.items as Array).has("library_book") and (st.items as Array).size() < MAX_ITEMS:
			st.items.append("library_book")
		if next != "":
			_tell(id, "Next quest: %s" % QUESTS.get(next, next), Color("9fd8ff"))
		else:
			st.chain = true
			st.gate_pass_until = elapsed + Rules.CHAIN_PASS
			_tell(id, "QUEST CHAIN DONE! +%d. The guards owe you one: walk out a gate in the next %ds." % [Rules.CHAIN_BONUS, int(Rules.CHAIN_PASS)], Color("ffd24a"))
			_fx.rpc_id(id, "badge", Vector3.ZERO, "")
			_log("%s finished the whole quest chain!" % _name(id))
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
				if it.item == "extinguisher":
					st.ext_charges = 2
					_tell(id, "Fire extinguisher: 2 sprays. Blinds cameras and staff, knocks people over, floor gets slippery.", Color("9fd8ff"))
		"counter":
			_npc_say("Uncle", _uncle_greeting(id))
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
			_moment("alarm", id)
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
		"bucket":
			var key := str(index)
			if float(world.bucket_ready.get(key, -1.0)) > elapsed:
				_tell(id, "Already on the floor. Mr. Mendes is NOT happy.", Color("ffb37a"))
				return
			world.bucket_ready[key] = elapsed + 60.0
			_puddle(it.pos, 2.6, 45.0, id, "water")
			_fx_all("splash", it.pos, "")
			_noise(it.pos, 8.0)
			_tell(id, "SPLOSH. Wet floor: anyone who sprints across it goes flying.", Color("7fd0ea"))
			_moment("bucket", id)
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
		if _rule() == "no_pass":
			b.npc.say("No passes today. Principal's orders.", 2.2)
		elif _rng.randf() < 0.6:
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
			if near.is_empty() or near.target == id:
				if _throw_samosa(id, p):
					return
			if not near.is_empty() and near.target != id:
				near.distracted_until = elapsed + 12.0
				near.npc.say(["Ooh, samosa! *munch*", "For ME? Well... I didn't see anything. *munch*", "Is this a bribe? ...It's working. *munch*"][_rng.randi() % 3], 3.0)
				if near.target != -1:
					_end_chase(near)
				_log("%s bribed %s with a samosa." % [_name(id), near.npc.display_name])
				_moment("bribe", id)
				_stat(id, "samosas")
			else:
				_tell(id, "Crunchy, spicy, perfect.", Color("7fe0a0"))
				_complete(id, "samosa")
				_stat(id, "samosas")
		"medical_note":
			var guard := _nearest_brain(p.global_position, 5.0, ["gate"])
			if not guard.is_empty() and guard.target != id:
				items.remove_at(slot)
				st.gate_pass_until = elapsed + 15.0
				guard.npc.say("Hmm... get well soon, kid. Go.", 3.0)
				_tell(id, "The guard bought it! Walk out now.", Color("7fe0a0"))
			else:
				_tell(id, "Show this to the gate guard up close.", Color("ffb37a"))
		"canteen_key":
			if p.global_position.distance_to(campus.service_gate_pos) < 3.5:
				_open_service_gate()
			else:
				_tell(id, "Use it at the service gate in the east wall.", Color("ffb37a"))
		"library_book":
			_tell(id, "Return it at the library desk (or wave it at a teacher: \"returning a book!\").", Color("9fd8ff"))
		"extinguisher":
			_spray(id, p)
			st.ext_charges = int(st.get("ext_charges", 2)) - 1
			if int(st.ext_charges) <= 0:
				items.remove_at(slot)
				_tell(id, "PSSHHHH! That was the last of it.", Color("9fd8ff"))
			else:
				_tell(id, "PSSHHHH! One spray left.", Color("9fd8ff"))


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
	get_tree().create_timer(t).timeout.connect(func():
		_paper_rescue(id, pos)
		var pulled := _noise(pos, 11.0)
		if status.has(id):
			status[id].best_distraction = maxi(int(status[id].best_distraction), pulled)
		_paper_hit(id, pos))


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
	if int(st.helper_answers) > score:
		_tell(id, "%s's texted answers saved you!" % str(st.helper_from), Color("7fe0a0"))
		score = int(st.helper_answers)
	st.helper_answers = -1
	score = clampi(score, 0, 100)
	st.exam_total = int(st.exam_total) + score * (2 if _event() == "exam_week" else 1)
	st.exams = int(st.exams) + 1
	_tell(id, "%s test: %d/100" % [SUBJECTS[room], score], Color("7fe0a0") if score >= 50 else Color("ffb37a"))
	_log("%s scored %d in the %s test." % [_name(id), score, SUBJECTS[room]])
	_moment("test", id)
	if score >= 20:
		_pay(id, score / 5, "for the test")
	if score == 100:
		_log("%s got full marks in %s!" % [_name(id), SUBJECTS[room]])


## Detention lines: copy the sentence exactly, get out sooner.
## A detention line counts if it's the same words: case, extra spaces and a
## final full stop don't matter. (The HUD checks with this too, before sending.)
static func essay_matches(text: String, want: String) -> bool:
	var norm := func(s: String) -> String:
		s = s.strip_edges().to_lower()
		while "  " in s:
			s = s.replace("  ", " ")
		return s.trim_suffix(".").strip_edges()
	return norm.call(text) == norm.call(want)


func _on_essay(id: int, text: String) -> void:
	var st: Dictionary = status[id]
	if st.state != "detention" or not _cooldown(id, "essay", 0.8):
		return
	var want: String = LINES[int(st.essay_line) % LINES.size()]
	if essay_matches(text, want):
		var off := Rules.LINE_SECONDS_LATE if int(st.catches) >= 4 else Rules.LINE_SECONDS
		st.timer = maxf(2.0, float(st.timer) - off)
		st.essay_line = (int(st.essay_line) + 1 + _rng.randi() % (LINES.size() - 1)) % LINES.size()
		_tell(id, "Line accepted. -%ds" % int(off), Color("7fe0a0"))
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
	_moment("boost", id, friend_id)
	_complete(id, "boost")
	_complete(friend_id, "boost")


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
		if absf(to.y) > 1.0 or not _within_reach(p, b.npc):
			continue  # another floor, or a wall / ceiling in between
		to.y = 0.0
		if to.length() < best and (to.length() < 0.8 or fwd.dot(to.normalized()) > 0.35):
			best = to.length()
			target = b
	# A friend right in front of you, closer than any staff: they go flying. No penalty.
	var friend := -1
	for other in status:
		var q: Node3D = players_root.get_node_or_null(str(other))
		if other == id or q == null or q.hidden or status[other].state not in ["class", "chased"]:
			continue
		var tq: Vector3 = q.global_position - p.global_position
		if absf(tq.y) > 1.0 or not _within_reach(p, q):
			continue
		tq.y = 0.0
		if tq.length() < best and (tq.length() < 0.8 or fwd.dot(tq.normalized()) > 0.35):
			best = tq.length()
			friend = other
	if friend != -1:
		if not _cooldown(id, "shove", 2.0):
			return
		var race := str(_rules.get("mode", "")) == "race"
		if _tumble(friend, fwd * 6.5 + Vector3.UP * 2.0, 2.0 if race else 1.3, "was shoved by %s" % _name(id)):
			_fx_all("shove", players_root.get_node(str(friend)).global_position, "")
			_tell(friend, "%s SHOVED you!" % _name(id), Color("ff9a4a"))
			_stat(id, "shoved_friends")
			_moment("shoved_friend", id, friend)
		return
	if target.is_empty():
		return
	if not _cooldown(id, "shove", 4.0):
		_tell(id, "Catch your breath first!", Color("ffb37a"))
		return
	var st: Dictionary = status[id]
	var npc: Node = target.npc
	_knock(target, fwd * 5.5, SHOVE_STUN, id)
	npc.say(["Whoa!", "Oof!", "How DARE you?!", "Aaah!", "My BACK!"][_rng.randi() % 5], 1.8)
	st.shoves += 1
	st.grabbed = false
	st.question = {}
	if target.has("report_on"):
		_stop_report(target)
	_fx_all("shove", npc.global_position, "")
	if target.target == id:
		_tell(id, "Shoved free! RUN!", Color("7fe0a0"))
	elif target.role != "extra":
		st.sus = minf(100.0, st.sus + 55.0)  # now they're definitely suspicious
	_log("%s shoved %s!" % [_name(id), npc.display_name])
	_moment("shove", id)


## Nothing solid between a player's chest and someone else's (shoves, grabs).
func _within_reach(p: Node3D, other: Node3D) -> bool:
	var from := p.global_position + Vector3(0, 1.1, 0)
	var to := other.global_position + Vector3(0, 1.1, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [p.get_rid(), other.get_rid()]
	return players_root.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
		_ball_hits(ball)
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
	world.heat_bumps = int(world.heat_bumps) + 1
	_gather(campus.assembly, "Fire drill! Everyone out!")
	for id in status:
		_release(id, "FIRE DRILL! The principal ran out, and so did you. Walk back to class!")


## Principal's birthday: the staff go for cake at the canteen for a while.
func _start_party() -> void:
	world.party_until = elapsed + 30.0
	var i := _find_interactable("counter")
	var spot: Vector3 = campus.interactables[i].pos if i != -1 else campus.assembly
	_log("It's the principal's birthday! Staff are at the canteen for cake. GO!")
	_fx_all("bell", Vector3.ZERO, "")
	_gather(spot, "Cake! Happy birthday, Principal!")


## Staff (not the canteen uncle) walk to `spot` and mill about there.
func _gather(spot0: Vector3, line: String) -> void:
	var k := 0
	for b in _brains:
		if b.role in ["teacher", "patrol", "sitter"] and b.npc.name != "Uncle":
			if b.state == "chase":
				_end_chase(b)
			b.state = "evacuate"
			b.npc.pose = 0
			var spot: Vector3 = spot0 + Vector3((k % 5) * 1.3 - 2.6, 0, (k / 5) * 1.3 + 1.5)
			b.npc.go_to(_path(b.npc.global_position, spot), b.walk * 1.8)
			b.npc.say(line, 2.0)
			k += 1
	for r in rooms:
		r.calling = false


func _open_service_gate() -> void:
	world.gate_until = elapsed + GATE_OPEN_TIME
	_fx_all("gate", campus.service_gate_pos, "")
	_log("The service gate is open!")


## A paper ball landing by the detention office: "someone did two of your lines!"
func _paper_rescue(id: int, pos: Vector3) -> void:
	if pos.distance_to(campus.detention_spot) > 7.0:
		return
	for other in status:
		if other != id and status[other].state == "detention":
			status[other].timer = maxf(2.0, float(status[other].timer) - 10.0)
			_tell(other, "A paper ball through the window: %s did two of your lines! -10 s" % _name(id), Color("7fe0a0"))
			_tell(id, "Bullseye! %s's detention: -10 s" % _name(other), Color("7fe0a0"))
			_stat(id, "rescues")
			_moment("rescue", id, other)


## Race mode: a paper ball landing on a rival makes staff look their way.
func _paper_hit(id: int, pos: Vector3) -> void:
	for other in status:
		var q := players_root.get_node_or_null(str(other))
		if other == id or q == null or status[other].state not in ["class", "chased"]:
			continue
		if q.global_position.distance_to(pos) < 1.8:
			var race := str(_rules.get("mode", "")) == "race"
			status[other].sus = minf(99.0, float(status[other].sus) + (30.0 if race else 12.0))
			_tell(other, "%s hit you with a paper ball! Everyone's looking..." % _name(id), Color("ff9a4a"))
			_tell(id, "Direct hit on %s!" % _name(other), Color("7fe0a0"))
			_moment("paper_hit", id, other)
			_stat(id, "paper_hits")


## Staff within `radius` (on the same floor) come to look. Returns how many came.
func _noise(pos: Vector3, radius: float) -> int:
	var pulled := 0
	for b in _brains:
		if b.role in ["extra"] or b.state in ["chase", "evacuate", "attendance"] or _distracted(b):
			continue
		if b.npc.global_position.distance_to(pos) > radius or absf(b.npc.global_position.y - pos.y) > FLOOR_REACH:
			continue  # too far, or on another floor
		if b.role == "sitter" and b.npc.name == "Uncle":
			continue
		b.resume = b.state
		b.state = "investigate"
		b.timer = 3.0
		b.npc.alert = 1
		b.npc.pose = 0
		b.npc.say("What was that?!", 1.5)
		b.npc.go_to(_path(b.npc.global_position, pos), b.walk * 1.5)
		pulled += 1
	return pulled


# --- Voices: staff hear your microphone (how loud, never what you say) ------------------------------

const VOICE_WINDOW := 0.3  # seconds of mic frames judged together
## Quick shouts for players without a mic (B): [text, how far staff hear it (m)].
const SHOUT_LIST := [["Psst!", 2.0], ["RUN!", 13.0], ["Over here!", 10.0], ["HELP!", 13.0]]
const HUSH_LINES := ["Who's talking?!", "I HEARD that.", "Something funny back there?", "Is someone chatting in MY class?"]
const QUIET_LINES := ["Quiet at the back, %s!", "%s! Do you want to share it with the whole class?", "Not a word, %s.", "%s, one more sound and you're out."]
const HEARD_LINES := ["I heard that.", "Who's there?", "Is someone talking out there?!", "I can hear you, you know!", "Hello? Who's that?"]

var _voice_peak := {}  # peer id -> loudest mic frame in the current window
var _voice_t := 0.0


## Mic frame from the Voice autoload (host).
func _on_voice(id: int, rms: float) -> void:
	_voice_peak[id] = maxf(float(_voice_peak.get(id, 0.0)), rms)


func _voice_step(delta: float) -> void:
	_voice_t += delta
	if _voice_t < VOICE_WINDOW:
		return
	_voice_t = 0.0
	for id in _voice_peak:
		_heard(int(id), voice_radius(float(_voice_peak[id])))
	_voice_peak.clear()


## How far staff hear a voice this loud (RMS of the mic): 0 = not at all. A whisper
## carries a metre or two, talking about 7 m, a yell right down the corridor.
static func voice_radius(rms: float) -> float:
	var db := 20.0 * log(maxf(rms, 0.00001)) / log(10.0)
	if db < -46.0:
		return 0.0
	return clampf(1.5 + (db + 42.0) * 0.5, 1.0, 16.0)


func _hear_voices() -> bool:
	return bool(_rules.get("hear", true))


## Staff within `radius` of player `id` (same floor, half as far through a wall) react
## to the noise they made: talking in class turns the teacher round, talking where you
## shouldn't be brings staff to look, talking in a locker gives you away.
func _heard(id: int, radius: float) -> void:
	if radius <= 0.0 or not _hear_voices() or not status.has(id) or round_over or not _started:
		return
	var p: Node3D = players_root.get_node_or_null(str(id))
	if p == null:
		return
	var st: Dictionary = status[id]
	if st.state == "detention":
		if radius >= 9.0 and _cooldown(id, "hush_detention", 6.0):
			st.timer = minf(float(st.timer) + 3.0, 90.0)
			_tell(id, "\"SILENCE in detention!\"  (+3 s)", Color("ff9a4a"))
		return
	if st.state not in ["class", "chased"]:
		return
	var pos := p.global_position
	var near: Array = []
	for b in _brains:
		if b.role == "extra" or _stunned(b) or _distracted(b) or b.state == "evacuate" or b.npc.name == "Uncle":
			continue
		var npc: Node = b.npc
		if absf(npc.global_position.y - pos.y) > FLOOR_REACH:
			continue
		var reach: float = radius * float(b.get("ears", 1.0))
		var d: float = npc.global_position.distance_to(pos)
		if d > reach or (d > reach * 0.5 and not _within_reach(p, npc)):
			continue
		near.append(b)
	var reacted := false
	for b in near:
		if _cooldown(id, "heard:%s" % b.npc.name, 4.0) and _heard_by(b, id, p, st, radius):
			reacted = true
	if reacted:
		_stat(id, "heard")
		_moment("heard", id)
		print("[%.1f] staff heard %s (%.0f m): %s" % [elapsed, _name(id), radius, (near[0].npc as Node).speech])


## One staff member heard `id`. Returns whether they did something about it.
func _heard_by(b: Dictionary, id: int, p: Node3D, st: Dictionary, radius: float) -> bool:
	var npc: Node = b.npc
	var pos := p.global_position
	if b.state == "chase":
		if b.target == id and p.hidden and not b.get("saw_hide", false):
			b.saw_hide = true
			b.hide_judged = true
			npc.say("I can HEAR you in there! Out!", 2.5)
			return true
		return false
	if p.hidden:
		# In a locker or a stall, and not quiet about it: they know exactly where you are.
		npc.say("Who's in there?! I can hear you!", 2.5)
		st.sus = 100.0
		if b.chaser:
			_start_chase(b, id, pos)
			b.saw_hide = true
			b.hide_judged = true
		else:
			_call_help(id, pos, npc.display_name)
		_log("%s heard %s hiding!" % [npc.display_name, _name(id)])
		return true
	var own: bool = b.role == "teacher" and b.room == current_room(id) and campus.room_of(pos) == b.room
	if own:
		if elapsed < float(world.passing_until) or radius < 4.0:
			return false  # chatting between classes, or a whisper: fine
		if b.state == "write":
			# Back to the class, writing on the board... and someone laughs.
			b.state = "watch"
			b.timer = 4.0
			npc.say(HUSH_LINES[_rng.randi() % HUSH_LINES.size()], 2.2)
			return true
		if b.state in ["watch", "stare", "patrol"]:
			st.sus = minf(99.0, float(st.sus) + 4.0 + radius)
			npc.say(QUIET_LINES[_rng.randi() % QUIET_LINES.size()] % _name(id), 2.5)
			npc.stop(npc.yaw_towards(pos - npc.global_position))
			return true
		return false
	if b.role == "sitter" and b.npc.name == "Librarian":
		npc.say("SHHH! This is a LIBRARY.", 2.0)
	if not _suspicious(id, p, b):
		return false  # somewhere you're allowed to be: talk all you like
	if b.state in ["attendance", "handout", "investigate", "stare"]:
		npc.stop(npc.yaw_towards(pos - npc.global_position))
		return false
	b.resume = b.state
	b.state = "investigate"
	b.timer = 3.5
	npc.alert = 1
	npc.pose = 0
	npc.say(HEARD_LINES[_rng.randi() % HEARD_LINES.size()], 2.0)
	npc.go_to(_path(npc.global_position, pos), b.walk * 1.5)
	return true


## A quick shout (no mic needed): everyone sees it over your head, staff hear it.
func _on_shout(id: int, p: Node3D, k: int) -> void:
	if not _cooldown(id, "shout", 1.5):
		return
	var pick: Array = SHOUT_LIST[clampi(k, 0, SHOUT_LIST.size() - 1)]
	_fx_all("shout", p.global_position, "%d|%s" % [id, pick[0]])
	_heard(id, float(pick[1]))


# --- Physical chaos: tumbles, wet floors, trolleys, extinguishers ----------------------------------

const SLIP_SPEED := 4.6        # faster than this over a wet floor and you're on your back
const CRASH_SPEED := 8.5       # two students closing faster than this bounce off each other
const MOP_EVERY := 32.0        # Mr. Mendes mops a patch of corridor this often
var _trolleys: Array[Node] = []


## Knock a student over (they fly along `push`, then get up). False if they can't be.
func _tumble(id: int, push: Vector3, seconds: float, why := "") -> bool:
	var p: Node3D = players_root.get_node_or_null(str(id))
	if p == null or p.hidden or not status.has(id) or status[id].state not in ["class", "chased"]:
		return false
	if elapsed < float(status[id].get("tumble_until", -1.0)) + 0.6:
		return false  # still picking themselves up
	status[id].tumble_until = elapsed + seconds
	_off_trolley(id)
	for t in _trolleys:
		if is_instance_valid(t) and t.pusher == id:
			t.release(Vector3.ZERO)
	p.tumble.rpc_id(id, push, seconds)
	_fx_all("tumble", p.global_position, str(id))
	_stat(id, "tumbles")
	_moment("tumble", id)
	if why != "":
		print("[%.1f] %s %s" % [elapsed, _name(id), why])
	return true


## Knock a staff member (or a walking student) flat. `by`: the player responsible.
func _knock(b: Dictionary, push: Vector3, seconds: float, by := -1) -> bool:
	if _stunned(b) or (b.role == "extra" and b.state == "sit"):
		return false
	b.stunned_until = elapsed + seconds
	b.grab_until = -1.0
	if status.has(b.target):
		status[b.target].grabbed = false  # knocking a friend's captor over frees them too
		status[b.target].question = {}
	b.npc.stun(push, seconds)
	b.knocked_at = elapsed
	b.knock_push = push
	b.knocked_by = by
	_fx_all("books", b.npc.global_position, "%.2f,%.2f" % [push.x, push.z])
	return true


func _puddle(pos: Vector3, radius: float, seconds: float, by: int, kind: String) -> void:
	var list: Array = world.puddles
	list.append({"p": pos, "r": radius, "until": elapsed + seconds, "by": by, "kind": kind})
	while list.size() > 12:
		list.pop_front()


func _chaos_step(players: Dictionary, _delta: float) -> void:
	var now := elapsed
	world.puddles = (world.puddles as Array).filter(func(pd): return float(pd.until) > now)
	world.clouds = (world.clouds as Array).filter(func(c): return float(c.until) > now)
	world.calls = (world.calls as Array).filter(func(c): return float(c[2]) > now)
	var ids: Array = players.keys()
	# Two students sprinting into each other: both on the floor.
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Node3D = players[ids[i]]
			var c: Node3D = players[ids[j]]
			if a.hidden or c.hidden or a.seated or c.seated:
				continue
			var to: Vector3 = a.global_position - c.global_position
			if absf(to.y) > 1.0:
				continue
			to.y = 0.0
			if to.length() > 0.75 or float(a.net_speed) + float(c.net_speed) < CRASH_SPEED or not (a.sprinting or c.sprinting):
				continue
			var away := to.normalized() if to.length() > 0.01 else Vector3.RIGHT
			var hit_a := _tumble(ids[i], away * 4.5 + Vector3.UP * 2.0, 1.2)
			var hit_c := _tumble(ids[j], -away * 4.5 + Vector3.UP * 2.0, 1.2)
			if hit_a or hit_c:
				_log("%s and %s crashed into each other!" % [_name(ids[i]), _name(ids[j])])
	# Dominoes: someone knocked flat takes out whoever they land on.
	for b in _brains:
		if now - float(b.get("knocked_at", -99.0)) > 0.6:
			continue
		var at: Vector3 = b.npc.global_position
		var push: Vector3 = b.get("knock_push", Vector3.ZERO)
		for o in _brains:
			if o == b or o.npc.global_position.distance_to(at) > 1.0:
				continue
			if _knock(o, push * 0.8, 1.6, int(b.get("knocked_by", -1))):
				o.npc.say(["WHOA—", "Not again!", "OOF!", "Watch it!"][_rng.randi() % 4], 1.6)
				var by := int(b.get("knocked_by", -1))
				if status.has(by):
					_stat(by, "dominoes")
					_moment("domino", by)
					_log("DOMINO! %s took out %s!" % [str(b.npc.display_name).get_slice(" (", 0) if b.npc.display_name != "" else "A student", str(o.npc.display_name).get_slice(" (", 0) if o.npc.display_name != "" else "a student"])
		for id in ids:
			if int(id) != int(b.get("knocked_by", -1)) and (players[id] as Node3D).global_position.distance_to(at) < 0.9:
				_tumble(id, push * 0.7 + Vector3.UP * 1.5, 1.1, "was flattened by a falling %s" % b.npc.display_name)
	# Wet floors: sprint across one and you're on your back. So is a chasing teacher.
	for pd: Dictionary in world.puddles:
		var at: Vector3 = pd.p
		var r: float = pd.r
		for id in ids:
			var q: Node3D = players[id]
			var d := Vector2(q.global_position.x - at.x, q.global_position.z - at.z).length()
			if d < r and absf(q.global_position.y - at.y) < 1.0 and q.sprinting and float(q.net_speed) > SLIP_SPEED:
				var fwd := -q.global_transform.basis.z
				fwd.y = 0.0
				if _tumble(id, fwd.normalized() * 5.5 + Vector3.UP * 1.5, 1.3, "slipped on the wet floor"):
					_tell(id, "WET FLOOR!", Color("7fd0ea"))
		for b in _brains:
			var npc: Node = b.npc
			var d := Vector2(npc.global_position.x - at.x, npc.global_position.z - at.z).length()
			if d >= r or absf(npc.global_position.y - at.y) > 1.0 or float(npc.net_speed) < 3.2:
				continue
			if _knock(b, npc.forward() * 4.5, 1.8, int(pd.by)):
				npc.say(["WHOAAA—", "WHO LEFT THIS HERE?!", "My knee!", "SLIPPERY!"][_rng.randi() % 4], 1.8)
				if status.has(int(pd.by)):
					_stat(int(pd.by), "slips")
					_moment("slip_trap", int(pd.by))
				_log("%s slipped on the wet floor!" % str(npc.display_name).get_slice(" (", 0) if npc.display_name != "" else "A student slipped on the wet floor!")
	# Mr. Mendes mops as he goes.
	for b in _brains:
		if b.npc.name == "Peon" and b.state == "patrol" and now >= float(b.get("mop_at", MOP_EVERY)):
			b.mop_at = now + MOP_EVERY + _rng.randf_range(0.0, 10.0)
			_puddle(b.npc.global_position, 2.2, 50.0, -1, "water")
			b.npc.say(Lines.pick(_rng, "Peon", "mop"), 2.5)
	# Trolleys at speed flatten whoever they hit.
	for t in _trolleys:
		if not is_instance_valid(t) or t.speed() < 3.0:
			continue
		var at: Vector3 = t.global_position
		var push: Vector3 = t.roll * 0.9 + Vector3.UP * 1.5
		var by: int = t.last_pusher
		var hit := false
		for b in _brains:
			if b.npc.global_position.distance_to(at) < 1.0 and _knock(b, t.roll * 0.9, 2.0, by):
				b.npc.say(["OOF!", "A TROLLEY?!", "My SHINS!", "Who's driving that thing?!"][_rng.randi() % 4], 2.0)
				hit = true
				if status.has(by):
					_stat(by, "trolley_hits")
					_moment("trolley", by)
					_log("%s's trolley flattened %s!" % [_name(by), str(b.npc.display_name).get_slice(" (", 0) if b.npc.display_name != "" else "a student"])
		for id in ids:
			if int(id) != t.pusher and int(id) != t.rider and (players[id] as Node3D).global_position.distance_to(at) < 0.95:
				hit = _tumble(id, push, 1.3, "was run over by a trolley") or hit
		if hit:
			t.roll *= 0.6
	# Riders follow their trolley; a rider who gets chased or caught hops out.
	for t in _trolleys:
		if is_instance_valid(t) and t.rider != -1 and (not status.has(t.rider) or status[t.rider].state not in ["class", "chased"]):
			_off_trolley(t.rider)


## A ball flying fast enough knocks over whoever it hits.
func _ball_hits(ball: Node) -> void:
	if ball.holder != -1 or ball.linear_velocity.length() < 6.0 or elapsed < float(ball.get_meta("hit_cool", -1.0)):
		return
	var at: Vector3 = ball.global_position
	var push: Vector3 = ball.linear_velocity * 0.45
	push.y = 0.0
	for b in _brains:
		if (b.npc.global_position + Vector3(0, 1.0, 0)).distance_to(at) < 0.75 and _knock(b, push, 1.5, int(ball.last_thrower)):
			b.npc.say(["OW! My HEAD!", "Who threw that?!", "BASKETBALL?!"][_rng.randi() % 3], 1.8)
			ball.set_meta("hit_cool", elapsed + 0.8)
			ball.linear_velocity *= -0.3
			if status.has(int(ball.last_thrower)):
				_stat(int(ball.last_thrower), "ball_hits")
				_moment("ball_hit", int(ball.last_thrower))
				_log("%s beaned %s with a basketball!" % [_name(int(ball.last_thrower)), str(b.npc.display_name).get_slice(" (", 0) if b.npc.display_name != "" else "a student"])
			return
	for id in status:
		var q: Node3D = players_root.get_node_or_null(str(id))
		if q and int(id) != int(ball.last_thrower) and (q.global_position + Vector3(0, 1.0, 0)).distance_to(at) < 0.7:
			if _tumble(id, push + Vector3.UP * 1.5, 1.0, "was hit by a basketball"):
				ball.set_meta("hit_cool", elapsed + 0.8)
				ball.linear_velocity *= -0.3
				return


## Fire extinguisher: a cloud nobody (or no camera) can see through, a blast that knocks
## over whoever's in front, and a slippery floor for half a minute.
func _spray(id: int, p: Node3D) -> void:
	var fwd: Vector3 = -p.get_node("Head").global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at: Vector3 = p.global_position + fwd * 2.2
	(world.clouds as Array).append({"p": at, "r": 3.2, "until": elapsed + 9.0})
	_puddle(at, 2.4, 30.0, id, "foam")
	_fx_all("spray", p.global_position + Vector3(0, 1.2, 0), "%.2f,%.2f" % [fwd.x, fwd.z])
	for b in _brains:
		var to: Vector3 = b.npc.global_position - p.global_position
		if absf(to.y) > 1.2 or to.length() > 4.2 or fwd.dot(Vector3(to.x, 0, to.z).normalized()) < 0.6:
			continue
		if _knock(b, fwd * 5.0, 1.8, id) and b.role != "extra":
			b.npc.say(["*COUGH* I can't SEE!", "MY EYES!", "*cough cough* WHO DID THAT?!"][_rng.randi() % 3], 2.0)
	for other in status:
		var q: Node3D = players_root.get_node_or_null(str(other))
		if other == id or q == null:
			continue
		var to: Vector3 = q.global_position - p.global_position
		if absf(to.y) < 1.2 and to.length() < 3.8 and fwd.dot(Vector3(to.x, 0, to.z).normalized()) > 0.6:
			_tumble(other, fwd * 4.0 + Vector3.UP * 1.5, 0.9, "was blasted by %s's extinguisher" % _name(id))
	_noise(at, 9.0)
	_stat(id, "sprays")
	_moment("spray", id)
	_log("%s set off a fire extinguisher!" % _name(id))


## Throw a samosa: a staff member in front of you stops to eat it; a friend gets splatted.
func _throw_samosa(id: int, p: Node3D) -> bool:
	var fwd: Vector3 = -p.get_node("Head").global_transform.basis.z
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	var best := {}
	var best_d := 14.0
	for b in _brains:
		if b.role == "extra" or b.npc.name == "Uncle":
			continue
		var to: Vector3 = b.npc.global_position - p.global_position
		var d := Vector3(to.x, 0, to.z).length()
		if absf(to.y) < 1.5 and d < best_d and d > 0.5 and flat.dot(Vector3(to.x, 0, to.z) / d) > 0.85 and _within_reach(p, b.npc):
			best = b
			best_d = d
	if not best.is_empty():
		best.distracted_until = elapsed + 7.0
		best.npc.stop(best.npc.yaw_towards(p.global_position - best.npc.global_position))
		best.npc.say(["A flying SAMOSA?! ...Don't mind if I do. *munch*", "Is it raining samosas? *munch munch*", "Mmm. Evidence destroyed. *munch*"][_rng.randi() % 3], 3.5)
		if best.target != -1:
			_end_chase(best)
		_fx_all("samosa_arc", p.global_position + Vector3(0, 1.5, 0), "%.2f,%.2f,%.2f" % [best.npc.global_position.x, best.npc.global_position.y + 1.4, best.npc.global_position.z])
		_stat(id, "samosas")
		_moment("samosa_throw", id)
		_log("%s threw a samosa at %s. It worked." % [_name(id), best.npc.display_name.get_slice(" (", 0)])
		return true
	for other in status:
		var q: Node3D = players_root.get_node_or_null(str(other))
		if other == id or q == null or q.hidden:
			continue
		var to: Vector3 = q.global_position - p.global_position
		var d := Vector3(to.x, 0, to.z).length()
		if absf(to.y) < 1.5 and d < 12.0 and d > 0.4 and flat.dot(Vector3(to.x, 0, to.z) / d) > 0.9:
			_fx_all("samosa_arc", p.global_position + Vector3(0, 1.5, 0), "%.2f,%.2f,%.2f" % [q.global_position.x, q.global_position.y + 1.4, q.global_position.z])
			_fx.rpc_id(other, "splat", Vector3.ZERO, _name(id))
			_tell(other, "%s hit you in the face with a SAMOSA!" % _name(id), Color("e0a050"))
			_heard(other, 6.0)  # "HEY!"
			_stat(id, "samosas")
			_moment("samosa_splat", id, other)
			return true
	return false


## E on a trolley: grab it, let go of it (it rolls on), or (crouching) hop in.
func _on_trolley(id: int, p: Node3D, trolley_name: String) -> void:
	var t: Node = null
	for x in _trolleys:
		if is_instance_valid(x) and str(x.name) == trolley_name:
			t = x
	if t == null or p.global_position.distance_to(t.global_position) > 2.6:
		return
	if t.pusher == id:
		var fwd: Vector3 = -p.global_transform.basis.z
		fwd.y = 0.0
		t.release(fwd.normalized() * (float(p.net_speed) + 3.5))
		_fx_all("throw", t.global_position, "")
		return
	if t.rider == id:
		_off_trolley(id)
		return
	if p.crouching and t.rider == -1 and t.pusher != id:
		for x in _trolleys:
			if is_instance_valid(x) and x.rider == id:
				return
		t.rider = id
		p.ride.rpc_id(id, str(t.name))
		_tell(id, "You're in the trolley! Someone push. [Space] hop out.", Color("7fe0a0"))
		_moment("ride", id)
		return
	if t.pusher == -1:
		for x in _trolleys:
			if is_instance_valid(x) and x.pusher == id:
				x.release(Vector3.ZERO)
		t.grab(id)


func _off_trolley(id: int) -> void:
	for t in _trolleys:
		if is_instance_valid(t) and t.rider == id:
			t.rider = -1
			var p: Node = players_root.get_node_or_null(str(id))
			if p:
				p.ride.rpc_id(id, "")


static func _segment_hits_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r


# --- The public address system: the academy talks to everyone -----------------------------------

const PA_LINES := [
	"Students are reminded that fleeing through ventilation systems is not an approved extracurricular activity.",
	"The Department of Advanced Queueing reminds you: the queue for the queue starts at the queue.",
	"Lost property: one left shoe, one alibi, and a student's entire sense of direction.",
	"The Faculty of Theoretical Attendance confirms that you are, in theory, present.",
	"Today's canteen special: yesterday's samosas, at tomorrow's prices.",
	"Would the owner of the trolley on the assembly ground please stop driving it at staff.",
	"A reminder that the fire alarm is for fires. And for fire drills. And for nothing else. Mostly.",
	"Congratulations to the Chess Club, who have been in the same game since 1994.",
	"The library would like its silence back. Whoever took it, no questions asked.",
	"Students seen running in the corridors will be made to walk. Slowly. Forever.",
	"Reminder: the wet floor sign is a warning, not a challenge.",
	"The principal's car has been touched again. The principal knows. The principal always knows.",
	"The Bachelor of Unnecessary Science is now accepting applications. Nobody knows why.",
	"Lunch is cancelled. Lunch is uncancelled. Please stand by for further lunch updates.",
	"Mr. Mendes would like to know who keeps kicking over his bucket.",
	"Hall passes are not collectable trading cards. Please stop trading them.",
]
const PA_CAUGHT := ["Will %s please report to the principal's office. Immediately.", "%s to the principal's office, please. Bring an excuse.",
	"Attention: %s has been caught. Again. Let this be a lesson to the rest of you."]
const PA_HEAT := ["", "", "Staff are reminded to patrol the corridors. Students are reminded that they are being watched.",
	"Security is increased. The proctor and the vice principal are now walking the upper floors.",
	"LOCKDOWN. All gates are watched. All chai breaks are cancelled. Everyone: sit down."]
const PA_SPOTS := [["canteen", "Attention all staff: a parent is waiting for you at the canteen. A very angry parent."],
	["assembly", "Attention staff: free cake on the assembly ground. First come, first served."],
	["staffroom", "Emergency staff meeting in the staff room. Now. Bring biscuits."]]
var _pa_next := 70.0


func _announce(text: String) -> void:
	_fx_all("pa", Vector3.ZERO, text)
	print("[%.1f] PA: %s" % [elapsed, text])


func _pa_step() -> void:
	if elapsed < _pa_next:
		return
	_pa_next = elapsed + _rng.randf_range(80.0, 115.0)
	_announce(PA_LINES[_rng.randi() % PA_LINES.size()])


# --- Pranks and mission control --------------------------------------------------------------------

## Hold a friend's locker (or stall) shut for three seconds.
func _on_hold_door(id: int, p: Node3D, locker: int, friend: int) -> void:
	var q: Node3D = players_root.get_node_or_null(str(friend))
	if q == null or not q.hidden or locker < 0 or locker >= campus.lockers.size():
		return
	var spot: Dictionary = campus.lockers[locker]
	if (spot.pos as Vector3).distance_to(q.global_position) > 0.4 or p.global_position.distance_to(spot.out) > 2.2:
		return
	if not _cooldown(id, "hold_door", 8.0):
		return
	world.held[str(locker)] = elapsed + 3.0
	_tell(friend, "The door won't open! %s is holding it shut!" % _name(id), Color("ff9a4a"))
	_tell(id, "Holding %s in. Three seconds of pure evil." % _name(friend), Color("7fe0a0"))
	_stat(id, "pranks")
	_moment("hold_door", id, friend)
	_moment("held_in", friend, id)


## Escaped: a fake announcement pulls the staff to one place. Once a round each.
func _on_announce(id: int, k: int) -> void:
	var st: Dictionary = status[id]
	if st.state != "escaped":
		return
	if st.get("announced", false):
		_tell(id, "The office changed the PA password. Once was enough.", Color("ffb37a"))
		return
	var pick: Array = PA_SPOTS[clampi(k, 0, PA_SPOTS.size() - 1)]
	var spot: Vector3 = campus.assembly
	match str(pick[0]):
		"canteen":
			var i := _find_interactable("counter")
			if i != -1:
				spot = campus.interactables[i].pos
		"staffroom":
			var i := _find_interactable("bell")
			if i != -1:
				spot = campus.interactables[i].pos
	st.announced = true
	_announce(str(pick[1]))
	var came := 0
	for b in _brains:
		if b.role in ["teacher", "patrol", "gate"] and b.state != "chase" and b.npc.global_position.distance_to(spot) < 70.0 \
				and absf(b.npc.global_position.y - spot.y) < FLOOR_REACH * 2.0:
			b.resume = b.state
			b.state = "investigate"
			b.timer = 10.0
			b.npc.pose = 0
			b.npc.go_to(_path(b.npc.global_position, spot + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2))), b.walk * 1.6)
			b.distracted_until = elapsed + 4.0
			came += 1
	st.assists = int(st.assists) + 1
	_tell(id, "Announcement made. %d staff are on their way. +%d" % [came, ASSIST_POINTS], Color("7fe0a0"))
	_stat(id, "rescues")
	_moment("announce", id)


## Escaped: the service gate, opened remotely from the security office's phone line. Once a round.
func _on_remote_gate(id: int) -> void:
	var st: Dictionary = status[id]
	if st.state != "escaped":
		return
	if st.get("opened_gate", false):
		_tell(id, "They've changed the gate code.", Color("ffb37a"))
		return
	st.opened_gate = true
	_open_service_gate()
	st.assists = int(st.assists) + 1
	_log("%s opened the service gate from outside!" % _name(id))
	_tell(id, "Service gate open for %d s. Tell your friends! +%d" % [int(GATE_OPEN_TIME), ASSIST_POINTS], Color("7fe0a0"))
	_moment("gate", id)


## Escaped: call a friend inside. Their phone RINGS (staff nearby hear it), then the
## two of you can talk from anywhere for 40 s.
func _on_call(id: int, to: int) -> void:
	var q: Node3D = players_root.get_node_or_null(str(to))
	if q == null or not status.has(to) or status[to].state == "escaped" or to == id or status[id].state != "escaped":
		return
	if not _cooldown(id, "call", 60.0):
		_tell(id, "Your phone's cooling down. Try again in a bit.", Color("ffb37a"))
		return
	(world.calls as Array).append([id, to, elapsed + 40.0])
	_fx_all("ring", q.global_position, str(to))
	_heard(to, 7.0)  # *RING RING*
	_tell(to, "%s is calling! You can talk to them from anywhere for 40 s. (Staff heard your phone...)" % _name(id), Color("7fe0a0"))
	_tell(id, "Calling %s: you can talk for 40 s." % _name(to), Color("7fe0a0"))
	_moment("call", id, to)


# --- End of round: the class CCTV archive ------------------------------------------------------------

## The round's awards, from everyone's counters: [{"title", "name", "line"}], best first.
func _awards(rows: Array) -> Array:
	var stat := func(row: Dictionary, key: String) -> float:
		return float((_stats.get(str(row.name), {}) as Dictionary).get(key, 0.0))
	var best := func(score: Callable) -> Dictionary:
		var pick := {}
		var top := 0.0
		for row: Dictionary in rows:
			var v: float = score.call(row)
			if v > top:
				top = v
				pick = row
		return {"row": pick, "v": top}
	var out := []
	var add := func(title: String, found: Dictionary, line: String) -> void:
		if not (found.row as Dictionary).is_empty():
			out.append({"title": title, "name": str(found.row.name), "line": line % found.v})
	add.call("CLOSEST CALL", best.call(func(r): return stat.call(r, "max:close")), "hit %d%% suspicion and walked away")
	add.call("BIGGEST SNITCH", best.call(func(r): return stat.call(r, "snitched")), "blamed a friend %d time(s)")
	add.call("MOST WANTED", best.call(func(r): return stat.call(r, "max:chase")), "chased for %d seconds straight")
	add.call("CHAOS AGENT", best.call(func(r): return stat.call(r, "dominoes") + stat.call(r, "trolley_hits") + stat.call(r, "ball_hits") + stat.call(r, "slips")),
		"flattened staff %d time(s)")
	add.call("LOUDEST", best.call(func(r): return stat.call(r, "heard")), "heard by the staff %d time(s)")
	add.call("SMOOTH TALKER", best.call(func(r): return stat.call(r, "excuses")), "talked their way out %d time(s)")
	add.call("ACADEMIC WEAPON", best.call(func(r): return float(r.get("tests", 0))), "%d test points")
	add.call("GUARDIAN ANGEL", best.call(func(r): return stat.call(r, "rescues") + float(r.get("assists", 0))), "helped friends %d time(s)")
	add.call("MOST BETRAYED", best.call(func(r): return stat.call(r, "snitched_on")), "blamed by friends %d time(s)")
	add.call("STUNT DOUBLE", best.call(func(r): return stat.call(r, "tumbles")), "fell over %d time(s)")
	add.call("SAMOSA ENTHUSIAST", best.call(func(r): return stat.call(r, "samosas")), "%d samosa(s) eaten, bribed or thrown")
	var periods := maxi(1, int(world.periods))
	var skipper: Dictionary = best.call(func(r): return 100.0 - 100.0 * minf(1.0, stat.call(r, "present") / periods) if not bool(r.escaped) else 0.0)
	if float(skipper.v) >= 50.0:
		out.append({"title": "WORST ATTENDANCE", "name": str(skipper.row.name), "line": "attended %d%% of classes" % int(100.0 - float(skipper.v))})
	add.call("DETENTION REGULAR", best.call(func(r): return float(r.get("caught", 0))), "caught %d time(s)")
	return out.slice(0, 6)


# Replay: the host keeps the last few seconds of everyone's movement (10 times a
# second) and, whenever something clip-worthy happens, saves a clip around it. The
# best clip of the round plays on everyone's screen at the final bell.
const CLIP_WEIGHTS := {"snitch": 6, "domino": 6, "trolley": 6, "slip_trap": 5, "ball_hit": 5, "caught": 4, "spray": 4,
	"samosa_throw": 4, "samosa_splat": 4, "excuse_ok": 4, "close_call": 3, "shoved_friend": 3, "hold_door": 3, "lecture": 2}
const CLIP_TITLES := {"snitch": "%s SELLS OUT A FRIEND", "domino": "DOMINO!", "trolley": "THE TROLLEY OF DOOM", "slip_trap": "WET FLOOR STRIKES",
	"ball_hit": "NOTHING BUT FACE", "caught": "%s GETS CAUGHT", "spray": "THE EXTINGUISHER INCIDENT", "samosa_throw": "SAMOSA DIPLOMACY",
	"samosa_splat": "SAMOSA TO THE FACE", "excuse_ok": "THE EXCUSE THAT WORKED", "close_call": "THE CLOSEST CALL",
	"shoved_friend": "FRIENDLY FIRE", "hold_door": "LOCKED IN", "lecture": "THE LECTURE"}
const CLIP_BEFORE := 5.0
const CLIP_AFTER := 3.0
var _frames: Array = []       # [{"t", "e": {key: [x, y, z, yaw, flags]}}]
var _clip_events: Array = []  # [{"t", "fx": kind, "pos", "extra"}] or [{"t", "say": key, "text"}]
var _said := {}               # npc name -> what they were last saying (to spot new lines)
const CLIP_FX := ["spray", "books", "tumble", "samosa_arc", "splash", "whistle", "shout"]
var _frame_t := 0.0
var _clip_due: Array = []     # [{"at", "kind", "id", "other", "t", "focus", "w"}]
var _best_clip := {}


func _clip_record(players: Dictionary) -> void:
	if elapsed < _frame_t:
		return
	_frame_t = elapsed + 0.1
	var e := {}
	for id in players:
		var p: Node3D = players[id]
		var flags := (1 if p.crouching else 0) | (2 if p.tumbling else 0) | (4 if p.hidden else 0) | (8 if p.seated else 0)
		var pos := p.global_position
		e["p%d" % int(id)] = [pos.x, pos.y, pos.z, p.rotation.y, flags]
	for b in _brains:
		var npc: Node3D = b.npc
		if not is_instance_valid(npc):
			continue
		var pos := npc.global_position
		e[str(npc.name)] = [pos.x, pos.y, pos.z, npc.rotation.y, (2 if npc.stunned else 0) | (8 if npc.pose == 1 else 0) | (16 if npc.alert == 2 else 0)]
		var line := str(npc.speech)
		if line != str(_said.get(npc.name, "")):
			_said[npc.name] = line
			if line != "":
				_clip_events.append({"t": elapsed, "say": str(npc.name), "text": line})
	_frames.append({"t": elapsed, "e": e})
	while not _frames.is_empty() and float(_frames[0].t) < elapsed - CLIP_BEFORE - CLIP_AFTER - 1.0:
		_frames.pop_front()
	while not _clip_events.is_empty() and float(_clip_events[0].t) < elapsed - CLIP_BEFORE - CLIP_AFTER - 1.0:
		_clip_events.pop_front()
	for k in range(_clip_due.size() - 1, -1, -1):
		if elapsed >= float(_clip_due[k].at):
			_clip_save(_clip_due[k])
			_clip_due.remove_at(k)


func _clip_moment(kind: String, id: int, other: int) -> void:
	if not CLIP_WEIGHTS.has(kind) or round_over:
		return
	var w := int(CLIP_WEIGHTS[kind])
	if w < int(_best_clip.get("w", 0)) or (w == int(_best_clip.get("w", 0)) and elapsed - float(_best_clip.get("t", 0.0)) < 30.0):
		return  # we already have a better (or as good and recent) one
	var p: Node3D = players_root.get_node_or_null(str(id))
	if p == null:
		return
	var title := str(CLIP_TITLES[kind])
	if "%s" in title:
		title = title % _name(id).to_upper()
	_clip_due.append({"at": elapsed + CLIP_AFTER, "kind": kind, "id": id, "other": other, "t": elapsed, "focus": p.global_position, "w": w, "title": title})


## Keep the frames around a moment: only who was within 22 m of it.
func _clip_save(due: Dictionary) -> void:
	var focus: Vector3 = due.focus
	var keys := {}
	var frames := []
	for f: Dictionary in _frames:
		if float(f.t) < float(due.t) - CLIP_BEFORE:
			continue
		frames.append(f)
		for key in f.e:
			var v: Array = f.e[key]
			if Vector3(v[0], v[1], v[2]).distance_to(focus) < 22.0:
				keys[key] = true
	if frames.size() < 10:
		return
	var order: Array = keys.keys()
	var packed := []
	for f: Dictionary in frames:
		var row := PackedFloat32Array()
		row.append(float(f.t) - float(due.t))
		for key in order:
			var v: Array = f.e.get(key, [])
			if v.is_empty():
				row.append_array(PackedFloat32Array([0, -999, 0, 0, 0]))
			else:
				row.append_array(PackedFloat32Array([v[0], v[1], v[2], v[3], v[4]]))
		packed.append(row)
	var events := []
	for ev: Dictionary in _clip_events:
		if float(ev.t) >= float(due.t) - CLIP_BEFORE and (not ev.has("say") or keys.has(ev.say)) 				and (not ev.has("pos") or (ev.pos as Vector3).distance_to(focus) < 25.0):
			var copy := ev.duplicate()
			copy.t = float(ev.t) - float(due.t)
			events.append(copy)
	_best_clip = {"w": due.w, "t": due.t, "title": due.title, "focus": focus, "keys": order, "frames": packed,
		"when": elapsed, "kind": due.kind, "subject": "p%d" % int(due.id), "events": events}


## The clip to show at the final bell, with what everyone in it looks like.
func _clip_final() -> Dictionary:
	for due: Dictionary in _clip_due:
		_clip_save(due)  # something happened in the last seconds: keep it anyway
	_clip_due.clear()
	if _best_clip.is_empty():
		return {}
	var looks := {}
	var names := {}
	for key: String in _best_clip.keys:
		if key.begins_with("p"):
			var id := int(key.substr(1))
			var info: Dictionary = Network.players.get(id, {})
			looks[key] = P.apply_prefs(P.make_look(id, int(info.get("classroom", 0))), info.get("look", {}))
			names[key] = str(info.get("name", ""))
		else:
			var b := _brain_by_name(key)
			if not b.is_empty():
				looks[key] = b.look
				names[key] = str(b.npc.display_name).get_slice(" (", 0)
	var out: Dictionary = _best_clip.duplicate()
	out.looks = looks
	out.names = names
	print("[replay] %s: %d frames, %d people" % [out.title, (out.frames as Array).size(), (out.keys as Array).size()])
	return out


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
	_update_heat(false)
	if float(world.party_at) > 0.0 and elapsed >= float(world.party_at):
		world.party_at = -1.0
		_start_party()
	var alarm_on: bool = elapsed < float(world.alarm_until) or elapsed < float(world.party_until)
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
	if _event() != "power_cut":
		_cctv_step(delta, players)
	_update_balls()
	_uncle_chatter(players)
	_pa_step()
	_clip_record(players)
	_coin_step(players)
	_voice_step(delta)
	_chaos_step(players, delta)
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
	var race_over: bool = float(world.race_end_at) > 0.0 and elapsed >= float(world.race_end_at)
	if elapsed >= round_time or all_done or race_over:
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
			_style_step(id, p, st, delta)
			if p.global_position.y < -0.9:
				_washed_back(id, p)
			elif campus.escaped(p.global_position):
				st.state = "escaped"
				st.time = elapsed
				st.sus = 0.0
				st.seen = false
				st.grabbed = false
				_tell(id, "You're OUT! Phone > HELP OUT: text friends answers, prank-call staff, send money.", Color("7fe0a0"))
				_fx.rpc_id(id, "win", Vector3.ZERO, "")
				_log("%s ESCAPED the university!" % _name(id))
				_moment("escaped", id)
				for b in _brains:
					if b.target == id:
						_end_chase(b)
				if str(_rules.get("mode", "")) == "race" and int(world.race_winner) == -1:
					world.race_winner = id
					world.race_end_at = elapsed + 4.0
					_log("%s WINS THE RACE!" % _name(id))
					_fx_all("bell", Vector3.ZERO, "")


## Close calls, silent walks and time unseen (all only while out of class, not during the bell).
func _style_step(id: int, p: Node3D, st: Dictionary, delta: float) -> void:
	var pos := p.global_position
	var moved := Vector2(pos.x - st.last_pos.x, pos.z - st.last_pos.z).length() if st.last_pos != Vector3.ZERO else 0.0
	st.last_pos = pos
	# CLOSE CALL: suspicion over 80, then out of sight for 1.5 s without a chase.
	if st.seen:
		st.calm_t = 0.0
		if float(st.sus) >= 80.0 and st.state == "class":
			st.peak = true
			st.peak_sus = maxf(float(st.get("peak_sus", 0.0)), float(st.sus))
	elif st.peak:
		st.calm_t = float(st.calm_t) + delta
		if st.calm_t >= 1.5:
			st.peak = false
			if st.state == "class":
				_style(id, "close_call")
				_stat(id, "max:close", float(st.get("peak_sus", 80.0)))
				_moment("close_call", id)
			st.peak_sus = 0.0
	var out: bool = st.state == "class" and campus.room_of(pos) != current_room(id) and elapsed > float(world.passing_until) \
			and elapsed > float(st.pass_until)
	if out and not st.seen and not p.hidden:
		st.unseen_run = float(st.unseen_run) + delta
		st.longest_unseen = maxf(float(st.longest_unseen), float(st.unseen_run))
		st.silent_m = float(st.silent_m) + minf(moved, 1.0)
		if st.silent_m >= Rules.SILENT_METRES:
			st.silent_m = 0.0
			_style(id, "silent")
	else:
		st.unseen_run = 0.0
		if st.seen:
			st.silent_m = 0.0
	# Opening quest: answered the register this period, and now out of the room.
	if int(st.present_period) == int(world.period) and out:
		_complete(id, "slip")


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
		score += int(st.get("assists", 0)) * ASSIST_POINTS
		score += int(st.style)
		if st.chain:
			score += Rules.CHAIN_BONUS
		var speedy: bool = _rule() == "speed" and st.state == "escaped" and float(st.time) <= Rules.DAILY_SPEED
		if speedy:
			score += 300
		var won: bool = int(world.race_winner) == id
		if won:
			score += Rules.RACE_WIN_BONUS
		st.score = score
		list.append({"id": id, "name": _name(id), "score": score, "escaped": st.state == "escaped", "time": st.time,
			"quests": done, "caught": st.caught, "spotted": st.spotted, "tests": int(st.get("exam_total", 0)), "assists": int(st.get("assists", 0)),
			"cash": int(st.cash), "style": int(st.style), "warnings": int(st.warnings),
			"chain": bool(st.chain), "speedy": speedy, "won": won, "closest": float(st.closest), "closest_who": str(st.closest_who),
			"longest_unseen": float(st.longest_unseen), "best_distraction": int(st.best_distraction), "class_bonus": false})
	# Class mode: everyone out (2+ players) = +50% for everyone.
	var everyone := list.size() >= 2 and str(_rules.get("mode", "class")) == "class"
	for row in list:
		everyone = everyone and bool(row.escaped)
	if everyone:
		for row in list:
			row.score = int(round(int(row.score) * (1.0 + Rules.CLASS_ESCAPE_BONUS)))
			row.class_bonus = true
		_log("THE WHOLE CLASS ESCAPED! +50% for everyone!")
	list.sort_custom(func(a, b): return a.score > b.score)
	results = list
	for b in _brains:
		b.npc.stop(b.npc.rotation.y)
		b.npc.alert = 0
	awards = _awards(list)
	replay = _clip_final()
	_fx_all("bell", Vector3.ZERO, "end")
	_log("The final bell rang!")
	_report_moments()
	if OS.get_cmdline_user_args().has("--quit-at-end"):  # dev/CI: stop once the round is over
		get_tree().create_timer(1.0).timeout.connect(get_tree().quit)


## Dev report: how often something happened to each player, and the longest stretch
## where nothing did (the thing to design away: 30 s of nothing is 30 s of boredom).
func _report_moments() -> void:
	for id in status:
		var times: Array = [0.0]
		for m: Dictionary in _moments:
			if int(m.id) == int(id):
				times.append(float(m.t))
		times.append(elapsed)
		var longest := 0.0
		var quiet := 0
		for k in range(1, times.size()):
			var gap: float = float(times[k]) - float(times[k - 1])
			longest = maxf(longest, gap)
			if gap > 45.0:
				quiet += 1
		print("[moments] %s: %d moments in %ds, longest quiet stretch %ds, %d quiet stretches over 45 s" 				% [_name(id), times.size() - 2, int(elapsed), int(longest), quiet])


## Heat: time, catches and fire alarms make the school stricter. New patrols come on duty.
func _update_heat(quiet: bool) -> void:
	var floor_heat := 2 if _event() == "inspection" else 1
	var heat := Rules.heat_for(elapsed / maxf(1.0, round_time), int(world.heat_bumps), floor_heat)
	if _fresh():
		heat = mini(heat, 2)
	if OS.get_cmdline_user_args().has("--heat4"):  # dev
		heat = 4
	if heat > int(world.heat) or quiet:
		var rose: bool = heat > int(world.heat)
		world.heat = heat
		if rose and not quiet:
			_log(Rules.HEAT_NAMES[heat].to_upper())
			_fx_all("heat", Vector3.ZERO, str(heat))
			_announce(PA_HEAT[clampi(heat, 1, 4)])
	for k in range(_pending_staff.size() - 1, -1, -1):
		if int(_pending_staff[k][0]) <= int(world.heat):
			(_pending_staff[k][1] as Callable).call()
			_pending_staff.remove_at(k)


## Escaped: ring the bell at the gate. The nearest staff come out to see who it is,
## away from wherever they were watching.
func _on_outside_bell(id: int, p: Node3D) -> void:
	if not _cooldown(id, "outside_bell", 40.0):
		_tell(id, "They're already coming to look. Wait a bit.", Color("ffb37a"))
		return
	var near: Array = []
	for b in _brains:
		if b.role in ["gate", "patrol", "teacher"] and b.state != "chase":
			near.append(b)
	near.sort_custom(func(a, c): return a.npc.global_position.distance_to(p.global_position) < c.npc.global_position.distance_to(p.global_position))
	var spot: Vector3 = p.global_position
	var came := 0
	for b in near.slice(0, 3):
		b.resume = b.state
		b.state = "investigate"
		b.timer = 6.0
		b.npc.alert = 1
		b.npc.pose = 0
		b.npc.say("Who's ringing at this hour?!", 2.0)
		b.npc.go_to(_path(b.npc.global_position, spot), b.walk * 1.4)
		b.distracted_until = elapsed + 3.0
		came += 1
	_fx_all("office_bell", spot, "")
	status[id].assists = int(status[id].assists) + 1
	_tell(id, "Ding-dong! %d staff are coming out to the gate. +%d" % [came, ASSIST_POINTS], Color("7fe0a0"))
	_log("%s rang the bell at the gate!" % _name(id))


## Rain: grounds staff see less far. Everyone else as usual.
func _range(b: Dictionary) -> float:
	return float(b.range) * (0.6 if _event() == "rain" and b.get("outdoor", false) else 1.0)


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
	if b.has("report_on"):
		_report_step(b)
		return  # running to tell a teacher
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
			if not _suspicious(id, p, b) or not _can_see(npc, p, _range(b), b.fov):
				continue
			st.seen = true
			st.watch_pos = npc.global_position
			var dist: float = npc.global_position.distance_to(p.global_position)
			var rate: float = 34.0 * b.alertness * clampf(1.25 - dist / b.range, 0.3, 1.25) * (0.6 if p.crouching else 1.0)
			if b.role == "teacher" and b.room == current_room(id):
				rate *= 1.0 + 0.6 * int(st.strikes)  # an angry teacher misses nothing
			if b.get("likes_marks", false) and _average_mark(id) >= 70.0:
				rate *= 0.55  # Ms. Okafor forgives a lot from a good student
			if dist < 4.0:
				rate *= 2.5  # right under their nose
			if b.state == "evacuate":
				rate *= 0.5  # chatting at the assembly point
			if _in_crowd(p):
				rate *= 0.45
			if int(world.heat) >= 4:
				rate *= 1.3  # lockdown: everyone's on edge
			st.sus = minf(100.0, st.sus + rate * delta)
			if st.sus > spotted_sus:
				spotted_sus = st.sus
				spotted = id
	if spotted != -1:
		npc.alert = 1
		if spotted_sus >= 100.0 and status[spotted].state != "chased":
			if b.chaser:
				_start_chase(b, spotted, players[spotted].global_position)
			elif b.get("tells", false):
				_start_report(b, spotted)
			else:
				npc.say(["THIEF! Somebody catch them!", "Shhh! PRINCIPAL MA'AM!"][0 if npc.name == "Uncle" else 1], 2.5)
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
		var ears: float = NOISE_RADIUS * (1.6 if npc.name == "Librarian" else 1.0) * (1.5 if _event() == "rain" else 1.0)
		for id in players:
			var p: Node3D = players[id]
			var heard: float = ears
			if p.sprinting and status[id].state in ["class", "chased"] \
					and p.global_position.distance_to(npc.global_position) < heard \
					and absf(p.global_position.y - npc.global_position.y) < FLOOR_REACH:
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
				if elapsed < float(b.get("lecture_until", -1.0)) and int(b.t / 3.0) != int((b.t - delta) / 3.0):
					b.lecture_i = int(b.get("lecture_i", 0)) + 1
					npc.say(LECTURE[int(b.lecture_i) % LECTURE.size()], 3.0)
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
			_stat(id, "present")
			_log("%s answered attendance for %s!" % [_name(b.proxied_by), _name(id)])
			_moment("proxy", int(b.proxied_by), id)
			_style(int(b.proxied_by), "proxy")
			_complete(int(b.proxied_by), "proxy")
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
		_stat(next, "present")
		rooms[b.room].called.append(next)
		st.present_period = int(world.period)
		_pay(next, 5, "for being present")
	else:
		npc.say("%s?  ...%s?" % [_name(next), _name(next)], 2.0)
		b.waiting = next
		b.proxied = false
		b.timer = 2.2  # window for a friend to answer (R)
		for other in players:
			if other != next and status[other].state == "class" and campus.room_of(players[other].global_position) == b.room:
				_fx.rpc_id(other, "hint_proxy", Vector3.ZERO, _name(next))


func _gate_guard(b: Dictionary, delta: float) -> void:
	var npc: Node = b.npc
	if not npc.is_idle():
		return
	b.timer -= delta
	match b.state:
		"post":
			npc.holding = false
			npc.stop(float(b.home_yaw) + sin(b.t * 0.7) * 0.9)
			if b.timer <= 0.0 and int(world.heat) >= 4:
				b.timer = 10.0  # lockdown: no chai breaks
			elif b.timer <= 0.0:
				b.state = "break"
				b.timer = 8.0
				npc.stop(float(b.home_yaw) + PI / 2.0)
				npc.holding = true
				npc.say(Lines.pick(_rng, "Guard", "break"), 3.0)
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


## A student's average test mark so far this round (0 before their first test).
func _average_mark(id: int) -> float:
	var st: Dictionary = status.get(id, {})
	return float(st.get("exam_total", 0)) / float(st.get("exams", 0)) if int(st.get("exams", 0)) > 0 else 0.0


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
			var sharp: bool = int(world.heat) >= 3  # heat 3+: cameras see further and react faster
			if not _can_see_from(cam.pos, fwd, p, 20.0 if sharp else 16.0, 55.0, float(cam.get("floor", 0.0))):
				continue
			st.seen = true
			st.watch_pos = cam.pos
			st.sus = minf(100.0, st.sus + 22.0 * delta * (0.45 if _in_crowd(p) else 1.0) * (1.6 if sharp else 1.0))
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
	status[id].chase_from = elapsed
	_moment("spotted", id)
	status[id].peak = false
	b.min_dist = 99.0
	b.npc.alert = 2
	b.npc.pose = 0
	b.npc.holding = false
	b.npc.say(Lines.pick(_rng, str(b.npc.name), "spot", _name(id)), 2.5)
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
	if b.has("leash") and npc.global_position.distance_to(b.home) > float(b.leash):
		# Mr. Tanaka doesn't do corridors.
		npc.say("Hmph. Not worth leaving my class for. I KNOW your face, %s." % _name(id), 3.0)
		st.sus = 70.0
		_end_chase(b)
		return
	var seen := _can_see(npc, p, b.range * 1.4, 200.0)
	var dist: float = npc.global_position.distance_to(p.global_position)
	b.min_dist = minf(float(b.get("min_dist", 99.0)), dist)
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
		npc.say(Lines.pick(_rng, str(npc.name), "lost", _name(id)), 2.0)
		_log("%s escaped %s." % [_name(id), npc.display_name])
		if float(b.min_dist) < float(st.closest):
			st.closest = float(b.min_dist)
			st.closest_who = str(npc.display_name).get_slice(" (", 0)
		_end_chase(b)
		_style(id, "shake_off")
		_moment("shook_off", id)
		return
	# Catching takes a moment: the student is grabbed and can shove free.
	if dist < CATCH_DIST and (not p.hidden or b.saw_hide) and (p.hidden or _within_reach(p, npc)):
		if float(b.get("grab_until", -1.0)) < 0.0:
			b.grab_until = elapsed + GRAB_TIME
			st.grabbed = true
			if _can_question(b, id, p):
				_question(b, id)
			else:
				npc.say("Got you now—!", 1.2)
				_tell(id, "GRABBED!  Left-click to SHOVE free!", Color("ff6a6a"))
		elif elapsed >= float(b.grab_until):
			if not (st.get("question", {}) as Dictionary).is_empty():
				_catch(b, id, "No answer? Principal's office. NOW.")
			else:
				_catch(b, id)
			return
	elif float(b.get("grab_until", -1.0)) >= 0.0 and dist > 2.2:
		b.grab_until = -1.0
		st.grabbed = false
		st.question = {}
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
		status[id].question = {}
		var ran: float = elapsed - float(status[id].get("chase_from", elapsed))
		if ran > 0.0 and status[id].state == "chased":
			_stat(id, "chase", ran)
			_stat(id, "max:chase", ran)
		status[id].chase_from = elapsed
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
	_off_trolley(id)
	var st: Dictionary = status[id]
	st.question = {}
	st.catches = int(st.catches) + 1
	st.peak = false
	world.heat_bumps = int(world.heat_bumps) + 1
	if Rules.warning_only(Network.current_map, int(st.catches)):
		# First Day, first catch: a telling-off and back to your seat.
		st.warnings = int(st.warnings) + 1
		st.state = "class"
		st.grabbed = false
		st.sus = 40.0
		b.npc.say("This is your WARNING, %s. Back to your seat. Next time: detention." % _name(id), 3.5)
		_tell(id, "Let off with a WARNING. Next catch means detention!", Color("ffb37a"))
		_fx.rpc_id(id, "caught", Vector3.ZERO, "")
		_log("%s got a warning from %s." % [_name(id), b.npc.display_name])
		_teleport(id, st.seat, 0.0)
		_end_chase(b)
		return
	st.state = "detention"
	st.caught += 1
	_moment("caught", id)
	# Short at first, longer every time (see Rules.DETENTION); shoving staff makes it worse.
	st.timer = minf(Rules.detention_time(Network.current_map, int(st.catches)) + 8.0 * st.shoves, 90.0)
	_tell(id, "DETENTION: %d s." % int(st.timer), Color("ff6a6a"))
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
	b.npc.say(reason if reason != "" else Lines.pick(_rng, str(b.npc.name), "catch", _name(id)), 3.0)
	_announce(PA_CAUGHT[_rng.randi() % PA_CAUGHT.size()] % _name(id))
	_fx.rpc_id(id, "caught", Vector3.ZERO, "")
	_log("%s was caught by %s! Detention." % [_name(id), b.npc.display_name])
	_teleport(id, campus.detention_spot, 0.0)
	_end_chase(b)


# --- Excuses: you get a few seconds to talk your way out -------------------------------------------

const QUESTION_TIME := 4.0
const QUESTION_LINES := ["Why are you outside your class, %s?", "And where do YOU think you're going, %s?",
	"%s. Explain yourself. Now.", "Out of class again, %s? One good reason."]
## id -> [what you say, how often it works (before the staff member's own gullibility)]
const EXCUSES := {
	"pass": ["I've got a hall pass, look!", 1.0],
	"note": ["Medical emergency! Here's my note.", 0.9],
	"book": ["Just returning this library book.", 0.75],
	"washroom": ["Just coming back from the washroom!", 0.5],
	"sent": ["%s sent me to fetch something.", 0.45],
	"lost": ["I'm new! I'm looking for %s.", 0.35],
	"snitch": ["It was %s! They made me do it!", 1.0],
}
const EXCUSE_OK := {
	"pass": "Fine. Walk. Don't run.", "note": "Hmm... get well soon, then. Go.", "book": "The library's that way. Quickly!",
	"washroom": "Washroom. Right. Straight back to class.", "sent": "Hmph. Tell them to fetch it themselves next time.",
	"lost": "Lost? ...Your class is THAT way. Go.",
}
const EXCUSE_NO := {
	"pass": "That pass is expired. Nice try.", "note": "That's YOUR handwriting.", "book": "That book's due in 2031. Nice try.",
	"washroom": "The washroom is the OTHER way.", "sent": "Funny. I just saw them in the staff room.",
	"lost": "Lost? Since September?",
}


## Can this staff member stop and question the student they just grabbed?
func _can_question(b: Dictionary, id: int, p: Node3D) -> bool:
	if p.hidden or b.saw_hide or b.role == "extra":
		return false
	return not (b.get("remember", {}) as Dictionary).has(id)


## "Why are you outside your class?" A few seconds to pick an excuse (or shove and run).
func _question(b: Dictionary, id: int) -> void:
	var st: Dictionary = status[id]
	b.grab_until = elapsed + QUESTION_TIME
	var npc: Node = b.npc
	npc.stop(npc.yaw_towards(players_root.get_node(str(id)).global_position - npc.global_position))
	npc.say(QUESTION_LINES[_rng.randi() % QUESTION_LINES.size()] % _name(id), QUESTION_TIME)
	var picks := _excuse_options(b, id)
	var texts := []
	for e: Array in picks:
		texts.append(e[1])
	st.question = {"by": str(npc.name), "who": str(npc.display_name).get_slice(" (", 0), "until": elapsed + QUESTION_TIME,
		"ids": picks.map(func(e): return e[0]), "texts": texts, "friends": picks.map(func(e): return e[2])}
	_moment("questioned", id)
	print("[%.1f] %s questions %s: %s" % [elapsed, npc.display_name, _name(id), str(st.question.ids)])


## [[id, text, friend id or -1], ...]: up to four excuses that make sense right now.
func _excuse_options(b: Dictionary, id: int) -> Array:
	var st: Dictionary = status[id]
	var items: Array = st.items
	var out := []
	if items.has("hall_pass") or elapsed < float(st.pass_until):
		out.append(["pass", EXCUSES.pass[0], -1])
	if items.has("medical_note"):
		out.append(["note", EXCUSES.note[0], -1])
	if items.has("library_book"):
		out.append(["book", EXCUSES.book[0], -1])
	# A friend close by to blame.
	var p: Node3D = players_root.get_node(str(id))
	var blame := -1
	var best := 30.0
	for other in status:
		var q: Node3D = players_root.get_node_or_null(str(other))
		if other == id or q == null or q.hidden or status[other].state not in ["class", "chased"]:
			continue
		var d: float = q.global_position.distance_to(p.global_position)
		if d < best:
			best = d
			blame = other
	var talk := []
	talk.append(["washroom", EXCUSES.washroom[0], -1])
	var boss := "Dr. Haddad" if b.npc.name != "VP" else "Ms. Okafor"
	talk.append(["sent", EXCUSES.sent[0] % boss, -1])
	var room_name: String = Network.CLASSROOMS[current_room(id)]
	talk.append(["lost", EXCUSES.lost[0] % ("the " + room_name if room_name == "Lab" else room_name), -1])
	talk.shuffle()
	var room := 3 if blame != -1 else 4
	while out.size() < room and not talk.is_empty():
		out.append(talk.pop_front())
	if blame != -1:
		out.append(["snitch", EXCUSES.snitch[0] % _name(blame), blame])
	return out.slice(0, 4)


## The student picked excuse `k` (index into their question's options).
func _on_excuse(id: int, p: Node3D, k: int) -> void:
	var st: Dictionary = status[id]
	var q: Dictionary = st.get("question", {})
	if q.is_empty() or elapsed > float(q.until) or k < 0 or k >= (q.ids as Array).size():
		return
	var b := _brain_by_name(str(q.by))
	if b.is_empty() or b.target != id:
		st.question = {}
		return
	var kind: String = q.ids[k]
	var text: String = q.texts[k]
	st.question = {}
	_fx_all("shout", p.global_position, "%d|%s" % [id, text])  # everyone close by hears your excuse
	var npc: Node = b.npc
	if kind == "snitch":
		_snitch(b, id, int(q.friends[k]))
		return
	var heard: Dictionary = b.get_or_add("heard", {})
	var used: Array = heard.get_or_add(id, [])
	var told: Dictionary = st.get_or_add("excuses_used", {})
	var chance: float = float(EXCUSES[kind][1]) * float(b.get("gullible", 1.0))
	if kind in ["pass", "note", "book"]:
		chance = maxf(chance, float(EXCUSES[kind][1]) * 0.8)  # proof in hand beats a strict teacher
	if kind == "washroom" and _near_kind(p.global_position, "toilet", 15.0):
		chance += 0.3
	if kind == "sent" and not _nearest_brain(p.global_position, 20.0, ["patrol"]).is_empty() and b.npc.name != "VP":
		chance *= 0.3  # the person you named is right there
	if kind == "lost" and Network.current_map == 0:
		chance += 0.25  # First Day: everyone's a little lost
	if _in_gate_zone(p.global_position) or b.get("outdoor", false):
		chance *= 0.5  # at the gate, covered in mud...
	if int(told.get(kind, 0)) >= 2:
		chance *= 0.4  # staff talk to each other: they've heard that one today
	if elapsed < float(st.get("vouched_until", -1.0)):
		chance += 0.3
	var repeat: bool = used.has(kind)
	used.append(kind)
	told[kind] = int(told.get(kind, 0)) + 1
	if repeat or _rng.randf() > chance:
		npc.say(("You used that one already, %s." % _name(id)) if repeat else str(EXCUSE_NO.get(kind, "Nice try.")), 3.0)
		_moment("excuse_fail", id)
		_log("%s tried \"%s\" on %s. It did NOT work." % [_name(id), text, npc.display_name])
		_catch(b, id, "Principal's office. NOW.")
		return
	# It worked.
	var items: Array = st.items
	if kind == "pass" and elapsed >= float(st.pass_until):
		items.erase("hall_pass")
	elif kind == "note":
		items.erase("medical_note")
	npc.say(str(EXCUSE_OK.get(kind, "Fine. Go.")), 3.0)
	if b.get("remembers", false):
		(b.get_or_add("remember", {}) as Dictionary)[id] = true
		_tell(id, "%s believed you. She won't a second time." % npc.display_name, Color("ffb37a"))
	_let_go(b, id, 20.0)
	_stat(id, "excuses")
	_moment("excuse_ok", id)
	_log("%s talked their way out of %s: \"%s\"" % [_name(id), npc.display_name, text])


## Blame a friend: you walk, they're in trouble.
func _snitch(b: Dictionary, id: int, friend: int) -> void:
	var npc: Node = b.npc
	var q: Node3D = players_root.get_node_or_null(str(friend))
	_let_go(b, id, 15.0)
	status[id].sus = 50.0
	_stat(id, "snitched")
	_moment("snitch", id, friend)
	if q == null or not status.has(friend) or status[friend].state not in ["class", "chased"]:
		npc.say("Whoever that is, I'll find them.", 2.5)
		return
	_stat(friend, "snitched_on")
	_moment("snitched_on", friend, id)
	_log("%s told %s it was %s!" % [_name(id), npc.display_name, _name(friend)])
	_tell(friend, "%s TOLD %s IT WAS YOU!" % [_name(id).to_upper(), str(npc.display_name).get_slice(" (", 0).to_upper()], Color("ff6a6a"))
	var ft: Dictionary = status[friend]
	if b.chaser and ft.state == "class" and _can_see(npc, q, b.range * 1.3, 220.0):
		npc.say("YOU! %s! Get back here!" % _name(friend), 2.5)
		ft.sus = 100.0
		_start_chase(b, friend, q.global_position)
	else:
		npc.say("%s, is it? I'll remember that name." % _name(friend), 2.5)
		ft.sus = maxf(float(ft.sus), 85.0)
		ft.strikes = mini(3, int(ft.strikes) + 1)


## Released after a good excuse: a few seconds to walk back without being hunted.
func _let_go(b: Dictionary, id: int, walk: float) -> void:
	var st: Dictionary = status[id]
	_end_chase(b)
	st.state = "class"
	st.grabbed = false
	st.sus = 35.0
	st.pass_until = maxf(float(st.pass_until), elapsed + walk)
	b.distracted_until = elapsed + 2.5


## A friend next to someone being questioned: "They're with me!" Their excuse
## becomes more believable, and now the staff have noticed you too.
func _on_vouch(id: int, p: Node3D, friend: int) -> void:
	var q: Node3D = players_root.get_node_or_null(str(friend))
	if q == null or friend == id or not status.has(friend) or q.global_position.distance_to(p.global_position) > 3.0:
		return
	var ft: Dictionary = status[friend]
	if (ft.get("question", {}) as Dictionary).is_empty() or elapsed < float(ft.get("vouched_until", -1.0)):
		return
	ft.vouched_until = float(ft.question.until) + 0.5
	status[id].sus = minf(99.0, float(status[id].sus) + 30.0)
	_fx_all("shout", p.global_position, "%d|%s" % [id, ["They're with me!", "It's true, I saw it!", "Sir, ma'am, I can explain!"][_rng.randi() % 3]])
	_tell(friend, "%s is vouching for you! Your excuse just got better." % _name(id), Color("7fe0a0"))
	_moment("vouch", id, friend)


func _near_kind(pos: Vector3, kind: String, radius: float) -> bool:
	for it: Dictionary in campus.interactables:
		if it.kind == kind and (it.pos as Vector3).distance_to(pos) < radius:
			return true
	return false


# --- Detention rescue: friends outside can get you out early -----------------------------------------

const BAIL_PRICE := 40
const OFFICE_COOLDOWN := 60.0


## Out of detention early (a friend's doing, or the fire alarm).
func _release(id: int, why: String) -> void:
	var st: Dictionary = status.get(id, {})
	if st.is_empty() or st.state != "detention":
		return
	st.timer = 0.0  # _update_player lets them out this tick, with the walk-back grace
	_tell(id, why, Color("7fe0a0"))


## Help Out: ring the principal's office. They step out to take the call: half the
## time left for everyone in detention.
func _on_call_office(id: int, to: int) -> void:
	if status[id].state != "escaped":
		return
	if not status.has(to) or status[to].state != "detention":
		_tell(id, "Nobody's in detention right now.", Color("ffb37a"))
		return
	if not _cooldown(id, "office", OFFICE_COOLDOWN):
		_tell(id, "The office stopped picking up. Try again in a bit.", Color("ffb37a"))
		return
	for other in status:
		if status[other].state == "detention":
			status[other].timer = maxf(2.0, float(status[other].timer) * 0.5)
			_tell(other, "The principal went to take a phone call (%s). Half your detention's gone!" % _name(id), Color("7fe0a0"))
	status[id].assists = int(status[id].assists) + 1
	_tell(id, "You called the principal's office. Detention halved! +%d" % ASSIST_POINTS, Color("7fe0a0"))
	_stat(id, "rescues")
	_moment("rescue", id, to)
	_moment("rescued", to, id)


# --- The prefect doesn't chase: she runs off to tell your teacher --------------------------------------

const REPORT_TIME := 9.0


func _start_report(b: Dictionary, id: int) -> void:
	if b.has("report_on"):
		return
	var teacher := _brain_of_room(current_room(id))
	var who: String = str(teacher.npc.display_name) if not teacher.is_empty() else "the principal"
	b.report_on = id
	b.report_until = elapsed + REPORT_TIME
	b.npc.say("I'm TELLING %s!" % who.to_upper(), 3.0)
	b.npc.alert = 2
	if not teacher.is_empty():
		b.npc.go_to(_path(b.npc.global_position, teacher.npc.global_position), 3.6)
	_tell(id, "%s is running to tell %s! Stop her (shove) or get back to class!" % [b.npc.display_name.get_slice(" (", 0), who], Color("ff9a4a"))
	_moment("reported", id)


func _stop_report(b: Dictionary) -> void:
	var id: int = int(b.report_on)
	b.erase("report_on")
	b.npc.alert = 0
	b.npc.say("Ow! FINE. I didn't see anything.", 2.5)
	b.state = "return"
	_resume(b)
	if status.has(id):
		_tell(id, "Report stopped. She won't be telling anyone.", Color("7fe0a0"))


func _report_step(b: Dictionary) -> void:
	if not b.has("report_on") or elapsed < float(b.report_until):
		return
	var id: int = int(b.report_on)
	b.erase("report_on")
	b.npc.alert = 0
	b.state = "return"
	_resume(b)
	if not status.has(id) or status[id].state != "class":
		return
	var st: Dictionary = status[id]
	st.strikes = mini(3, int(st.strikes) + 1)
	st.sus = 90.0
	b.npc.say("There. I told on you. Enjoy detention!", 2.5)
	_log("%s told on %s!" % [b.npc.display_name.get_slice(" (", 0), _name(id)])
	_call_help(id, players_root.get_node(str(id)).global_position, b.npc.display_name)


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
	return _can_see_from(npc.eye_position(), npc.forward(), p, view_range, fov_deg, npc.global_position.y)


## `floor_y`: height of the floor the watcher stands on (see FLOOR_REACH).
func _can_see_from(eye: Vector3, fwd: Vector3, p: Node3D, view_range: float, fov_deg: float, floor_y: float) -> bool:
	if p.hidden or absf(p.global_position.y - floor_y) > FLOOR_REACH:
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
	for c: Dictionary in world.clouds:
		if float(c.until) > elapsed and _segment_hits_sphere(eye, target, (c.p as Vector3) + Vector3(0, 1.1, 0), float(c.r)):
			return false  # extinguisher smoke
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
