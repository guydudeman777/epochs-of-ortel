class_name FaceView
extends RefCounted
## Puts a person's head on a soldier model, dresses it from their FaceData and sets expressions.
## It reads faces and never changes them.

const HEAD_SCENE: String = "res://assets/models/head_mh.glb"
const GROWN_HAIR_SCENE: String = "res://assets/models/hair_gen.glb"
const MANIFEST: String = "res://assets/models/head_mh_manifest.json"
const HAIR_SHADER: String = "res://src/view/face/hair_tinted.gdshader"
const SKIN_SHADER: String = "res://src/view/face/skin.gdshader"
const STRAND_DETAIL: String = "res://assets/textures/mh/hair_detail.png"
const SCALE_MAP: String = "res://assets/textures/mh/scales.png"
const SEXES: Array[String] = ["female", "male"]
const RACES: Array[String] = ["african", "asian", "caucasian"]
const HAIR_TONES: Array[Color] = [
	Color(0.035, 0.03, 0.027), Color(0.085, 0.06, 0.045), Color(0.17, 0.11, 0.07),
	Color(0.29, 0.19, 0.1), Color(0.3, 0.13, 0.06), Color(0.47, 0.36, 0.22),
]
const SHELL_SHADER: String = "res://src/view/face/hair_shell.gdshader"
const UNDERCAP: String = "hair_undercap"
const UNDERCAP_FULL: String = "hair_undercap_full"
## Styles with their own solid layer, or a bare crown, so nothing goes under them.
const NO_UNDERCAP: Array[StringName] = [&"balding", &"coils", &"coils_short", &"shoulder_back"]
## Styles with gaps low on the head that also reach below the hairline all round, so a whole cap stays hidden.
const COVERS_SCALP: Array[StringName] = [&"elvs_hazel_hair"]
## A mesh named "feat_name" is drawn when a face lists that feature.
const FEATURE_MARK: String = "feat_"
## How strongly each form's skin shows scales.
const SCALED_FORMS: Dictionary[StringName, float] = {&"merrow": 1.0}
## Forms with a fish's eyes: wet and black all over, with no lashes.
const FISH_EYED_FORMS: Array[StringName] = [&"merrow"]
const FISH_EYE_SHADER: String = "res://src/view/face/fish_eye.gdshader"
const FIN_SHADER: String = "res://src/view/face/fin.gdshader"
## About the colour of the skin textures, so a fin's root matches the tinted skin it grows from.
const FIN_SKIN: Color = Color(0.85, 0.68, 0.58)
## Shell and horn, darker and glossier than the skin it grows from.
const CHITIN_PARTS: Array[String] = ["antennae", "mandibles", "plates"]
## A mesh named "hair_style__piece" is one more piece of that style.
const PIECE_MARK: String = "__"
const YOUNG_LIMIT: float = 0.3
const MIDDLE_LIMIT: float = 0.65
## MakeHuman's neutral face stares with the brows pressed low. These relax everyone a little.
const RESTING_UNITS: Dictionary[StringName, float] = {
	&"eye-left-slit": 0.14, &"eye-right-slit": 0.14, &"eyebrows-left-inner-up": 0.32, &"eyebrows-right-inner-up": 0.32,
}
const NEUTRAL: Dictionary[StringName, float] = {}
const HAPPY: Dictionary[StringName, float] = {
	&"mouth-corner-puller": 0.8, &"eye-left-slit": 0.28, &"eye-right-slit": 0.28, &"eyebrows-left-inner-up": 0.2, &"eyebrows-right-inner-up": 0.2,
}
const LAUGHING: Dictionary[StringName, float] = {
	&"mouth-corner-puller": 0.95, &"mouth-open": 0.32, &"mouth-retraction": 0.3, &"eye-left-slit": 0.42, &"eye-right-slit": 0.42,
}
const ANGRY: Dictionary[StringName, float] = {
	&"eyebrows-left-down": 1.5, &"eyebrows-right-down": 1.5, &"eye-left-slit": 0.45, &"eye-right-slit": 0.45,
	&"nose-compression": 0.9, &"mouth-compression": 0.8, &"mouth-depression": 0.35,
}
const SAD: Dictionary[StringName, float] = {
	&"eyebrows-left-inner-up": 1.0, &"eyebrows-right-inner-up": 1.0, &"mouth-depression": 0.65, &"eye-left-slit": 0.2, &"eye-right-slit": 0.2,
}
const SHOCKED: Dictionary[StringName, float] = {
	&"eyebrows-left-up": 0.9, &"eyebrows-right-up": 0.9, &"eye-left-opened-up": 0.7, &"eye-right-opened-up": 0.7, &"mouth-open": 0.62,
}

