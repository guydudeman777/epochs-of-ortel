class_name QuestsPanel
extends GamePanel
## What you have given your word to, what is asked of anyone in the town you are in, and what is past.


func fill(me: CharacterData) -> void:
	var taken: Array[QuestData] = []
	var offered: Array[QuestData] = []
	var past: Array[QuestData] = []
	var here: int = _where_am_i(me)
	for id: int in _sorted_ids():
		var q: QuestData = ctx.world.quests[id]
		if q.taker_id == me.id and q.state == QuestData.State.TAKEN:
			taken.append(q)
		elif q.state == QuestData.State.OFFERED and q.settlement_id == here:
			offered.append(q)
		elif q.taker_id == me.id:
			past.append(q)
	heading("Your word")
	if taken.is_empty():
		text(dim("You have given your word to nobody."))
	for q: QuestData in taken:
		var words: String = "%s %s" % [q.summary, dim("  for %s, %d coin, %s" % [name_of(q.giver_id), q.reward_gold, _due(q)])]
		if q.kind == QuestService.BRING_GOODS and here == q.settlement_id:
			row(words, [["Hand over", act.bind(Actions.turn_in_quest.bind(ctx, me.id, q.id))]])
		else:
			text(words)
	heading("Asked here")
	if here < 0:
		text(dim("Out on the land nobody asks you anything."))
	elif offered.is_empty():
		text(dim("Nobody in %s wants anything of you." % town_name(here)))
	for q: QuestData in offered:
		row("%s %s" % [q.summary, dim("  %s, %d coin, %s" % [name_of(q.giver_id), q.reward_gold, _due(q)])],
				[["Take it", act.bind(Actions.take_quest.bind(ctx, me.id, q.id))]])
	heading("Past")
	if past.is_empty():
		text(dim("Nothing yet."))
	for i: int in range(past.size() - 1, maxi(past.size() - 20, 0) - 1, -1):
		var q: QuestData = past[i]
		text("%s %s" % [q.summary, dim("  " + enum_word(QuestData.State.keys(), q.state))])


func _where_am_i(me: CharacterData) -> int:
	var band: WarbandData = ctx.warband(me.warband_id)
	if band != null:
		return band.at_settlement_id
	return me.settlement_id


func _due(q: QuestData) -> String:
	if q.due_day < 0:
		return "no end"
	return "%d days left" % maxi(q.due_day - ctx.today(), 0)


func _sorted_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(ctx.world.quests.keys())
	ids.sort()
	return ids
