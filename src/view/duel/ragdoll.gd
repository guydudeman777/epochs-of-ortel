class_name Ragdoll
extends RefCounted
## Physics for a body that has stopped holding itself up. The bones are made when it falls, so people still on their feet
## cost nothing here.
## It only shows what has happened: nothing in the simulation depends on how a body falls.

## Layers: the ground is on 1. Limp bodies meet the ground, each other and themselves. Dropped gear meets the ground and other dropped gear.
const LIMP_LAYER: int = 2
const LOOSE_LAYER: int = 4
const GROUND_MASK: int = 1
const LIMP_MASK: int = GROUND_MASK | LIMP_LAYER
const FRICTION: float = 0.9
const BOUNCE: float = 0.0
const LINEAR_DAMP: float = 0.25
const ANGULAR_DAMP: float = 2.2
const NO_END: float = 0.0
## How far a hinge opens past its rest pose unless it says. A knee at rest is straight, and an elbow is already bent.
const HINGE_BACK: float = 3.0
const WEAPON_MASS: float = 1.3
const SHIELD_MASS: float = 3.0
## How clear of each other two parts must be before they collide, so they do not catch again at once.
const PARTED_GAP: float = 0.015
const HAND_R: String = "hand_r"
const SHIELD_ARM: String = "lowerarm_l"
## Neighbours whose shapes meet at a joint, so they would fight each other if they could collide.
const NEIGHBOURS: Array[Array] = [
	["pelvis", "spine_01"], ["pelvis", "spine_03"], ["spine_01", "spine_03"], ["spine_03", "head"],
	["pelvis", "thigh_l"], ["pelvis", "thigh_r"], ["spine_01", "thigh_l"], ["spine_01", "thigh_r"], ["thigh_l", "thigh_r"],
	["spine_03", "upperarm_l"], ["upperarm_l", "lowerarm_l"], ["lowerarm_l", "hand_l"],
	["spine_03", "upperarm_r"], ["upperarm_r", "lowerarm_r"], ["lowerarm_r", "hand_r"],
	["thigh_l", "calf_l"], ["calf_l", "foot_l"], ["thigh_r", "calf_r"], ["calf_r", "foot_r"],
]
## Parents before children. Bones left out, like the collarbones and the neck, ride on their parent.
## end: the bone it reaches to. length: used when nothing follows it, along the way the bone before it runs.
## kind: "cone" or "hinge". bends: the way a hinge folds the limb, in the skeleton's axes. Angles count from the rest pose.
const BONES: Array[Dictionary] = [
	{"bone": "pelvis", "end": "spine_01", "radius": 0.13, "mass": 12.0, "kind": "root"},
	{"bone": "spine_01", "end": "spine_03", "radius": 0.12, "mass": 10.0, "kind": "cone", "swing": 13.0, "twist": 8.0},
	{"bone": "spine_03", "end": "neck_01", "radius": 0.13, "mass": 14.0, "kind": "cone", "swing": 15.0, "twist": 10.0},
	{"bone": "head", "length": 0.2, "radius": 0.09, "mass": 5.0, "kind": "cone", "swing": 30.0, "twist": 28.0},
	{"bone": "upperarm_l", "end": "lowerarm_l", "radius": 0.045, "mass": 2.5, "kind": "cone", "swing": 75.0, "twist": 35.0},
	{"bone": "lowerarm_l", "end": "hand_l", "radius": 0.038, "mass": 1.6, "kind": "hinge", "bends": Vector3(0.0, 0.0, 1.0), "folds": 100.0, "opens": 40.0},
	{"bone": "hand_l", "length": 0.09, "radius": 0.035, "mass": 0.5, "kind": "cone", "swing": 40.0, "twist": 20.0},
	{"bone": "upperarm_r", "end": "lowerarm_r", "radius": 0.045, "mass": 2.5, "kind": "cone", "swing": 75.0, "twist": 35.0},
	{"bone": "lowerarm_r", "end": "hand_r", "radius": 0.038, "mass": 1.6, "kind": "hinge", "bends": Vector3(0.0, 0.0, 1.0), "folds": 100.0, "opens": 40.0},
	{"bone": "hand_r", "length": 0.09, "radius": 0.035, "mass": 0.5, "kind": "cone", "swing": 40.0, "twist": 20.0},
	{"bone": "thigh_l", "end": "calf_l", "radius": 0.075, "mass": 8.0, "kind": "cone", "swing": 48.0, "twist": 12.0},
	{"bone": "calf_l", "end": "foot_l", "radius": 0.055, "mass": 3.5, "kind": "hinge", "bends": Vector3(0.0, 0.0, -1.0), "folds": 140.0},
	{"bone": "foot_l", "end": "ball_l", "radius": 0.042, "mass": 1.1, "kind": "cone", "swing": 35.0, "twist": 12.0},
	{"bone": "thigh_r", "end": "calf_r", "radius": 0.075, "mass": 8.0, "kind": "cone", "swing": 48.0, "twist": 12.0},
	{"bone": "calf_r", "end": "foot_r", "radius": 0.055, "mass": 3.5, "kind": "hinge", "bends": Vector3(0.0, 0.0, -1.0), "folds": 140.0},
	{"bone": "foot_r", "end": "ball_r", "radius": 0.042, "mass": 1.1, "kind": "cone", "swing": 35.0, "twist": 12.0},
]


