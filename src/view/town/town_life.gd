class_name TownLife
extends Node3D
## The animals of a town and the birds over it: hens scratching behind the homes, dogs nosing about the streets, pigs
## where the poor live, goats, the herds in a farm's or a ranch's paddocks, horses tied up before the tavern, and
## flocks wheeling overhead (gulls by the water, crows inland). Only for the look of the place: nothing here is in the
## world, and none of it is saved. Fewer are about after dark.

## Each kind's model, how fast it goes, how far it wanders, and how long it stands between goes.
const KINDS: Dictionary[StringName, Array] = {
	&"chicken": ["walk_animal_chicken", 0.7, 4.0, Vector2(1.0, 4.0)],
	&"dog": ["walk_animal_dog", 1.6, 18.0, Vector2(2.0, 8.0)],
	&"pig": ["walk_animal_pig", 0.6, 5.0, Vector2(3.0, 9.0)],
	&"goat": ["walk_animal_goat", 0.8, 7.0, Vector2(2.0, 7.0)],
	&"sheep": ["walk_animal_sheep", 0.6, 0.0, Vector2(3.0, 10.0)],
	&"cow": ["walk_animal_cow", 0.5, 0.0, Vector2(5.0, 14.0)],
	&"horse": ["horse", 0.9, 0.0, Vector2(4.0, 12.0)],
}
const HORSE_SCENE: String = "res://assets/models/horse.glb"
const BIRDS_PER_FLOCK: int = 9

class Beast:
	var node: Node3D
	var kind: StringName
	var home: Vector2
	## A pen to keep inside, as [middle, turn, width, depth], or empty to roam round home.
	var pen: Array = []
	var target: Vector2
	var wait: float = 0.0
	var step: float = 0.0
	var tied: bool = false

var _layout: TownLayout
var _beasts: Array[Beast] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _birds: MultiMeshInstance3D = null
var _flocks: Array[Array] = []
var _night: float = 0.0


static func make(layout: TownLayout, night: float, seed_value: int) -> TownLife:
	var out: TownLife = TownLife.new()
	out.name = "Life"
	out._layout = layout
	out._night = night
	out._rng.seed = seed_value
	return out


func _ready() -> void:
	var awake: float = 1.0 - _night * 0.85
	# Hens behind homes, more in a farm town; pigs and goats where the poor live; a few dogs anywhere.
	var homes: Array[TownLayout.Piece] = []
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.spot < 0 and (piece.quarter == &"poor" or piece.quarter == &"common" or piece.quarter == &"craft"):
			homes.append(piece)
	var flocks: int = roundi(float(4 if _layout.is_town else 3) * awake)
	for k: int in range(mini(flocks, homes.size())):
		var piece: TownLayout.Piece = homes[_rng.randi_range(0, homes.size() - 1)]
		var yard: Vector2 = piece.to_town(0.0, piece.low.z - 2.0)
		for n: int in range(_rng.randi_range(3, 5)):
			_add(&"chicken", yard, [])
	for k: int in range(roundi(float(2 + int(_layout.poverty * 3.0)) * awake)):
		var piece: TownLayout.Piece = homes[_rng.randi_range(0, homes.size() - 1)] if not homes.is_empty() else null
		if piece != null:
			_add(&"dog", piece.to_town(0.0, piece.front() + 2.0), [])
	for k: int in range(roundi(_layout.poverty * 3.0 * awake)):
		var poor: Array[TownLayout.Piece] = _layout.in_quarter(&"poor")
		if not poor.is_empty():
			var piece: TownLayout.Piece = poor[_rng.randi_range(0, poor.size() - 1)]
			for n: int in range(2):
				_add(&"pig", piece.to_town(0.0, piece.low.z - 2.5), [])
	if _layout.is_town and _rng.randf() < 0.5 and not homes.is_empty():
		var piece: TownLayout.Piece = homes[_rng.randi_range(0, homes.size() - 1)]
		for n: int in range(3):
			_add(&"goat", piece.to_town(0.0, piece.low.z - 2.5), [])
	# The herds in their paddocks.
	if _layout.works != null:
		var pens: Array[Array] = _layout.works.pens
		for kind: StringName in _layout.works.herds:
			for n: int in range(_layout.works.herds[kind]):
				if pens.is_empty():
					break
				var pen: Array = pens[n % pens.size()]
				_add(kind, pen[0] as Vector2, pen)
	# Horses tied up before the tavern.
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.kind == &"tavern":
			for side: float in [-1.0, 1.0]:
				if _rng.randf() < 0.7:
					var beast: Beast = _add(&"horse", piece.to_town(side * 4.2, piece.high.z + 1.6), [])
					if beast != null:
						beast.tied = true
						beast.node.rotation.y = atan2(Vector2.from_angle(piece.turn).x, Vector2.from_angle(piece.turn).y) + PI * 0.5 * side
	if _night < 0.6:
		_build_birds()


