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
## What forms with a body of their own wear, built on their shells, with its own manifest of looks.
const FORM_GEAR_SCENE: String = "res://assets/models/kheth_gear.glb"
const FORM_GEAR_MANIFEST: String = "res://assets/models/kheth_gear_manifest.json"
## A form's own look standing in for the human garment in each slot, so a kheth soldier in a man's kit still shows armour.
const FORM_STANDINS: Dictionary[StringName, Dictionary] = {
	&"kheth": {&"body_armour": "kheth_plates", &"head_armour": "kheth_crest", &"cloak": "kheth_mantle", &"belt": "kheth_belt", &"hands": "kheth_bracers",
			&"over": "kheth_harness", &"underwear_bottom": "kheth_sash"},
}
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
## After the dye, how a garment has been kept: wear and grime digits 0 to 9, then a colon and a trim colour, as
## "tunic@7a3020~42" or "fine_gown@58060a~10:d4a845".
const FINISH_MARK: String = "~"
## What is worn when a realm's arms go on a surcoat and the shield: "arms@field:charge colour:charge", from arms_of.
const ARMS: String = "arms"
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
## How each kind of stuff is drawn: texture, metres one tile covers, metal, roughness, normal strength, family (as
## gear.gdshader counts them) and sheen. No texture is plain colour.
const KINDS: Dictionary[String, Array] = {
	"linen": ["cloth", 0.06, 0.0, 0.92, 0.5, 0, 0.15], "underlinen": ["linen", 0.06, 0.0, 0.9, 0.5, 0, 0.1], "fine_linen": ["linen", 0.045, 0.0, 0.8, 0.3, 0, 0.12],
	"cloth": ["cloth", 0.07, 0.0, 0.88, 0.6, 0, 0.25], "wool": ["wool", 0.085, 0.0, 0.96, 0.75, 0, 0.38],
	"silk": ["cloth", 0.045, 0.0, 0.42, 0.2, 0, 0.6], "velvet": ["felt", 0.1, 0.0, 0.85, 0.35, 0, 1.0], "quilt": ["quilt", 0.3, 0.0, 0.9, 1.0, 0, 0.22],
	"felt": ["felt", 0.15, 0.0, 0.97, 0.5, 0, 0.3], "net": ["cloth", 0.06, 0.0, 0.9, 0.4, 7, 0.1],
	"fur": ["fur", 0.16, 0.0, 1.0, 1.0, 4, 0.8], "leather": ["leather", 0.22, 0.0, 0.68, 0.8, 1, 0.08], "leather_dark": ["leather", 0.22, 0.0, 0.62, 0.8, 1, 0.08],
	"suede": ["leather", 0.3, 0.0, 0.88, 0.5, 1, 0.25], "mail": ["mail", 0.06, 0.82, 0.5, 1.0, 3, 0.0], "scale": ["scale", 0.12, 0.75, 0.42, 1.0, 3, 0.0],
	"lamellar": ["lamellar", 0.24, 0.45, 0.55, 1.0, 3, 0.0], "plate": ["plate", 0.5, 0.9, 0.3, 0.4, 2, 0.0], "steel": ["plate", 0.5, 0.9, 0.28, 0.4, 2, 0.0],
	"brigandine": ["brigandine", 0.2, 0.15, 0.85, 1.0, 6, 0.25], "plates": ["plates", 0.36, 0.1, 0.8, 1.0, 6, 0.25], "straw": ["straw", 0.12, 0.0, 0.92, 1.0, 5, 0.1],
	"iron": ["plate", 0.5, 0.85, 0.45, 0.6, 2, 0.0], "bronze": ["plate", 0.5, 0.95, 0.35, 0.4, 2, 0.0], "brass": ["", 1.0, 0.95, 0.32, 0.0, 2, 0.0],
	"gold": ["", 1.0, 1.0, 0.25, 0.0, 2, 0.0], "shell": ["scale", 0.05, 0.0, 0.3, 0.5, 2, 0.0], "bone": ["leather", 0.1, 0.0, 0.55, 0.3, 1, 0.0],
	"chitin": ["plate", 0.3, 0.2, 0.3, 0.6, 2, 0.0], "wood": ["leather", 0.3, 0.0, 0.7, 0.8, 1, 0.0],
}
## How deep cloth folds hang on parts, by the start of their names. Others hang plain.
const FOLDS: Array = [
	[["skirt", "kilt", "gown", "robe", "kaftan", "coat_", "wrap_", "shift_skirt", "sark_skirt", "tabard"], 1.0], [["cloak", "mantle", "cape"], 0.8],
	[["shirt", "over_long", "padded", "tunic_short", "shift", "jack"], 0.35], [["trousers", "hose", "hood", "cowl", "sleeve"], 0.3],
]
## Plate on limbs is lames this many metres long.
const LAMES: Dictionary[String, float] = {
	"plate_arms": 0.055, "plate_legs": 0.07, "tassets_l": 0.05, "tassets_r": 0.05, "gauntlet": 0.022, "sabaton": 0.02, "gorget": 0.03, "fauld": 0.045,
}
## A garment worth this much or more has an embroidered band round its edges.
const TRIM_VALUE: int = 30
## Thread for trims: gold on the dearest, else silver or a dark contrasting band.
const GOLD_THREAD: Color = Color(0.82, 0.62, 0.24)
const SILVER_THREAD: Color = Color(0.78, 0.78, 0.74)
## How dirty people of each wealth look, from bonded to noble (Outfits tiers).
const GRIME_BY_TIER: Array[float] = [0.75, 0.55, 0.35, 0.18, 0.08]
const SHIELD_SHADER: String = "res://src/view/face/shield_paint.gdshader"
## The painted face laid over a shield bearing arms.
const SHIELD_PAINT: String = "shield_paint"
## How worn and faded a garment looks at a value of nothing. Dear clothes look new.
const MOST_WEAR: float = 0.45
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
	## 0 to 1: frayed, patched and stained, or rusting.
	var wear: float = 0.2
	var grime: float = 0.25
	## Transparent for none.
	var trim: Color = NO_TINT
	## Paints the realm's charge on it.
	var arms: bool = false


