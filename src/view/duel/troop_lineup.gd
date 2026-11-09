extends Node3D
## Peoples' soldiers standing in ranks on a battle field, to look at their trees: each row one people, each soldier
## kitted out as their troop is (Actions.kit_out), named with their rank above them.
##
## godot --path . res://src/view/duel/troop_lineup.tscn -- --people=hallowed,steppe,freehold --tiers=1,3,5
## --branch=line shows one branch's line only; with none, every troop of those tiers. --weapons stands one levy with each
## weapon there is instead, turned to show it. --out=path%d.png --shots=2 saves
## pictures and quits. --close looks along the front rank from nearer. --ground and --biome pick the field, as in the
## battle scene. --crowd draws everyone as one of a crowd, as far fighters are.

const PEOPLE: int = 300
const ROW_GAP: float = 3.4
const FILE_GAP: float = 1.7
const LABEL_HEIGHT: float = 2.25
const WEAPONS_A_ROW: int = 6

var _kernel: SimKernel
var _hub: EventHub
var _camera: Camera3D
var _shots: Array[float] = []
var _shot_index: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	for item: String in ViewUtil.arg("shots", "").split(",", false):
		_shots.append(item.to_float())
	load(FaceView.HEAD_SCENE)
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = ViewUtil.arg("seed", "3").to_int()
	config.named_target = PEOPLE
	_hub = EventHub.new()
	add_child(_hub)
	_kernel = SimKernel.new(WorldGenerator.generate(config, DefRegistry.catalog), DefRegistry.catalog, _hub)
	var ctx: SimContext = _kernel.ctx
	var ground: BattleGround = _pick_ground(ctx)
	if ground.samples > 2:
		FieldStage.build(self, ground, ViewUtil.arg("hour", "11").to_float(), 7)
	else:
		ArenaStage.build(self, 30.0, 0)
	var peoples: PackedStringArray = ViewUtil.arg("people", "hallowed,steppe,freehold").split(",", false)
	var tiers: Array[int] = []
	for item: String in ViewUtil.arg("tiers", "1,3,5").split(",", false):
		tiers.append(item.to_int())
	var branches: Array[StringName] = []
	for item: String in ViewUtil.arg("branch", "").split(",", false):
		branches.append(StringName(item))
	var widest: int = 0
	if OS.get_cmdline_user_args().has("--weapons"):
		peoples = PackedStringArray([peoples[0]])
		var people: StringName = StringName(peoples[0])
		widest = WEAPONS_A_ROW
		var count: int = ctx.defs.weapon_ids.size()
		for i: int in range(count):
			var file: int = i % WEAPONS_A_ROW
			var row: int = i / WEAPONS_A_ROW
			var at: Vector3 = Vector3((file - (WEAPONS_A_ROW - 1) * 0.5) * FILE_GAP * 1.2, 0.0, row * ROW_GAP * 0.8)
			at.y = ground.height_at(Vector2(at.x, at.z))
			_stand(ctx, people, TroopOps.levy_for(ctx, null), at, i, ctx.defs.weapon_ids[i])
		peoples.clear()
		for row: int in range(ceili(float(count) / WEAPONS_A_ROW)):
			peoples.append(String(people))
	for row: int in range(peoples.size() if widest == 0 else 0):
		var people: StringName = StringName(peoples[row])
		var troops: Array[StringName] = _troops_of(ctx, people, tiers, branches)
		widest = maxi(widest, troops.size())
		for file: int in range(troops.size()):
			var at: Vector3 = Vector3((file - (troops.size() - 1) * 0.5) * FILE_GAP, 0.0, row * ROW_GAP)
			at.y = ground.height_at(Vector2(at.x, at.z))
			_stand(ctx, people, troops[file], at, file * 31 + row * 7)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	var depth: float = (peoples.size() - 1) * ROW_GAP * (0.8 if OS.get_cmdline_user_args().has("--weapons") else 1.0)
	var middle: Vector3 = Vector3(0.0, ground.height_at(Vector2(0.0, depth * 0.5)) + 1.0, depth * 0.5)
	if OS.get_cmdline_user_args().has("--close"):
		_camera.position = Vector3(-widest * FILE_GAP * 0.15, middle.y + 0.8, -5.5)
		_camera.look_at(Vector3(0.0, middle.y + 0.1, 1.0), Vector3.UP)
	else:
		var back: float = maxf(widest * FILE_GAP * 0.95, 7.0) + depth * 0.5
		_camera.position = middle + Vector3(0.0, back * 0.2 + 1.2, -back)
		_camera.look_at(middle + Vector3(0.0, 0.1, 0.0), Vector3.UP)