## Makes a body's physics bones. Joint limits count from the pose the bones are made in, so the skeleton stands at rest
## for that moment, then goes back to the pose it was in.
static func prepare(body: Node3D) -> PhysicalBoneSimulator3D:
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(body)
	ViewUtil.find_player(body).active = false
	var names: Array[String] = []
	for spec: Dictionary in BONES:
		names.append(spec["bone"] as String)
	var kept: Array[String] = still_there(skeleton, names)
	var count: int = skeleton.get_bone_count()
	var positions: PackedVector3Array = PackedVector3Array()
	var turns: Array[Quaternion] = []
	var scales: PackedVector3Array = PackedVector3Array()
	for i: int in range(count):
		positions.append(skeleton.get_bone_pose_position(i))
		turns.append(skeleton.get_bone_pose_rotation(i))
		scales.append(skeleton.get_bone_pose_scale(i))
	skeleton.reset_bone_poses()
	var simulator: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()
	skeleton.add_child(simulator)
	for spec: Dictionary in BONES:
		if kept.has(spec["bone"] as String):
			simulator.add_child(_make_bone(skeleton, spec))
	for i: int in range(count):
		skeleton.set_bone_pose_position(i, positions[i])
		skeleton.set_bone_pose_rotation(i, turns[i])
		skeleton.set_bone_pose_scale(i, scales[i])
	return simulator


static func _make_bone(skeleton: Skeleton3D, spec: Dictionary) -> PhysicalBone3D:
	var bone_name: String = spec["bone"]
	var id: int = skeleton.find_bone(bone_name)
	var rest: Transform3D = skeleton.get_bone_global_rest(id)
	var world_along: Vector3 = _reach(skeleton, id, spec)
	var length: float = world_along.length()
	var along: Vector3 = rest.basis.inverse() * world_along
	var up: Vector3 = Vector3.UP if absf(along.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var body_basis: Basis = Basis.looking_at(along, up)
	var bone: PhysicalBone3D = PhysicalBone3D.new()
	bone.name = "limp_" + bone_name
	# This property exists only by name, so it has to be set by name.
	bone.set("bone_name", bone_name)
	bone.body_offset = Transform3D(body_basis, body_basis * Vector3(0.0, 0.0, -length * 0.5))
	var radius: float = spec["radius"]
	var mass: float = spec["mass"]
	bone.mass = mass
	bone.friction = FRICTION
	bone.bounce = BOUNCE
	bone.linear_damp = LINEAR_DAMP
	bone.angular_damp = ANGULAR_DAMP
	bone.collision_layer = LIMP_LAYER
	bone.collision_mask = LIMP_MASK
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(length, radius * 2.0 + 0.01)
	shape.shape = capsule
	shape.basis = Basis(Vector3.RIGHT, PI * 0.5)
	bone.add_child(shape)
	bone.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, length * 0.5))
	_set_joint(bone, spec, rest.basis * body_basis, world_along.normalized())
	return bone


## The way from a bone's joint to the end of its body, in the skeleton's axes.
static func _reach(skeleton: Skeleton3D, id: int, spec: Dictionary) -> Vector3:
	var start: Vector3 = skeleton.get_bone_global_rest(id).origin
	if spec.has("end"):
		var end_name: String = spec["end"]
		return skeleton.get_bone_global_rest(skeleton.find_bone(end_name)).origin - start
	var parent: int = skeleton.get_bone_parent(id)
	var running: Vector3 = (start - skeleton.get_bone_global_rest(parent).origin).normalized()
	var length: float = spec["length"]
	return running * length