## A realm's arms as a body wears them.
class Arms:
	extends RefCounted
	var field: Color = Color.WHITE
	var metal: Color = Color.WHITE
	var charge: int = 0


## Everything a list of what is worn comes to.
class Dressing:
	extends RefCounted
	var pieces: Array[Piece] = []
	## Weapons and the shield, from the body model.
	var held: Array[String] = []
	## Bits of all the garments worn, for hiding what they cover.
	var bits: int = 0
	var hides_hair: bool = false
	## The realm's arms, or null.
	var arms: Arms = null


static var _joints: Dictionary = {}
static var _clip_speeds: Dictionary = {}
static var _base_rest: Dictionary[StringName, Transform3D] = {}
static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _garment_manifest: Dictionary = {}
## One copy of each garment's mesh and skin, by name, to make worn ones from.
static var _garment_meshes: Dictionary[String, ArrayMesh] = {}
static var _garment_skins: Dictionary[String, Skin] = {}
static var _garment_defs: Dictionary[StringName, ArmourDef] = {}
## The painted face of a shield, made once from the shield's shape.
static var _shield_mesh: ArrayMesh = null
## Look -> the slot a garment drawn as it is worn in.
static var _look_slots: Dictionary[String, StringName] = {}


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
	var dress: Dressing = dressing(worn, tint, face.form if own_body else &"")
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
	_show_garments(model, skeleton, weights, dress.pieces, crowd, 0 if own_body else dress.bits, dress.arms)
	_paint_shield(model, skeleton, dress.arms if dress.held.has("shield") else null)


