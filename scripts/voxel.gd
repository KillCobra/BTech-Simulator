extends RefCounted
## Merges many coloured boxes into one ArrayMesh (one draw call per builder).
## UV stores the position on each face in metres and UV2 the face size, which
## voxel.gdshader uses to draw soft highlighted edges: the chunky diorama look.

const SHADER := preload("res://shaders/voxel.gdshader")

# [normal, u axis, v axis] with u x v = normal.
const FACES := [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]

static var _material: ShaderMaterial
# Dev (--audit): world-space boxes are recorded with the code that placed them.
static var recording := false
static var recorded: Array = []
var world_space := false

var rng := RandomNumberGenerator.new()
var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()
var _col := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _boxes := 0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


func _init(seed_value := 0) -> void:
	rng.seed = seed_value


## Adds an axis-aligned box. `jitter` randomly shifts brightness for variety.
func box(center: Vector3, size: Vector3, color: Color, jitter := 0.0, skip_bottom := false) -> void:
	var c := color
	if jitter > 0.0:
		var j := rng.randf_range(-jitter, jitter)
		c = Color(clampf(c.r + j, 0, 1), clampf(c.g + j, 0, 1), clampf(c.b + j, 0, 1), c.a)
	# Boxes are often built flush (a leg ending exactly where a seat ends), and
	# two coplanar faces flicker as the camera moves. Growing every box by its
	# own fraction of a millimetre makes one face win cleanly.
	_boxes += 1
	if recording and world_space:
		var where := []
		for f in get_stack().slice(1, 6):
			where.append("%s:%d" % [str(f.function), int(f.line)])
		recorded.append([center, size, color, " < ".join(where)])
	var grow := 0.0002 + 0.0003 * float((_boxes * 7919) % 5)
	var half := size * 0.5 + Vector3.ONE * grow
	size = half * 2.0
	for face in FACES:
		var n: Vector3 = face[0]
		if skip_bottom and n == Vector3.DOWN:
			continue
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var su := absf(size.dot(u))
		var sv := absf(size.dot(v))
		var p0 := center + n * absf(half.dot(n)) - u * (su * 0.5) - v * (sv * 0.5)
		var p1 := p0 + u * su
		var p2 := p1 + v * sv
		var p3 := p0 + v * sv
		var face_size := Vector2(su, sv)
		# Godot treats clockwise triangles as front faces.
		_pos.append_array([p0, p2, p1, p0, p3, p2])
		_uv.append_array([Vector2(0, 0), Vector2(su, sv), Vector2(su, 0), Vector2(0, 0), Vector2(0, sv), Vector2(su, sv)])
		for k in 6:
			_nrm.append(n)
			_col.append(c)
			_uv2.append(face_size)


func is_empty() -> bool:
	return _pos.is_empty()


func commit() -> ArrayMesh:
	if _pos.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _pos
	arrays[Mesh.ARRAY_NORMAL] = _nrm
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Commits into a MeshInstance3D using the shared voxel material.
func to_instance(mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	mi.material_override = mat if mat else material()
	return mi

