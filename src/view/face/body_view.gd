class_name BodyView
extends RefCounted
## Makes a person's body: the shared rigged model, shaped by their FaceData, with the skeleton moved to
## match, dressed from a list of what they wear. A shape key changes the mesh but not the bones, so each person
## gets their own bone rests and skins. It reads faces and never changes them.
##
## What is worn is a list of names: looks from the garment build (a GarmentDef's model), weapons and "shield".
## A look may carry its dye after DYE_MARK, as "tunic@7a3020". Each look is a few garment meshes, made for a body
## only when it wears them, from garments_mh.glb. Garments hide the skin and the inner layers they cover by bits
## the build wrote on every face, so nothing pokes through.

const BODY_SCENE: String = "res://assets/models/body_mh.glb"
const MANIFEST: String = "res://assets/models/body_mh_manifest.json"
const GARMENT_SCENE: String = "res://assets/models/garments_mh.glb"
const GARMENT_MANIFEST: String = "res://assets/models/garments_mh_manifest.json"
const GARMENT_DEFS: String = "res://content/defs/armours/%s.tres"
const GEAR_SHADER: String = "res://src/view/face/gear.gdshader"
const TEXTURES: String = "res://assets/textures/gear/%s_%s.png"
const BODY_PARTS: Array[String] = ["body_female", "body_male", "body_crowd"]
const CROWD_BODY: String = "body_crowd"
const CROWD_SUFFIX: String = "_crowd"
const CROWD_HAIR: String = "cap_crowd"
const COVER_META: StringName = &"cover_bits"
const FITTED_META: StringName = &"fitted"
const BODY_MESHES_META: StringName = &"body_meshes"
## Garment meshes made for this body so far, by name.
const GARMENTS_META: StringName = &"garment_meshes"
## Set on a mesh for something the body no longer holds, like a sword let fall.
const DROPPED_META: StringName = &"dropped"
## Between a look and its dye in what is worn.
const DYE_MARK: String = "@"
## In what is worn when the head is covered, so the hair must go. Callers ask hides_hair, or for this name.
const HIDES_HAIR: String = "helmet"
## Worn under everything when nothing else is, so nobody is naked by default.
const SMALLCLOTHES: String = "loincloth"
## Which model a weapon shows as. Bare hands show nothing.
const WEAPON_PARTS: Dictionary[StringName, String] = {&"arming_sword": "sword", &"axe": "axe", &"mace": "mace", &"spear": "spear"}
## Plain sets of looks, for test scenes and anyone with no GarmentDefs to hand.
const PLAIN_CLOTHES: Array[String] = ["braies", "shirt", "trousers", "boots", "belt"]
const MAIL_CLOTHES: Array[String] = ["braies", "shirt", "trousers", "boots", "mail", "surcoat", "belt"]
const COMMONER: Array[String] = ["braies", "shirt", "trousers", "boots", "belt"]
const SOLDIER: Array[String] = ["braies", "shirt", "trousers", "boots", "mail", "surcoat", "belt", "sword", "shield"]
const HELMET: Array[String] = ["mail_coif", "helm_nasal", HIDES_HAIR]
const NO_TINT: Color = Color(0.0, 0.0, 0.0, 0.0)
## A side's colour goes on the outermost of these a person wears.
const TINTED_PARTS: Array[String] = [
	"surcoat", "surcoat_skirt_l", "surcoat_skirt_r", "shirt", "shirt_skirt_l", "shirt_skirt_r", "tunic_short", "short_skirt_l", "short_skirt_r",
	"over_long", "coat_skirt_l", "coat_skirt_r", "robe_skirt_l", "robe_skirt_r", "kaftan_skirt_l", "kaftan_skirt_r", "padded", "padded_skirt_l",
	"padded_skirt_r", "tunic_skirt_l", "tunic_skirt_r",
]
## How each kind of stuff is drawn: texture, metres one tile covers, metal, roughness, normal strength. No texture is
## plain colour.
const KINDS: Dictionary[String, Array] = {
	"linen": ["cloth", 0.1, 0.0, 0.92, 0.6], "underlinen": ["linen", 0.07, 0.0, 0.9, 0.55], "fine_linen": ["linen", 0.05, 0.0, 0.8, 0.35], "cloth": ["cloth", 0.12, 0.0, 0.9, 0.7], "wool": ["wool", 0.16, 0.0, 0.96, 0.9],
	"silk": ["cloth", 0.07, 0.0, 0.42, 0.25], "quilt": ["quilt", 0.3, 0.0, 0.9, 1.0], "felt": ["felt", 0.2, 0.0, 0.97, 0.6],
	"fur": ["fur", 0.16, 0.0, 1.0, 1.0], "leather": ["leather", 0.22, 0.0, 0.62, 0.8], "leather_dark": ["leather", 0.22, 0.0, 0.55, 0.8],
	"suede": ["leather", 0.3, 0.0, 0.88, 0.5], "mail": ["mail", 0.075, 0.72, 0.52, 0.8], "scale": ["scale", 0.12, 0.7, 0.45, 1.0],
	"lamellar": ["lamellar", 0.24, 0.45, 0.55, 1.0], "plate": ["plate", 0.5, 0.85, 0.4, 0.5], "steel": ["plate", 0.5, 0.85, 0.38, 0.5],
	"brigandine": ["brigandine", 0.2, 0.15, 0.85, 1.0], "plates": ["plates", 0.36, 0.1, 0.8, 1.0], "straw": ["straw", 0.12, 0.0, 0.92, 1.0],
	"iron": ["", 1.0, 0.85, 0.5, 0.0], "brass": ["", 1.0, 0.9, 0.5, 0.0], "gold": ["", 1.0, 1.0, 0.32, 0.0],
}
## How worn and faded a garment looks at a value of nothing. Dear clothes look new.
const MOST_WEAR: float = 0.6
const WEAR_FREE_VALUE: float = 60.0
const WORN_COLOR: Color = Color(0.36, 0.31, 0.25)
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