## Dresses a body made by make in something else, in place: garments come and go, and the skin and head hide what
## the new clothes cover and show what the old ones did. head is the body's head from FaceView.attach, or null.
static func redress(model: Node3D, face: FaceData, male: bool, age: float, worn: Array[String], head: Node3D = null, tint: Color = NO_TINT) -> void:
	var own_body: bool = has_own_body(face)
	var bits: int = 0 if own_body else dressing(worn, tint).bits
	model.set_meta(COVER_META, bits)
	show_detail(model, face, male, age, worn, false, tint)
	for part: Variant in model.get_meta(BODY_MESHES_META, []) as Array:
		var mesh: MeshInstance3D = part as MeshInstance3D
		if mesh.visible and mesh.material_override is ShaderMaterial and BODY_PARTS.has(String(mesh.name)):
			(mesh.material_override as ShaderMaterial).set_shader_parameter(&"hidden_bits", bits)
	if head == null or own_body:
		return
	FaceView.dress(head, face, male, age)
	for part: Node in head.find_children("skin", "MeshInstance3D", true, false):
		((part as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter(&"hidden_bits", bits)
	if hides_hair(worn):
		FaceView.hide_hair(head)


## Makes, shows and hides the garment meshes. Those not worn are hidden, not freed, so a body switching to crowd
## detail and back keeps what it was fitted with.
static func _show_garments(model: Node3D, skeleton: Skeleton3D, weights: Dictionary[StringName, float], pieces: Array[Piece], crowd: bool, bits: int,
		arms: Arms = null) -> void:
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
		mesh.material_override = _garment_material(piece, bits, arms)


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
## form, for a body of its own, wears its form's own looks and stands them in for human ones slot by slot; a human
## body never wears a form's looks.
static func dressing(worn: Array[String], tint: Color = NO_TINT, form: StringName = &"") -> Dressing:
	var out: Dressing = Dressing.new()
	var manifest: Dictionary = _garments()
	var looks: Dictionary = manifest["looks"] as Dictionary
	var parts: Dictionary = manifest["parts"] as Dictionary
	var weapons: Array[String] = []
	weapons.assign(WEAPON_PARTS.values())
	var worn_looks: Dictionary[String, bool] = {}
	# A form's own looks first, so they win over a human garment standing in for the same slot.
	var ordered: Array[String] = []
	for entry: String in worn:
		if form != &"" and entry.begins_with("%s_" % form):
			ordered.push_front(entry)
		else:
			ordered.append(entry)
	for entry: String in ordered:
		var look_name: String = entry.get_slice(DYE_MARK, 0)
		if look_name == ARMS:
			out.arms = _read_arms(entry)
			continue
		if weapons.has(look_name) or look_name == "shield":
			out.held.append(look_name)
			continue
		var own_look: bool = look_name.begins_with("%s_" % form) if form != &"" else _is_form_look(look_name)
		if form != &"" and not own_look:
			look_name = (FORM_STANDINS.get(form, {}) as Dictionary).get(_slot_of_look(look_name), "") as String
			if worn_looks.has(look_name):
				continue
		elif form == &"" and own_look:
			continue
		if not looks.has(look_name):
			continue
		worn_looks[look_name] = true
		var look: Dictionary = looks[look_name] as Dictionary
		var after: String = entry.get_slice(DYE_MARK, 1) if entry.contains(DYE_MARK) else ""
		var dye_code: String = after.get_slice(FINISH_MARK, 0)
		var dye: Color = Color.html(dye_code) if dye_code.length() == 6 else NO_TINT
		var finish: String = after.get_slice(FINISH_MARK, 1) if after.contains(FINISH_MARK) else ""
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
			_read_finish(piece, finish)
			out.pieces.append(piece)
	_settle(out, parts, manifest)
	if out.arms != null:
		_wear_arms(out)
	elif tint.a > 0.0:
		_tint_outermost(out, tint)
	for piece: Piece in out.pieces:
		out.bits |= (parts.get(piece.part, {}) as Dictionary).get("bits", 0) as int
	return out


## Reads "42" or "42:d4a845" after the finish mark into a piece. Trims go only on what has a dye of its own.
static func _read_finish(piece: Piece, finish: String) -> void:
	if finish.length() < 2:
		return
	piece.wear = float(finish.unicode_at(0) - 48) / 9.0
	piece.grime = float(finish.unicode_at(1) - 48) / 9.0
	var trim_code: String = finish.get_slice(":", 1) if finish.contains(":") else ""
	if trim_code.length() == 6 and piece.dyeable:
		piece.trim = Color.html(trim_code)


## The worn entry for a realm's arms, or nothing for no realm. Add it to what a soldier wears.
static func arms_of(f: FactionData) -> String:
	if f == null:
		return ""
	return "%s%s%s:%s:%d" % [ARMS, DYE_MARK, Heraldry.field(f).to_html(false), Heraldry.charge_color(f).to_html(false), int(Heraldry.charge(f))]


static func _read_arms(entry: String) -> Arms:
	var code: String = entry.get_slice(DYE_MARK, 1)
	var arms: Arms = Arms.new()
	arms.field = Color.html(code.get_slice(":", 0))
	arms.metal = Color.html(code.get_slice(":", 1))
	arms.charge = code.get_slice(":", 2).to_int()
	return arms


## The realm's field on the outermost dyed coat, and its charge on a surcoat.
static func _wear_arms(out: Dressing) -> void:
	_tint_outermost(out, out.arms.field)
	for piece: Piece in out.pieces:
		if piece.part.begins_with("surcoat") or piece.part.begins_with("tabard"):
			piece.color = out.arms.field
			piece.arms = true


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
## realm, when given, puts its arms on a surcoat and the shield; give a soldier's realm. tier, when given, is how well
## off they are (Outfits tiers): the poor go dirtier and more worn, the rich clean.
static func worn_for(equipment: EquipmentData, seed: int = -1, realm: FactionData = null, tier: int = -1) -> Array[String]:
	var worn: Array[String] = []
	var dye_seed: int = seed if seed >= 0 else hash(equipment.armour_ids)
	var dressed_under: bool = false
	for armour_id: StringName in equipment.armour_ids:
		var def: GarmentDef = garment(armour_id) as GarmentDef
		if def == null or def.model.is_empty():
			continue
		dressed_under = dressed_under or def.slot == &"underwear_bottom"
		worn.append(def.model + _dye_of(def, dye_seed, tier))
	if not dressed_under:
		worn.push_front(SMALLCLOTHES)
	if WEAPON_PARTS.has(equipment.weapon_id):
		worn.append(WEAPON_PARTS[equipment.weapon_id])
	if equipment.has_shield:
		worn.append("shield")
	var arms: String = arms_of(realm)
	if not arms.is_empty():
		worn.append(arms)
	if dressing(worn).hides_hair:
		worn.append(HIDES_HAIR)
	return worn


## A garment's dye and finish, after the marks: worn, faded and dirty the cheaper it is and the poorer the wearer,
## with an embroidered band when dear. Undyed stuff takes only the finish.
static func _dye_of(def: GarmentDef, dye_seed: int, tier: int = -1) -> String:
	var cheap: float = clampf(1.0 - float(def.value) / WEAR_FREE_VALUE, 0.0, 1.0)
	var wear: float = MOST_WEAR * cheap
	var grime: float = lerpf(0.15, 0.5, cheap)
	if tier >= 0:
		var t: int = clampi(tier, 0, GRIME_BY_TIER.size() - 1)
		grime = GRIME_BY_TIER[t]
		wear = clampf(wear + (0.35 - 0.12 * float(t)), 0.0, 1.0)
	# Each garment wears its own way, a little.
	wear = clampf(wear + (float(absi(hash([dye_seed, def.id, 1])) % 100) / 100.0 - 0.5) * 0.25, 0.0, 1.0)
	var code: String = ""
	if not def.colors.is_empty():
		var color: Color = def.colors[absi(hash([dye_seed, def.id])) % def.colors.size()]
		color = color.lerp(WORN_COLOR, 0.3 * wear).darkened(0.1 * wear)
		code = color.to_html(false)
	var finish: String = "%d%d" % [clampi(roundi(wear * 9.0), 0, 9), clampi(roundi(grime * 9.0), 0, 9)]
	var under: bool = def.slot == &"underwear_top" or def.slot == &"underwear_bottom"
	if def.value >= TRIM_VALUE and not under:
		var thread: Color = GOLD_THREAD if def.value >= 50 else SILVER_THREAD
		if def.value < 50 and absi(hash([dye_seed, def.id, 2])) % 2 == 0 and not def.colors.is_empty():
			# A band in another of the garment's dyes, darkened.
			thread = def.colors[absi(hash([dye_seed, def.id, 3])) % def.colors.size()].darkened(0.35)
		finish += ":" + thread.to_html(false)
	return DYE_MARK + code + FINISH_MARK + finish


## Each body hides what its garments cover. The head reads the same.
static func _cover_bits(worn: Array[String]) -> int:
	return dressing(worn).bits


static func _garment_material(piece: Piece, bits: int, arms: Arms) -> ShaderMaterial:
	var painted: bool = piece.arms and arms != null
	var folds: float = _folds_of(piece.part)
	var lames: float = LAMES.get(piece.part, 0.0)
	var key: String = "%s|%s|%d|%d|%d|%s|%.2f|%.2f|%s" % [piece.kind, piece.color.to_html(false), bits, roundi(piece.wear * 9.0), roundi(piece.grime * 9.0),
			piece.trim.to_html(), folds, lames, "%s%d" % [arms.metal.to_html(false), arms.charge] if painted else "-"]
	if _materials.has(key):
		return _materials[key]
	var spec: Array = KINDS.get(piece.kind, KINDS["cloth"])
	var material: ShaderMaterial = _tiled(spec[0] as String, piece.color, spec[1] as float, spec[2] as float, spec[3] as float, spec[4] as float)
	material.set_shader_parameter(&"family", spec[5] as int)
	material.set_shader_parameter(&"sheen", spec[6] as float)
	material.set_shader_parameter(&"wear", piece.wear)
	material.set_shader_parameter(&"grime", piece.grime)
	material.set_shader_parameter(&"trim", 1.0 if piece.trim.a > 0.0 else 0.0)
	if piece.trim.a > 0.0:
		material.set_shader_parameter(&"trim_color", piece.trim)
	material.set_shader_parameter(&"folds", folds)
	material.set_shader_parameter(&"lames", lames)
	material.set_shader_parameter(&"arms", painted)
	if painted:
		material.set_shader_parameter(&"charge_color", arms.metal)
		material.set_shader_parameter(&"charge", arms.charge)
	material.set_shader_parameter(&"hidden_bits", 0 if painted else bits)
	_materials[key] = material
	return material


static func _folds_of(part: String) -> float:
	for row: Variant in FOLDS:
		var prefixes: Array = (row as Array)[0] as Array
		for prefix: Variant in prefixes:
			if part.begins_with(prefix as String) or part.contains("_" + (prefix as String)):
				return (row as Array)[1] as float
	return 0.0


static func _hair_cap(color: Color) -> ShaderMaterial:
	var material: ShaderMaterial = _tiled("", Color(0.09, 0.07, 0.05), 1.0, 0.0, 0.9, 0.0)
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"folds", 0.0)
	material.set_shader_parameter(&"sheen", 0.4)
	material.set_shader_parameter(&"seam_line", 0.0)
	material.set_shader_parameter(&"grime", 0.0)
	material.set_shader_parameter(&"wear", 0.0)
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


## Lays the realm's arms over the face of the shield, as a disc riding on the same bone, or takes them off.
static func _paint_shield(model: Node3D, skeleton: Skeleton3D, arms: Arms) -> void:
	var paint: MeshInstance3D = model.get_meta(SHIELD_PAINT) as MeshInstance3D if model.has_meta(SHIELD_PAINT) else null
	if arms == null:
		if paint != null:
			paint.visible = false
		return
	if paint == null:
		var shield: MeshInstance3D = null
		for part: Variant in model.get_meta(BODY_MESHES_META, []) as Array:
			if String((part as MeshInstance3D).name) == "shield":
				shield = part as MeshInstance3D
		if shield == null:
			return
		paint = _shield_disc(shield)
		if paint == null:
			return
		# Under the shield, so it goes when the shield is hidden or let fall.
		shield.add_child(paint)
		paint.skeleton = paint.get_path_to(skeleton)
		model.set_meta(SHIELD_PAINT, paint)
	paint.visible = true
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHIELD_SHADER) as Shader
	material.set_shader_parameter(&"field", arms.field)
	material.set_shader_parameter(&"metal", arms.metal)
	material.set_shader_parameter(&"charge", arms.charge)
	paint.material_override = material


