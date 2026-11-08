class_name LandSystem
extends SimSystem
## The slow change of the land. Lumber camps eat into the woods around their towns, and woods grow back around towns that
## have emptied. Rulers clearing land on purpose is a decision, and goes through Actions.

const FELLED_PER_CAMP_MONTH: float = 0.035
const REGROWN_PER_MONTH: float = 0.06
const EMPTY_SHARE: float = 0.25


func tick(ctx: SimContext) -> void:
	if ctx.world.map.land_id == &"":
		return
	for id: int in ctx.settlement_ids():
		if ctx.is_turn(id):
			_month_of_land(ctx, ctx.world.settlements[id])


func _month_of_land(ctx: SimContext, s: SettlementData) -> void:
	var camps: int = 0
	for business_id: int in s.business_ids:
		if ctx.world.businesses[business_id].building_id == &"lumber_camp":
			camps += 1
	if camps > 0 and LandOps.has_land_for(ctx, s, &"woods"):
		LandOps.fell(ctx, s, camps * FELLED_PER_CAMP_MONTH)
	elif camps == 0 and PopService.total(s) < s.capacity * EMPTY_SHARE:
		LandOps.regrow(ctx, s, REGROWN_PER_MONTH)
