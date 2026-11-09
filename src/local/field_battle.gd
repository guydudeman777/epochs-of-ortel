class_name FieldBattle
extends RefCounted
## The battle two real bands fight when the player's meets an enemy, with no scene in it. Named people fight as themselves.
## Each unnamed soldier gets a temporary fighter. Only so many stand on the field at once, and the rest wait their turn and
## walk on as others fall, so every head in the troop count is met in the end. What comes of it goes back to the world in finish.

## Who a side has left to send on. Named people first, then soldiers in a shuffled order.
class Waiting:
	var character_id: int = -1
	var troop_id: StringName = &""

const ON_FIELD: int = 16
const FIELD_RADIUS: float = 17.0
const LINE_GAP: float = 1.9
const LINES_APART: float = 11.0
## Seconds between one reinforcement and the next, per side.
const COME_ON_EVERY: float = 0.6
const COME_ON_FROM: float = 0.85
## Spread across the field that someone coming on may start from.
const COME_ON_SPREAD: float = 8.0

var ctx: SimContext
var fight: LocalFight
var band_ids: Array[int] = [-1, -1]
var site_id: int = -1
## Those who came on since the view last looked. The view empties this.
var joined: Array[DuelFighter] = []
var finished: bool = false
## What happened, in words, for whoever asks after.
var summary: String = ""
## The player's fighter, or null if the player is not in it.
var player_fighter: DuelFighter = null
var _waiting: Array[Array] = [[], []]
var _races: Array[StringName] = [&"", &""]
var _troop_of: Dictionary[int, StringName] = {}
var _labels: Array[String] = ["", ""]
var _factions: Array[int] = [-1, -1]
var _leaders: Array[int] = [-1, -1]
## Unnamed fallen settled without a fight on the field, by side.
var _settled: Array[Dictionary] = [{}, {}]
var _timers: Array[float] = [0.0, 0.0]
## How strong each side was when it began, for what it teaches the other.
var _strength_at_start: Array[float] = [0.0, 0.0]


## Starts the battle the player's band has met, or returns null if there is none to start.
static func begin(context: SimContext) -> FieldBattle:
	var enemy: WarbandData = context.warband(context.world.encounter_band_id)
	var player: CharacterData = context.character(context.world.player_character_id)
	if enemy == null or player == null:
		return null
	var mine: WarbandData = context.warband(player.warband_id)
	if mine == null:
		return null
	var battle: FieldBattle = FieldBattle.new()
	battle._set_up(context, mine, enemy, player.id)
	return battle


func _set_up(context: SimContext, mine: WarbandData, enemy: WarbandData, player_id: int) -> void:
	ctx = context
	fight = LocalFight.new(ctx)
	fight.arena_radius = FIELD_RADIUS
	band_ids = [mine.id, enemy.id]
	site_id = WarbandOps.site_of(ctx, mine)
	ctx.held_bands[mine.id] = true
	ctx.held_bands[enemy.id] = true
	var bands: Array[WarbandData] = [mine, enemy]
	var rng: RandomNumberGenerator = ctx.rng(&"field_battle")
	for side: int in range(2):
		var band: WarbandData = bands[side]
		var battle_side: BattleSide = BattleSide.from_band(band)
		_races[side] = BattleResolver._side_race(ctx, battle_side, site_id)
		_labels[side] = band.display_name
		_factions[side] = band.faction_id
		_leaders[side] = band.leader_id
		_strength_at_start[side] = BattleResolver.strength(ctx, battle_side)
		_waiting[side] = _muster(band, player_id, rng)
		_form_line(side)
		fight.waiting[side] = _waiting[side].size()


## The named first, the player at the head of them, then the soldiers in no particular order.
func _muster(band: WarbandData, player_id: int, rng: RandomNumberGenerator) -> Array:
	var named: Array[int] = band.member_ids.duplicate()
	named.sort()
	var out: Array = []
	if named.has(player_id):
		named.erase(player_id)
		named.push_front(player_id)
	for id: int in named:
		var person: Waiting = Waiting.new()
		person.character_id = id
		out.append(person)
	var soldiers: Array = []
	var kinds: Array[StringName] = []
	kinds.assign(band.troops.keys())
	kinds.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	for kind: StringName in kinds:
		for i: int in range(band.troops[kind]):
			var soldier: Waiting = Waiting.new()
			soldier.troop_id = kind
			soldiers.append(soldier)
	for i: int in range(soldiers.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, i)
		var kept: Waiting = soldiers[i]
		soldiers[i] = soldiers[other]
		soldiers[other] = kept
	out.append_array(soldiers)
	return out


func _form_line(side: int) -> void:
	var count: int = mini(_waiting[side].size(), ON_FIELD)
	for i: int in range(count):
		# The player stands in the middle of the line, so the first in the muster goes there.
		var slot: int = (i + count / 2) % count
		var across: float = (float(slot) - float(count - 1) * 0.5) * LINE_GAP
		var along: float = LINES_APART * 0.5 * (-1.0 if side == 0 else 1.0)
		_come_on(side, Vector2(across, along))


