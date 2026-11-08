extends SceneTree
## Runs many battles between NPCs and prints how they come out, for tuning.
## Run: godot --headless --path . --script res://tools/battle_balance.gd


const NEAR_LINE: Array[StringName] = [&"man_at_arms", &"levy_spearman", &"levy_spearman", &"man_at_arms", &"pikeman", &"plate_knight"]
const FAR_LINE: Array[StringName] = [&"man_at_arms", &"levy_spearman", &"pikeman", &"man_at_arms", &"rebel_militia", &"plate_knight"]
const BATTLES: int = 40
const PER_SIDE: int = 8
const LONGEST_SECONDS: float = 300.0


func _init() -> void:
	var catalog: DefCatalog = DefCatalog.new()
	catalog.load_all()
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 41
	config.named_target = 2000
	var hub: EventHub = EventHub.new()
	var k: SimKernel = SimKernel.new(WorldGenerator.generate(config, catalog), catalog, hub)
	var people: Array[int] = []
	for id: int in k.ctx.character_ids():
		if k.ctx.is_adult(k.ctx.character(id)):
			people.append(id)
	var seconds: float = 0.0
	var near_wins: int = 0
	var counts: Dictionary[DuelFighter.State, int] = {}
	var lost: int = 0
	var at: int = 0
	var fought: int = 0
	var started: int = Time.get_ticks_usec()
	var steps: int = 0
	for battle: int in range(BATTLES):
		if at + PER_SIDE * 2 > people.size():
			break
		var fight: LocalFight = LocalFight.new(k.ctx)
		fight.arena_radius = 17.0
		for side: int in range(2):
			var line: Array[StringName] = NEAR_LINE if side == 0 else FAR_LINE
			for i: int in range(PER_SIDE):
				var id: int = people[at]
				at += 1
				Actions.kit_out(k.ctx, id, line[i % line.size()])
				fight.add_fighter(id, side, Vector2(float(i) * 1.9 - 7.0, -5.5 if side == 0 else 5.5), Vector2(0.0, 1.0 if side == 0 else -1.0))
		var agents: Array[DuelAgent] = []
		for f: DuelFighter in fight.fighters:
			agents.append(DuelAgent.new(fight, f))
		var inputs: Array[DuelInput] = []
		inputs.resize(fight.fighters.size())
		var lost_before: int = k.ctx.stat(&"limbs_lost")
		var ticks: int = 0
		while not fight.over and ticks * LocalFight.STEP < LONGEST_SECONDS:
			for i: int in range(agents.size()):
				inputs[i] = agents[i].decide(LocalFight.STEP)
			fight.step_all(inputs)
			ticks += 1
		steps += ticks
		fought += 1
		seconds += ticks * LocalFight.STEP
		lost += k.ctx.stat(&"limbs_lost") - lost_before
		if fight.winning_side == 0:
			near_wins += 1
		for f: DuelFighter in fight.fighters:
			var so_far: int = counts.get(f.state, 0)
			counts[f.state] = so_far + 1
	var per_step: float = float(Time.get_ticks_usec() - started) / maxf(float(steps), 1.0)
	print("%d battles of %d a side: %.0f s long, near line won %d, limbs lost %d, %.0f us a step." % [fought, PER_SIDE, seconds / fought, near_wins, lost, per_step])
	for state: DuelFighter.State in counts:
		print("  %s: %d" % [DuelFighter.State.keys()[state], counts[state]])
	hub.free()
	quit(0)
