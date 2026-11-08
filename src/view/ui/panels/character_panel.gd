class_name CharacterPanel
extends GamePanel
## Who you are: body, mind, skills, traits, wounds and standing.


func fill(me: CharacterData) -> void:
	var race: String = String(GeneticsService.dominant_race(me))
	var sex: String = "man" if me.sex == SimEnums.Sex.MALE else "woman"
	text("[b]%s[/b], a %d year old %s %s. %s of %s, living in %s." % [name_of(me.id), floori(ctx.age_years(me)), race, sex,
			String(me.occupation).capitalize(), realm_name(me.faction_id), town_name(me.settlement_id)])
	text(_standing(me))
	heading("Body and mind")
	var a: AttributesData = me.attributes
	text("Might %d    Agility %d    Wits %d    Will %d    Health %d%%" % [a.might, a.agility, a.wits, a.will, roundi(a.health * 100.0)])
	text("Fight %d%%    Walk %d%%    Work %d%%    Blood %d%%    Lasting harm %d%%" % [
			roundi(LimbService.fighting_capacity(ctx, me) * 100.0), roundi(LimbService.mobility(ctx, me) * 100.0),
			roundi(LimbService.work_capacity(ctx, me) * 100.0), roundi(me.body.blood * 100.0), roundi(LimbService.lasting_damage(me) * 100.0)])
	heading("Wounds")
	_wounds(me)
	heading("Skills")
	var skills: PackedStringArray = PackedStringArray()
	for skill: StringName in sorted_names(me.skills.levels.keys()):
		skills.append("%s %d" % [String(skill).capitalize(), me.skills.levels[skill]])
	text("    ".join(skills) if not skills.is_empty() else dim("You have learned nothing worth the name."))
	heading("Traits")
	var traits: PackedStringArray = PackedStringArray()
	for t: StringName in me.traits:
		traits.append(ctx.defs.traits[t].display_name if ctx.defs.traits.has(t) else String(t))
	text(", ".join(traits) if not traits.is_empty() else dim("None to speak of."))
	heading("Purse")
	text("Coin %d    Debt %d" % [me.inventory.gold, me.debt])


func _standing(me: CharacterData) -> String:
	var status: String = enum_word(SimEnums.LegalStatus.keys(), me.legal.status)
	if me.legal.status == SimEnums.LegalStatus.FREE:
		return "You are free."
	var owner: String = realm_name(me.legal.owner_id) if me.legal.owner_kind == SimEnums.OwnerKind.FACTION else name_of(me.legal.owner_id)
	var until: String = ""
	if me.legal.term_end_day >= 0:
		until = ", for %d more days" % maxi(me.legal.term_end_day - ctx.today(), 0)
	return "You are %s, held by %s%s." % [status, owner, until]


func _wounds(me: CharacterData) -> void:
	var any: bool = false
	for part: StringName in me.body.lost_parts:
		text("[color=#%s]%s lost[/color]" % [MenuStyle.BAD.to_html(false), _part_name(part)])
		any = true
	for part: StringName in ctx.defs.body_part_ids:
		var level: SimEnums.WoundLevel = LimbService.part_level(ctx, me, part)
		if level == SimEnums.WoundLevel.UNHURT or level == SimEnums.WoundLevel.LOST:
			continue
		var bleeding: bool = false
		for w: WoundData in me.body.wounds:
			bleeding = bleeding or (w.part_id == part and w.bleed > 0.0)
		text("%s: %s%s" % [_part_name(part), enum_word(SimEnums.WoundLevel.keys(), level), ", bleeding" if bleeding else ""])
		any = true
	if not any:
		text(dim("Whole and unhurt."))


func _part_name(part: StringName) -> String:
	if ctx.defs.body_parts.has(part) and not ctx.defs.body_parts[part].display_name.is_empty():
		return ctx.defs.body_parts[part].display_name
	return String(part).replace("_", " ").capitalize()
