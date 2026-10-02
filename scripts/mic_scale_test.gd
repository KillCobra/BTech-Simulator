extends SceneTree
## Mic scale check: `godot --headless --path . -s scripts/mic_scale_test.gd`.
## The mic sensitivity slider (1-10), the dB meter and AUTO-SET all share the helpers on Settings:
## every step must round-trip to the stored gate, and the gate must stay inside what Settings accepts.

func _init() -> void:
	var s: Node = preload("res://autoload/settings.gd").new()  # never added to the tree: no _ready, no apply()
	var ok := true
	for k in range(1, 11):
		var g: float = s.gate_for_sensitivity(float(k))
		var back: float = s.sensitivity_for_gate(g)
		var fine: bool = absf(back - k) < 0.01 and g >= 0.0019 and g <= 0.08
		if not fine:
			print("[mic] step %d: gate %.5f maps back to %.3f" % [k, g, back])
		ok = ok and fine
	var old_default: float = s.sensitivity_for_gate(0.012)  # the old default gate shows as 5.6, which the slider snaps to 6
	ok = ok and absf(old_default - 5.6) < 0.1
	ok = ok and float(s.mic_meter(0.0)) == 0.0 and float(s.mic_meter(1.0)) == 1.0
	ok = ok and float(s.mic_meter(s.gate_for_sensitivity(10.0))) < float(s.mic_meter(s.gate_for_sensitivity(1.0)))  # the white line moves right as sensitivity drops
	s.free()
	print("[mic] %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