static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary
	return _manifest


## The skin of this person's sex nearest their heritage and age, picked by their skin variant.
static func skin_for(face: FaceData, male: bool, age: float) -> String:
	var skins: Dictionary = manifest()["skins"] as Dictionary
	var sex: String = "male" if male else "female"
	var dominant: String = String(dominant_population(face))
	var bucket: String = "young" if age < YOUNG_LIMIT else ("middle" if age < MIDDLE_LIMIT else "old")
	var best_score: int = -1
	var best: Array[String] = []
	var names: Array = skins.keys()
	names.sort()
	for skin_name: String in names:
		var info: Dictionary = skins[skin_name] as Dictionary
		var info_sex: String = info["sex"]
		var info_race: String = info["race"]
		var info_age: String = info["age"]
		if info_sex != sex:
			continue
		var score: int = (2 if info_race == dominant else 0) + (1 if info_age == bucket else 0)
		if score > best_score:
			best_score = score
			best = []
		if score == best_score:
			best.append(skin_name)
	return best[face.skin_variant % best.size()]


static func dominant_population(face: FaceData) -> StringName:
	var best: StringName = &"caucasian"
	var best_share: float = -1.0
	for population: StringName in FaceService.POPULATIONS:
		var share: float = face.heritage.get(population, 0.0)
		if share > best_share:
			best = population
			best_share = share
	return best


## Gives a body from BodyView this person's head. The head's meshes are skinned to the body's skeleton,
## so the neck bends with the body.
static func attach(body: Node3D, face: FaceData, male: bool, age: float) -> Node3D:
	# A form with a body of its own has its head on already, as part of its shell. What comes back stands in for a
	# head with nothing in it, so a caller hiding the head of someone far off does not hide the whole shell.
	if BodyView.has_own_body(face):
		return BodyView.form_head(body)
	var skeleton: Skeleton3D = ViewUtil.find_skeleton(body)
	var head: Node3D = (load(HEAD_SCENE) as PackedScene).instantiate() as Node3D
	skeleton.add_child(head)
	head.add_child((load(GROWN_HAIR_SCENE) as PackedScene).instantiate() as Node3D)
	dress(head, face, male, age)
	for part: Node in head.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		# A style a person does not wear never needs fitting to them.
		if not mesh.visible:
			continue
		mesh.skeleton = mesh.get_path_to(skeleton)
		BodyView.refit_skin(mesh, skeleton)
		if String(mesh.name) == "skin":
			# The body's clothes cover the head model's lower edge, so it follows the same rule.
			(mesh.material_override as ShaderMaterial).set_shader_parameter(&"hidden_bits", body.get_meta(BodyView.COVER_META, 0) as int)
	return head