## A disc just proud of the shield's painted face, found from the shield's own rest shape: its flattest axis is the
## way it faces, the boss standing out in front, and up on it is the way up the body.
static func _shield_disc(shield: MeshInstance3D) -> MeshInstance3D:
	var source: ArrayMesh = shield.mesh as ArrayMesh
	if _shield_mesh == null:
		var wood: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var iron: PackedVector3Array = source.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] if source.get_surface_count() > 1 else PackedVector3Array()
		var centre: Vector3 = Vector3.ZERO
		for v: Vector3 in wood:
			centre += v
		centre /= float(maxi(wood.size(), 1))
		var spread: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		for v: Vector3 in wood:
			var d: Vector3 = v - centre
			spread.x += d * d.x
			spread.y += d * d.y
			spread.z += d * d.z
		var facing: Vector3 = _flattest(spread)
		var ahead: Vector3 = Vector3.ZERO
		for v: Vector3 in iron:
			ahead += v - centre
		if ahead.dot(facing) < 0.0:
			facing = -facing
		var front: float = -INF
		var radius: float = 0.0
		for v: Vector3 in wood:
			front = maxf(front, (v - centre).dot(facing))
			var flat: Vector3 = (v - centre) - facing * (v - centre).dot(facing)
			radius = maxf(radius, flat.length())
		var up: Vector3 = (Vector3.UP - facing * Vector3.UP.dot(facing)).normalized()
		var across: Vector3 = up.cross(facing).normalized()
		var middle: Vector3 = centre + facing * (front + 0.004)
		var bone: int = 0
		var skin: Skin = shield.skin
		for b: int in range(skin.get_bind_count()):
			if String(skin.get_bind_name(b)) == "lowerarm_l":
				bone = b
		_shield_mesh = _disc_mesh(middle, across, up, facing, radius * 0.93, bone)
	var paint: MeshInstance3D = MeshInstance3D.new()
	paint.name = SHIELD_PAINT
	paint.mesh = _shield_mesh
	paint.skin = shield.skin
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return paint


