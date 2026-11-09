class_name ShipModel
extends RefCounted
## A cog for the map: a broad clinker hull, a castle at each end, one mast and a square sail in the band's colours. Built
## from a handful of boxes, big enough to read from high up. It faces +z, as band tokens do.

const HULL_COLOR: Color = Color(0.3, 0.2, 0.12)
const DECK_COLOR: Color = Color(0.45, 0.34, 0.22)
const MAST_COLOR: Color = Color(0.25, 0.18, 0.11)
const SAIL_COLOR: Color = Color(0.82, 0.76, 0.62)


static func make(sail_tint: Color, stripe: Color) -> Node3D:
	var ship: Node3D = Node3D.new()
	ship.name = "Ship"
	# The hull narrows to the bow and the stern. Three blocks, each a little narrower and higher than the middle.
	_box(ship, Vector3(6.0, 3.0, 12.0), Vector3(0.0, 0.6, 0.0), HULL_COLOR)
	_box(ship, Vector3(4.6, 3.6, 4.0), Vector3(0.0, 1.0, 7.4), HULL_COLOR)
	_box(ship, Vector3(5.0, 4.4, 4.2), Vector3(0.0, 1.4, -7.4), HULL_COLOR)
	_box(ship, Vector3(5.4, 0.3, 11.4), Vector3(0.0, 2.15, 0.0), DECK_COLOR)
	# Castles fore and aft.
	_box(ship, Vector3(4.4, 1.6, 3.2), Vector3(0.0, 4.2, 7.6), DECK_COLOR)
	_box(ship, Vector3(4.8, 2.2, 3.6), Vector3(0.0, 4.6, -7.6), DECK_COLOR)
	# The mast, the yard and the sail.
	_box(ship, Vector3(0.5, 17.0, 0.5), Vector3(0.0, 10.5, 0.8), MAST_COLOR)
	_box(ship, Vector3(10.0, 0.4, 0.4), Vector3(0.0, 17.2, 0.8), MAST_COLOR)
	var sail: MeshInstance3D = _box(ship, Vector3(9.0, 8.5, 0.2), Vector3(0.0, 12.6, 1.05), SAIL_COLOR.lerp(sail_tint, 0.35))
	sail.rotation.x = -0.12
	_box(ship, Vector3(9.05, 1.6, 0.25), Vector3(0.0, 12.6, 1.1), stripe)
	# A pennant at the top.
	_box(ship, Vector3(0.15, 0.8, 2.6), Vector3(0.0, 19.4, -0.4), stripe)
	return ship


static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material = material
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node
