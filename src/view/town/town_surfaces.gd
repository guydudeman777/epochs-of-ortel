class_name TownSurfaces
extends RefCounted
## The one material every walkable town piece is drawn with (town_surface.gdshader): the palette its models were
## built with, and for each swatch of the palette the surface it is made of. The swatches come from the manifest the
## Blender build writes, so the rows here always match the models.

## The surfaces of tools/art/build_surfaces.py, in its order.
enum Surface { PLASTER, PLANKS, ASHLAR, RUBBLE, BRICK, THATCH, SHINGLE, COBBLE, FLAGS, WEAVE }

const SHADER: Shader = preload("res://src/view/town/town_surface.gdshader")
const ALBEDO: String = "res://assets/textures/town/surface_albedo.png"
const NORMAL: String = "res://assets/textures/town/surface_normal.png"
## Any walk model's palette: they are all built from the same one.
const PALETTE: String = "res://assets/models/walk_any_stall_palette.png"
const ROWS: int = 64
const NONE: int = 255
## Each swatch's surface and how many metres one tile of it covers.
const SURFACES: Dictionary[String, Array] = {
	"daub": [Surface.PLASTER, 2.5], "plaster": [Surface.PLASTER, 2.5], "dome": [Surface.PLASTER, 3.0],
	"timber": [Surface.PLANKS, 1.8], "timber_dark": [Surface.PLANKS, 1.8], "pale_wood": [Surface.PLANKS, 1.8],
	"dead_wood": [Surface.PLANKS, 1.6], "shield_wood": [Surface.PLANKS, 1.6], "bark": [Surface.PLANKS, 1.2],
	"stone": [Surface.ASHLAR, 2.4], "whitestone": [Surface.ASHLAR, 2.6],
	"stone_dark": [Surface.RUBBLE, 2.0], "blackstone": [Surface.RUBBLE, 2.2], "coral": [Surface.RUBBLE, 1.6],
	"mudbrick": [Surface.BRICK, 2.0], "terracotta": [Surface.BRICK, 1.0],
	"thatch": [Surface.THATCH, 1.8], "thatch_dark": [Surface.THATCH, 1.8], "reed": [Surface.THATCH, 1.5],
	"turf": [Surface.THATCH, 2.5], "kelp": [Surface.THATCH, 1.6],
	"shingle": [Surface.SHINGLE, 1.8], "slate": [Surface.SHINGLE, 1.8], "elf_roof": [Surface.SHINGLE, 1.6],
	"felt": [Surface.WEAVE, 0.8], "felt_dark": [Surface.WEAVE, 0.8], "linen": [Surface.WEAVE, 0.6],
	"cloth_red": [Surface.WEAVE, 0.6], "cloth_blue": [Surface.WEAVE, 0.6], "cloth_bone": [Surface.WEAVE, 0.6],
	"gambeson": [Surface.WEAVE, 0.6], "hide": [Surface.WEAVE, 1.4], "rope": [Surface.WEAVE, 0.4],
}
const METAL: Array[String] = ["iron", "steel", "mail", "brass"]
const GLOW: Dictionary[String, float] = {"window": 0.5, "ember": 1.0}

static var _material: ShaderMaterial = null


## The shared material, made once.
static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	if ResourceLoader.exists(PALETTE):
		_material.set_shader_parameter(&"palette", load(PALETTE))
	_material.set_shader_parameter(&"kinds", ImageTexture.create_from_image(kinds_image(swatches())))
	if ResourceLoader.exists(ALBEDO):
		_material.set_shader_parameter(&"surface_albedo", load(ALBEDO))
		_material.set_shader_parameter(&"surface_normal", load(NORMAL))
	return _material


## The palette's rows by name, as the build wrote them.
static func swatches() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(TownLayout.MANIFEST):
		return out
	var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(TownLayout.MANIFEST))
	if read is Dictionary:
		for name: Variant in (read as Dictionary).get("swatches", []) as Array:
			out.append(str(name))
	return out


## A row of texels, one for each palette row, saying what that swatch is made of.
static func kinds_image(names: Array[String]) -> Image:
	var image: Image = Image.create(ROWS, 1, false, Image.FORMAT_RGBA8)
	for row: int in range(ROWS):
		var swatch: String = names[row] if row < names.size() else ""
		var surface: int = NONE
		var metres: float = 2.0
		if SURFACES.has(swatch):
			surface = SURFACES[swatch][0] as int
			metres = SURFACES[swatch][1] as float
		image.set_pixel(row, 0, Color8(surface, 255 if METAL.has(swatch) else 0, clampi(roundi(metres / 8.0 * 255.0), 1, 255),
				roundi((GLOW.get(swatch, 0.0) as float) * 255.0)))
	return image


## Night from 0 (day) to 1, for the windows and embers.
static func set_night(amount: float) -> void:
	material().set_shader_parameter(&"night", amount)


## Draws a model, made from its scene, with the town's material, and gives it its own look.
static func dress(node: Node, look: Color) -> void:
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = found as MeshInstance3D
		mesh.material_override = material()
		mesh.set_instance_shader_parameter(&"variety", Vector4(look.r, look.g, look.b, look.a))
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material()
		(node as MeshInstance3D).set_instance_shader_parameter(&"variety", Vector4(look.r, look.g, look.b, look.a))
