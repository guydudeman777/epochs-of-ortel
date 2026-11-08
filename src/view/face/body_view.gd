class_name BodyView
extends RefCounted
## Makes a person's body: the shared rigged model, shaped by their FaceData, with the skeleton moved to
## match, dressed from a list of garments. A shape key changes the mesh but not the bones, so each person
## gets their own bone rests and skins. It reads faces and never changes them.

const BODY_SCENE: String = "res://assets/models/body_mh.glb"
const MANIFEST: String = "res://assets/models/body_mh_manifest.json"
const GEAR_SHADER: String = "res://src/view/face/gear.gdshader"
const TEXTURES: String = "res://assets/textures/gear/%s_%s.png"
const BODY_PARTS: Array[String] = ["body_female", "body_male", "body_crowd"]
const CROWD_BODY: String = "body_crowd"
const CROWD_SUFFIX: String = "_crowd"
const COVER_META: StringName = &"cover_bits"
const FITTED_META: StringName = &"fitted"
const BODY_MESHES_META: StringName = &"body_meshes"
## Set on a mesh for something the body no longer holds, like a sword let fall.
const DROPPED_META: StringName = &"dropped"
## Bits saying which skin a garment makes safe to leave undrawn. Set by the art build.
const COVER_BITS: Dictionary[String, int] = {&"shirt": 1, &"trousers": 2, &"boots": 4, &"mail": 8, &"coif": 16}
## Which model a weapon shows as. Bare hands show nothing.
const WEAPON_PARTS: Dictionary[StringName, String] = {&"arming_sword": "sword", &"axe": "axe", &"mace": "mace", &"spear": "spear"}
const MAIL_CLOTHES: Array[String] = ["trousers", "boots", "mail", "mail_skirt_l", "mail_skirt_r", "surcoat", "surcoat_skirt_l", "surcoat_skirt_r", "belt", "buckle"]
const PLAIN_CLOTHES: Array[String] = ["shirt", "shirt_skirt_l", "shirt_skirt_r", "trousers", "boots", "belt", "buckle"]
## No plate model yet, so plate shows as mail. Padding shows as plain clothes.
const MAIL_ARMOURS: Array[StringName] = [&"mail_hauberk", &"plate_harness"]
const NO_TINT: Color = Color(0.0, 0.0, 0.0, 0.0)
const TINTED_PARTS: Array[String] = ["surcoat", "surcoat_skirt_l", "surcoat_skirt_r", "shirt", "shirt_skirt_l", "shirt_skirt_r"]
const COMMONER: Array[String] = ["shirt", "shirt_skirt_l", "shirt_skirt_r", "trousers", "boots", "belt", "buckle"]
const SOLDIER: Array[String] = ["trousers", "boots", "mail", "mail_skirt_l", "mail_skirt_r", "surcoat", "surcoat_skirt_l", "surcoat_skirt_r", "belt", "buckle", "sword", "shield"]
const HELMET: Array[String] = ["coif", "helmet", "helmet_band", "nasal"]
## Parts of a garment with a crowd version. Skirts, belt, helmet and weapons are cheap enough already.
const HAS_CROWD_VERSION: Array[String] = ["shirt", "trousers", "boots", "mail", "surcoat", "coif"]
## Forms with a body of their own, worn on the same skeleton in place of the human body and head.
const FORM_BODIES: Dictionary[StringName, String] = {&"kheth": "res://assets/models/kheth_shell.glb"}
const CHITIN_SHADER: String = "res://src/view/face/chitin.gdshader"
## Colourings of the kheth: back, belly, markings and sheen. Amber, rust, beetle black, olive and sand.
const CHITIN_COLOURS: Array = [
	[Color(0.26, 0.13, 0.05), Color(0.58, 0.4, 0.18), Color(0.07, 0.04, 0.025), Color(0.25, 0.45, 0.15)],
	[Color(0.3, 0.08, 0.04), Color(0.62, 0.36, 0.2), Color(0.09, 0.03, 0.02), Color(0.45, 0.15, 0.55)],
	[Color(0.05, 0.045, 0.045), Color(0.24, 0.18, 0.12), Color(0.42, 0.3, 0.08), Color(0.15, 0.4, 0.5)],
	[Color(0.14, 0.15, 0.06), Color(0.46, 0.42, 0.22), Color(0.05, 0.06, 0.02), Color(0.35, 0.55, 0.15)],
	[Color(0.42, 0.31, 0.17), Color(0.72, 0.6, 0.42), Color(0.18, 0.1, 0.05), Color(0.3, 0.3, 0.5)],
]
## The node holding a form's own body, on the model.
const FORM_BODY_META: StringName = &"form_body"
## Metres one tile covers.
const TILE_MAIL: float = 0.075
const TILE_CLOTH: float = 0.12
const TILE_LEATHER: float = 0.22