## For a helmet, which the hair would poke through.
static func hide_hair(head: Node3D) -> void:
	for part: Node in head.find_children("hair_*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).visible = false


static func dress(head: Node3D, face: FaceData, male: bool, age: float) -> void:
	var weights: Dictionary[StringName, float] = shape_weights(face, male, age)
	for part: Node in head.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		var part_name: String = String(mesh.name)
		mesh.visible = _part_visible(part_name, face)
		if not mesh.visible:
			continue
		mesh.material_override = _material_for(part_name, face, male, age)
		var array_mesh: ArrayMesh = mesh.mesh as ArrayMesh
		for i: int in range(array_mesh.get_blend_shape_count()):
			var shape: StringName = array_mesh.get_blend_shape_name(i)
			var value: float = weights.get(shape, 0.0)
			mesh.set_blend_shape_value(i, value)


static func _part_visible(part_name: String, face: FaceData) -> bool:
	if part_name.begins_with(FEATURE_MARK):
		return face.features.has(StringName(part_name.trim_prefix(FEATURE_MARK)))
	if part_name == "lashes":
		return not FISH_EYED_FORMS.has(face.form)
	if part_name == UNDERCAP:
		return not face.hair_style.is_empty() and not NO_UNDERCAP.has(face.hair_style)
	if part_name == UNDERCAP_FULL:
		return COVERS_SCALP.has(face.hair_style)
	if part_name.begins_with("hair_"):
		return part_name.trim_prefix("hair_").get_slice(PIECE_MARK, 0) == String(face.hair_style)
	if part_name.begins_with("brow_"):
		return part_name.trim_prefix("brow_") == String(face.brow_style)
	if part_name.begins_with("beard_"):
		return part_name.trim_prefix("beard_") == String(face.beard_style)
	return true


static func shape_weights(face: FaceData, male: bool, age: float) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	for key: StringName in face.sliders:
		var value: float = face.sliders[key]
		out[StringName("s_%s_p" % key)] = maxf(value, 0.0)
		out[StringName("s_%s_n" % key)] = maxf(-value, 0.0)
	for unit: StringName in RESTING_UNITS:
		out[StringName("x_%s" % unit)] = RESTING_UNITS[unit]
	var active_sex: int = 1 if male else 0
	var age_old: float = clampf(age, 0.0, 1.0)
	for s: int in range(2):
		for a: int in range(2):
			var age_name: String = "old" if a == 1 else "young"
			var share: float = (1.0 if s == active_sex else 0.0) * (age_old if a == 1 else 1.0 - age_old)
			out[StringName("m_universal_%s_%s" % [SEXES[s], age_name])] = share
			for r: int in range(3):
				var heritage_share: float = face.heritage.get(StringName(RACES[r]), 0.0)
				out[StringName("m_%s_%s_%s" % [RACES[r], SEXES[s], age_name])] = share * heritage_share
	if face.form != &"":
		out[StringName("r_%s" % face.form)] = 1.0
	return out


## Weights by MakeHuman expression unit, such as FaceView.HAPPY. Others return to resting.
static func set_expression(head: Node3D, units: Dictionary[StringName, float]) -> void:
	for part: Node in head.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = part as MeshInstance3D
		if not mesh.visible:
			continue
		var array_mesh: ArrayMesh = mesh.mesh as ArrayMesh
		for i: int in range(array_mesh.get_blend_shape_count()):
			var shape: String = String(array_mesh.get_blend_shape_name(i))
			if shape.begins_with("x_"):
				var unit: StringName = StringName(shape.trim_prefix("x_"))
				var resting: float = RESTING_UNITS.get(unit, 0.0)
				var value: float = units.get(unit, resting)
				mesh.set_blend_shape_value(i, value)


static func _material_for(part_name: String, face: FaceData, male: bool, age: float) -> Material:
	var data: Dictionary = manifest()
	if part_name == "skin":
		return skin_material(face, male, age)
	if part_name == "eyes":
		var eyes: Dictionary = data["eyes"] as Dictionary
		var eye_path: String = eyes[String(face.eye_color)]
		if FISH_EYED_FORMS.has(face.form):
			var fish: ShaderMaterial = ShaderMaterial.new()
			fish.shader = load(FISH_EYE_SHADER) as Shader
			fish.set_shader_parameter(&"map", load(eye_path) as Texture2D)
			return fish
		var eye: StandardMaterial3D = _textured(eye_path, 0.16, 0.5)
		eye.albedo_color = Color(0.68, 0.68, 0.66)
		# The eye texture leaves the cornea shell see-through.
		eye.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		eye.alpha_scissor_threshold = 0.5
		return eye
	if part_name.begins_with(FEATURE_MARK):
		return feature_material(part_name.trim_prefix(FEATURE_MARK), face)
	var attachments: Dictionary = data["attachments"] as Dictionary
	if part_name == "teeth" or part_name == "tongue":
		var entry: Dictionary = attachments[part_name] as Dictionary
		var path: String = entry["map"]
		var mouth_part: StandardMaterial3D = _textured(path, 0.42, 0.45)
		mouth_part.albedo_color = Color(0.95, 0.88, 0.74)
		return mouth_part
	var hair_color: Color = hair_color(face, age)
	if part_name == "lashes":
		return _tinted(attachments["lashes"] as Dictionary, hair_color * 0.4, 0.2, 0.5)
	if part_name.begins_with("brow_"):
		var brows: Dictionary = data["brows"] as Dictionary
		return _tinted(brows[part_name.trim_prefix("brow_")] as Dictionary, hair_color * 1.2, 0.15, 0.2)
	if part_name.begins_with("beard_"):
		var beards: Dictionary = data["beards"] as Dictionary
		var beard: Dictionary = beards[part_name.trim_prefix("beard_")] as Dictionary
		return _shell_material(beard, hair_color) if beard.has("shell") else _tinted(beard, hair_color, 0.3, 0.38)
	var hair: Dictionary = data["hair"] as Dictionary
	var style: Dictionary = hair[part_name.trim_prefix("hair_")] as Dictionary
	return _shell_material(style, hair_color) if style.has("shell") else _tinted(style, hair_color, 0.35, 0.42)


## Fins grow from the skin's colour to a brighter, see-through rim. Gill flaps are skin, with a red gap under
## them. Chitin is darker and shines.
static func feature_material(feature: String, face: FaceData) -> Material:
	if not CHITIN_PARTS.has(feature):
		var fin: ShaderMaterial = ShaderMaterial.new()
		fin.shader = load(FIN_SHADER) as Shader
		# The skin texture is warm, so the tint alone is far bluer than skin looks. This is about what they make together.
		var skin: Color = face.skin_tint * FIN_SKIN
		if feature == "gills":
			fin.set_shader_parameter(&"root_color", Color(0.38, 0.08, 0.1))
			fin.set_shader_parameter(&"rim_color", skin)
			fin.set_shader_parameter(&"streaks", 0.0)
		else:
			var rim: Color = skin.lerp(Color(0.35, 0.8, 0.88), 0.6)
			rim.a = 0.55
			fin.set_shader_parameter(&"root_color", skin)
			fin.set_shader_parameter(&"rim_color", rim)
			fin.set_shader_parameter(&"ray_color", skin * 0.7)
		return fin
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = (face.skin_tint * Color(0.42, 0.3, 0.2)).lerp(Color(0.12, 0.08, 0.05), 0.35)
	material.roughness = 0.38
	material.metallic_specular = 0.55
	return material


static func hair_color(face: FaceData, age: float) -> Color:
	var position: float = clampf(face.hair_tone, 0.0, 1.0) * float(HAIR_TONES.size() - 1)
	var low: int = mini(int(position), HAIR_TONES.size() - 2)
	var color: Color = HAIR_TONES[low].lerp(HAIR_TONES[low + 1], position - float(low))
	return color.lerp(Color(0.42, 0.41, 0.39), smoothstep(0.45, 0.9, age) * 0.85)


static func skin_material(face: FaceData, male: bool, age: float) -> ShaderMaterial:
	var skins: Dictionary = manifest()["skins"] as Dictionary
	var info: Dictionary = skins[skin_for(face, male, age)] as Dictionary
	var path: String = info["albedo"]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SKIN_SHADER) as Shader
	material.set_shader_parameter(&"map", load(path) as Texture2D)
	material.set_shader_parameter(&"tint", face.skin_tint)
	if SCALED_FORMS.has(face.form):
		material.set_shader_parameter(&"scales", SCALED_FORMS[face.form])
		material.set_shader_parameter(&"scale_map", load(SCALE_MAP) as Texture2D)
		var bare: Array = manifest()["bare_skin_uv"] as Array
		var bare_u: float = bare[0]
		var bare_v: float = bare[1]
		material.set_shader_parameter(&"bare_uv", Vector2(bare_u, bare_v))
	return material


