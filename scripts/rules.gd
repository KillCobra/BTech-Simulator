extends RefCounted
## Round rules shared by the host (Director) and every client (HUD, lobby):
## round events, the daily challenge, the detention ladder, heat levels, the
## quest chain and each map's special mechanic. Everything here is data or a
## pure function, so all peers agree on it.

# --- Detention ---------------------------------------------------------------------------------

## Seconds in detention for the 1st, 2nd, 3rd and 4th+ catch in a round.
const DETENTION := [8.0, 15.0, 25.0, 35.0]
## Per map (index = map id): First Day is gentle, Downtown is harsh. The very first
## catch on First Day is only a warning.
const DETENTION_SCALE := [0.5, 1.0, 1.0, 1.0, 1.2]
const LINE_SECONDS := 5.0       # each detention line takes this much off...
const LINE_SECONDS_LATE := 3.0  # ...but only this much from the 4th catch on


static func detention_time(map_id: int, catch_no: int) -> float:
	var base: float = DETENTION[clampi(catch_no - 1, 0, DETENTION.size() - 1)]
	return snappedf(base * float(DETENTION_SCALE[clampi(map_id, 0, DETENTION_SCALE.size() - 1)]), 1.0)


static func warning_only(map_id: int, catch_no: int) -> bool:
	return map_id == 0 and catch_no == 1


# --- Heat: the school gets stricter as the round goes on -------------------------------------------

const HEAT_NAMES := ["", "Heat 1: teachers only", "Heat 2: the prefect and caretaker are patrolling",
	"Heat 3: CCTV sharper, the proctor and vice principal walk the upper floors",
	"Heat 4: LOCKDOWN. Every guard is on duty, no more chai breaks"]
## Which patrols come on duty at which heat (by NPC id). Map grounds staff are always on.
const HEAT_STAFF := {"Peon": 2, "Prefect": 2, "Proctor": 3, "VP": 3}


## Heat from how far into the round we are, plus bumps (catches, fire alarms).
static func heat_for(fraction: float, bumps: int, floor_heat: int) -> int:
	var by_time := 1 + int(clampf(fraction, 0.0, 0.999) / 0.25)
	return clampi(maxi(by_time + bumps, floor_heat), 1, 4)


# --- Quest chain -----------------------------------------------------------------------------------

## Step 1 is always the opening quest; step 2 is picked from TIER_2 (plus a co-op quest
## when friends are playing); step 3 is a risky one. Finishing all three earns a gate pass.
const OPENING := "slip"
const TIER_2 := ["notice", "hoop", "samosa", "library", "bell", "register"]
const TIER_2_COOP := ["boost", "proxy"]
const TIER_3 := ["exam", "selfie"]
const CHAIN_PASS := 40.0   # seconds of gate pass for finishing the chain
const CHAIN_BONUS := 200   # score for finishing the chain


# --- Style: close calls ---------------------------------------------------------------------------

const STYLE := {
	"close_call": ["CLOSE CALL", 50],
	"silent": ["SILENT", 30],
	"proxy": ["PROXY", 20],
	"shake_off": ["SHOOK THEM OFF", 60],
	"quest": ["QUEST", 25],
}
const SILENT_METRES := 25.0  # walked this far outside class without being seen = SILENT
const CLASS_ESCAPE_BONUS := 0.5  # everyone out (2+ players, class mode): +50% score
const RACE_WIN_BONUS := 300


# --- Round events -----------------------------------------------------------------------------------

const EVENTS := {
	"inspection": ["SURPRISE INSPECTION", "The whole staff is on patrol from the first bell (starts at Heat 2)."],
	"birthday": ["PRINCIPAL'S BIRTHDAY", "Halfway through, the staff gather at the canteen for cake. Go!"],
	"rain": ["RAIN", "Fewer eyes outside, but wet shoes squeak: sprinting is heard from further away."],
	"power_cut": ["POWER CUT", "The CCTV is off and the corridors are dark."],
	"exam_week": ["EXAM WEEK", "Tests come sooner in every period, and every mark counts double."],
}
const EVENT_CHANCE := 0.6


static func random_event(rng: RandomNumberGenerator) -> String:
	if rng.randf() > EVENT_CHANCE:
		return ""
	var keys := EVENTS.keys()
	return keys[rng.randi() % keys.size()]


static func event_name(id: String) -> String:
	return str(EVENTS[id][0]) if EVENTS.has(id) else ""


static func event_about(id: String) -> String:
	return str(EVENTS[id][1]) if EVENTS.has(id) else ""


# --- Daily challenge ----------------------------------------------------------------------------------

const DAILY_RULES := {
	"no_pass": "No hall passes today: the canteen is out and the teachers won't sign any.",
	"broke": "You start with Rs 0. Find coins to buy anything.",
	"speed": "Escape before 3:00 for the speed bonus.",
}
const DAILY_SPEED := 180.0
const DAILY_XP := 300
const DAILY_RS := 100


## Today's date as YYYYMMDD (local time).
static func today() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


## The same challenge for everyone on a given date: map, event and one extra rule.
static func daily(date: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bunk-master-daily-%d" % date)
	var rules := DAILY_RULES.keys()
	var events := EVENTS.keys()
	var map_id := rng.randi() % 5
	var rule: String = rules[rng.randi() % rules.size()]
	var event: String = events[rng.randi() % events.size()]
	return {"map": map_id, "rule": rule, "event": event, "date": date}


static func daily_text(d: Dictionary) -> String:
	var maps := ["First Day", "Grand Campus", "Whispering Pines", "Lagoon Island", "Downtown Campus"]
	return "%s  ·  %s\n%s" % [maps[clampi(int(d.map), 0, 4)], event_name(str(d.event)), str(DAILY_RULES.get(str(d.rule), ""))]


# --- Maps: what each one teaches -------------------------------------------------------------------

const MAP_TIPS := [
	"FIRST DAY: learn the basics. Answer the register, wait for the teacher to turn to the board, then slip out.",
	"GRAND CAMPUS: three floors joined in a ring. Watch the CCTV in the corridors and use the stairs to lose a chaser.",
	"WHISPERING PINES: a river splits the grounds. Cross by the ranger's bridge, the rope bridge or the stepping stones.",
	"LAGOON ISLAND: three ways off: the long bridge past the toll guards, the ferry at the east pier, or hop the rocks to a fishing boat.",
	"DOWNTOWN CAMPUS: classes up to the 5th floor, a long way down. Then a checkpoint, the metro, or the torn fence in the north alley (crouch).",
]


static func map_tip(map_id: int) -> String:
	return MAP_TIPS[clampi(map_id, 0, MAP_TIPS.size() - 1)]
