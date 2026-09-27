extends SceneTree
## Voice codec check: `godot --headless --path . -s scripts/voice_codec_test.gd`.
## Encodes a sweep and speech-like noise with scripts/adpcm.gd, decodes it
## and prints the signal-to-noise ratio (fails below 20 dB) and the packet size.

func _init() -> void:
	var codec := preload("res://scripts/adpcm.gd")
	var frame_len := 320
	var rate := 16000.0
	var worst := 999.0
	for kind in ["sweep", "buzz", "quiet"]:
		var frame := PackedFloat32Array()
		frame.resize(frame_len)
		for i in frame.size():
			var t := i / rate
			match kind:
				"sweep": frame[i] = 0.4 * sin(TAU * (200.0 + 2300.0 * t * 25.0) * t)  # 200 Hz -> 2.5 kHz
				"buzz": frame[i] = 0.3 * sin(TAU * 180.0 * t) + 0.1 * sin(TAU * 900.0 * t) + randf_range(-0.03, 0.03)
				"quiet": frame[i] = 0.02 * sin(TAU * 300.0 * t)
		var packet: PackedByteArray = codec.encode(frame, 0.1, 7)
		var back: PackedFloat32Array = codec.decode(packet)
		var sig := 0.0
		var err := 0.0
		for i in frame.size():
			sig += frame[i] * frame[i]
			err += pow(frame[i] - back[i], 2.0)
		var snr := 10.0 * log(sig / maxf(err, 1e-12)) / log(10.0)
		worst = minf(worst, snr)
		print("[voice] %s: %d bytes per 20 ms, SNR %.1f dB" % [kind, packet.size(), snr])
	print("[voice] %s" % ("OK" if worst >= 20.0 else "FAIL: codec too noisy"))
	quit(0 if worst >= 20.0 else 1)