## One garment mesh to show, and how.
class Piece:
	extends RefCounted
	var part: String = ""
	var kind: String = ""
	var color: Color = Color.WHITE
	var dyeable: bool = false
	var layer: int = 0


## Everything a list of what is worn comes to.
class Dressing:
	extends RefCounted
	var pieces: Array[Piece] = []
	## Weapons and the shield, from the body model.
	var held: Array[String] = []
	## Bits of all the garments worn, for hiding what they cover.
	var bits: int = 0
	var hides_hair: bool = false


static var _joints: Dictionary = {}
static var _clip_speeds: Dictionary = {}
static var _base_rest: Dictionary[StringName, Transform3D] = {}
static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _garment_manifest: Dictionary = {}
## One copy of each garment's mesh and skin, by name, to make worn ones from.
static var _garment_meshes: Dictionary[String, ArrayMesh] = {}
static var _garment_skins: Dictionary[String, Skin] = {}
static var _garment_defs: Dictionary[StringName, ArmourDef] = {}


## A new body with its skeleton fitted, wearing these. crowd picks the low-detail meshes.
static func make(face: FaceData, male: bool, age: float, worn: Array[String], crowd: bool = false, tint: Color = NO_TINT) -> Node3D:
	var model: Node3D = (load(BODY_SCENE) as PackedScene).instantiate() as Node3D
	var own_body: bool = has_own_body(face)
	# A body of its own is built on the skeleton as it stands, so every one of that form is the same height.
	var none: Dictionary[StringName, float] = {}
	fit_skeleton(ViewUtil.find_skeleton(model), none if own_body else FaceView.shape_weights(face, male, age))
	model.set_meta(COVER_META, 0 if own_body else dressing(worn, tint).bits)
	show_detail(model, face, male, age, worn, crowd, tint)
	# After the body's own meshes are counted, so showing and hiding them never touches it.
	if own_body:
		_wear_form_body(model, face, male, age)
	return model


static func has_own_body(face: FaceData) -> bool:
	return FORM_BODIES.has(face.form)


## Whether what is worn covers the head so the hair must not show.
static func hides_hair(worn: Array[String]) -> bool:
	return worn.has(HIDES_HAIR) or dressing(worn, NO_TINT).hides_hair


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
	var dress: Dressing = dressing(worn, tint)
	var shown: Array[String] = dress.held.duplicate()
	if crowd and not own_body and not dress.hides_hair and not worn.has(HIDES_HAIR):
		shown.append(CROWD_HAIR)
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
		mesh.visible = part_name == shown_body or shown.has(part_name)
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
		elif part_name == CROWD_HAIR:
			mesh.material_override = _hair_cap(FaceView.hair_color(face, age))
	_show_garments(model, skeleton, weights, [] as Array[Piece] if own_body else dress.pieces, crowd, dress.bits)


