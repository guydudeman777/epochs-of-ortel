class_name TownWater
extends RefCounted
## The water by a town you walk in: a sheet at the water's level out to the skyline on the water's side
## (town_water.gdshader), the boats and ships on it rocking at their moorings, and an unseen edge along the strand so
## nobody walks out onto the water. The quays, jetties and piers carry their own edges.

const SHADER: Shader = preload("res://src/view/town/town_water.gdshader")
const SHEET: float = 3000.0
const SHEET_STEPS: int = 240

## Each floating thing's node, its rest, and its own phase, for rocking.
var floaters: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _phase: Array[float] = []


static func build(parent: Node3D, layout: TownLayout, night: float) -> TownWater:
	var out: TownWater = TownWater.new()
	if layout.water_dir == Vector2.ZERO:
		return out
	var sheet: MeshInstance3D = MeshInstance3D.new()
	sheet.name = "Water"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2.ONE * SHEET
	plane.subdivide_width = SHEET_STEPS
	plane.subdivide_depth = SHEET_STEPS
	sheet.mesh = plane
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"night", night)
	sheet.material_override = material
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its near edge just inland of the shore, the rest out over the water.
	var middle: Vector2 = layout.water_dir * (layout.shore_line - 20.0 + SHEET * 0.5)
	sheet.position = Vector3(middle.x, TownHarbour.WATER_Y, middle.y)
	parent.add_child(sheet)
	if layout.harbour != null:
		out._build_floaters(parent, layout)
		out._build_edge(parent, layout)
	return out


func _build_floaters(parent: Node3D, layout: TownLayout) -> void:
	var group: Node3D = Node3D.new()
	group.name = "Floaters"
	parent.add_child(group)
	for floater: TownHarbour.Floater in layout.harbour.floaters:
		var path: String = TownBuilder.MODELS % floater.model
		if not ResourceLoader.exists(path):
			continue
		var node: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		var tint: float = fposmod(sin(floater.at.x * 12.9898 + floater.at.y * 78.233) * 43758.5453, 1.0)
		TownSurfaces.dress(node, Color(tint, 0.7, 0.8, 0.0))
		node.transform = TownBuilder.place_of(floater.at, floater.turn, 1.0, TownHarbour.WATER_Y)
		group.add_child(node)
		floaters.append(node)
		_rest.append(node.transform)
		_phase.append(tint * TAU)


## Boats and ships rise and fall, and roll and pitch a little, each in its own time.
func rock(time: float) -> void:
	for i: int in range(floaters.size()):
		var t: float = time * 0.7 + _phase[i]
		var big: float = 0.5 if floaters[i].name.contains("ship") else 1.0
		var tilt: Basis = Basis.from_euler(Vector3(sin(t * 0.8) * 0.02 * big, 0.0, sin(t * 1.1 + 0.7) * 0.035 * big))
		floaters[i].transform = Transform3D(_rest[i].basis * tilt, _rest[i].origin + Vector3(0.0, sin(t * 1.3) * 0.06 * big, 0.0))


## An unseen edge along the strand where the sand is just under the walker's feet, open where the piers go out; and
## past the ends of a quay, to the town's edge.
func _build_edge(parent: Node3D, layout: TownLayout) -> void:
	var harbour: TownHarbour = layout.harbour
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "WaterEdge"
	parent.add_child(body)
	var along: Vector2 = layout.water_dir.orthogonal()
	const STEP: float = 2.0
	var s: float = -layout.edge
	while s < layout.edge:
		var mid: float = s + STEP * 0.5
		s += STEP
		var open: bool = false
		for landing: float in harbour.landings:
			var mouth: float = (TownHarbour.JETTY_WIDTH if harbour.quay else TownHarbour.PIER_WIDTH) * 0.5 - 0.1
			open = open or absf(mid - landing) < mouth
		if open:
			continue
		var out: float = layout.shore_line + (0.0 if harbour.quay else TownHarbour.wander(mid) + TownHarbour.STRAND_STOP)
		var at: Vector2 = layout.water_dir * out + along * mid
		if at.length() > layout.edge + 4.0:
			continue
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(STEP + 0.4, 3.0, 0.6)
		shape.shape = box
		shape.position = Vector3(at.x, 1.5, at.y)
		shape.rotation.y = atan2(layout.water_dir.x, layout.water_dir.y)
		body.add_child(shape)