static func _set_joint(bone: PhysicalBone3D, spec: Dictionary, body_basis: Basis, limb: Vector3) -> void:
	var kind: String = spec["kind"]
	match kind:
		"cone":
			# A cone joint's X axis is the limb's line.
			var side: Vector3 = limb.cross(Vector3.FORWARD)
			if side.length() < 0.05:
				side = limb.cross(Vector3.RIGHT)
			var y: Vector3 = side.normalized()
			var wanted: Basis = Basis(limb, y, limb.cross(y).normalized())
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			bone.joint_rotation = (body_basis.inverse() * wanted).get_euler()
			bone.set("joint_constraints/swing_span", spec["swing"])
			bone.set("joint_constraints/twist_span", spec["twist"])
		"hinge":
			# A hinge turns about its Z axis. Turning about limb x bends carries the limb towards bends.
			var bends: Vector3 = spec["bends"]
			var axis: Vector3 = limb.cross(bends).normalized()
			var x: Vector3 = limb
			var wanted: Basis = Basis(x, axis.cross(x).normalized(), axis)
			var folds: float = spec["folds"]
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			bone.joint_rotation = (body_basis.inverse() * wanted).get_euler()
			bone.set("joint_constraints/angular_limit_enabled", true)
			bone.set("joint_constraints/angular_limit_upper", folds)
			var opens: float = spec.get("opens", HINGE_BACK)
			bone.set("joint_constraints/angular_limit_lower", -opens)
		_:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE


static func _bind_of(mesh: MeshInstance3D, bone_name: String) -> Transform3D:
	var skin: Skin = mesh.skin
	for i: int in range(skin.get_bind_count()):
		if String(skin.get_bind_name(i)) == bone_name:
			return skin.get_bind_pose(i)
	return Transform3D.IDENTITY


static func _visible_part(body: Node3D, part_name: String) -> MeshInstance3D:
	var found: Array[Node] = body.find_children(part_name, "MeshInstance3D", true, false)
	if found.is_empty() or not (found[0] as MeshInstance3D).visible:
		return null
	return found[0] as MeshInstance3D