## Makes, shows and hides the garment meshes. Those not worn are hidden, not freed, so a body switching to crowd
## detail and back keeps what it was fitted with.
static func _show_garments(model: Node3D, skeleton: Skeleton3D, weights: Dictionary[StringName, float], pieces: Array[Piece], crowd: bool, bits: int) -> void:
	if not model.has_meta(GARMENTS_META):
		var made: Dictionary[String, MeshInstance3D] = {}
		model.set_meta(GARMENTS_META, made)
	var meshes: Dictionary[String, MeshInstance3D] = model.get_meta(GARMENTS_META)
	var wanted: Dictionary[String, Piece] = {}
	var parts: Dictionary = _garments()["parts"] as Dictionary
	for piece: Piece in pieces:
		var info: Dictionary = parts.get(piece.part, {}) as Dictionary
		var mesh_name: String = piece.part + CROWD_SUFFIX if crowd and info.get("crowd", false) else piece.part
		wanted[mesh_name] = piece
	for mesh_name: String in meshes:
		if not wanted.has(mesh_name):
			meshes[mesh_name].visible = false
	for mesh_name: String in wanted:
		var piece: Piece = wanted[mesh_name]
		var mesh: MeshInstance3D = meshes.get(mesh_name, null)
		if mesh == null:
			mesh = _new_garment(mesh_name, skeleton, weights)
			if mesh == null:
				continue
			meshes[mesh_name] = mesh
		if mesh.has_meta(DROPPED_META):
			continue
		mesh.visible = true
		mesh.material_override = _garment_material(piece.kind, piece.color, bits, piece.part)


static func _new_garment(mesh_name: String, skeleton: Skeleton3D, weights: Dictionary[StringName, float]) -> MeshInstance3D:
	_load_garment_meshes()
	if not _garment_meshes.has(mesh_name):
		return null
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = mesh_name
	mesh.mesh = _garment_meshes[mesh_name]
	mesh.skin = _garment_skins[mesh_name]
	skeleton.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	refit_skin(mesh, skeleton)
	apply_shape(mesh, weights)
	return mesh


## What a list of worn names comes to: the garment meshes in their colours, what is held, and what is hidden.
static func dressing(worn: Array[String], tint: Color = NO_TINT) -> Dressing:
	var out: Dressing = Dressing.new()
	var manifest: Dictionary = _garments()
	var looks: Dictionary = manifest["looks"] as Dictionary
	var parts: Dictionary = manifest["parts"] as Dictionary
	var weapons: Array[String] = []
	weapons.assign(WEAPON_PARTS.values())
	for entry: String in worn:
		var look_name: String = entry.get_slice(DYE_MARK, 0)
		if weapons.has(look_name) or look_name == "shield":
			out.held.append(look_name)
			continue
		if not looks.has(look_name):
			continue
		var look: Dictionary = looks[look_name] as Dictionary
		var dye: Color = Color.html(entry.get_slice(DYE_MARK, 1)) if entry.contains(DYE_MARK) else NO_TINT
		out.hides_hair = out.hides_hair or (look.get("hides_hair", false) as bool)
		for row: Variant in look["parts"] as Array:
			var spec: Array = row as Array
			var piece: Piece = Piece.new()
			piece.part = spec[0] as String
			piece.kind = spec[1] as String
			var base: Array = spec[2] as Array
			piece.color = Color(base[0] as float, base[1] as float, base[2] as float)
			piece.dyeable = spec[3] as bool
			piece.layer = look.get("layer", 0) as int
			if piece.dyeable and dye.a > 0.0:
				piece.color = dye
			out.pieces.append(piece)
	_settle(out, parts, manifest)
	if tint.a > 0.0:
		_tint_outermost(out, tint)
	for piece: Piece in out.pieces:
		out.bits |= (parts.get(piece.part, {}) as Dictionary).get("bits", 0) as int
	return out


## Swaps belts for their outer versions over armour and coats, and drops a skirt hidden under a longer one further out.
static func _settle(out: Dressing, parts: Dictionary, manifest: Dictionary) -> void:
	var belted_over: Array = manifest.get("belted_over", []) as Array
	var over_versions: Dictionary = manifest.get("over_versions", {}) as Dictionary
	var over: bool = false
	for piece: Piece in out.pieces:
		over = over or belted_over.has(piece.part)
	var kept: Array[Piece] = []
	var seen: Dictionary[String, Piece] = {}
	for piece: Piece in out.pieces:
		if over and over_versions.has(piece.part):
			piece.part = over_versions[piece.part] as String
		var skirt: Dictionary = (parts.get(piece.part, {}) as Dictionary).get("skirt", {}) as Dictionary
		var covered: bool = false
		if not skirt.is_empty():
			for other: Piece in out.pieces:
				var outer: Dictionary = (parts.get(other.part, {}) as Dictionary).get("skirt", {}) as Dictionary
				if outer.is_empty() or other == piece:
					continue
				if (outer["offset"] as float) > (skirt["offset"] as float) and (outer["hem"] as float) <= (skirt["hem"] as float) + 0.05:
					covered = true
		if covered:
			continue
		# The same mesh twice, as when two looks share sleeves, is drawn once, as the outer one has it.
		if seen.has(piece.part):
			var first: Piece = seen[piece.part]
			if piece.layer > first.layer:
				kept[kept.find(first)] = piece
				seen[piece.part] = piece
			continue
		seen[piece.part] = piece
		kept.append(piece)
	out.pieces = kept


