class_name QuestSystem
extends SimSystem
## Lords ask for what their towns really need: a band preying on them broken, grain for a hungry town. Quests lapse,
## fail, or are done, and NPC captains take them the same way the player does, through Actions.

## Quests long finished are dropped after this many days, so the save does not grow for ever.
const FORGET_AFTER_DAYS: int = 360
const NPC_TAKE_CHANCE: float = 0.25


## Wired by SimKernel to EventHub.band_beaten.
func on_band_beaten(winner_band_id: int, loser_band_id: int, ctx: SimContext) -> void:
	var winner: WarbandData = ctx.warband(winner_band_id)
	if winner == null or loser_band_id < 0:
		return
	for id: int in _sorted_ids(ctx):
		var q: QuestData = ctx.world.quests[id]
		if q.kind == QuestService.HUNT_BAND and q.state == QuestData.State.TAKEN and q.target_id == loser_band_id and q.taker_id == winner.leader_id:
			QuestService.complete(ctx, q)


func tick(ctx: SimContext) -> void:
	var today: int = ctx.today()
	var open_at: Dictionary[int, int] = {}
	var bands_at: Dictionary[int, Array] = {}
	var indexed: bool = false
	for id: int in _sorted_ids(ctx):
		var q: QuestData = ctx.world.quests[id]
		var finished: bool = q.state != QuestData.State.OFFERED and q.state != QuestData.State.TAKEN
		if finished:
			if today - q.due_day > FORGET_AFTER_DAYS:
				ctx.world.quests.erase(id)
			continue
		var gone: bool = q.kind == QuestService.HUNT_BAND and ctx.warband(q.target_id) == null
		var giver_gone: bool = ctx.character(q.giver_id) == null
		if gone or giver_gone or (q.due_day >= 0 and today > q.due_day):
			q.state = QuestData.State.FAILED if q.state == QuestData.State.TAKEN else QuestData.State.LAPSED
			continue
		if q.state == QuestData.State.OFFERED:
			open_at[q.settlement_id] = open_at.get(q.settlement_id, 0) + 1
			if q.kind == QuestService.HUNT_BAND:
				if not indexed:
					bands_at = _bands_in_towns(ctx)
					indexed = true
				_npc_may_take(ctx, q, bands_at.get(q.settlement_id, []) as Array)
	for sid: int in ctx.settlement_ids():
		if not ctx.is_turn(sid) or open_at.get(sid, 0) >= QuestService.OPEN_PER_TOWN:
			continue
		_offer_for(ctx, ctx.world.settlements[sid])


func _offer_for(ctx: SimContext, s: SettlementData) -> void:
	var f: FactionData = ctx.faction(s.faction_id)
	var ruler: CharacterData = ctx.character(f.ruler_id) if f != null else null
	if ruler == null or f.treasury <= 0:
		return
	var band: WarbandData = QuestService.band_to_hunt(ctx, s)
	if band != null and not _already_asked(ctx, QuestService.HUNT_BAND, band.id):
		QuestService.offer_hunt(ctx, s, ruler, band)
	elif s.food_ratio < QuestService.HUNGRY_BELOW and not _already_asked_at(ctx, QuestService.BRING_GOODS, s.id):
		QuestService.offer_grain(ctx, s, ruler)


## A captain of the giver's realm, idle in the town, may take a hunt.
func _npc_may_take(ctx: SimContext, q: QuestData, here: Array) -> void:
	var s: SettlementData = ctx.settlement(q.settlement_id)
	if s == null or here.is_empty():
		return
	var rng: RandomNumberGenerator = ctx.rng(&"quests")
	for id: int in here:
		var band: WarbandData = ctx.warband(id)
		if band == null or band.at_settlement_id != s.id or band.faction_id != s.faction_id:
			continue
		if band.leader_id == ctx.world.player_character_id or not AgentPolicy.is_ai_controlled(ctx, band.leader_id):
			continue
		if WarbandOps.headcount(band) < q.amount:
			continue
		if rng.randf() < NPC_TAKE_CHANCE and Actions.take_quest(ctx, band.leader_id, q.id).success:
			if not Actions.give_chase(ctx, band.leader_id, q.target_id).success:
				Actions.march_to(ctx, band.leader_id, WarbandOps.place_of(ctx, ctx.warband(q.target_id)))
			return


## Band ids in each town, in id order.
func _bands_in_towns(ctx: SimContext) -> Dictionary[int, Array]:
	var out: Dictionary[int, Array] = {}
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		if band != null and band.at_settlement_id >= 0:
			if not out.has(band.at_settlement_id):
				out[band.at_settlement_id] = []
			out[band.at_settlement_id].append(id)
	return out


func _already_asked(ctx: SimContext, kind: StringName, target_id: int) -> bool:
	for id: int in ctx.world.quests:
		var q: QuestData = ctx.world.quests[id]
		if q.kind == kind and q.target_id == target_id and (q.state == QuestData.State.OFFERED or q.state == QuestData.State.TAKEN):
			return true
	return false


func _already_asked_at(ctx: SimContext, kind: StringName, settlement_id: int) -> bool:
	for id: int in ctx.world.quests:
		var q: QuestData = ctx.world.quests[id]
		if q.kind == kind and q.settlement_id == settlement_id and (q.state == QuestData.State.OFFERED or q.state == QuestData.State.TAKEN):
			return true
	return false


func _sorted_ids(ctx: SimContext) -> Array[int]:
	var ids: Array[int] = []
	ids.assign(ctx.world.quests.keys())
	ids.sort()
	return ids