## The axis a cloud of points spreads least along, from its spread matrix, by a few turns of inverse iteration.
static func _flattest(spread: Basis) -> Vector3:
	var guess: Vector3 = Vector3(1.0, 0.3, 0.2).normalized()
	var shifted: Basis = spread
	if absf(shifted.determinant()) < 1e-9:
		shifted = Basis(spread.x + Vector3(1e-5, 0.0, 0.0), spread.y + Vector3(0.0, 1e-5, 0.0), spread.z + Vector3(0.0, 0.0, 1e-5))
	var inverse: Basis = shifted.inverse()
	for i: int in range(24):
		guess = (inverse * guess).normalized()
	return guess


static func _disc_mesh(middle: Vector3, across: Vector3, up: Vector3, facing: Vector3, radius: float, bone: int) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var bones: PackedInt32Array = PackedInt32Array()
	var weights: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var rings: int = 6
	var sides: int = 36
	for r: int in range(rings + 1):
		var share: float = float(r) / float(rings)
		for s: int in range(sides):
			var angle: float = TAU * float(s) / float(sides)
			var flat: Vector2 = Vector2(cos(angle), sin(angle)) * radius * share
			# Domed a little, as the boards are.
			var rise: float = (1.0 - share * share) * 0.006
			verts.append(middle + across * flat.x + up * flat.y + facing * rise)
			normals.append(facing)
			uvs.append(flat / radius)
			bones.append_array([bone, 0, 0, 0])
			weights.append_array([1.0, 0.0, 0.0, 0.0])
	for r: int in range(rings):
		for s: int in range(sides):
			var a: int = r * sides + s
			var b: int = r * sides + (s + 1) % sides
			var c: int = (r + 1) * sides + (s + 1) % sides
			var d: int = (r + 1) * sides + s
			indices.append_array([a, b, c, a, c, d])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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


