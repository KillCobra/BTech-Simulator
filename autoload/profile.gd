extends Node
## Your progress, saved on this PC (user://profile.cfg): XP and rank, stars and
## best escape times per map, the Rs you've saved up, cosmetics you've bought and
## the daily challenge. Registered as the `Profile` autoload. Each player keeps
## their own; the host's profile decides which maps can be picked in the lobby.

signal changed

const PATH := "user://profile.cfg"
const TEST_PATH := "user://profile_test.cfg"  # dev/test runs (any command-line args) never touch the real one
const Rules := preload("res://scripts/rules.gd")
const MAP_COUNT := 5

## Rank titles: [first level with this title, title, name-tag style it unlocks].
const RANKS := [
	[1, "Fresher", ""],
	[3, "Backbencher", "rank_blue"],
	[6, "Proxy King", "rank_green"],
	[10, "Canteen Legend", "rank_purple"],
	[15, "Bunk Master", "rank_gold"],
]

## Cosmetics bought with saved-up Rs: "pref:value" -> [label, price]. Everything
## else in the character creator (colours, hair, the classic uniform...) is free.
const COSMETICS := {
	"hat:1": ["Cap", 60], "hat:2": ["Beanie", 80], "hat:3": ["Headband", 50],
	"glasses_style:3": ["Shades", 120],
	"bag_style:1": ["Sling bag", 40],
	"uniform:sweater": ["Sweater vest", 100], "uniform:sports": ["Sports tracksuit", 120],
	"uniform:blazer": ["Blazer", 150], "uniform:kurta": ["Kurta", 150], "uniform:labcoat": ["Lab coat", 200],
	"tag:gold": ["Gold name tag", 100], "tag:neon": ["Neon name tag", 150], "tag:fire": ["Fire name tag", 250],
}
## Name-tag styles: id -> [label, text colour, outline colour].
const TAGS := {
	"": ["Plain", Color(1, 1, 1, 0.9), Color(0, 0, 0, 1)],
	"rank_blue": ["Backbencher blue", Color("9fd8ff"), Color("1a3a5a")],
	"rank_green": ["Proxy King green", Color("7fe0a0"), Color("1a4a2a")],
	"rank_purple": ["Canteen Legend purple", Color("d6a8ff"), Color("3a1a5a")],
	"rank_gold": ["Bunk Master gold", Color("ffd24a"), Color("5a3a00")],
	"gold": ["Gold", Color("ffc93c"), Color("2a1a0e")],
	"neon": ["Neon", Color("5ff5ff"), Color("0a2a6a")],
	"fire": ["Fire", Color("ffb040"), Color("b0200a")],
}

var xp := 0
var bank := 0              # Rs saved up across rounds (spent on cosmetics)
var rounds := 0
var escapes := 0
var maps := {}             # map id -> {"stars": [escaped, all quests, never caught], "best": seconds or -1}
var owned: Array = []      # cosmetic ids bought
var daily_done := 0        # date (YYYYMMDD) of the last daily challenge you finished
var last_summary := {}     # what the last round gave you, for the results screen


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var cfg := ConfigFile.new()
	var fresh := cfg.load(_path()) != OK
	xp = int(cfg.get_value("profile", "xp", 0))
	bank = int(cfg.get_value("profile", "bank", 0))
	rounds = int(cfg.get_value("profile", "rounds", 0))
	escapes = int(cfg.get_value("profile", "escapes", 0))
	daily_done = int(cfg.get_value("profile", "daily_done", 0))
	owned = cfg.get_value("profile", "owned", [])
	maps = {}
	for id in MAP_COUNT:
		var m: Variant = cfg.get_value("maps", str(id), {})
		var stars: Array = (m as Dictionary).get("stars", [false, false, false]) if m is Dictionary else [false, false, false]
		maps[id] = {"stars": stars, "best": float((m as Dictionary).get("best", -1.0)) if m is Dictionary else -1.0}
	if fresh:
		_grandfather_look()
		save()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "xp", xp)
	cfg.set_value("profile", "bank", bank)
	cfg.set_value("profile", "rounds", rounds)
	cfg.set_value("profile", "escapes", escapes)
	cfg.set_value("profile", "daily_done", daily_done)
	cfg.set_value("profile", "owned", owned)
	for id in maps:
		cfg.set_value("maps", str(id), maps[id])
	cfg.save(_path())
	changed.emit()


static func _path() -> String:
	if OS.get_cmdline_user_args().has("--fresh-profile"):
		return "user://profile_fresh_%d.cfg" % OS.get_process_id()
	return TEST_PATH if not OS.get_cmdline_user_args().is_empty() else PATH


## Players from before the shop existed keep whatever they were already wearing.
func _grandfather_look() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://look.cfg") != OK:
		return
	for key in cfg.get_section_keys("look"):
		var id := "%s:%s" % [key, str(cfg.get_value("look", key))]
		if COSMETICS.has(id) and not owned.has(id):
			owned.append(id)


# --- Levels and ranks ----------------------------------------------------------------------------

## XP needed to go from `level` to `level + 1`.
static func xp_for(level: int) -> int:
	return 300 + 150 * (level - 1)


