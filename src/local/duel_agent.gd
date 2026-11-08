class_name DuelAgent
extends RefCounted
## How an NPC fights. It sees only what a person could see, and answers with the same input the player's keys make.
## Alone it duels. In a group it spreads out over the enemy, works round behind whoever is busy, and may break and run.

const PREFERRED_MOVES: Array[DuelFighter.Move] = [
	DuelFighter.Move.OVERHEAD, DuelFighter.Move.OVERHEAD, DuelFighter.Move.LEFT, DuelFighter.Move.LEFT,
	DuelFighter.Move.RIGHT, DuelFighter.Move.RIGHT, DuelFighter.Move.THRUST, DuelFighter.Move.LOW,
]
const GIVE_UP_BELOW: float = 0.25
## Stubborn people fight on until they are nearly finished.
const GIVE_UP_BELOW_RESOLUTE: float = 0.12
const RETHINK_TARGET: float = 1.2
## How much further a person will walk, in metres, to face someone nobody else is on.
const CROWDED_TARGET_PENALTY: float = 1.6
const FLANK_DISTANCE: float = 0.9
const MORALE_CHECK: float = 0.5
## How close a fleeing friend or a live blow must be for it to count.
const NEAR: float = 5.0
const WATCH_REACH: float = 0.4
## Numbers alone do not break a line. It takes seeing friends fall too.
const MOST_FEAR_FROM_NUMBERS: float = 0.45

var _fight: LocalFight
var _me: DuelFighter
var _rng: RandomNumberGenerator
var _wait: float = 0.6
var _strafe: float = 0.0
var _strafe_time: float = 0.0
var _read_swing: DuelFighter = null
var _will_answer: bool = false
var _answer: DuelFighter.Guard = DuelFighter.Guard.NONE
var _output: DuelInput = DuelInput.new()
var _target_time: float = 0.0
var _morale_time: float = 0.0
var _starting_enemies: int = 0
var _starting_friends: int = 0


func _init(fight: LocalFight, me: DuelFighter) -> void:
	_fight = fight
	_me = me
	_rng = fight.ctx.rng(&"duel_agent")
	_morale_time = _rng.randf_range(0.0, MORALE_CHECK)


func _skill(c: CharacterData) -> float:
	var combat: int = c.skills.levels.get(&"combat", 0)
	return clampf(combat / 100.0 * 0.6 + c.attributes.wits * 0.03 + c.attributes.agility * 0.02, 0.0, 1.0)


## What this fighter does this moment.
func decide(seconds: float) -> DuelInput:
	var ctx: SimContext = _fight.ctx
	var c: CharacterData = ctx.character(_me.character_id)
	_output.attack = DuelFighter.Move.NONE
	_output.move = Vector2.ZERO
	if c == null or _fight.over or _me.is_out():
		_output.guard = DuelFighter.Guard.NONE
		return _output
	var limit: float = GIVE_UP_BELOW_RESOLUTE if c.traits.has(&"resolute") else GIVE_UP_BELOW
	_output.give_up = LimbService.fighting_capacity(ctx, c) < limit
	_think_about_running(c, seconds)
	if _output.flee:
		_output.guard = DuelFighter.Guard.NONE
		return _output
	_pick_target(seconds)
	var other: DuelFighter = _output.target
	if other == null:
		other = _fight.nearest_enemy(_me)
	if other == null:
		_output.guard = DuelFighter.Guard.NONE
		return _output
	var skill: float = _skill(c)
	_wait -= seconds
	_strafe_time -= seconds
	if _strafe_time <= 0.0:
		_strafe = _rng.randf_range(-0.7, 0.7)
		_strafe_time = _rng.randf_range(0.8, 2.0)
	_watch_for_blows(skill)
	var distance: float = _me.position.distance_to(other.position)
	var want: float = _me.reach * 0.85
	var approach: float = clampf((distance - want) * 2.0, -0.7, 1.0)
	_output.move = Vector2(_strafe_towards_flank(other), approach)
	if _output.guard == DuelFighter.Guard.NONE and _me.state == DuelFighter.State.READY and _wait <= 0.0 and distance <= _me.reach + 0.05 and _me.stamina > 0.2:
		_output.attack = _pick_move(other, c)
		_wait = _rng.randf_range(0.5, 1.5) * (1.3 - skill * 0.5)
	return _output


## Someone busy with a friend of mine can be got at from behind, so walk round them.
func _strafe_towards_flank(other: DuelFighter) -> float:
	if other.target == null or other.target == _me:
		return _strafe
	var behind: Vector2 = other.position - other.facing * FLANK_DISTANCE
	var ahead: Vector2 = (other.position - _me.position).normalized()
	var right: Vector2 = Vector2(-ahead.y, ahead.x)
	return clampf((behind - _me.position).dot(right), -1.0, 1.0)