static func _textured(path: String, roughness: float, specular: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load(path) as Texture2D
	material.roughness = roughness
	material.metallic_specular = specular
	return material


## Hair in layers: one material for each, chained so the mesh is drawn once for each layer.
static func _shell_material(entry: Dictionary, color: Color) -> ShaderMaterial:
	var path: String = entry["map"]
	var shell: Dictionary = entry["shell"]
	var layer_value: float = shell["layers"]
	var layers: int = int(layer_value)
	var shader: Shader = load(SHELL_SHADER) as Shader
	var tile: Texture2D = load(path) as Texture2D
	var outer: ShaderMaterial = null
	for layer: int in range(layers - 1, -1, -1):
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter(&"tile", tile)
		material.set_shader_parameter(&"color", color)
		material.set_shader_parameter(&"layer", float(layer) / float(layers - 1))
		for key: String in ["sag", "comb", "curly", "lump", "root"]:
			var value: float = shell[key]
			material.set_shader_parameter(StringName(key), value)
		material.next_pass = outer
		outer = material
	return outer


static func _tinted(entry: Dictionary, color: Color, specular: float, cutoff: float) -> ShaderMaterial:
	var path: String = entry["map"]
	var gain: float = entry["gain"]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(HAIR_SHADER) as Shader
	material.set_shader_parameter(&"map", load(path) as Texture2D)
	material.set_shader_parameter(&"color", color)
	material.set_shader_parameter(&"average", maxf(gain, 0.01))
	material.set_shader_parameter(&"specular_amount", specular)
	material.set_shader_parameter(&"cutoff", cutoff)
	var strand_axis: float = entry.get("strand_axis", 1.0)
	material.set_shader_parameter(&"strand_axis", int(strand_axis))
	material.set_shader_parameter(&"strand_map", load(STRAND_DETAIL) as Texture2D)
	return material