static var _joints: Dictionary = {}
static var _clip_speeds: Dictionary = {}
static var _base_rest: Dictionary[StringName, Transform3D] = {}
static var _materials: Dictionary[String, ShaderMaterial] = {}


## A new body with its skeleton fitted, wearing these garments. crowd picks the low-detail meshes.
static func make(face: FaceData, male: bool, age: float, worn: Array[String], crowd: bool = false, tint: Color = NO_TINT) -> Node3D:
	var model: Node3D = (load(BODY_SCENE) as PackedScene).instantiate() as Node3D
	var own_body: bool = has_own_body(face)
	# A body of its own is built on the skeleton as it stands, so every one of that form is the same height.
	var none: Dictionary[StringName, float] = {}
	fit_skeleton(ViewUtil.find_skeleton(model), none if own_body else FaceView.shape_weights(face, male, age))
	model.set_meta(COVER_META, _cover_bits(worn))
	show_detail(model, face, male, age, worn, crowd, tint)
	# After the body's own meshes are counted, so showing and hiding them never touches it.
	if own_body:
		_wear_form_body(model, face, male, age)
	return model


static func has_own_body(face: FaceData) -> bool:
	return FORM_BODIES.has(face.form)


## Puts a form's own body on the skeleton. Its head is shaped by the same sliders as a human head.
static func _wear_form_body(model: Node3D, face: FaceData, male: bool, age: float) -> void:
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(model)
	var form_body: Node3D = (load(FORM_BODIES[face.form]) as PackedScene).instantiate() as Node3D
	skeleton.add_child(form_body)
	model.set_meta(FORM_BODY_META, form_body)
	var weights: Dictionary[StringName, float] = FaceView.shape_weights(face, male, age)
	for part: Node in form_body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		mesh.skeleton = mesh.get_path_to(skeleton)
		refit_skin(mesh, skeleton)
		apply_shape(mesh, weights)
		mesh.material_override = _shell_material(String(mesh.name), face)


## Chitin in one of the people's colourings, picked by the skin variant a person inherits. The joints between
## plates are soft and dark; the eyes are faceted.
static func _shell_material(part_name: String, face: FaceData) -> ShaderMaterial:
	var colours: Array = CHITIN_COLOURS[face.skin_variant % CHITIN_COLOURS.size()]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(CHITIN_SHADER) as Shader
	material.set_shader_parameter(&"dorsal", colours[0])
	material.set_shader_parameter(&"ventral", colours[1])
	material.set_shader_parameter(&"accent", colours[2])
	material.set_shader_parameter(&"sheen", colours[3])
	if part_name == "kheth_eyes":
		material.set_shader_parameter(&"compound", 1.0)
	elif part_name == "kheth_soft":
		material.set_shader_parameter(&"dorsal", (colours[0] as Color) * 0.35)
		material.set_shader_parameter(&"ventral", (colours[1] as Color) * 0.35)
	return material


## Shows a body in full or in its low-detail crowd meshes. Each mesh is fitted the first time it is shown, and stays fitted.
static func show_detail(model: Node3D, face: FaceData, male: bool, age: float, worn: Array[String], crowd: bool, tint: Color = NO_TINT) -> void:
	var weights: Dictionary[StringName, float] = FaceView.shape_weights(face, male, age)
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(model)
	var shown_body: String = CROWD_BODY if crowd else ("body_male" if male else "body_female")
	var own_body: bool = has_own_body(face)
	if own_body:
		shown_body = ""
	var parts: Array[String] = []
	for item: String in worn:
		# Human clothes do not fit a body of another form. It keeps only what it holds.
		if own_body and not (WEAPON_PARTS.values().has(item) or item == "shield"):
			continue
		parts.append(item + CROWD_SUFFIX if crowd and HAS_CROWD_VERSION.has(item) else item)
	if crowd and not worn.has("coif") and not own_body:
		parts.append("cap" + CROWD_SUFFIX)
	var hidden_bits: int = model.get_meta(COVER_META, 0) as int
	# Only the body's own meshes. A head attached later hangs from the same skeleton, and is not ours to show or hide.
	if not model.has_meta(BODY_MESHES_META):
		model.set_meta(BODY_MESHES_META, model.find_children("*", "MeshInstance3D", true, false))
	var own_meshes: Array = model.get_meta(BODY_MESHES_META)
	for part: Variant in own_meshes:
		var mesh: MeshInstance3D = part as MeshInstance3D
		var part_name: String = String(mesh.name)
		# Whatever a body has dropped stays dropped.
		if mesh.has_meta(DROPPED_META):
			continue
		mesh.visible = part_name == shown_body or parts.has(part_name)
		if not mesh.visible or mesh.has_meta(FITTED_META):
			continue
		mesh.set_meta(FITTED_META, true)
		var array_mesh: ArrayMesh = mesh.mesh as ArrayMesh
		if array_mesh.get_blend_shape_count() > 0:
			apply_shape(mesh, weights)
			# Weapons have no shapes. They keep their bind and so ride along with the moved bone.
			refit_skin(mesh, skeleton)
		if part_name == shown_body:
			var skin_material: ShaderMaterial = FaceView.skin_material(face, male, age)
			skin_material.set_shader_parameter(&"hidden_bits", hidden_bits)
			mesh.material_override = skin_material
		elif array_mesh.get_blend_shape_count() > 0:
			var material: ShaderMaterial = _gear_material(part_name.trim_suffix(CROWD_SUFFIX), tint)
			if part_name == "cap" + CROWD_SUFFIX:
				material = material.duplicate() as ShaderMaterial
				material.set_shader_parameter(&"color", FaceView.hair_color(face, age))
			mesh.material_override = material


