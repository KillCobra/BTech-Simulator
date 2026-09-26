extends SceneTree
## Dev tool: finds props that float. Builds every map with box recording on,
## joins boxes that touch into groups, and reports small groups that touch
## nothing that holds them up (a floor, wall, table...).
## Run: godot --headless --path . -s scripts/prop_audit.gd [-- --map=N]

const Voxel := preload("res://scripts/voxel.gd")
const CampusBuilder := preload("res://scenes/world/campus_builder.gd")
const Maps := preload("res://scenes/world/maps/maps.gd")
const EPS := 0.035
const CELL := 2.0

var _parent: PackedInt32Array


func _init() -> void:
	var only := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			only = int(arg.trim_prefix("--map="))
	for id in Maps.LIST.size():
		if only != -1 and id != only:
			continue
		_audit(id)
	quit()


func _audit(id: int) -> void:
	Voxel.recorded = []
	Voxel.recording = true
	var root := Node3D.new()
	get_root().add_child(root)
	var campus := CampusBuilder.new()
	campus.build(root, id)
	Voxel.recording = false
	var boxes: Array = Voxel.recorded
	var n := boxes.size()
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	lo.resize(n)
	hi.resize(n)
	for i in n:
		var half: Vector3 = (boxes[i][1] as Vector3).abs() * 0.5
		lo[i] = boxes[i][0] - half
		hi[i] = boxes[i][0] + half
	# Spatial grid (xz) of box indices.
	var grid := {}
	for i in n:
		for gx in range(floori(lo[i].x / CELL), floori(hi[i].x / CELL) + 1):
			for gz in range(floori(lo[i].z / CELL), floori(hi[i].z / CELL) + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				grid[key].append(i)
	_parent = PackedInt32Array()
	_parent.resize(n)
	for i in n:
		_parent[i] = i
	for key in grid:
		var cell: PackedInt32Array = grid[key]
		for a in cell.size():
			var i := cell[a]
			for b in range(a + 1, cell.size()):
				var j := cell[b]
				if _touch(lo[i], hi[i], lo[j], hi[j]):
					_union(i, j)
	# Groups: anchored if any box is big (structure) or reaches the ground.
	var groups := {}
	for i in n:
		var r := _find(i)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(i)
	var floating := []
	for r in groups:
		var members: Array = groups[r]
		var anchored := false
		var glo := Vector3.INF
		var ghi := -Vector3.INF
		for i in members:
			var size: Vector3 = hi[i] - lo[i]
			if size.x > 4.0 or size.z > 4.0 or lo[i].y <= 0.06:
				anchored = true
				break
			glo = glo.min(lo[i])
			ghi = ghi.max(hi[i])
		if anchored:
			continue
		floating.append([glo, ghi, members])
	print("=== map %d (%s): %d boxes, %d groups, %d floating" % [id, Maps.title(id), n, groups.size(), floating.size()])
	# One line per kind of floating thing (same size and colours), with what it nearly touches.
	var kinds := {}
	for f in floating:
		var cols := {}
		for i in f[2]:
			cols[(boxes[i][2] as Color).to_html(false)] = true
		var size: Vector3 = (f[1] - f[0]).snapped(Vector3.ONE * 0.01)
		var sig := "%s %s" % [size, ",".join(cols.keys())]
		if kinds.has(sig):
			kinds[sig][0] += 1
			continue
		var near := _nearest(f[0], f[1], f[2], lo, hi, boxes)
		kinds[sig] = [1, f, near]
	for sig in kinds:
		var k: Array = kinds[sig]
		var f: Array = k[1]
		print("  %3dx %s  e.g. at %s  gap below %.2f  nearest: %s" % [k[0], sig, ((f[0] + f[1]) / 2.0).snapped(Vector3.ONE * 0.01),
			_gap_below(f[0], f[1], lo, hi), k[2]])
	root.queue_free()


## Distance down to the nearest box top under this group's footprint (-1: none).
func _gap_below(glo: Vector3, ghi: Vector3, lo: PackedVector3Array, hi: PackedVector3Array) -> float:
	var best := INF
	for i in lo.size():
		if hi[i].y <= glo.y + 0.001 and lo[i].x < ghi.x and hi[i].x > glo.x and lo[i].z < ghi.z and hi[i].z > glo.z:
			best = minf(best, glo.y - hi[i].y)
	return best if best < INF else glo.y


## The closest other box: how far, which way, its size and colour.
func _nearest(glo: Vector3, ghi: Vector3, members: Array, lo: PackedVector3Array, hi: PackedVector3Array, boxes: Array) -> String:
	var best := INF
	var best_i := -1
	var gap := Vector3.ZERO
	for i in lo.size():
		if members.has(i):
			continue
		var d := Vector3(maxf(0.0, maxf(lo[i].x - ghi.x, glo.x - hi[i].x)), maxf(0.0, maxf(lo[i].y - ghi.y, glo.y - hi[i].y)),
			maxf(0.0, maxf(lo[i].z - ghi.z, glo.z - hi[i].z)))
		if d.length() < best:
			best = d.length()
			best_i = i
			gap = Vector3(signf(boxes[i][0].x - (glo.x + ghi.x) / 2.0) * d.x, signf(boxes[i][0].y - (glo.y + ghi.y) / 2.0) * d.y,
				signf(boxes[i][0].z - (glo.z + ghi.z) / 2.0) * d.z)
	if best_i == -1:
		return "none"
	return "%.2f away %s  (%s %s)" % [best, gap.snapped(Vector3.ONE * 0.01), (hi[best_i] - lo[best_i]).snapped(Vector3.ONE * 0.01), (boxes[best_i][2] as Color).to_html(false)]


func _touch(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3) -> bool:
	return alo.x <= bhi.x + EPS and ahi.x >= blo.x - EPS and alo.y <= bhi.y + EPS and ahi.y >= blo.y - EPS \
			and alo.z <= bhi.z + EPS and ahi.z >= blo.z - EPS


func _find(i: int) -> int:
	while _parent[i] != i:
		_parent[i] = _parent[_parent[i]]
		i = _parent[i]
	return i


func _union(a: int, b: int) -> void:
	var ra := _find(a)
	var rb := _find(b)
	if ra != rb:
		_parent[ra] = rb
