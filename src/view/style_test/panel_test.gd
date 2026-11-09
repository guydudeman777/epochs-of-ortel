extends Control
## The big panels over a real world, to judge them by, and the inventory's buttons pressed as a player would.
##
## godot --path . res://src/view/style_test/panel_test.tscn --resolution 1920x1080 -- --panel=inventory --out=C:/tmp/inv.png
## --seed=number. --kit=soldier dresses you as a man-at-arms of your realm and fills your pack; --kit=noble as a lord.
## --press=slot_shirt (or carried_<id>) presses that slot after the first picture and takes a second, to "<out>_after.png".
## --rich gives you coin; --wounded cuts you about a little, to see wounds on the body.

var _ctx: SimContext
var _panels: GamePanels


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuStyle.apply(self)
	var back: TextureRect = MenuStyle.backdrop(self)
	back.modulate = Color(0.55, 0.5, 0.42)
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = ViewUtil.arg("seed", "3").to_int()
	World.new_game(config)
	GameClock.paused = true
	_ctx = Simulation.kernel.ctx
	# A few days, so the chronicle and the world have something in them.
	Simulation.kernel.advance_days(ViewUtil.arg("days", "40").to_int())
	_prepare(_ctx.character(_ctx.world.player_character_id))
	_panels = GamePanels.new()
	add_child(_panels)
	_panels.setup(_ctx)
	_panels.show_panel(StringName(ViewUtil.arg("panel", "inventory")))
	var out_path: String = ViewUtil.arg("out", "")
	if out_path.is_empty():
		return
	# --panels=a,b,c takes a picture of each, to "<out>_<panel>.png".
	for panel: String in ViewUtil.arg("panels", "").split(",", false):
		_panels.show_panel(StringName(panel))
		await _settle()
		_save("%s_%s.png" % [out_path.get_basename(), panel])
	if not ViewUtil.arg("panels", "").is_empty():
		get_tree().quit(0)
		return
	await _settle()
	_save(out_path)
	var press: String = ViewUtil.arg("press", "")
	if not press.is_empty():
		var target: Node = _panels.find_child(press, true, false)
		if target is BaseButton:
			(target as BaseButton).pressed.emit()
		else:
			print("PANEL no button %s" % press)
		await _settle()
		_save(out_path.get_basename() + "_after.png")
	get_tree().quit(0)


func _settle() -> void:
	for _i: int in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	print("SHOT %s (%s)" % [path, error_string(image.save_png(path))])


## Dresses and equips the player for a picture. A test harness, so it sets state by hand as the tests do.
func _prepare(me: CharacterData) -> void:
	if me == null:
		return
	match ViewUtil.arg("kit", ""):
		"soldier":
			Actions.kit_out(_ctx, me.id, &"man_at_arms")
			for item: StringName in [&"tunic", &"hood", &"cloak", &"padded_jack", &"kettle_hat", &"leather_gloves", &"fur_boots", &"tabard"]:
				me.inventory.items[item] = me.inventory.items.get(item, 0) + 1
		"noble":
			me.equipment.armour_ids = Outfits.outfit(_ctx.defs, Outfits.culture_of(_ctx, me), GeneticsService.dominant_race(me),
					me.sex == SimEnums.Sex.MALE, Outfits.NOBLE, &"noble", me.id)
			for item: StringName in [&"mail_hauberk", &"bascinet", &"gauntlets", &"surcoat"]:
				me.inventory.items[item] = 1
	if OS.get_cmdline_user_args().has("--rich"):
		me.inventory.gold += 640
		me.inventory.goods[&"grain"] = 12
	if OS.get_cmdline_user_args().has("--wounded"):
		Actions.land_blow(_ctx, me.id, me.id, &"forearm_l", false)
		Actions.land_blow(_ctx, me.id, me.id, &"thigh_r", true)
	if OS.get_cmdline_user_args().has("--quest"):
		_quests(me)
	if OS.get_cmdline_user_args().has("--band"):
		_band(me)


## Puts you where something is asked, and has you take one thing on.
func _quests(me: CharacterData) -> void:
	var ids: Array[int] = []
	ids.assign(_ctx.world.quests.keys())
	ids.sort()
	for id: int in ids:
		var q: QuestData = _ctx.world.quests[id]
		if q.state == QuestData.State.OFFERED:
			me.settlement_id = q.settlement_id
			Actions.take_quest(_ctx, me.id, q.id)
			return


## A band of your own, with troops of several ranks and some experience. Until every people has its own tree, the
## old troops are given ranks and a line to rise along here, to show the party page whole.
func _band(me: CharacterData) -> void:
	var made: ActionResult = Actions.form_warband(_ctx, me.id, SimEnums.WarbandRole.PARTY, mini(me.inventory.gold, 120))
	var band: WarbandData = _ctx.warband(me.warband_id)
	if not made.success or band == null:
		print("PANEL no band: %s" % made.reason)
		return
	var ranks: Dictionary[StringName, int] = {&"levy_spearman": 1, &"archer": 2, &"man_at_arms": 3, &"pikeman": 3, &"plate_knight": 5}
	for troop_id: StringName in ranks:
		var def: TroopDef = _ctx.defs.troops.get(troop_id, null)
		if def == null:
			continue
		if def.tier <= 1 and def.upgrades_to.is_empty():
			def.tier = ranks[troop_id]
		band.troops[troop_id] = {&"levy_spearman": 14, &"archer": 6, &"man_at_arms": 4, &"pikeman": 5, &"plate_knight": 1}[troop_id] as int
	var levy: TroopDef = _ctx.defs.troops.get(&"levy_spearman", null)
	if levy != null and levy.upgrades_to.is_empty():
		levy.upgrades_to.assign([&"man_at_arms", &"pikeman"])
		levy.upgrade_xp = 40
		levy.upgrade_cost = 30
	band.troop_xp[&"levy_spearman"] = 130.0
	band.supplies = 60.0
	for member: int in _ctx.world.characters:
		var c: CharacterData = _ctx.world.characters[member]
		if c.settlement_id == me.settlement_id and c.warband_id < 0 and c.id != me.id and _ctx.is_adult(c) and band.member_ids.size() < 4:
			WarbandOps.add_member(_ctx, band, c)