## Moves each bone by how its joint moves under these shapes, keeping its rotation.
static func fit_skeleton(skeleton: Skeleton3D, weights: Dictionary[StringName, float]) -> void:
	_load_tables()
	var moved: Dictionary[int, Transform3D] = {}
	for i: int in range(skeleton.get_bone_count()):
		var bone_name: StringName = StringName(skeleton.get_bone_name(i))
		var rest: Transform3D = _base_rest[bone_name]
		var shapes: Dictionary = _joints.get(String(bone_name), {}) as Dictionary
		var offset: Vector3 = Vector3.ZERO
		for key: String in shapes:
			var share: float = weights.get(StringName(key), 0.0)
			if share != 0.0:
				var delta: Array = shapes[key] as Array
				offset += Vector3(delta[0] as float, delta[1] as float, delta[2] as float) * share
		moved[i] = Transform3D(rest.basis, rest.origin + offset)
	for i: int in range(skeleton.get_bone_count()):
		var parent: int = skeleton.get_bone_parent(i)
		var local: Transform3D = moved[i] if parent < 0 else moved[parent].affine_inverse() * moved[i]
		skeleton.set_bone_rest(i, local)
	skeleton.reset_bone_poses()


## The mesh's own copy of its skin, bound to this skeleton's rests. Any skeleton with the same bone names will do.
static func refit_skin(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	var skin: Skin = mesh.skin.duplicate() as Skin
	for i: int in range(skin.get_bind_count()):
		var bone: int = skeleton.find_bone(String(skin.get_bind_name(i)))
		skin.set_bind_pose(i, skeleton.get_bone_global_rest(bone).affine_inverse())
	mesh.skin = skin


static func apply_shape(mesh: MeshInstance3D, weights: Dictionary[StringName, float]) -> void:
	var array_mesh: ArrayMesh = mesh.mesh as ArrayMesh
	for i: int in range(array_mesh.get_blend_shape_count()):
		var value: float = weights.get(array_mesh.get_blend_shape_name(i), 0.0)
		mesh.set_blend_shape_value(i, value)


## How high this person's hips are at rest, for seating them on a mount.
static func hip_height(skeleton: Skeleton3D) -> float:
	return skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")).origin.y


## How high this person's eyes are when standing, for framing a portrait.
static func eye_height(skeleton: Skeleton3D) -> float:
	return skeleton.get_bone_global_rest(skeleton.find_bone("head")).origin.y + 0.03


static func _cover_bits(worn: Array[String]) -> int:
	var bits: int = 0
	for item: String in worn:
		bits |= COVER_BITS.get(item, 0) as int
	return bits


## What someone with this gear wears, for BodyView.make.
static func worn_for(equipment: EquipmentData) -> Array[String]:
	var worn: Array[String] = []
	var in_mail: bool = false
	for armour_id: StringName in MAIL_ARMOURS:
		in_mail = in_mail or equipment.armour_ids.has(armour_id)
	worn.assign(MAIL_CLOTHES if in_mail else PLAIN_CLOTHES)
	if WEAPON_PARTS.has(equipment.weapon_id):
		worn.append(WEAPON_PARTS[equipment.weapon_id])
	if equipment.has_shield:
		worn.append("shield")
	if equipment.armour_ids.has(&"helmet"):
		worn.append_array(HELMET)
	return worn


## A side's own colour on what it wears over its armour.
static func _gear_material(part_name: String, tint: Color) -> ShaderMaterial:
	if tint.a > 0.0 and TINTED_PARTS.has(part_name):
		var key: String = part_name + tint.to_html()
		if not _materials.has(key):
			var own: ShaderMaterial = _gear_material(part_name, NO_TINT).duplicate() as ShaderMaterial
			own.set_shader_parameter(&"color", tint)
			_materials[key] = own
		return _materials[key]
	if _materials.has(part_name):
		return _materials[part_name]
	_load_tables()
	var material: ShaderMaterial
	match part_name:
		"mail", "mail_skirt_l", "mail_skirt_r", "coif":
			material = _tiled("mail", Color(0.72, 0.73, 0.76), TILE_MAIL, 0.72, 0.52, 0.8)
		"surcoat", "surcoat_skirt_l", "surcoat_skirt_r":
			material = _tiled("cloth", Color(0.36, 0.09, 0.08), TILE_CLOTH, 0.0, 0.9, 0.7)
			material.set_shader_parameter(&"badge", true)
		"shirt", "shirt_skirt_l", "shirt_skirt_r":
			material = _tiled("cloth", Color(0.62, 0.57, 0.46), TILE_CLOTH, 0.0, 0.92, 0.7)
		"trousers":
			material = _tiled("cloth", Color(0.27, 0.23, 0.19), TILE_CLOTH, 0.0, 0.92, 0.7)
		"boots":
			material = _tiled("leather", Color(0.2, 0.13, 0.09), TILE_LEATHER, 0.0, 0.62, 0.8)
		"belt":
			material = _tiled("leather", Color(0.11, 0.07, 0.05), TILE_LEATHER, 0.0, 0.55, 0.8)
		"helmet", "nasal":
			material = _plain(Color(0.42, 0.43, 0.45), 0.85, 0.5)
		"cap":
			material = _plain(Color(0.09, 0.07, 0.05), 0.0, 0.9)
		"helmet_band", "buckle":
			material = _plain(Color(0.45, 0.33, 0.16), 0.9, 0.5)
		_:
			material = _plain(Color(0.5, 0.5, 0.5), 0.0, 0.9)
	_materials[part_name] = material
	return material


static func _tiled(kind: String, color: Color, tile_metres: float, metal: float, rough: float, normal_strength: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(GEAR_SHADER) as Shader
	material.set_shader_parameter(&"albedo_map", load(TEXTURES % [kind, "albedo"]) as Texture2D)
	material.set_shader_parameter(&"normal_map", load(TEXTURES % [kind, "normal"]) as Texture2D)
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"tile", 1.0 / tile_metres)
	material.set_shader_parameter(&"metal", metal)
	material.set_shader_parameter(&"rough", rough)
	material.set_shader_parameter(&"normal_strength", normal_strength)
	return material


static func _plain(color: Color, metal: float, rough: float) -> ShaderMaterial:
	var material: ShaderMaterial = _tiled("leather", color, 10.0, metal, rough, 0.05)
	material.set_shader_parameter(&"albedo_map", null)
	return material


## What a person's clips are named with, for how they are armed: "_spear" for a spear in both hands, "_free" for a
## weapon with no shield, and nothing for a weapon and shield. A clip with no such version is the same for all.
static func kit_suffix(worn: Array[String]) -> String:
	if worn.has("spear"):
		return "_spear"
	if worn.has("shield"):
		return ""
	return "_free"


## The person's own version of a clip, for what they hold, where the body has one.
static func kit_clip(player: AnimationPlayer, clip: StringName, worn: Array[String]) -> StringName:
	var own: StringName = StringName(String(clip) + kit_suffix(worn))
	return own if player.has_animation(own) else clip


## Metres a second a looped stepping clip covers at its own speed, as the build measured it. 1 for any other clip.
static func clip_speed(clip: StringName) -> float:
	if _clip_speeds.is_empty():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
		_clip_speeds = manifest.get("clip_speeds", {}) as Dictionary
	var speed: float = _clip_speeds.get(String(clip), 1.0) as float
	return speed


static func _load_tables() -> void:
	if _joints.is_empty():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
		_joints = manifest["joints"] as Dictionary
	if _base_rest.is_empty():
		# The skeleton as it was built. Read from a fresh copy, as the caller's may be fitted already.
		var fresh: Node3D = (load(BODY_SCENE) as PackedScene).instantiate() as Node3D
		var source: Skeleton3D = ViewUtil.find_skeleton(fresh)
		for i: int in range(source.get_bone_count()):
			_base_rest[StringName(source.get_bone_name(i))] = source.get_bone_global_rest(i)
		fresh.free()
