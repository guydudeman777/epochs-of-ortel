class_name QuestsPanel
extends GamePanel
## What you have given your word to, what is asked of anyone in the town you are in, and what is past: each a note
## on vellum, with who asks, what they pay, and how long is left.

const PAST_SHOWN: int = 20
const NOTE_WIDTH: float = 380.0


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
	PanelStyle.heading(self, "Your word", &"seal")
	var mine: HFlowContainer = _board()
	for q: QuestData in taken:
		var action: Array = []
		if q.kind == QuestService.BRING_GOODS and here == q.settlement_id:
			action = ["Hand over", act.bind(Actions.turn_in_quest.bind(ctx, me.id, q.id))]
		mine.add_child(_note(q, action, true))
	if taken.is_empty():
		add_child(PanelStyle.words("You have given your word to nobody.", 16, MenuStyle.DIM))
	PanelStyle.heading(self, "Asked here", &"scroll")
	if here < 0:
		add_child(PanelStyle.words("Out on the land nobody asks you anything.", 16, MenuStyle.DIM))
	elif offered.is_empty():
		add_child(PanelStyle.words("Nobody in %s wants anything of you." % town_name(here), 16, MenuStyle.DIM))
	else:
		var asked: HFlowContainer = _board()
		for q: QuestData in offered:
			asked.add_child(_note(q, ["Take it", act.bind(Actions.take_quest.bind(ctx, me.id, q.id))], false))
	PanelStyle.heading(self, "Past", &"hourglass")
	if past.is_empty():
		add_child(PanelStyle.words("Nothing yet.", 16, MenuStyle.DIM))
	for i: int in range(past.size() - 1, maxi(past.size() - PAST_SHOWN, 0) - 1, -1):
		var q: QuestData = past[i]
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		var done: bool = q.state == QuestData.State.DONE
		line.add_child(Glyph.make(&"star" if done else &"cross", 16.0, PanelStyle.GILT if done else MenuStyle.FAINT))
		line.add_child(MenuStyle.label(q.summary, 15))
		line.add_child(MenuStyle.label(enum_word(QuestData.State.keys(), q.state), 14, MenuStyle.DIM))
		add_child(line)


func _board() -> HFlowContainer:
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 12)
	flow.add_theme_constant_override(&"v_separation", 12)
	add_child(flow)
	return flow


## One note: the sign of the task, what is asked in ink, who asks and what they pay, and a button.
func _note(q: QuestData, action: Array, held: bool) -> PanelContainer:
	var note: PanelContainer = PanelContainer.new()
	note.theme_type_variation = &"Vellum"
	note.custom_minimum_size = Vector2(NOTE_WIDTH, 0.0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	note.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	column.add_child(top)
	var hunt: bool = q.kind == QuestService.HUNT_BAND
	top.add_child(Glyph.make(&"sword" if hunt else &"wheat", 30.0, PanelStyle.RUBRIC))
	var title: Label = PanelStyle.ink(q.summary, 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var giver: CharacterData = person(q.giver_id)
	var asks: HBoxContainer = HBoxContainer.new()
	asks.add_theme_constant_override(&"separation", 8)
	column.add_child(asks)
	if giver != null:
		asks.add_child(likeness(giver, 40.0))
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	asks.add_child(words)
	words.add_child(PanelStyle.ink("Asked by %s of %s" % [plain_name(q.giver_id), town_name(q.settlement_id)], 15, PanelStyle.INK_FADED))
	words.add_child(PanelStyle.ink("%d coin, %s" % [q.reward_gold, _due(q)], 15, PanelStyle.RUBRIC if held else PanelStyle.INK))
	if not action.is_empty():
		var button: Button = PanelStyle.button(action[0] as String, action[1] as Callable)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
		column.add_child(button)
	return note


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
