extends SceneTree
## Fights ranks of one people's tree against each other, and levies' weapons against each other, with NPCs on both sides,
## and prints how often each side wins. For tuning troop trees and weapons, so ranks matter and no one weapon wins.
## Run: godot --headless --path . --script res://tools/battle/rank_balance.gd [-- --people=hallowed --battles=30]

const LONGEST_SECONDS: float = 200.0

var _k: SimKernel
var _hub: EventHub
var _people: Array[int] = []
var _at: int = 0


func _init() -> void:
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all()
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 43
	config.named_target = 4000
	_hub = EventHub.new()
	_k = SimKernel.new(WorldGenerator.generate(config, catalog), catalog, _hub)
	for id: int in _k.ctx.character_ids():
		var c: CharacterData = _k.ctx.character(id)
		if _k.ctx.is_adult(c) and GeneticsService.dominant_race(c) == &"human" and c.body.wounds.is_empty():
			_people.append(id)
	var people: StringName = StringName(_arg("people", "hallowed"))
	var battles: int = _arg("battles", "30").to_int()
	var tree: Array[StringName] = TroopOps.tree_of(_k.ctx, people)
	var levy: StringName = TroopOps.levy_for(_k.ctx, null) if people == &"hallowed" else tree[0]
	var line2: StringName = _k.ctx.defs.troops[levy].upgrades_to[0]
	var line3: StringName = _k.ctx.defs.troops[line2].upgrades_to[0]
	var line4: StringName = _k.ctx.defs.troops[line3].upgrades_to[0]
	var line5: StringName = _k.ctx.defs.troops[line4].upgrades_to[0]
	print("ranks of %s, %d battles each, share the first side wins:" % [people, battles])
	for match_up: Array in [[levy, 5, line2, 5], [levy, 5, line3, 5], [line2, 5, line3, 5], [line3, 5, line5, 5], [levy, 10, line3, 5], [line3, 6, line5, 3], [levy, 12, line5, 3]]:
		var won: float = _fights(match_up[0] as StringName, match_up[1] as int, match_up[2] as StringName, match_up[3] as int, battles, &"")
		print("  %2d %-22s against %2d %-22s %3d%%" % [match_up[1], match_up[0], match_up[3], match_up[2], roundi(won * 100.0)])
	print("levies one against one, by weapon, against levies with any weapon:")
	var levy_def: TroopDef = _k.ctx.defs.troops[levy]
	for weapon: StringName in levy_def.weapon_choices:
		var won: float = _fights(levy, 1, levy, 1, battles * 2, weapon)
		print("  %-14s %3d%%" % [weapon, roundi(won * 100.0)])
	_hub.free()
	quit(0)


## Share of battles the first side wins. weapon, if given, arms the first side with it alone.
func _fights(a: StringName, count_a: int, b: StringName, count_b: int, battles: int, weapon: StringName) -> float:
	var wins: float = 0.0
	for battle: int in range(battles):
		if _at + count_a + count_b > _people.size():
			_at = 0
		var fight: LocalFight = LocalFight.new(_k.ctx)
		fight.arena_radius = 17.0
		var used: Array[int] = []
		for side: int in range(2):
			var count: int = count_a if side == 0 else count_b
			for i: int in range(count):
				var id: int = _people[_at]
				_at += 1
				used.append(id)
				var c: CharacterData = _k.ctx.character(id)
				Actions.kit_out(_k.ctx, id, a if side == 0 else b)
				if side == 0 and weapon != &"":
					Actions.equip(_k.ctx, id, weapon, TroopOps.shield_for(_k.ctx, _k.ctx.defs.troops[a], weapon, id), c.equipment.armour_ids)
				fight.add_fighter(id, side, Vector2((i - (count - 1) * 0.5) * 1.9, -5.5 if side == 0 else 5.5), Vector2(0.0, 1.0 if side == 0 else -1.0))
		var agents: Array[DuelAgent] = []
		for f: DuelFighter in fight.fighters:
			agents.append(DuelAgent.new(fight, f))
		var inputs: Array[DuelInput] = []
		inputs.resize(fight.fighters.size())
		var ticks: int = 0
		while not fight.over and ticks * LocalFight.STEP < LONGEST_SECONDS:
			for i: int in range(agents.size()):
				inputs[i] = agents[i].decide(LocalFight.STEP)
			fight.step_all(inputs)
			ticks += 1
		if fight.winning_side == 0:
			wins += 1.0
		elif fight.winning_side < 0:
			wins += 0.5
		# Everyone walks away whole for the next fight, as if it had been a drill.
		for id: int in used:
			var c: CharacterData = _k.ctx.character(id)
			if c != null:
				c.body.wounds.clear()
				c.body.lost_parts.clear()
				c.body.blood = 1.0
		_people.assign(_people.filter(func(id: int) -> bool: return _k.ctx.character(id) != null))
	return wins / float(battles)


func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return fallback
