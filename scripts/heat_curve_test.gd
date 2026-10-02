extends SceneTree
## Heat pacing check: `godot --headless --path . -s scripts/heat_curve_test.gd`.
## Pins Rules.heat_for: the clock sets the level (25% / 55% / 80% of the round), two separate bits of
## trouble add one level, never more, it never goes down as the round goes on, and lockdown never
## comes before 55% of the round. Prints "[heat] OK" or "[heat] FAIL".

const Rules := preload("res://scripts/rules.gd")


func _init() -> void:
	var ok := true
	# By the clock alone: exactly at the thresholds.
	var clock := [[0.0, 1], [0.24, 1], [0.25, 2], [0.54, 2], [0.55, 3], [0.79, 3], [0.80, 4], [1.0, 4]]
	for c in clock:
		var got: int = Rules.heat_for(float(c[0]), 0, 1)
		if got != int(c[1]):
			print("[heat] FAIL: at %.2f of the round heat should be %d, got %d" % [float(c[0]), int(c[1]), got])
			ok = false
	# Trouble: one event changes nothing, two add one level, a pile-up of more adds nothing more.
	for k in 101:
		var f := k / 100.0
		var base: int = Rules.heat_for(f, 0, 1)
		if Rules.heat_for(f, 1, 1) != base:
			print("[heat] FAIL: one bit of trouble changed the heat at %.2f" % f)
			ok = false
		var plus := mini(base + 1, 4)
		for trouble in range(2, 9):
			if Rules.heat_for(f, trouble, 1) != plus:
				print("[heat] FAIL: %d troubles at %.2f should be heat %d, got %d" % [trouble, f, plus, Rules.heat_for(f, trouble, 1)])
				ok = false
	# Never cools as the round goes on, and lockdown is never before 55%.
	for trouble in range(0, 9):
		var prev := 0
		for k in 101:
			var f := k / 100.0
			var h: int = Rules.heat_for(f, trouble, 1)
			if h < prev:
				print("[heat] FAIL: heat fell from %d to %d at %.2f with %d troubles" % [prev, h, f, trouble])
				ok = false
			if h >= 4 and f < 0.55:
				print("[heat] FAIL: lockdown at %.2f of the round with %d troubles" % [f, trouble])
				ok = false
			prev = h
	# The very start with a lot of trouble is heat 2 at most (it used to be lockdown at 0:00).
	if Rules.heat_for(0.0, 8, 1) != 2:
		print("[heat] FAIL: lots of trouble at the start should be heat 2, got %d" % Rules.heat_for(0.0, 8, 1))
		ok = false
	# The inspection event sets a floor.
	if Rules.heat_for(0.0, 0, 2) != 2 or Rules.heat_for(0.9, 0, 2) != 4:
		print("[heat] FAIL: the heat floor is not respected")
		ok = false
	# When each level arrives by the clock alone.
	for minutes in [5, 8, 12]:
		var secs: float = float(minutes) * 60.0
		var line: String = "[heat] %2d min round, heat 2/3/4 at" % minutes
		for at in Rules.HEAT_AT:
			var t: float = secs * float(at)
			line += " %d:%02d" % [floori(t / 60.0), int(t) % 60]
		print(line)
	print("[heat] %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