func _pick_target(seconds: float) -> void:
	_target_time -= seconds
	var current: DuelFighter = _output.target
	if current != null and not current.is_out() and _target_time > 0.0:
		return
	_target_time = RETHINK_TARGET
	var best: DuelFighter = null
	var best_score: float = INF
	for candidate: DuelFighter in _fight.fighters:
		if candidate.side == _me.side or candidate.is_out():
			continue
		var score: float = _me.position.distance_to(candidate.position)
		for friend: DuelFighter in _fight.fighters:
			if friend != _me and friend.side == _me.side and friend.target == candidate and not friend.is_out():
				score += CROWDED_TARGET_PENALTY
		if score < best_score:
			best_score = score
			best = candidate
	_output.target = best


## Whether this person has had enough. It adds up what they can see: how the sides stand, how hurt they are, who
## near them has already run. A strong will carries more of it. Once someone runs they do not come back.
func _think_about_running(c: CharacterData, seconds: float) -> void:
	if _output.flee:
		return
	_morale_time -= seconds
	if _morale_time > 0.0:
		return
	_morale_time = MORALE_CHECK
	var friends: int = _fight.strength_of(_me.side)
	var enemies: int = _fight.strength_of(1 - _me.side)
	_starting_friends = maxi(_starting_friends, friends)
	_starting_enemies = maxi(_starting_enemies, enemies)
	# Two people duelling settle it between them.
	if _starting_friends + _starting_enemies <= 2 or enemies == 0:
		return
	var running_near: int = 0
	for friend: DuelFighter in _fight.fighters:
		if friend.side == _me.side and friend.fleeing and friend.position.distance_to(_me.position) < NEAR:
			running_near += 1
	var outnumbered: float = float(enemies) / float(maxi(friends, 1)) - 1.0
	var fallen: float = 1.0 - float(friends) / float(_starting_friends)
	var hurt: float = 1.0 - LimbService.fighting_capacity(_fight.ctx, c)
	var fear: float = minf(maxf(outnumbered, 0.0) * 0.2, MOST_FEAR_FROM_NUMBERS) + fallen * 0.6 + hurt * 0.6 + running_near * 0.2
	var nerve: float = 0.55 + c.attributes.will * 0.06
	if c.traits.has(&"craven"):
		nerve -= 0.3
	if c.traits.has(&"resolute"):
		nerve += 0.3
	if fear > nerve and _rng.randf() < 0.5:
		_output.flee = true


## Guards against a swing it has had time to read, if it reads it at all. Watches whoever is about to land nearest.
func _watch_for_blows(skill: float) -> void:
	var swinging: DuelFighter = null
	for enemy: DuelFighter in _fight.fighters:
		if enemy.side == _me.side or enemy.state != DuelFighter.State.WINDUP:
			continue
		if enemy.position.distance_to(_me.position) > enemy.reach + WATCH_REACH:
			continue
		if swinging == null or enemy.state_length - enemy.state_time < swinging.state_length - swinging.state_time:
			swinging = enemy
	if swinging == null:
		_read_swing = null
		_output.guard = DuelFighter.Guard.NONE
		return
	if swinging != _read_swing:
		_read_swing = swinging
		_will_answer = _rng.randf() < 0.3 + skill * 0.5
		_answer = LocalFight.MEETS[swinging.move]
		# Someone slow to read it may still guard, but on the wrong side.
		if _rng.randf() > 0.4 + skill * 0.55:
			_answer = (_rng.randi_range(1, 4) as DuelFighter.Guard)
	if _will_answer and swinging.state_time >= 0.32 - skill * 0.18:
		_output.guard = _answer


func _pick_move(other: DuelFighter, c: CharacterData) -> DuelFighter.Move:
	# A point is what a spear is for. Blunt things and short blades do little with theirs.
	if _fight.ctx.defs.weapons.has(c.equipment.weapon_id):
		var weapon: WeaponDef = _fight.ctx.defs.weapons[c.equipment.weapon_id]
		if weapon.thrust_power > weapon.swing_power and _rng.randf() < 0.65:
			if not other.is_guarding() or LocalFight.MEETS[DuelFighter.Move.THRUST] != other.guard:
				return DuelFighter.Move.THRUST
	for i: int in range(4):
		var move: DuelFighter.Move = PREFERRED_MOVES[_rng.randi_range(0, PREFERRED_MOVES.size() - 1)]
		if not other.is_guarding() or LocalFight.MEETS[move] != other.guard:
			return move
	return DuelFighter.Move.LOW
