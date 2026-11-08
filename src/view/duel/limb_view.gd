class_name LimbView
extends RefCounted
## Shows what has been lost from a body. A lost part's bone shrinks to nothing, which draws everything skinned to it
## in to the joint, clothes and all, and a stump goes over the join. It reads wounds and never changes them.

## Scale that makes a bone's mesh vanish while leaving numbers a matrix can still be inverted from.
const GONE: float = 0.001
const BONES: Dictionary[StringName, String] = {
	&"arm_l": "upperarm_l", &"forearm_l": "lowerarm_l", &"hand_l": "hand_l",
	&"arm_r": "upperarm_r", &"forearm_r": "lowerarm_r", &"hand_r": "hand_r",
	&"thigh_l": "thigh_l", &"shin_l": "calf_l", &"foot_l": "foot_l",
	&"thigh_r": "thigh_r", &"shin_r": "calf_r", &"foot_r": "foot_r",
	&"neck": "neck_01",
}
const STUMP_RADIUS: Dictionary[StringName, float] = {
	&"arm_l": 0.065, &"forearm_l": 0.05, &"hand_l": 0.036,
	&"arm_r": 0.065, &"forearm_r": 0.05, &"hand_r": 0.036,
	&"thigh_l": 0.09, &"shin_l": 0.06, &"foot_l": 0.045,
	&"thigh_r": 0.09, &"shin_r": 0.06, &"foot_r": 0.045,
	&"neck": 0.06,
}
const STUMP_COLOR: Color = Color(0.3, 0.035, 0.03)
const PIECE_MASS: float = 3.0


## Makes the body match what its owner has lost. Safe to call again as more goes.
static func show_losses(body: Node3D, lost_parts: Array[StringName]) -> void:
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(body)
	for part_id: StringName in lost_parts:
		if not BONES.has(part_id):
			continue
		var bone: int = skeleton.find_bone(BONES[part_id])
		if bone < 0 or skeleton.get_bone_pose_scale(bone).x < 0.5:
			continue
		skeleton.set_bone_pose_scale(bone, Vector3.ONE * GONE)
		_add_stump(skeleton, bone, STUMP_RADIUS[part_id])
	if lost_parts.has(&"arm_l") or lost_parts.has(&"forearm_l") or lost_parts.has(&"hand_l"):
		_hide_part(body, "shield")


static func _hide_part(body: Node3D, part_name: String) -> void:
	for part: Node in body.find_children(part_name, "MeshInstance3D", true, false):
		(part as MeshInstance3D).visible = false
		part.set_meta(BodyView.DROPPED_META, true)


## A rounded end at the joint, riding on the bone above it.
static func _add_stump(skeleton: Skeleton3D, bone: int, radius: float) -> void:
	var parent: int = skeleton.get_bone_parent(bone)
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_name = skeleton.get_bone_name(parent)
	skeleton.add_child(attachment)
	var ball: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	ball.mesh = sphere
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = STUMP_COLOR
	material.roughness = 0.45
	ball.material_override = material
	ball.position = skeleton.get_bone_rest(bone).origin
	attachment.add_child(ball)


## What came off, as a loose piece that falls: a copy of the body with everything but that limb shrunk away.
static func drop_piece(scene: Node3D, from_body: Node3D, part_id: StringName, face: FaceData, male: bool, age: float, worn: Array[String], with_head: bool, tint: Color = BodyView.NO_TINT) -> void:
	if not BONES.has(part_id):
		return
	var from_skeleton: Skeleton3D = ViewUtil.find_skeleton(from_body)
	var bone_name: String = BONES[part_id]
	var piece: Node3D = BodyView.make(face, male, age, worn, false, tint)
	if with_head:
		var head: Node3D = FaceView.attach(piece, face, male, age)
		if worn.has("helmet"):
			FaceView.hide_hair(head)
	var holder: RigidBody3D = RigidBody3D.new()
	holder.mass = PIECE_MASS
	holder.collision_layer = Ragdoll.LOOSE_LAYER
	holder.collision_mask = Ragdoll.GROUND_MASK
	var shape: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = STUMP_RADIUS[part_id]
	capsule.height = maxf(capsule.radius * 2.0, 0.28)
	shape.shape = capsule
	holder.add_child(shape)
	scene.add_child(holder)
	holder.add_child(piece)
	ViewUtil.find_player(piece).active = false
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(piece)
	var top: int = skeleton.find_bone(bone_name)
	var parent: int = skeleton.get_bone_parent(top)
	# Shrinks from the skeleton's root down, then grows back at the limb, so only the limb keeps its size.
	var kept: Dictionary[int, bool] = {}
	_collect(skeleton, top, kept)
	var root: int = parent
	while skeleton.get_bone_parent(root) >= 0:
		root = skeleton.get_bone_parent(root)
	skeleton.set_bone_pose_scale(root, Vector3.ONE * GONE)
	skeleton.set_bone_pose_scale(top, Vector3.ONE / GONE)
	for i: int in range(skeleton.get_bone_count()):
		if kept.has(i):
			skeleton.set_bone_pose_rotation(i, from_skeleton.get_bone_pose_rotation(from_skeleton.find_bone(skeleton.get_bone_name(i))))
		elif _is_ancestor(skeleton, skeleton.get_bone_parent(i), top) and not _is_ancestor(skeleton, i, top):
			# Branches off the way to the limb, such as the other arm and the legs, go altogether.
			skeleton.set_bone_pose_scale(i, Vector3.ONE * GONE)
	var world_bone: Transform3D = from_skeleton.global_transform * from_skeleton.get_bone_global_pose(from_skeleton.find_bone(bone_name))
	holder.global_position = world_bone.origin
	# The limb's joint in the copy sits at the holder, turned as it was on the body.
	var own_pose: Transform3D = skeleton.get_bone_global_pose(top)
	piece.transform = Transform3D(world_bone.orthonormalized().basis, Vector3.ZERO) * Transform3D(own_pose.orthonormalized().basis.inverse(), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -own_pose.origin)
	holder.apply_central_impulse(Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0)) * PIECE_MASS * 0.7)
	holder.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.25)


static func _collect(skeleton: Skeleton3D, bone: int, into: Dictionary[int, bool]) -> void:
	into[bone] = true
	for child: int in skeleton.get_bone_children(bone):
		_collect(skeleton, child, into)


static func _is_ancestor(skeleton: Skeleton3D, candidate: int, of: int) -> bool:
	var at: int = skeleton.get_bone_parent(of)
	while at >= 0:
		if at == candidate:
			return true
		at = skeleton.get_bone_parent(at)
	return false