## The garment build's manifest, with the looks and parts of the forms' own gear added in.
static func _garments() -> Dictionary:
	if _garment_manifest.is_empty():
		_garment_manifest = JSON.parse_string(FileAccess.get_file_as_string(GARMENT_MANIFEST)) as Dictionary
		if FileAccess.file_exists(FORM_GEAR_MANIFEST):
			var own: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FORM_GEAR_MANIFEST)) as Dictionary
			(_garment_manifest["looks"] as Dictionary).merge(own.get("looks", {}) as Dictionary)
			(_garment_manifest["parts"] as Dictionary).merge(own.get("parts", {}) as Dictionary)
	return _garment_manifest


## One copy of every garment mesh to make worn ones from, human and the forms' own.
static func _load_garment_meshes() -> void:
	if not _garment_meshes.is_empty():
		return
	for path: String in [GARMENT_SCENE, FORM_GEAR_SCENE]:
		if not ResourceLoader.exists(path):
			continue
		var source: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		for part: Node in source.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = part as MeshInstance3D
			_garment_meshes[String(mesh.name)] = mesh.mesh as ArrayMesh
			_garment_skins[String(mesh.name)] = mesh.skin
		source.free()


## Whether a look is one of a form's own, for a body of its own.
static func _is_form_look(look: String) -> bool:
	for form: StringName in FORM_BODIES:
		if look.begins_with("%s_" % form):
			return true
	return false


## The slot a look is worn in, from the garments drawn as it. Empty for a look no garment uses.
static func _slot_of_look(look: String) -> StringName:
	if _look_slots.is_empty():
		var folder: String = GARMENT_DEFS.get_base_dir()
		for file_name: String in ResourceLoader.list_directory(folder):
			if not file_name.ends_with(".tres"):
				continue
			var def: GarmentDef = garment(StringName(file_name.get_basename())) as GarmentDef
			if def != null and not def.model.is_empty() and not _look_slots.has(def.model):
				_look_slots[def.model] = def.slot
	return _look_slots.get(look, &"")


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