func _come_on(side: int, at: Vector2) -> void:
	var next: Waiting = _waiting[side].pop_front()
	fight.waiting[side] = _waiting[side].size()
	var id: int = next.character_id
	if id < 0:
		var temp: CharacterData = CharacterFactory.create_temp_fighter(ctx, _race_for(side), &"soldier", _factions[side])
		id = temp.id
		_troop_of[id] = next.troop_id
		Actions.kit_out(ctx, id, next.troop_id)
	elif ctx.character(id) == null:
		return
	var towards: Vector2 = Vector2(0.0, 1.0 if side == 0 else -1.0)
	var f: DuelFighter = fight.add_fighter(id, side, at, towards)
	if id == ctx.world.player_character_id:
		player_fighter = f
	joined.append(f)


func _race_for(side: int) -> StringName:
	if _races[side] != &"":
		return _races[side]
	return ctx.defs.race_ids[0]


## Call each frame once the fight has moved on. Sends on whoever is waiting, while there is room.
func top_up(seconds: float) -> void:
	if finished or fight.over:
		return
	var rng: RandomNumberGenerator = ctx.rng(&"field_battle")
	for side: int in range(2):
		_timers[side] -= seconds
		if _timers[side] > 0.0 or _waiting[side].is_empty() or fight.standing_on(side) >= ON_FIELD:
			continue
		_timers[side] = COME_ON_EVERY
		var edge: float = FIELD_RADIUS * COME_ON_FROM * (-1.0 if side == 0 else 1.0)
		_come_on(side, Vector2(rng.randf_range(-COME_ON_SPREAD, COME_ON_SPREAD), edge))


## Whether this fighter is a temporary stand-in for a soldier with no name.
func is_unnamed(character_id: int) -> bool:
	return _troop_of.has(character_id)


## Who the player is fighting beside and against, for the screen.
func label_of(side: int) -> String:
	return _labels[side]


## Decides what is left of the battle at a stroke, the way a battle out of sight is decided. For once the player is out of it.
func settle_the_rest() -> void:
	if finished or fight.over:
		return
	var sides: Array[BattleSide] = [BattleSide.new(), BattleSide.new()]
	for side: int in range(2):
		sides[side].faction_id = _factions[side]
		sides[side].leader_id = _leaders[side]
		sides[side].troops = _still_in_it(side)
	var rng: RandomNumberGenerator = ctx.rng(&"field_battle")
	var power_a: float = BattleResolver.strength(ctx, sides[0]) * rng.randf_range(0.8, 1.2) + float(fight.strength_of(0)) * 0.01
	var power_b: float = BattleResolver.strength(ctx, sides[1]) * rng.randf_range(0.8, 1.2) + float(fight.strength_of(1)) * 0.01
	var win: int = 0 if power_a >= power_b else 1
	var margin: float = maxf(power_a, power_b) / maxf(power_a + power_b, 0.001)
	_settled[win] = _lose_share(sides[win], 0.5 * (1.0 - margin), rng)
	_settled[1 - win] = _lose_share(sides[1 - win], 0.5 + 0.4 * margin, rng)
	_settle_named(1 - win, win, rng)
	_settle_named(win, -1, rng)
	fight.over = true
	fight.winning_side = win
	fight.waiting = [0, 0]
	_waiting = [[], []]


func _still_in_it(side: int) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for f: DuelFighter in fight.fighters:
		if f.side == side and not f.is_out() and _troop_of.has(f.character_id):
			var kind: StringName = _troop_of[f.character_id]
			var have: int = out.get(kind, 0)
			out[kind] = have + 1
	for entry: Waiting in _waiting[side]:
		if entry.troop_id != &"":
			var have: int = out.get(entry.troop_id, 0)
			out[entry.troop_id] = have + 1
	return out


func _lose_share(side: BattleSide, share: float, rng: RandomNumberGenerator) -> Dictionary:
	var before: Dictionary[StringName, int] = side.troops.duplicate()
	BattleResolver._apply_casualties(side, share, rng)
	var lost: Dictionary = {}
	for kind: StringName in before:
		var left: int = side.troops.get(kind, 0)
		lost[kind] = before[kind] - left
	return lost


## Named people who were still standing take their chances, as they would in any battle.
func _settle_named(side: int, winner: int, rng: RandomNumberGenerator) -> void:
	var ids: Array[int] = []
	for f: DuelFighter in fight.fighters:
		if f.side == side and not f.is_out() and not _troop_of.has(f.character_id):
			ids.append(f.character_id)
	for entry: Waiting in _waiting[side]:
		if entry.character_id >= 0:
			ids.append(entry.character_id)
	ids.sort()
	var lost: bool = winner >= 0
	for id: int in ids:
		var c: CharacterData = ctx.character(id)
		if c == null:
			continue
		var chance: float = BattleResolver.NAMED_WOUNDED_LOSER if lost else BattleResolver.NAMED_WOUNDED_WINNER
		var blows: int = BattleResolver.NAMED_BLOWS_LOSER if lost else BattleResolver.NAMED_BLOWS_WINNER
		if rng.randf() < chance:
			LimbService.battle_wounds(ctx, c, rng.randi_range(1, blows), rng)
		if lost and ctx.character(id) != null and rng.randf() < BattleResolver.NAMED_CAPTURE_LOSER:
			BattleResolver._capture_named(ctx, c, _side_for_capture(winner), site_id)


