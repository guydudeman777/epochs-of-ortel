class_name FamilyPanel
extends GamePanel
## Your blood: parents, spouse, children, the house, and who you become when you die.


func fill(me: CharacterData) -> void:
	var dynasty: DynastyData = ctx.world.dynasties.get(me.dynasty_id, null)
	if dynasty != null:
		text("House [b]%s[/b], founded by %s. %d of the blood still live." % [dynasty.display_name, name_of(dynasty.founder_id), dynasty.living_member_ids.size()])
	var heir: CharacterData = SuccessionService.find_heir(ctx, me)
	heading("Heir")
	if heir != null:
		text("If you die, you go on as [b]%s[/b], %d years old, in %s." % [name_of(heir.id), floori(ctx.age_years(heir)), town_name(heir.settlement_id)])
	else:
		text("[color=#%s]You have no heir. If you die, the line ends.[/color]" % MenuStyle.BAD.to_html(false))
	heading("Parents")
	_person_line(me.father_id, "Father")
	_person_line(me.mother_id, "Mother")
	heading("Spouse")
	if me.spouse_id >= 0:
		_person_line(me.spouse_id, "")
	else:
		text(dim("Unwed."))
	heading("Children")
	if me.children_ids.is_empty():
		text(dim("None."))
	for id: int in me.children_ids:
		_person_line(id, "")
	if dynasty != null:
		heading("The rest of the house")
		var shown: int = 0
		for id: int in dynasty.living_member_ids:
			if id == me.id or id == me.spouse_id or me.children_ids.has(id) or id == me.father_id or id == me.mother_id:
				continue
			_person_line(id, "")
			shown += 1
			if shown >= 30:
				text(dim("And %d more." % (dynasty.living_member_ids.size() - shown)))
				break


func _person_line(id: int, role: String) -> void:
	var c: CharacterData = person(id)
	var lead: String = "%s: " % role if not role.is_empty() else ""
	if c == null:
		text(lead + dim("unknown"))
		return
	var age: String = "%d" % floori(ctx.age_years(c)) if c.death_day < 0 else "died aged %d" % floori(float(c.death_day - c.birth_day) / CalendarData.DAYS_PER_YEAR)
	text("%s%s, %s, %s%s" % [lead, name_of(id), age, String(c.occupation), dim("   %s" % town_name(c.settlement_id)) if c.death_day < 0 else ""])
