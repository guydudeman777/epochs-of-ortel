class_name DuelFight
extends LocalFight
## Two people, one on each side. The one left standing decides what happens to the other.

## What a killing stroke on someone who cannot defend does, in blows at most.
const FINISH_BLOWS: int = 8

var a: DuelFighter
var b: DuelFighter
var winner_id: int = -1
var loser_id: int = -1
var _inputs: Array[DuelInput] = [null, null]


func _init(context: SimContext, a_id: int, b_id: int) -> void:
	super(context)
	a = add_fighter(a_id, 0, Vector2(0.0, -2.0), Vector2(0.0, 1.0))
	b = add_fighter(b_id, 1, Vector2(0.0, 2.0), Vector2(0.0, -1.0))


func advance(seconds: float, input_a: DuelInput, input_b: DuelInput) -> void:
	_inputs[0] = input_a
	_inputs[1] = input_b
	advance_all(seconds, _inputs)


func step(input_a: DuelInput, input_b: DuelInput) -> void:
	_inputs[0] = input_a
	_inputs[1] = input_b
	step_all(_inputs)


func other_of(f: DuelFighter) -> DuelFighter:
	return b if f == a else a


func _check_over() -> void:
	super()
	if over and loser_id < 0:
		var loser: DuelFighter = a if a.is_out() else b
		var winner: DuelFighter = b if a.is_out() else a
		loser_id = loser.character_id
		winner_id = winner.character_id if not winner.is_out() else -1


## The winner spares the loser, who walks off with what they have.
func spare() -> void:
	_event(&"spared", _fighter_of(loser_id), &"")


## The winner kills someone who can no longer defend. Same blows as any other, so a helmet still gets in the way.
func finish() -> void:
	var victim: DuelFighter = _fighter_of(loser_id)
	if victim == null or ctx.character(loser_id) == null:
		return
	for i: int in range(FINISH_BLOWS):
		if ctx.character(loser_id) == null:
			break
		Actions.land_blow(ctx, winner_id, loser_id, &"neck", true)
		if ctx.character(loser_id) != null:
			Actions.land_blow(ctx, winner_id, loser_id, &"torso", true)
	if ctx.character(loser_id) == null:
		victim._set_state(DuelFighter.State.DEAD)
		_event(&"dead", victim, &"neck")


func _fighter_of(id: int) -> DuelFighter:
	if a.character_id == id:
		return a
	return b if b.character_id == id else null