func _side_for_capture(side: int) -> BattleSide:
	var band: WarbandData = ctx.warband(band_ids[side])
	var out: BattleSide = BattleSide.from_band(band) if band != null else BattleSide.new()
	return out


## Carries the battle back into the world: the dead, the taken, the loot and the ledgers. Call once the fight is over.
func finish() -> void:
	if finished:
		return
	finished = true
	var win: int = fight.winning_side
	var dead: Array[int] = [0, 0]
	var taken: Array[int] = [0, 0]
	for side: int in range(2):
		var band: WarbandData = ctx.warband(band_ids[side])
		var lost_here: Dictionary[StringName, int] = {}
		var fallen_here: int = 0
		var taken_here: int = 0
		for f: DuelFighter in fight.fighters:
			if f.side != side or not _troop_of.has(f.character_id):
				continue
			var kind: StringName = _troop_of[f.character_id]
			var have: int = lost_here.get(kind, 0)
			if f.state == DuelFighter.State.DEAD:
				lost_here[kind] = have + 1
				fallen_here += 1
			elif side != win and win >= 0 and (f.state == DuelFighter.State.DOWN or f.state == DuelFighter.State.YIELDED):
				lost_here[kind] = have + 1
				taken_here += 1
		var settled: Dictionary = _settled[side]
		for kind: StringName in settled:
			var count: int = settled[kind]
			var have: int = lost_here.get(kind, 0)
			lost_here[kind] = have + count
			var alive: int = roundi(count * BattleResolver.CAPTIVE_SHARE) if side != win else 0
			taken_here += alive
			fallen_here += count - alive
		if band != null:
			_take_from_troops(band, lost_here)
			if win >= 0:
				TroopOps.gain_xp(ctx, band, TroopOps.battle_xp(_strength_at_start[1 - side], side == win))
		ctx.bump(&"ledger_troops_fallen", fallen_here)
		dead[side] = fallen_here
		taken[side] = taken_here
	_named_on_losing_side(win)
	var winner_side: BattleSide = _side_for_capture(win) if win >= 0 else null
	if winner_side != null:
		BattleResolver.take_alive(ctx, winner_side, _races[1 - win], taken[1 - win], site_id)
		var loser_band: WarbandData = ctx.warband(band_ids[1 - win])
		if loser_band != null and winner_side.band != null:
			BattleResolver._loot(winner_side, BattleSide.from_band(loser_band))
		ctx.events.battle_resolved.emit(_labels[win], _labels[1 - win], site_id)
		ctx.events.band_beaten.emit(band_ids[win], band_ids[1 - win])
	_let_go_of_bands()
	ctx.clear_temp_characters()
	WarbandSystem.part_after_battle(ctx, band_ids[0])
	WarbandSystem.part_after_battle(ctx, band_ids[1])
	Actions.end_encounter(ctx)
	summary = _describe(win, dead, taken)


func _take_from_troops(band: WarbandData, lost: Dictionary[StringName, int]) -> void:
	for kind: StringName in lost:
		var have: int = band.troops.get(kind, 0)
		var left: int = maxi(have - lost[kind], 0)
		TroopOps.lose_xp(band, kind, have, left)
		if left <= 0:
			band.troops.erase(kind)
		else:
			band.troops[kind] = left


## Named people beaten down or giving up on the losing side are the winner's to keep, if the winner's law allows.
func _named_on_losing_side(win: int) -> void:
	if win < 0:
		return
	var winner_side: BattleSide = _side_for_capture(win)
	for f: DuelFighter in fight.fighters:
		if f.side == win or _troop_of.has(f.character_id):
			continue
		var c: CharacterData = ctx.character(f.character_id)
		if c != null and (f.state == DuelFighter.State.DOWN or f.state == DuelFighter.State.YIELDED):
			BattleResolver._capture_named(ctx, c, winner_side, site_id)


## Bands that lost everyone can break up now that their troops have been counted.
func _let_go_of_bands() -> void:
	ctx.held_bands.clear()
	var to_break: Array[int] = []
	to_break.assign(ctx.bands_to_break_up.keys())
	to_break.sort()
	ctx.bands_to_break_up.clear()
	for id: int in to_break:
		var band: WarbandData = ctx.warband(id)
		if band != null:
			WarbandOps.destroy(ctx, band)
	for id: int in band_ids:
		var band: WarbandData = ctx.warband(id)
		if band != null:
			WarbandOps.destroy_if_empty(ctx, band)


func _describe(win: int, dead: Array[int], taken: Array[int]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if win < 0:
		lines.append("Nobody held the field.")
	else:
		lines.append("%s held the field." % _labels[win])
	for side: int in range(2):
		lines.append("%s lost %d dead and %d beaten." % [_labels[side], dead[side], taken[side]])
	return "\n".join(lines)
