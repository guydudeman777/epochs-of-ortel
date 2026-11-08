class_name QuestService
extends RefCounted
## The kinds of quest, how each is made from a real want, and paying out. Rules here bind NPCs and the player alike.

const HUNT_BAND: StringName = &"hunt_band"
const BRING_GOODS: StringName = &"bring_goods"
## How far from a town a band must be for its lord to want it gone.
const HUNT_RANGE: float = 220.0
const HUNT_DAYS: int = 40
const BRING_DAYS: int = 30
const HUNT_PAY_PER_HEAD: int = 3
## A town's food store this far short makes its lord ask for grain.
const HUNGRY_BELOW: float = 0.85
const GRAIN_ASKED: int = 40
const GRAIN_PAY_SHARE: float = 1.6
const OPEN_PER_TOWN: int = 2


## Pays the taker what the giver's realm can pay, and marks the quest done. Returns what was paid.
static func complete(ctx: SimContext, q: QuestData) -> int:
	q.state = QuestData.State.DONE
	var taker: CharacterData = ctx.character(q.taker_id)
	var s: SettlementData = ctx.settlement(q.settlement_id)
	var f: FactionData = ctx.faction(s.faction_id) if s != null else null
	if taker == null or f == null:
		return 0
	var paid: int = mini(q.reward_gold, maxi(f.treasury, 0))
	f.treasury -= paid
	Actions.wallet_of(ctx, taker).gold += paid
	ctx.bump(&"quests_done")
	return paid


## The nearest band within HUNT_RANGE that preys on this town, or null.
static func band_to_hunt(ctx: SimContext, s: SettlementData) -> WarbandData:
	var at: Vector2 = ctx.world.map.positions.get(s.id, Vector2.INF)
	if at == Vector2.INF:
		return null
	var best: WarbandData = null
	var best_distance: float = HUNT_RANGE
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		if band == null or not _preys_on(ctx, band, s):
			continue
		var distance: float = WarbandOps.place_of(ctx, band).distance_to(at)
		if distance < best_distance:
			best = band
			best_distance = distance
	return best


static func _preys_on(ctx: SimContext, band: WarbandData, s: SettlementData) -> bool:
	if band.role == SimEnums.WarbandRole.BANDIT or band.role == SimEnums.WarbandRole.SLAVER:
		return band.faction_id != s.faction_id
	return band.role == SimEnums.WarbandRole.ARMY and FactionOps.are_at_war(ctx, band.faction_id, s.faction_id)


static func offer_hunt(ctx: SimContext, s: SettlementData, ruler: CharacterData, band: WarbandData) -> QuestData:
	var q: QuestData = _new_quest(ctx, HUNT_BAND, s, ruler)
	q.target_id = band.id
	q.amount = WarbandOps.headcount(band)
	q.reward_gold = maxi(q.amount * HUNT_PAY_PER_HEAD, 10)
	q.due_day = ctx.today() + HUNT_DAYS
	q.summary = "Break %s, %d strong, who prey on %s." % [band.display_name, q.amount, s.display_name]
	return q


static func offer_grain(ctx: SimContext, s: SettlementData, ruler: CharacterData) -> QuestData:
	var q: QuestData = _new_quest(ctx, BRING_GOODS, s, ruler)
	q.target_thing = &"grain"
	q.amount = GRAIN_ASKED
	q.reward_gold = ceili(Pricing.price_of(s, &"grain") * GRAIN_ASKED * GRAIN_PAY_SHARE)
	q.due_day = ctx.today() + BRING_DAYS
	q.summary = "Bring %d grain to hungry %s." % [GRAIN_ASKED, s.display_name]
	return q


static func _new_quest(ctx: SimContext, kind: StringName, s: SettlementData, giver: CharacterData) -> QuestData:
	var q: QuestData = QuestData.new()
	q.id = ctx.new_id()
	q.kind = kind
	q.giver_id = giver.id
	q.settlement_id = s.id
	q.offered_day = ctx.today()
	ctx.world.quests[q.id] = q
	return q