static func _tint_outermost(out: Dressing, tint: Color) -> void:
	var top: int = -1
	for piece: Piece in out.pieces:
		if piece.dyeable and TINTED_PARTS.has(piece.part):
			top = maxi(top, piece.layer)
	for piece: Piece in out.pieces:
		if piece.dyeable and piece.layer == top and TINTED_PARTS.has(piece.part):
			piece.color = tint


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


## The garment worn under this id, or null for an id that is not one.
static func garment(id: StringName) -> ArmourDef:
	if not _garment_defs.has(id):
		var path: String = GARMENT_DEFS % String(id)
		_garment_defs[id] = load(path) as ArmourDef if ResourceLoader.exists(path) else null
	return _garment_defs[id]


## What someone with this gear wears, for BodyView.make. seed picks among each garment's dyes, so two people in the
## same clothes need not match; give the wearer's id. Without one, the same clothes always come out the same colour.
static func worn_for(equipment: EquipmentData, seed: int = -1) -> Array[String]:
	var worn: Array[String] = []
	var dye_seed: int = seed if seed >= 0 else hash(equipment.armour_ids)
	var dressed_under: bool = false
	for armour_id: StringName in equipment.armour_ids:
		var def: GarmentDef = garment(armour_id) as GarmentDef
		if def == null or def.model.is_empty():
			continue
		dressed_under = dressed_under or def.slot == &"underwear_bottom"
		worn.append(def.model + _dye_of(def, dye_seed))
	if not dressed_under:
		worn.push_front(SMALLCLOTHES)
	if WEAPON_PARTS.has(equipment.weapon_id):
		worn.append(WEAPON_PARTS[equipment.weapon_id])
	if equipment.has_shield:
		worn.append("shield")
	if dressing(worn).hides_hair:
		worn.append(HIDES_HAIR)
	return worn


## A garment's dye, after the mark, worn and faded the cheaper it is. Nothing for undyed stuff.
static func _dye_of(def: GarmentDef, dye_seed: int) -> String:
	if def.colors.is_empty():
		return ""
	var color: Color = def.colors[absi(hash([dye_seed, def.id])) % def.colors.size()]
	var wear: float = MOST_WEAR * clampf(1.0 - float(def.value) / WEAR_FREE_VALUE, 0.0, 1.0)
	color = color.lerp(WORN_COLOR, 0.35 * wear).darkened(0.12 * wear)
	return DYE_MARK + color.to_html(false)


## Each body hides what its garments cover. The head reads the same.
static func _cover_bits(worn: Array[String]) -> int:
	return dressing(worn).bits


static func _garment_material(kind: String, color: Color, bits: int, part_name: String) -> ShaderMaterial:
	var badge: bool = part_name.begins_with("surcoat")
	var key: String = "%s|%s|%d|%s" % [kind, color.to_html(false), bits, badge]
	if _materials.has(key):
		return _materials[key]
	var spec: Array = KINDS.get(kind, KINDS["cloth"])
	var material: ShaderMaterial = _tiled(spec[0] as String, color, spec[1] as float, spec[2] as float, spec[3] as float, spec[4] as float)
	material.set_shader_parameter(&"badge", badge)
	material.set_shader_parameter(&"hidden_bits", 0 if badge else bits)
	_materials[key] = material
	return material


static func _hair_cap(color: Color) -> ShaderMaterial:
	var material: ShaderMaterial = _tiled("", Color(0.09, 0.07, 0.05), 1.0, 0.0, 0.9, 0.0)
	material.set_shader_parameter(&"color", color)
	return material


static func _tiled(kind: String, color: Color, tile_metres: float, metal: float, rough: float, normal_strength: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(GEAR_SHADER) as Shader
	if not kind.is_empty():
		material.set_shader_parameter(&"albedo_map", load(TEXTURES % [kind, "albedo"]) as Texture2D)
		material.set_shader_parameter(&"normal_map", load(TEXTURES % [kind, "normal"]) as Texture2D)
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"tile", 1.0 / tile_metres)
	material.set_shader_parameter(&"metal", metal)
	material.set_shader_parameter(&"rough", rough)
	material.set_shader_parameter(&"normal_strength", normal_strength)
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


## The garment build's manifest, and one copy of every garment mesh to make worn ones from.
static func _garments() -> Dictionary:
	if _garment_manifest.is_empty():
		_garment_manifest = JSON.parse_string(FileAccess.get_file_as_string(GARMENT_MANIFEST)) as Dictionary
	return _garment_manifest


static func _load_garment_meshes() -> void:
	if not _garment_meshes.is_empty():
		return
	var source: Node3D = (load(GARMENT_SCENE) as PackedScene).instantiate() as Node3D
	for part: Node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		_garment_meshes[String(mesh.name)] = mesh.mesh as ArrayMesh
		_garment_skins[String(mesh.name)] = mesh.skin
	source.free()


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
