class_name ChronicleRecorder
extends RefCounted
## Listens to the event hub and keeps running totals and a readable history.

const MIN_LOGGED_ENSLAVEMENT: int = 20

var _ctx: SimContext


func _init(ctx: SimContext) -> void:
	_ctx = ctx
	var hub: EventHub = ctx.events
	hub.character_born.connect(func(_id: int) -> void: _ctx.bump(&"births"))
	hub.character_died.connect(_on_died)
	hub.marriage_formed.connect(func(_a: int, _b: int) -> void: _ctx.bump(&"marriages"))
	hub.character_wounded.connect(func(_id: int, _p: StringName, _l: SimEnums.WoundLevel) -> void: _ctx.bump(&"wounds_taken"))
	hub.limb_lost.connect(_on_limb_lost)
	hub.character_enslaved.connect(_on_enslaved)
	hub.character_freed.connect(func(_id: int, _r: StringName) -> void: _ctx.bump(&"characters_freed"))
	hub.pop_enslaved.connect(_on_pop_enslaved)
	hub.pop_freed.connect(func(_s: int, _race: StringName, n: int, _r: StringName) -> void: _ctx.bump(&"pops_freed", n))
	hub.pop_escaped.connect(func(_s: int, _race: StringName, n: int) -> void: _ctx.bump(&"pops_escaped", n))
	hub.captives_sold.connect(func(_s: int, _race: StringName, n: int, _g: int) -> void: _ctx.bump(&"captives_sold", n))
	hub.revolt_started.connect(_on_revolt)
	hub.revolt_ended.connect(_on_revolt_ended)
	hub.settlement_captured.connect(_on_captured)
	hub.settlement_raided.connect(func(_s: int, _w: int) -> void: _ctx.bump(&"raids"))
	hub.settlement_founded.connect(func(_s: int) -> void: _ctx.bump(&"settlements_founded"))
	hub.faction_founded.connect(_on_faction_founded)
	hub.faction_destroyed.connect(_on_faction_destroyed)
	hub.realm_split.connect(_on_split)
	hub.war_declared.connect(_on_war)
	hub.peace_made.connect(_on_peace)
	hub.law_changed.connect(_on_law)
	hub.tech_discovered.connect(_on_tech)
	hub.battle_resolved.connect(func(_w: String, _l: String, _s: int) -> void: _ctx.bump(&"battles"))
	hub.business_founded.connect(func(_b: int) -> void: _ctx.bump(&"businesses_founded"))
	hub.warband_formed.connect(func(_w: int) -> void: _ctx.bump(&"warbands_formed"))
	hub.player_character_changed.connect(_on_player_changed)
	hub.player_line_ended.connect(func(_id: int) -> void: _ctx.log_event(&"player", "The player's line has ended."))


func _faction_name(id: int) -> String:
	var f: FactionData = _ctx.faction(id)
	return f.display_name if f != null else "the unaligned"


func _settlement_name(id: int) -> String:
	var s: SettlementData = _ctx.settlement(id)
	return s.display_name if s != null else "the wilds"


func _on_died(id: int, cause: StringName) -> void:
	_ctx.bump(&"deaths")
	_ctx.bump(StringName("deaths_" + String(cause)))
	var c: CharacterData = _ctx.character(id)
	if c != null and c.occupation == &"ruler":
		_ctx.log_event(&"death", "%s, ruler, died (%s)." % [c.given_name, cause])


func _on_limb_lost(id: int, part_id: StringName) -> void:
	var c: CharacterData = _ctx.character(id)
	if c != null and c.occupation == &"ruler":
		_ctx.log_event(&"maimed", "%s, ruler, lost the %s." % [c.given_name, _ctx.defs.body_parts[part_id].display_name])


func _on_enslaved(id: int, origin: SimEnums.BondageOrigin) -> void:
	_ctx.bump(&"characters_enslaved")
	_ctx.bump(StringName("characters_enslaved_" + str(SimEnums.BondageOrigin.keys()[origin]).to_lower()))
	if id == _ctx.world.player_character_id:
		var c: CharacterData = _ctx.character(id)
		_ctx.log_event(&"player", "%s, the player, was taken into bondage." % c.given_name)


func _on_pop_enslaved(s_id: int, race: StringName, count: int, origin: SimEnums.BondageOrigin) -> void:
	_ctx.bump(&"pops_enslaved", count)
	if count < MIN_LOGGED_ENSLAVEMENT:
		return
	_ctx.log_event(&"bondage", "%d %s taken into bondage at %s (%s)." % [count, race, _settlement_name(s_id), SimEnums.BondageOrigin.keys()[origin]])


func _on_revolt(s_id: int, race: StringName, rebels: int) -> void:
	_ctx.bump(&"revolts")
	_ctx.log_event(&"revolt", "%d %s rose in revolt at %s." % [rebels, race, _settlement_name(s_id)])


func _on_revolt_ended(s_id: int, won: bool) -> void:
	if won:
		_ctx.bump(&"revolts_won")
	_ctx.log_event(&"revolt", "The revolt at %s %s." % [_settlement_name(s_id), "succeeded" if won else "was crushed"])


func _on_captured(s_id: int, old_id: int, new_id: int) -> void:
	_ctx.bump(&"settlements_captured")
	_ctx.log_event(&"war", "%s fell: %s took it from %s." % [_settlement_name(s_id), _faction_name(new_id), _faction_name(old_id)])


func _on_faction_founded(id: int) -> void:
	_ctx.bump(&"factions_founded")
	_ctx.log_event(&"faction", "%s was founded." % _faction_name(id))


func _on_faction_destroyed(id: int) -> void:
	_ctx.bump(&"factions_destroyed")
	_ctx.log_event(&"faction", "%s was destroyed." % _faction_name(id))


func _on_split(new_id: int, old_id: int) -> void:
	_ctx.bump(&"realm_splits")
	_ctx.log_event(&"faction", "%s broke away from %s." % [_faction_name(new_id), _faction_name(old_id)])


func _on_war(a: int, b: int) -> void:
	_ctx.bump(&"wars")
	_ctx.log_event(&"war", "%s declared war on %s." % [_faction_name(a), _faction_name(b)])


func _on_peace(a: int, b: int) -> void:
	_ctx.bump(&"peaces")
	_ctx.log_event(&"war", "%s and %s made peace." % [_faction_name(a), _faction_name(b)])


func _on_law(id: int, what: StringName) -> void:
	_ctx.bump(&"law_changes")
	_ctx.bump(StringName("law_" + String(what)))
	var f: FactionData = _ctx.faction(id)
	var law: String = str(SimEnums.BondageLaw.keys()[f.laws.bondage_law]).to_lower() if f != null else ""
	match what:
		&"bondage_tightened":
			_ctx.log_event(&"law", "%s hardened its bondage law to %s." % [_faction_name(id), law])
		&"bondage_loosened":
			_ctx.log_event(&"law", "%s softened its bondage law to %s." % [_faction_name(id), law])
		_:
			_ctx.log_event(&"law", "%s reordered the standing of its peoples." % _faction_name(id))


func _on_tech(id: int, tech: StringName) -> void:
	_ctx.bump(&"techs_discovered")
	_ctx.log_event(&"tech", "%s discovered %s." % [_faction_name(id), tech])


func _on_player_changed(_old_id: int, new_id: int) -> void:
	_ctx.bump(&"player_handoffs")
	var c: CharacterData = _ctx.character(new_id)
	if c != null:
		_ctx.log_event(&"player", "Play passed to the heir, %s." % c.given_name)
