class_name KingdomPanel
extends GamePanel
## The realm you answer to, or failing that the realm of the town you are in: its ruler, laws, towns, wars and crafts.
## Then every realm of Ortel in short.


func fill(me: CharacterData) -> void:
	var f: FactionData = ctx.faction(me.faction_id)
	if f == null:
		var here: SettlementData = ctx.settlement(me.settlement_id)
		f = ctx.faction(here.faction_id) if here != null else null
		text(dim("You answer to no realm. This is the realm you are in."))
	if f != null:
		_realm(me, f)
	heading("The realms of Ortel")
	var ids: Array[int] = ctx.faction_ids()
	ids.sort_custom(func(a: int, b: int) -> bool: return _people(ctx.world.factions[a]) > _people(ctx.world.factions[b]))
	for id: int in ids:
		var other: FactionData = ctx.world.factions[id]
		if other.destroyed:
			continue
		var war: String = ""
		if f != null and f.at_war_with.has(id):
			war = " [color=#%s]at war with you[/color]" % MenuStyle.BAD.to_html(false)
		text("[b]%s[/b]%s: %d towns, %d people, ruled by %s%s" % [other.display_name, " (rebels)" if other.is_rebel else "",
				other.settlement_ids.size(), _people(other), name_of(other.ruler_id), war])


func _realm(me: CharacterData, f: FactionData) -> void:
	var culture: CultureDef = ctx.defs.cultures.get(f.culture_id, null)
	text("[b]%s[/b], a realm of the %s. Ruled by %s%s." % [f.display_name, culture.display_name if culture != null else String(f.culture_id),
			"you" if f.ruler_id == me.id else name_of(f.ruler_id),
			" since year %d" % floori(float(f.ruler_since_day) / CalendarData.DAYS_PER_YEAR) if f.ruler_since_day >= 0 else ""])
	text("Treasury %d coin. Tax %d%%." % [f.treasury, roundi(f.laws.tax_rate * 100.0)])
	heading("Laws")
	text("Bondage: %s%s. By custom: %s." % [enum_word(SimEnums.BondageLaw.keys(), f.laws.bondage_law),
			", passed to children" if f.laws.hereditary_bondage else "", enum_word(SimEnums.BondageLaw.keys(), f.laws.customary_bondage_law)])
	var standing: PackedStringArray = PackedStringArray()
	for race: StringName in sorted_names(f.laws.race_standing.keys()):
		standing.append("%s %s" % [race, enum_word(SimEnums.RaceStanding.keys(), f.laws.race_standing[race])])
	if not standing.is_empty():
		text("Peoples: " + ", ".join(standing))
	heading("Towns")
	var towns: Array[int] = f.settlement_ids.duplicate()
	towns.sort()
	for id: int in towns:
		var s: SettlementData = ctx.settlement(id)
		if s != null:
			text("%s: %d people, walls %.1f, garrison %d%s" % [s.display_name, PopService.total(s), s.fortification,
					FactionOps.garrison_size(s), dim("   raided %d days ago" % (ctx.today() - s.last_raided_day)) if s.last_raided_day >= 0 else ""])
	heading("Wars")
	if f.at_war_with.is_empty():
		text(dim("At peace."))
	for id: int in f.at_war_with:
		text("%s, %d months of war" % [realm_name(id), f.war_months])
	heading("Crafts known")
	var crafts: PackedStringArray = PackedStringArray()
	for tech: StringName in f.known_techs:
		crafts.append(ctx.defs.techs[tech].display_name if ctx.defs.techs.has(tech) else String(tech))
	text(", ".join(crafts) if not crafts.is_empty() else dim("Nothing beyond the plough."))


func _people(f: FactionData) -> int:
	var total: int = 0
	for id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(id)
		if s != null:
			total += PopService.total(s)
	return total
