class_name DefCatalog
extends RefCounted

## Read-only authored content, indexed by id.
const DEFAULT_ROOT: String = "res://content/defs"
const LAND_FILE: String = "/land/ortel.res"

var races: Dictionary[StringName, RaceDef] = {}
var traits: Dictionary[StringName, TraitDef] = {}
var goods: Dictionary[StringName, GoodDef] = {}
var troops: Dictionary[StringName, TroopDef] = {}
var buildings: Dictionary[StringName, BuildingDef] = {}
var techs: Dictionary[StringName, TechDef] = {}
var cultures: Dictionary[StringName, CultureDef] = {}
var body_parts: Dictionary[StringName, BodyPartDef] = {}
var weapons: Dictionary[StringName, WeaponDef] = {}
var armours: Dictionary[StringName, ArmourDef] = {}
## The one land the game is played on.
var land: LandDef = null
## Sorted ids, so iteration order never depends on dictionary or file order.
var race_ids: Array[StringName] = []
var trait_ids: Array[StringName] = []
var good_ids: Array[StringName] = []
var troop_ids: Array[StringName] = []
var building_ids: Array[StringName] = []
var tech_ids: Array[StringName] = []
var culture_ids: Array[StringName] = []
var body_part_ids: Array[StringName] = []
var weapon_ids: Array[StringName] = []
var armour_ids: Array[StringName] = []


func load_all(root: String = DEFAULT_ROOT) -> void:
	for res: Resource in _load_dir(root + "/races"):
		var def: RaceDef = res as RaceDef
		races[def.id] = def
		race_ids.append(def.id)
	for res: Resource in _load_dir(root + "/traits"):
		var def: TraitDef = res as TraitDef
		traits[def.id] = def
		trait_ids.append(def.id)
	for res: Resource in _load_dir(root + "/goods"):
		var def: GoodDef = res as GoodDef
		goods[def.id] = def
		good_ids.append(def.id)
	for res: Resource in _load_dir(root + "/troops"):
		var def: TroopDef = res as TroopDef
		troops[def.id] = def
		troop_ids.append(def.id)
	for res: Resource in _load_dir(root + "/buildings"):
		var def: BuildingDef = res as BuildingDef
		buildings[def.id] = def
		building_ids.append(def.id)
	for res: Resource in _load_dir(root + "/techs"):
		var def: TechDef = res as TechDef
		techs[def.id] = def
		tech_ids.append(def.id)
	for res: Resource in _load_dir(root + "/cultures"):
		var def: CultureDef = res as CultureDef
		cultures[def.id] = def
		culture_ids.append(def.id)
	for res: Resource in _load_dir(root + "/body_parts"):
		var def: BodyPartDef = res as BodyPartDef
		body_parts[def.id] = def
		body_part_ids.append(def.id)
	for res: Resource in _load_dir(root + "/weapons"):
		var def: WeaponDef = res as WeaponDef
		weapons[def.id] = def
		weapon_ids.append(def.id)
	for res: Resource in _load_dir(root + "/armours"):
		var def: ArmourDef = res as ArmourDef
		armours[def.id] = def
		armour_ids.append(def.id)
	if ResourceLoader.exists(root + LAND_FILE):
		land = ResourceLoader.load(root + LAND_FILE) as LandDef
	_sort_ids(body_part_ids)
	_sort_ids(weapon_ids)
	_sort_ids(armour_ids)
	_sort_ids(race_ids)
	_sort_ids(trait_ids)
	_sort_ids(good_ids)
	_sort_ids(troop_ids)
	_sort_ids(building_ids)
	_sort_ids(tech_ids)
	_sort_ids(culture_ids)


func _sort_ids(ids: Array[StringName]) -> void:
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


func _load_dir(path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(path):
		return out
	var files: PackedStringArray = ResourceLoader.list_directory(path)
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = ResourceLoader.load(path + "/" + file_name)
		if res != null:
			out.append(res)
	return out