## [level, xp into this level, xp needed for the next].
static func level_of(total: int) -> Array:
	var level := 1
	var left := total
	while left >= xp_for(level):
		left -= xp_for(level)
		level += 1
	return [level, left, xp_for(level)]


static func rank_for(level: int) -> Array:
	var best: Array = RANKS[0]
	for r: Array in RANKS:
		if level >= int(r[0]):
			best = r
	return best


func level() -> int:
	return int(level_of(xp)[0])


func rank_title() -> String:
	return str(rank_for(level())[1])


## The next rank: [level, title] or [] at the top.
func next_rank() -> Array:
	for r: Array in RANKS:
		if int(r[0]) > level():
			return r
	return []


# --- Maps ------------------------------------------------------------------------------------------

## Maps open in order: escape one to open the next (or reach level 3 x map number).
func map_unlocked(id: int) -> bool:
	if id <= 0:
		return true
	return bool((maps[id - 1].stars as Array)[0]) or level() >= 3 * id


func stars(id: int) -> Array:
	return maps.get(id, {"stars": [false, false, false]}).stars


func star_count(id: int) -> int:
	var n := 0
	for s in stars(id):
		if s:
			n += 1
	return n


func best_time(id: int) -> float:
	return float(maps.get(id, {"best": -1.0}).best)


# --- Cosmetics ---------------------------------------------------------------------------------------

func is_free(id: String) -> bool:
	return not COSMETICS.has(id) and not id.begins_with("tag:rank_")


func owns(id: String) -> bool:
	if id.begins_with("tag:rank_"):
		for r: Array in RANKS:
			if "tag:" + str(r[2]) == id:
				return level() >= int(r[0])
		return false
	return is_free(id) or owned.has(id)


func price(id: String) -> int:
	return int(COSMETICS[id][1]) if COSMETICS.has(id) else 0


## Spend saved-up Rs on a cosmetic. Returns "" or why not.
func buy(id: String) -> String:
	if owns(id):
		return ""
	if not COSMETICS.has(id):
		return "Earn it by ranking up."
	if bank < price(id):
		return "Not enough saved up: Rs %d of Rs %d." % [bank, price(id)]
	bank -= price(id)
	owned.append(id)
	save()
	return ""


# --- After a round ---------------------------------------------------------------------------------

## Our row of the results (see Director._end_round) -> XP, stars, best time, bank.
## Returns a summary for the results screen.
func apply_round(row: Dictionary, map_id: int, rules: Dictionary) -> Dictionary:
	var before := level_of(xp)
	var old_rank := rank_title()
	var was_open := []
	for id in MAP_COUNT:
		if map_unlocked(id):
			was_open.append(id)
	var sum := {"xp": 0, "lines": [], "new_stars": [], "record": false, "bank": 0, "map": map_id}
	var score := int(row.get("score", 0))
	var gain := maxi(25, score / 3)
	sum.lines.append(["Round score %d" % score, gain])
	var m: Dictionary = maps.get(map_id, {"stars": [false, false, false], "best": -1.0})
	var got := [bool(row.get("escaped", false)), int(row.get("quests", 0)) >= 3,
		bool(row.get("escaped", false)) and int(row.get("caught", 0)) == 0]
	var star_names := ["Escaped", "All quests done", "Escaped without being caught"]
	for k in 3:
		if got[k] and not bool(m.stars[k]):
			m.stars[k] = true
			sum.new_stars.append(k)
			sum.lines.append(["NEW STAR: %s" % star_names[k], 100])
			gain += 100
	if row.get("escaped", false):
		escapes += 1
		var t := float(row.get("time", 0.0))
		if float(m.best) < 0.0 or t < float(m.best):
			sum.record = float(m.best) >= 0.0
			m.best = t
	maps[map_id] = m
	if rules.get("daily", false) and row.get("escaped", false) and daily_done != int(rules.get("date", 0)):
		daily_done = int(rules.get("date", 0))
		gain += Rules.DAILY_XP
		bank += Rules.DAILY_RS
		sum.lines.append(["DAILY CHALLENGE done (+Rs %d)" % Rules.DAILY_RS, Rules.DAILY_XP])
	var saved := maxi(0, int(row.get("cash", 0)))
	bank += saved
	sum.bank = saved
	rounds += 1
	xp += gain
	sum.xp = gain
	sum.before = before
	sum.after = level_of(xp)
	sum.rank_up = rank_title() if rank_title() != old_rank else ""
	sum.unlocked = []
	for id in MAP_COUNT:
		if map_unlocked(id) and not was_open.has(id):
			sum.unlocked.append(id)
	save()
	last_summary = sum
	return sum


## What to chase next, for the results screen and the lobby.
func next_goal() -> String:
	for id in range(1, MAP_COUNT):
		if not map_unlocked(id):
			var names := ["First Day", "Grand Campus", "Whispering Pines", "Lagoon Island", "Downtown Campus"]
			return "Escape %s to unlock %s" % [names[id - 1], names[id]]
	var nr := next_rank()
	if not nr.is_empty():
		return "Reach level %d to become %s" % [int(nr[0]), str(nr[1])]
	return "Collect all 15 stars"
