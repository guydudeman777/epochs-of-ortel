class_name PartyPanel
extends GamePanel
## The band you march with: who leads, who follows, troops, captives, chest and food.


func fill(me: CharacterData) -> void:
	var band: WarbandData = ctx.warband(me.warband_id)
	if band == null:
		text("You march with nobody. In a town you can take to the road with a band of your own, or join one.")
		return
	var leads: bool = band.leader_id == me.id
	text("[b]%s[/b], %d strong, %s. Led by %s." % [band.display_name, WarbandOps.headcount(band),
			enum_word(SimEnums.WarbandRole.keys(), band.role), "you" if leads else name_of(band.leader_id)])
	text("Answering to %s. %s" % [realm_name(band.faction_id), _where(band)])
	heading("Named people")
	for id: int in band.member_ids:
		var c: CharacterData = person(id)
		if c == null:
			continue
		text("%s, %d, %s%s" % [name_of(id), floori(ctx.age_years(c)), String(GeneticsService.dominant_race(c)),
				dim("   fight %d%%" % roundi(LimbService.fighting_capacity(ctx, c) * 100.0))])
	heading("Troops")
	var any: bool = false
	for kind: StringName in sorted_names(band.troops.keys()):
		var def: TroopDef = ctx.defs.troops.get(kind, null)
		var wage: String = ""
		text("%d %s%s" % [band.troops[kind], def.display_name if def != null else String(kind), wage])
		any = true
	if not any:
		text(dim("None. Hire them in a town."))
	heading("Captives")
	var held: int = 0
	for race: StringName in sorted_names(band.captives.keys()):
		text("%d %s" % [band.captives[race], race])
		held += band.captives[race]
	if held == 0:
		text(dim("None."))
	elif leads and band.at_settlement_id >= 0:
		row("Let them go here.", [["Free them", act.bind(Actions.release_captives.bind(ctx, me.id))]])
	heading("Chest and food")
	var daily: float = maxf(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY, 0.001)
	text("Chest %d coin. Supplies %d, enough for %d days." % [band.inventory.gold, floori(band.supplies), floori(band.supplies / daily)])
	var ground: OverworldTerrain.Kind = ctx.terrain().kind_at(WarbandOps.place_of(ctx, band))
	text("Pace %d a day on %s." % [roundi(WarbandOps.travel_speed(ctx, band) * OverworldTerrain.SPEED[ground]), enum_word(OverworldTerrain.Kind.keys(), ground)])


func _where(band: WarbandData) -> String:
	if band.at_settlement_id >= 0:
		return "In %s." % town_name(band.at_settlement_id)
	if band.chase_band_id >= 0:
		var other: WarbandData = ctx.warband(band.chase_band_id)
		return "Chasing %s." % (other.display_name if other != null else "someone")
	if band.has_destination:
		return "On the move."
	return "Standing still."
