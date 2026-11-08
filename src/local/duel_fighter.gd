class_name DuelFighter
extends RefCounted
## One side of a duel, for as long as it lasts. Wounds and death live in the character, not here.

enum State { READY, WINDUP, RECOVER, GUARD, STAGGER, DOWN, YIELDED, DEAD, FLED }
## LEFT and RIGHT are the side of the attacker the blow starts from.
enum Move { NONE, OVERHEAD, LEFT, RIGHT, THRUST, LOW }
## LEFT and RIGHT are the defender's own sides.
enum Guard { NONE, UP, LEFT, RIGHT, LOW }

var character_id: int = -1
var side: int = 0
## Whom they are fighting. Blows and guards turn this way.
var target: DuelFighter = null
var fleeing: bool = false
var position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2(0.0, 1.0)
var state: State = State.READY
var state_time: float = 0.0
var state_length: float = 0.0
var move: Move = Move.NONE
var guard: Guard = Guard.NONE
var stamina: float = 1.0
var has_shield: bool = false
## How fast this fighter is moving, for the view.
var velocity: Vector2 = Vector2.ZERO
var reach: float = 0.85
var speed: float = 1.0


func is_out() -> bool:
	return state == State.DOWN or state == State.YIELDED or state == State.DEAD or state == State.FLED


func is_guarding() -> bool:
	return state == State.GUARD


func _set_state(new_state: State, length: float = 0.0) -> void:
	state = new_state
	state_time = 0.0
	state_length = length