## Which of these bones still has a body to move: none of them, or anything above them, may have been cut off.
static func still_there(skeleton: Skeleton3D, bone_names: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for bone_name: String in bone_names:
		var at: int = skeleton.find_bone(bone_name)
		var whole: bool = at >= 0
		while at >= 0:
			if skeleton.get_bone_pose_scale(at).x < 0.5:
				whole = false
			at = skeleton.get_bone_parent(at)
		if whole:
			out.append(bone_name)
	return out


## Lets go. The push is in world axes, and lands on the named bone with a little on the trunk.
## Returns the pairs of parts to pass to collide_again_once_parted.
static func go_limp(scene: Node3D, body: Node3D, simulator: PhysicalBoneSimulator3D, push: Vector3, struck_bone: String) -> Array[PackedStringArray]:
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(body)
	var names: Array[String] = []
	for spec: Dictionary in BONES:
		names.append(spec["bone"] as String)
	var kept: Array[String] = still_there(skeleton, names)
	# Nothing grips or braces any more, so what was held comes away.
	if kept.has(HAND_R):
		for weapon_part: String in BodyView.WEAPON_PARTS.values():
			_drop_loose(scene, body, skeleton, weapon_part, HAND_R, WEAPON_MASS)
	if kept.has(SHIELD_ARM):
		_drop_loose(scene, body, skeleton, "shield", SHIELD_ARM, SHIELD_MASS)
	var parting: Array[PackedStringArray] = _set_who_collides(simulator, skeleton, kept)
	simulator.active = true
	simulator.physical_bones_start_simulation()
	var struck: PhysicalBone3D = simulator.get_node_or_null("limp_" + struck_bone) as PhysicalBone3D
	if struck != null:
		struck.apply_central_impulse(push)
	var chest: PhysicalBone3D = simulator.get_node_or_null("limp_spine_03") as PhysicalBone3D
	if chest != null:
		chest.apply_central_impulse(push * 0.6)
	return parting


## Parts of a body stop each other, so it cannot fold into itself. Neighbours at a joint never collide. Two parts that
## overlap as it lets go, like an arm drawn across the chest, would throw it if pushed apart, so they pass through each
## other until they have parted. Returns those pairs, to go back to the caller until then.
static func _set_who_collides(simulator: PhysicalBoneSimulator3D, skeleton: Skeleton3D, kept: Array[String]) -> Array[PackedStringArray]:
	for pair: Array in NEIGHBOURS:
		_never_collide(simulator, pair[0] as String, pair[1] as String)
	var specs: Array[Dictionary] = []
	for spec: Dictionary in BONES:
		var bone_name: String = spec["bone"]
		if kept.has(bone_name):
			specs.append(spec)
	var parting: Array[PackedStringArray] = []
	for i: int in range(specs.size()):
		var first: PackedVector3Array = _segment_now(skeleton, specs[i])
		var first_radius: float = specs[i]["radius"]
		for j: int in range(i + 1, specs.size()):
			var a_name: String = specs[i]["bone"]
			var b_name: String = specs[j]["bone"]
			if _are_neighbours(a_name, b_name):
				continue
			var second_radius: float = specs[j]["radius"]
			if segment_distance(first, _segment_now(skeleton, specs[j])) < first_radius + second_radius:
				_never_collide(simulator, a_name, b_name)
				parting.append(PackedStringArray([a_name, b_name]))
	return parting


static func _are_neighbours(a: String, b: String) -> bool:
	for pair: Array in NEIGHBOURS:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


## Lets parts collide again once they have come apart. Returns the pairs still overlapping.
static func collide_again_once_parted(simulator: PhysicalBoneSimulator3D, parting: Array[PackedStringArray]) -> Array[PackedStringArray]:
	var still: Array[PackedStringArray] = []
	for pair: PackedStringArray in parting:
		var first: PhysicalBone3D = simulator.get_node_or_null("limp_" + pair[0]) as PhysicalBone3D
		var second: PhysicalBone3D = simulator.get_node_or_null("limp_" + pair[1]) as PhysicalBone3D
		if first == null or second == null:
			continue
		if segment_distance(_segment_of(first), _segment_of(second)) > _radius_of(pair[0]) + _radius_of(pair[1]) + PARTED_GAP:
			first.remove_collision_exception_with(second)
		else:
			still.append(pair)
	return still


## The two ends of a physics bone's body, wherever physics has put it.
static func _segment_of(bone: PhysicalBone3D) -> PackedVector3Array:
	var half: float = bone.joint_offset.origin.z
	var along: Vector3 = bone.global_basis.z * half
	return PackedVector3Array([bone.global_position + along, bone.global_position - along])


static func _radius_of(bone_name: String) -> float:
	for spec: Dictionary in BONES:
		if spec["bone"] == bone_name:
			var radius: float = spec["radius"]
			return radius
	return 0.0


static func _never_collide(simulator: PhysicalBoneSimulator3D, a: String, b: String) -> void:
	var first: PhysicalBone3D = simulator.get_node_or_null("limp_" + a) as PhysicalBone3D
	var second: PhysicalBone3D = simulator.get_node_or_null("limp_" + b) as PhysicalBone3D
	if first != null and second != null:
		first.add_collision_exception_with(second)


## Where a bone's body lies right now, as its two ends in the skeleton's axes.
static func _segment_now(skeleton: Skeleton3D, spec: Dictionary) -> PackedVector3Array:
	var bone_name: String = spec["bone"]
	var id: int = skeleton.find_bone(bone_name)
	var start: Vector3 = skeleton.get_bone_global_pose(id).origin
	if spec.has("end"):
		var end_name: String = spec["end"]
		return PackedVector3Array([start, skeleton.get_bone_global_pose(skeleton.find_bone(end_name)).origin])
	var running: Vector3 = (start - skeleton.get_bone_global_pose(skeleton.get_bone_parent(id)).origin).normalized()
	var length: float = spec["length"]
	return PackedVector3Array([start, start + running * length])


## The closest two line segments come.
static func segment_distance(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var closest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])
	return closest[0].distance_to(closest[1])


## A held thing is a loose thing of its own from here on.
static func _drop_loose(scene: Node3D, body: Node3D, skeleton: Skeleton3D, part_name: String, bone_name: String, mass: float) -> void:
	var held: MeshInstance3D = _visible_part(body, part_name)
	if held == null:
		return
	var world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)) * _bind_of(held, bone_name)
	var aabb: AABB = held.mesh.get_aabb()
	var holder: RigidBody3D = RigidBody3D.new()
	holder.mass = mass
	holder.collision_layer = LOOSE_LAYER
	holder.collision_mask = GROUND_MASK | LOOSE_LAYER
	var shape: CollisionShape3D = CollisionShape3D.new()
	var solid: BoxShape3D = BoxShape3D.new()
	solid.size = Vector3(maxf(aabb.size.x, 0.02), maxf(aabb.size.y, 0.02), maxf(aabb.size.z, 0.02))
	shape.shape = solid
	holder.add_child(shape)
	var loose: MeshInstance3D = MeshInstance3D.new()
	loose.mesh = held.mesh
	loose.material_override = held.material_override
	loose.position = -aabb.get_center()
	holder.add_child(loose)
	scene.add_child(holder)
	holder.global_transform = world * Transform3D(Basis.IDENTITY, aabb.get_center())
	held.visible = false
	held.set_meta(BodyView.DROPPED_META, true)