func _add(kind: StringName, home: Vector2, pen: Array) -> Beast:
	var look: Array = KINDS[kind]
	var path: String = HORSE_SCENE if kind == &"horse" else TownBuilder.MODELS % (look[0] as String)
	if not ResourceLoader.exists(path):
		return null
	var start: Vector2 = _spot_near(home, pen, look[2] as float)
	if start == Vector2.INF:
		return null
	var beast: Beast = Beast.new()
	beast.kind = kind
	beast.home = home
	beast.pen = pen
	beast.node = (load(path) as PackedScene).instantiate() as Node3D
	if kind != &"horse":
		var tint: float = _rng.randf()
		TownSurfaces.dress(beast.node, Color(tint, 0.5, 0.0, 0.0))
	else:
		var player: AnimationPlayer = ViewUtil.find_player(beast.node)
		if player != null and player.has_animation(&"idle"):
			player.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
			player.play(&"idle")
		if pen.is_empty():
			pass
		else:
			# Ranch horses run bare: no saddle, no bridle.
			for found: Node in beast.node.find_children("*tack*", "MeshInstance3D", true, false):
				(found as Node3D).visible = false
	beast.node.position = Vector3(start.x, 0.0, start.y)
	beast.node.rotation.y = _rng.randf() * TAU
	beast.target = start
	beast.wait = _rng.randf_range(0.0, 3.0)
	beast.step = _rng.randf() * TAU
	add_child(beast.node)
	_beasts.append(beast)
	return beast


## A point near home (inside its pen if it has one) on open ground, or INF if none is found.
func _spot_near(home: Vector2, pen: Array, roam: float) -> Vector2:
	for attempt: int in range(12):
		var at: Vector2
		if not pen.is_empty():
			var ahead: Vector2 = Vector2.from_angle(pen[1] as float)
			var across: Vector2 = Vector2(ahead.y, -ahead.x)
			at = (pen[0] as Vector2) + across * _rng.randf_range(-0.42, 0.42) * (pen[2] as float) + ahead * _rng.randf_range(-0.42, 0.42) * (pen[3] as float)
			return at
		at = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, maxf(roam, 1.0))
		if not _layout.blocked(at, 0.5) and at.length() < _layout.edge - 3.0 and not _layout.wet(at, 2.0):
			return at
	return Vector2.INF


func _process(delta: float) -> void:
	for beast: Beast in _beasts:
		_move(beast, delta)
	_fly(delta)


func _move(beast: Beast, delta: float) -> void:
	var look: Array = KINDS[beast.kind]
	var here: Vector2 = Vector2(beast.node.position.x, beast.node.position.z)
	if beast.wait > 0.0 or beast.tied:
		beast.wait -= delta
		# Standing: a hen pecks, the rest shift a little.
		var t: float = float(Time.get_ticks_msec()) * 0.001 + beast.step
		if beast.kind == &"chicken":
			beast.node.rotation.x = maxf(sin(t * 5.0), 0.0) * 0.5
		beast.node.position.y = 0.0
		if beast.wait <= 0.0 and not beast.tied:
			var next: Vector2 = _spot_near(beast.home, beast.pen, look[2] as float)
			if next != Vector2.INF:
				beast.target = next
		return
	var offset: Vector2 = beast.target - here
	var speed: float = look[1] as float
	if offset.length() < 0.15:
		var pause: Vector2 = look[3] as Vector2
		beast.wait = _rng.randf_range(pause.x, pause.y)
		beast.node.rotation.x = 0.0
		return
	var way: Vector2 = offset.normalized()
	var moved: Vector2 = way * minf(speed * delta, offset.length())
	beast.node.position += Vector3(moved.x, 0.0, moved.y)
	beast.node.rotation.y = lerp_angle(beast.node.rotation.y, atan2(way.x, way.y), clampf(delta * 5.0, 0.0, 1.0))
	beast.step += delta * speed * (14.0 if beast.kind == &"chicken" else 6.0)
	beast.node.position.y = absf(sin(beast.step)) * (0.05 if beast.kind == &"chicken" else 0.025)
	beast.node.rotation.x = 0.0
	beast.node.rotation.z = sin(beast.step) * 0.03


