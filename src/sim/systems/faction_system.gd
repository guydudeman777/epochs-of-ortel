class_name FactionSystem
extends SimSystem
## The mechanical side of a realm: wages, relations, empty thrones. Decisions live in AgentSystem.

const RELATION_DRIFT: int = 1
const MAX_STIPEND: int = 20
const STIPEND_SHARE: float = 0.05
const TREASURY_RESERVE: int = 8000
const SPENDING_SHARE: float = 0.04


func tick(ctx: SimContext) -> void:
	for id: int in ctx.faction_ids():
		if ctx.is_turn(id):
			_process(ctx, ctx.world.factions[id])


func _process(ctx: SimContext, f: FactionData) -> void:
	if f.settlement_ids.is_empty():
		FactionOps.destroy_faction(ctx, f)
		return
	if f.ruler_id < 0 or ctx.character(f.ruler_id) == null:
		_fill_throne(ctx, f)
	if not f.at_war_with.is_empty():
		f.war_months += 1
	_drift_relations(f)
	_pay_garrisons(ctx, f)
	_pay_ruler(ctx, f)
	_spend_surplus(ctx, f)


## Courts, works and patronage. The coin returns to the realm's markets.
func _spend_surplus(ctx: SimContext, f: FactionData) -> void:
	var surplus: int = f.treasury - TREASURY_RESERVE
	if surplus <= 0 or f.settlement_ids.is_empty():
		return
	var spent: int = roundi(surplus * SPENDING_SHARE)
	var each: int = floori(spent / float(f.settlement_ids.size()))
	for s_id: int in f.settlement_ids:
		ctx.settlement(s_id).purse += each
	f.treasury -= each * f.settlement_ids.size()


func _fill_throne(ctx: SimContext, f: FactionData) -> void:
	var nobody: CharacterData = CharacterData.new()
	nobody.id = -2
	var next: CharacterData = SuccessionService.find_ruler(ctx, nobody, f)
	if next != null:
		FactionOps.set_ruler(ctx, f, next)


func _drift_relations(f: FactionData) -> void:
	for id: int in f.relations:
		var value: int = f.relations[id]
		if value > 0:
			f.relations[id] = value - RELATION_DRIFT
		elif value < 0:
			f.relations[id] = value + RELATION_DRIFT


func _pay_garrisons(ctx: SimContext, f: FactionData) -> void:
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		var bill: float = 0.0
		for id: StringName in s.garrison:
			bill += ctx.defs.troops[id].wage * s.garrison[id]
		var owed: int = roundi(bill)
		var paid: int = mini(owed, f.treasury)
		f.treasury -= paid
		# Soldiers spend their wages locally, so the money stays in the realm.
		s.purse += paid
		if paid < owed:
			_garrison_desertion(ctx, s)


func _garrison_desertion(ctx: SimContext, s: SettlementData) -> void:
	var rng: RandomNumberGenerator = ctx.rng(&"faction")
	var ids: Array[StringName] = []
	ids.assign(s.garrison.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var race: StringName = PopService.dominant_free_race(s)
	for id: StringName in ids:
		var count: int = s.garrison[id]
		var gone: int = PopService.random_round(rng, count * 0.1)
		if count - gone <= 0:
			s.garrison.erase(id)
		else:
			s.garrison[id] = count - gone
		if race != &"":
			PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count += gone


func _pay_ruler(ctx: SimContext, f: FactionData) -> void:
	var ruler: CharacterData = ctx.character(f.ruler_id)
	if ruler == null:
		return
	var stipend: int = mini(MAX_STIPEND, roundi(f.treasury * STIPEND_SHARE))
	f.treasury -= stipend
	ruler.inventory.gold += stipend