func _pick_ground(ctx: SimContext) -> BattleGround:
	var sites: BattleSitesDef = BattleSitesDef.of_land(ctx.world.map.land_id) if ctx.world.map.land_id != &"" else null
	if sites == null:
		return BattleGround.flat()
	var site: BattleSiteDef = sites.first_of(StringName(ViewUtil.arg("ground", "field")), LandDef.BIOME_NAMES.find(StringName(ViewUtil.arg("biome", "temperate"))))
	return BattleGround.of_site(ctx, site if site != null else sites.sites[0])


## A people's troops of these ranks, along one branch or all of them, lowest rank first.
func _troops_of(ctx: SimContext, people: StringName, tiers: Array[int], branches: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in TroopOps.tree_of(ctx, people):
		var def: TroopDef = ctx.defs.troops[id]
		if not tiers.has(def.tier):
			continue
		if not branches.is_empty() and not branches.has(def.branch) and def.branch != &"levy":
			continue
		out.append(id)
		# Levies come three at a time, so their mixed arms show.
		if def.tier == 1:
			out.append(id)
			out.append(id)
	return out


func _stand(ctx: SimContext, people: StringName, troop: StringName, at: Vector3, pick: int, weapon: StringName = &"") -> void:
	var race: StringName = ctx.defs.cultures[people].primary_race
	var faction: int = -1
	for id: int in ctx.faction_ids():
		if ctx.world.factions[id].culture_id == people:
			faction = id
			break
	var c: CharacterData = CharacterFactory.create_temp_fighter(ctx, race, &"soldier", faction)
	for i: int in range(pick % 5):
		c = CharacterFactory.create_temp_fighter(ctx, race, &"soldier", faction)
	Actions.kit_out(ctx, c.id, troop)
	if weapon != &"":
		Actions.equip(ctx, c.id, weapon, false, c.equipment.armour_ids)
	var male: bool = c.sex == SimEnums.Sex.MALE
	var worn: Array[String] = BodyView.worn_for(c.equipment, c.id, ctx.faction(faction), Outfits.tier_of(ctx, c))
	var body: Node3D = BodyView.make(c.genetics.face, male, 0.25, worn, OS.get_cmdline_user_args().has("--crowd"))
	add_child(body)
	body.position = at
	# Turned a little, so what they hold is seen side on rather than end on.
	body.rotation.y = PI + (0.55 if pick % 2 == 0 else -0.45)
	var head: Node3D = FaceView.attach(body, c.genetics.face, male, 0.25)
	if BodyView.hides_hair(worn):
		FaceView.hide_hair(head)
	var player: AnimationPlayer = ViewUtil.find_player(body)
	var clip: StringName = BodyView.kit_clip(player, &"ready", worn)
	if player.has_animation(clip):
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
		player.seek(float(pick % 7) * 0.13, true)
	var def: TroopDef = ctx.defs.troops[troop]
	var label: Label3D = Label3D.new()
	label.text = "%s\n%s · tier %d" % [def.display_name, ctx.defs.weapons[c.equipment.weapon_id].display_name if ctx.defs.weapons.has(c.equipment.weapon_id) else "", def.tier]
	label.font_size = 24
	label.pixel_size = 0.0034
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.95, 0.9, 0.78)
	label.position = at + Vector3(0.0, LABEL_HEIGHT, 0.0)
	add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	if _shot_index < _shots.size() and _elapsed >= _shots[_shot_index]:
		var path: String = ViewUtil.arg("out", "") % _shot_index
		_shot_index += 1
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT %s" % path)
		if _shot_index >= _shots.size():
			get_tree().quit(0)
