extends RefCounted
## IMA ADPCM voice frames, 4 bits a sample (Voice autoload). A packet is
## [seq lo, seq hi, loudness (RMS x 1000), predictor (s16), step index] + the codes,
## two per byte. Every packet carries its own decoder state, so a lost one only
## costs its own 20 ms.

const HEADER := 6

const STEPS := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
	73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
	598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
	3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
	18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX_STEP := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]


static func encode(frame: PackedFloat32Array, rms: float, seq: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER + frame.size() / 2)
	out[0] = seq & 0xff
	out[1] = (seq >> 8) & 0xff
	out[2] = clampi(int(rms * 1000.0), 0, 255)
	var pred := clampi(int(frame[0] * 32767.0), -32768, 32767)
	# Start the step size where this frame's signal is (loud, fast frames need big steps).
	var swing := 0.0
	for i in range(1, mini(17, frame.size())):
		swing += absf(frame[i] - frame[i - 1])
	swing = swing / 16.0 * 32767.0
	var index := 0
	while index < 88 and STEPS[index] < swing:
		index += 1
	out.encode_s16(3, pred)
	out[5] = index
	for i in frame.size():
		var x := clampi(int(frame[i] * 32767.0), -32768, 32767)
		var step: int = STEPS[index]
		var diff := x - pred
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var delta := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			delta += step
		if diff >= step >> 1:
			code |= 2
			diff -= step >> 1
			delta += step >> 1
		if diff >= step >> 2:
			code |= 1
			delta += step >> 2
		pred = clampi(pred - delta if code & 8 else pred + delta, -32768, 32767)
		index = clampi(index + INDEX_STEP[code], 0, 88)
		var at := HEADER + (i >> 1)
		if i & 1:
			out[at] = out[at] | (code << 4)
		else:
			out[at] = code
	return out


static func decode(packet: PackedByteArray) -> PackedFloat32Array:
	var n := (packet.size() - HEADER) * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var pred := packet.decode_s16(3)
	var index := clampi(packet[5], 0, 88)
	for i in n:
		var byte: int = packet[HEADER + (i >> 1)]
		var code := (byte >> 4) & 15 if i & 1 else byte & 15
		var step: int = STEPS[index]
		var delta := step >> 3
		if code & 4:
			delta += step
		if code & 2:
			delta += step >> 1
		if code & 1:
			delta += step >> 2
		pred = clampi(pred - delta if code & 8 else pred + delta, -32768, 32767)
		index = clampi(index + INDEX_STEP[code], 0, 88)
		out[i] = pred / 32768.0
	return out