# --- Birds -------------------------------------------------------------------------------------------------------------

func _build_birds() -> void:
	var mesh: ArrayMesh = _bird_mesh()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BIRD_SHADER
	mesh.surface_set_material(0, material)
	var flocks: int = 3 if _layout.water_dir != Vector2.ZERO else 2
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = flocks * BIRDS_PER_FLOCK
	for f: int in range(flocks):
		var by_water: bool = _layout.water_dir != Vector2.ZERO and f < 2
		var middle: Vector2 = _layout.water_dir * _layout.shore_line if by_water else Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, 50.0)
		# Centre, height, radius, speed, gull or crow.
		_flocks.append([middle, _rng.randf_range(18.0, 34.0), _rng.randf_range(14.0, 30.0), _rng.randf_range(0.12, 0.22) * (1.0 if _rng.randf() < 0.5 else -1.0), by_water])
		for b: int in range(BIRDS_PER_FLOCK):
			multi.set_instance_custom_data(f * BIRDS_PER_FLOCK + b, Color(_rng.randf(), 1.0 if by_water else 0.0, _rng.randf_range(0.8, 1.2), _rng.randf()))
	_birds = MultiMeshInstance3D.new()
	_birds.name = "Birds"
	_birds.multimesh = multi
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_birds)
	_fly(0.0)


const BIRD_SHADER: Shader = preload("res://src/view/town/bird.gdshader")


## Each flock wheels round its own middle, each bird a little off the line, rising and falling.
func _fly(_delta: float) -> void:
	if _birds == null:
		return
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var multi: MultiMesh = _birds.multimesh
	for f: int in range(_flocks.size()):
		var flock: Array = _flocks[f]
		var middle: Vector2 = flock[0] as Vector2
		for b: int in range(BIRDS_PER_FLOCK):
			var i: int = f * BIRDS_PER_FLOCK + b
			var own: Color = multi.get_instance_custom_data(i)
			var angle: float = t * (flock[3] as float) + own.r * 1.6
			var radius: float = (flock[2] as float) * (0.7 + own.a * 0.5)
			var at: Vector2 = middle + Vector2.from_angle(angle) * radius
			var height: float = (flock[1] as float) + sin(t * 0.7 + own.r * 9.0) * 3.0
			var ahead: Vector2 = Vector2.from_angle(angle + PI * 0.5 * signf(flock[3] as float))
			var basis: Basis = Basis(Vector3.UP, atan2(ahead.x, ahead.y)).scaled(Vector3.ONE * own.b)
			multi.set_instance_transform(i, Transform3D(basis, Vector3(at.x, height, at.y)))


## A bird: a body and two wings, swept back, about half a metre across. Its nose to +Z.
static func _bird_mesh() -> ArrayMesh:
	var points: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 0.0, 0.2), Vector3(-0.04, 0.0, -0.05), Vector3(0.04, 0.0, -0.05), Vector3(0.0, 0.0, -0.2),
		Vector3(-0.32, 0.02, -0.12), Vector3(0.32, 0.02, -0.12), Vector3(-0.1, 0.0, 0.06), Vector3(0.1, 0.0, 0.06),
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 1, 2, 3, 6, 1, 4, 7, 5, 2, 0, 1, 6, 0, 7, 2])
	var normals: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in points:
		normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
