extends SceneTree
## Runs many duels between NPCs and prints how they come out, for tuning.
## Run: godot --headless --path . --script res://tools/duel_balance.gd


const FIGHTS: int = 200
const LONGEST_SECONDS: float = 240.0


func _init() -> void:
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all()
	for setup: Array in [["mail, shield", true, [&"mail_hauberk", &"mail_coif", &"helmet", &"trousers", &"boots"]], ["mail, no shield", false, [&"mail_hauberk", &"mail_coif", &"helmet", &"trousers", &"boots"]], ["cloth, no shield", false, [&"shirt", &"trousers", &"boots"]]]:
		_run_setup(catalog, setup[0] as String, setup[1] as bool, setup[2] as Array)
	quit(0)


func _run_setup(catalog: DefCatalog, title: String, shield: bool, armour: Array) -> void:
	var worn: Array[StringName] = []
	worn.assign(armour)
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 77
	config.named_target = 1200
	var hub: EventHub = EventHub.new()
	var k: SimKernel = SimKernel.new(WorldGenerator.generate(config, catalog), catalog, hub)
	var people: Array[int] = []
	for id: int in k.ctx.character_ids():
		if k.ctx.is_adult(k.ctx.character(id)):
			people.append(id)
	var seconds: float = 0.0
	var down: int = 0
	var yielded: int = 0
	var dead: int = 0
	var unfinished: int = 0
	var blows: int = 0
	var lost: int = 0
	var fights: int = 0
	var at: int = 0
	while fights < FIGHTS and at + 1 < people.size():
		var a_id: int = people[at]
		var b_id: int = people[at + 1]
		at += 2
		if k.ctx.character(a_id) == null or k.ctx.character(b_id) == null:
			continue
		fights += 1
		Actions.equip(k.ctx, a_id, &"arming_sword", shield, worn)
		Actions.equip(k.ctx, b_id, &"arming_sword", shield, worn)
		var fight: DuelFight = DuelFight.new(k.ctx, a_id, b_id)
		var first: DuelAgent = DuelAgent.new(fight, fight.a)
		var second: DuelAgent = DuelAgent.new(fight, fight.b)
		var lost_before: int = k.ctx.stat(&"limbs_lost")
		var blows_before: int = k.ctx.stat(&"wounds_taken")
		var ticks: int = 0
		while not fight.over and ticks * DuelFight.STEP < LONGEST_SECONDS:
			fight.step(first.decide(DuelFight.STEP), second.decide(DuelFight.STEP))
			ticks += 1
		seconds += ticks * DuelFight.STEP
		lost += k.ctx.stat(&"limbs_lost") - lost_before
		blows += k.ctx.stat(&"wounds_taken") - blows_before
		if not fight.over:
			unfinished += 1
		for f: DuelFighter in [fight.a, fight.b]:
			match f.state:
				DuelFighter.State.DOWN:
					down += 1
				DuelFighter.State.YIELDED:
					yielded += 1
				DuelFighter.State.DEAD:
					dead += 1
	print("%s: %d fights, %.0f s long, %.1f wounds each, %d limbs lost. Down %d, gave up %d, dead %d, unfinished %d." % [title, fights, seconds / fights, float(blows) / fights, lost, down, yielded, dead, unfinished])
	hub.free()
