class_name LocalFight
extends RefCounted
## The rules of people fighting up close, with no scene in them, for any number on two sides. The view shows it and the
## player's keys feed it. Blows go through Actions, so everything a fight does to a person stays done after it ends.
## A fight in progress is not saved.

const STEP: float = 1.0 / 60.0
const WALK_SPEED: float = 1.5
const BACK_SHARE: float = 0.65
const ATTACK_MOVE_SHARE: float = 0.35
const GUARD_MOVE_SHARE: float = 0.55
const TURN_RATE: float = 7.0
## How much faster than a walk someone runs for their life.
const FLEE_SHARE: float = 1.7
const STAMINA_SPRINT: float = 0.14
const SPRINT_NEEDS_BREATH: float = 0.05
const SPRINT_NEEDS_FORWARD: float = 0.5
const CLOSEST: float = 0.95
## A weapon this long is slow to strike with at someone inside this share of its reach.
const LONG_REACH: float = 1.7
const INSIDE_SHARE: float = 0.68
const INSIDE_SPEED: float = 0.55
## How far round a fighter's middle a tree or a wall stops them.
const BODY_RADIUS: float = 0.3
## Seconds, before a fighter's weapon speed and arm are counted.
const WINDUP: float = 0.5
const RECOVER: float = 0.55
const STRIKE_ARC: float = 65.0
const GUARD_ARC: float = 80.0
const GUARD_RAISE: float = 0.12
const PARRY_WINDOW: float = 0.3
const THRUST_EXTRA_REACH: float = 0.2
const STAMINA_ATTACK: float = 0.14
const STAMINA_BLOCK_SHIELD: float = 0.11
const STAMINA_BLOCK_WEAPON: float = 0.17
const STAMINA_REGEN: float = 0.17
const GUARD_REGEN_SHARE: float = 0.3
const PARRY_STAGGER: float = 0.6
const GUARD_BROKEN_STAGGER: float = 0.7
const RECOIL: float = 0.22
const HIT_STAGGER: float = 0.28
const HIT_STAGGER_PER_SEVERITY: float = 0.5
## A minute of a duel costs this many minutes of bleeding, so wounds matter before it ends.
const FIGHT_BLEED_MINUTES_PER_SECOND: float = 0.05
## Below these, a fighter cannot go on.
const FALLS_BELOW_MOBILITY: float = 0.2
const DROPS_WEAPON_BELOW_ARM: float = 0.12
const SHIELD_NEEDS_ARM: float = 0.25

## Where a blow can land from each direction, by target's part. LEFT comes from the attacker's left, onto the target's right.
const LANDS: Dictionary[DuelFighter.Move, Dictionary] = {
	DuelFighter.Move.OVERHEAD: {&"head": 34.0, &"neck": 5.0, &"arm_l": 11.0, &"arm_r": 14.0, &"torso": 28.0, &"forearm_r": 6.0, &"hand_r": 2.0},
	DuelFighter.Move.LEFT: {&"arm_r": 20.0, &"forearm_r": 18.0, &"hand_r": 7.0, &"torso": 22.0, &"abdomen": 18.0, &"neck": 5.0, &"head": 10.0},
	DuelFighter.Move.RIGHT: {&"arm_l": 18.0, &"forearm_l": 18.0, &"hand_l": 7.0, &"torso": 22.0, &"abdomen": 20.0, &"neck": 5.0, &"head": 10.0},
	DuelFighter.Move.THRUST: {&"torso": 40.0, &"abdomen": 34.0, &"neck": 6.0, &"head": 6.0, &"thigh_l": 7.0, &"thigh_r": 7.0},
	DuelFighter.Move.LOW: {&"thigh_l": 22.0, &"thigh_r": 22.0, &"shin_l": 22.0, &"shin_r": 22.0, &"foot_l": 6.0, &"foot_r": 6.0},
}
## The guard that meets each blow head on.
const MEETS: Dictionary[DuelFighter.Move, DuelFighter.Guard] = {
	DuelFighter.Move.OVERHEAD: DuelFighter.Guard.UP,
	DuelFighter.Move.LEFT: DuelFighter.Guard.RIGHT,
	DuelFighter.Move.RIGHT: DuelFighter.Guard.LEFT,
	DuelFighter.Move.THRUST: DuelFighter.Guard.LOW,
	DuelFighter.Move.LOW: DuelFighter.Guard.LOW,
}

var ctx: SimContext
var fighters: Array[DuelFighter] = []
## What happened since the view last looked. The view empties this.
var events: Array[DuelEvent] = []
var over: bool = false
## The side left standing, or -1 if neither is.
var winning_side: int = -1
var arena_radius: float = 9.0
## The ground fought on: its water drags and its trees and walls stand in the way. Null is bare level ground.
var ground: BattleGround = null
## How many more are waiting to come on, by side. A side is not beaten while any are left.
var waiting: Array[int] = [0, 0]
var clock: float = 0.0
var _left_over: float = 0.0
var _first: int = 0


func _init(context: SimContext) -> void:
	ctx = context


func add_fighter(id: int, side: int, at: Vector2, towards: Vector2) -> DuelFighter:
	var f: DuelFighter = _make_fighter(id, at, towards)
	f.side = side
	fighters.append(f)
	return f


func _make_fighter(id: int, at: Vector2, towards: Vector2) -> DuelFighter:
	var f: DuelFighter = DuelFighter.new()
	var c: CharacterData = ctx.character(id)
	f.character_id = id
	f.position = at
	f.facing = towards
	f.has_shield = c.equipment.has_shield and LimbService.capacity(ctx, c, &"left_arm") >= SHIELD_NEEDS_ARM
	if ctx.defs.weapons.has(c.equipment.weapon_id):
		var weapon: WeaponDef = ctx.defs.weapons[c.equipment.weapon_id]
		f.reach = weapon.reach
		f.speed = weapon.speed
	return f


## Moves the fight on by real seconds, in fixed steps, so the outcome does not depend on the frame rate.
## inputs line up with fighters.
func advance_all(seconds: float, inputs: Array[DuelInput]) -> void:
	_left_over += seconds
	while _left_over >= STEP:
		_left_over -= STEP
		step_all(inputs)


func step_all(inputs: Array[DuelInput]) -> void:
	clock += STEP
	# Whoever goes first in a step lands first, so the order turns over and neither side keeps that edge.
	var count: int = fighters.size()
	_first = (_first + 1) % maxi(count, 1)
	for i: int in range(count):
		var at: int = (_first + i) % count
		_update_fighter(fighters[at], inputs[at])
	if not over:
		_check_over()


## Over once a side has nobody left in it. Fighters who are out stay out, whatever order they went in.
func _check_over() -> void:
	var standing: Dictionary[int, bool] = {}
	var sides: Dictionary[int, bool] = {}
	for f: DuelFighter in fighters:
		sides[f.side] = true
		if not f.is_out() or waiting[f.side] > 0:
			standing[f.side] = true
	if standing.size() >= sides.size():
		return
	over = true
	if not standing.is_empty():
		winning_side = standing.keys()[0] as int
	_event(&"over", fighters[0], &"")


## How many of a side are still in the fight.
func standing_on(side: int) -> int:
	var count: int = 0
	for f: DuelFighter in fighters:
		if f.side == side and not f.is_out():
			count += 1
	return count


## How many a side still has, counting those not yet on the field.
func strength_of(side: int) -> int:
	return standing_on(side) + waiting[side]


func nearest_enemy(f: DuelFighter) -> DuelFighter:
	var best: DuelFighter = null
	var best_distance: float = INF
	for other: DuelFighter in fighters:
		if other.side == f.side or other.is_out():
			continue
		var distance: float = f.position.distance_squared_to(other.position)
		if distance < best_distance:
			best = other
			best_distance = distance
	return best


func _event(kind: StringName, f: DuelFighter, part_id: StringName, level: SimEnums.WoundLevel = SimEnums.WoundLevel.UNHURT, by: DuelFighter = null) -> void:
	var e: DuelEvent = DuelEvent.new()
	e.by_id = by.character_id if by != null else -1
	e.kind = kind
	e.character_id = f.character_id
	e.part_id = part_id
	e.level = level
	events.append(e)


func _update_fighter(f: DuelFighter, input: DuelInput) -> void:
	if f.state == DuelFighter.State.DEAD or f.state == DuelFighter.State.FLED:
		f.velocity = Vector2.ZERO
		return
	var c: CharacterData = ctx.character(f.character_id)
	if c == null:
		f._set_state(DuelFighter.State.DEAD)
		_event(&"dead", f, &"")
		return
	f.state_time += STEP
	if not LimbService.bleed_for(ctx, c, STEP * FIGHT_BLEED_MINUTES_PER_SECOND):
		f._set_state(DuelFighter.State.DEAD)
		_event(&"dead", f, &"")
		return
	if f.state == DuelFighter.State.DOWN or f.state == DuelFighter.State.YIELDED:
		f.velocity = Vector2.ZERO
		return
	if not _can_go_on(f, c, input):
		return
	if input.free:
		f.target = null
	else:
		f.target = input.target if input.target != null and not input.target.is_out() and input.target.side != f.side else nearest_enemy(f)
	f.fleeing = input.flee and not over
	if not over:
		_run_state(f, c, input)
	if f.state == DuelFighter.State.FLED:
		return
	_move(f, c, input)
	if f.state == DuelFighter.State.FLED:
		return
	f.stamina = minf(f.stamina + STEP * STAMINA_REGEN * (GUARD_REGEN_SHARE if f.is_guarding() else 1.0) * (0.35 + 0.65 * LimbService.capacity(ctx, c, &"wind")), 1.0)


## Whether a body can still fight. If not, it goes down or gives up, here, for anyone.
func _can_go_on(f: DuelFighter, c: CharacterData, input: DuelInput) -> bool:
	if not LimbService.is_conscious(ctx, c) or LimbService.mobility(ctx, c) < FALLS_BELOW_MOBILITY:
		f._set_state(DuelFighter.State.DOWN)
		_event(&"down", f, &"")
		return false
	if input.give_up or LimbService.capacity(ctx, c, &"right_arm") < DROPS_WEAPON_BELOW_ARM:
		f._set_state(DuelFighter.State.YIELDED)
		_event(&"yielded", f, &"")
		return false
	if f.has_shield and LimbService.capacity(ctx, c, &"left_arm") < SHIELD_NEEDS_ARM:
		f.has_shield = false
		_event(&"shield_lost", f, &"")
	return true


func _attack_speed(f: DuelFighter, c: CharacterData) -> float:
	var speed: float = f.speed * (0.55 + 0.45 * LimbService.weapon_arm(ctx, c)) * (0.7 + 0.3 * f.stamina)
	# Inside a long weapon's point, whoever holds it has to shorten their grip to strike at all.
	if f.reach >= LONG_REACH and f.target != null and f.position.distance_to(f.target.position) < f.reach * INSIDE_SHARE:
		speed *= INSIDE_SPEED
	return speed


func _run_state(f: DuelFighter, c: CharacterData, input: DuelInput) -> void:
	match f.state:
		DuelFighter.State.READY:
			if f.fleeing:
				pass
			elif input.attack != DuelFighter.Move.NONE and f.stamina >= STAMINA_ATTACK:
				f.stamina -= STAMINA_ATTACK
				f.move = input.attack
				f._set_state(DuelFighter.State.WINDUP, WINDUP / _attack_speed(f, c))
				_event(&"swing", f, &"")
			elif input.guard != DuelFighter.Guard.NONE:
				f.guard = input.guard
				f._set_state(DuelFighter.State.GUARD)
				_event(&"guard", f, &"")
		DuelFighter.State.WINDUP:
			if f.state_time >= f.state_length:
				f._set_state(DuelFighter.State.RECOVER, RECOVER / _attack_speed(f, c))
				_resolve(f)
		DuelFighter.State.RECOVER, DuelFighter.State.STAGGER:
			if f.state_time >= f.state_length:
				f.move = DuelFighter.Move.NONE
				f._set_state(DuelFighter.State.READY)
		DuelFighter.State.GUARD:
			if input.guard == DuelFighter.Guard.NONE:
				f.guard = DuelFighter.Guard.NONE
				f._set_state(DuelFighter.State.READY)
			elif input.guard != f.guard:
				# Shifting a guard takes as long as raising one, and is no parry.
				f.guard = input.guard
				f.state_time = 0.0
				_event(&"guard", f, &"")


func _in_arc(f: DuelFighter, target: Vector2, degrees: float) -> bool:
	var to_target: Vector2 = (target - f.position).normalized()
	return f.facing.dot(to_target) >= cos(deg_to_rad(degrees))


## Whom a blow finds: the one aimed at if the blade gets there, or else whoever is nearest in its way.
func _found_by(f: DuelFighter) -> DuelFighter:
	var reach: float = f.reach + (THRUST_EXTRA_REACH if f.move == DuelFighter.Move.THRUST else 0.0)
	var best: DuelFighter = null
	var best_distance: float = INF
	for candidate: DuelFighter in fighters:
		if candidate.side == f.side or candidate.is_out():
			continue
		var distance: float = f.position.distance_to(candidate.position)
		if distance > reach or not _in_arc(f, candidate.position, STRIKE_ARC):
			continue
		if candidate == f.target:
			return candidate
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _resolve(f: DuelFighter) -> void:
	var other: DuelFighter = _found_by(f)
	if other == null:
		_event(&"miss", f, &"")
		return
	if _is_covered(other, f):
		_block(f, other)
		return
	var part_id: StringName = _pick_part(f.move, other)
	var result: ActionResult = Actions.land_blow(ctx, f.character_id, other.character_id, part_id, f.move == DuelFighter.Move.THRUST)
	if not result.success:
		return
	var blow: LimbBlow = result.detail as LimbBlow
	_event(&"severed" if blow.severed else &"hit", other, part_id, blow.level, f)
	if blow.killed:
		other._set_state(DuelFighter.State.DEAD)
		_event(&"dead", other, part_id, blow.level, f)
		return
	if not other.is_out():
		other.guard = DuelFighter.Guard.NONE
		other.move = DuelFighter.Move.NONE
		other._set_state(DuelFighter.State.STAGGER, HIT_STAGGER + minf(blow.severity, 1.0) * HIT_STAGGER_PER_SEVERITY)


func _is_covered(defender: DuelFighter, attacker: DuelFighter) -> bool:
	if not defender.is_guarding() or defender.state_time < GUARD_RAISE or not _in_arc(defender, attacker.position, GUARD_ARC):
		return false
	var needed: DuelFighter.Guard = MEETS[attacker.move]
	if defender.guard == needed:
		return true
	# A shield covers everything above the knee whatever way it is held. Only a low cut goes under it.
	return defender.has_shield and attacker.move != DuelFighter.Move.LOW


func _block(attacker: DuelFighter, defender: DuelFighter) -> void:
	defender.stamina = maxf(defender.stamina - (STAMINA_BLOCK_SHIELD if defender.has_shield else STAMINA_BLOCK_WEAPON), 0.0)
	if defender.stamina <= 0.0:
		defender.guard = DuelFighter.Guard.NONE
		defender._set_state(DuelFighter.State.STAGGER, GUARD_BROKEN_STAGGER)
		_event(&"guard_broken", defender, &"")
		return
	if defender.state_time <= PARRY_WINDOW:
		attacker.move = DuelFighter.Move.NONE
		attacker._set_state(DuelFighter.State.STAGGER, PARRY_STAGGER)
		_event(&"parried", defender, &"")
		return
	attacker.state_length += RECOIL
	_event(&"blocked", defender, &"")


func _pick_part(move: DuelFighter.Move, target: DuelFighter) -> StringName:
	var rng: RandomNumberGenerator = ctx.rng(&"duel")
	var c: CharacterData = ctx.character(target.character_id)
	var table: Dictionary = LANDS[move]
	var total: float = 0.0
	var names: Array[StringName] = []
	names.assign(table.keys())
	names.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	for part_id: StringName in names:
		if not LimbService.is_lost(ctx, c, part_id):
			var weight: float = table[part_id]
			total += weight
	var roll: float = rng.randf() * total
	for part_id: StringName in names:
		if LimbService.is_lost(ctx, c, part_id):
			continue
		var weight: float = table[part_id]
		roll -= weight
		if roll <= 0.0:
			return part_id
	# Everything that way is already gone, so the blow finds what is left.
	return &"torso"


func _move(f: DuelFighter, c: CharacterData, input: DuelInput) -> void:
	var ahead: Vector2 = f.facing
	if input.free:
		if input.look.length() > 0.01:
			ahead = input.look.normalized()
	elif f.target != null:
		ahead = (f.target.position - f.position).normalized()
	var wish: Vector2 = input.move.limit_length(1.0)
	if over:
		wish = Vector2.ZERO
	var legs: float = 0.2 + 0.8 * LimbService.mobility(ctx, c)
	if ground != null:
		legs *= ground.pace_at(f.position)
	var velocity: Vector2
	if f.fleeing:
		# Straight out, away from the nearest danger and towards the edge.
		var out: Vector2 = -ahead * 0.6 + f.position.normalized() * 0.8
		ahead = out.normalized()
		velocity = ahead * WALK_SPEED * FLEE_SHARE * legs
	else:
		var share: float = 1.0
		match f.state:
			DuelFighter.State.WINDUP, DuelFighter.State.RECOVER:
				share = ATTACK_MOVE_SHARE
			DuelFighter.State.GUARD:
				share = GUARD_MOVE_SHARE
			DuelFighter.State.STAGGER:
				share = 0.2
			DuelFighter.State.READY:
				if input.sprint and wish.y > SPRINT_NEEDS_FORWARD and f.stamina > SPRINT_NEEDS_BREATH:
					share = FLEE_SHARE
					f.stamina = maxf(f.stamina - STEP * (STAMINA_SPRINT + STAMINA_REGEN), 0.0)
		# In fighter's terms y is towards the opponent, and x is to the right of that.
		var right: Vector2 = Vector2(-ahead.y, ahead.x)
		var along: float = wish.y * (BACK_SHARE if wish.y < 0.0 else 1.0)
		velocity = (ahead * along + right * wish.x) * WALK_SPEED * share * legs
	var turn: float = clampf(f.facing.angle_to(ahead), -TURN_RATE * STEP, TURN_RATE * STEP)
	f.facing = f.facing.rotated(turn)
	var next: Vector2 = f.position + velocity * STEP
	for other: DuelFighter in fighters:
		if other == f or other.is_out():
			continue
		if next.distance_to(other.position) < CLOSEST:
			next = other.position + (next - other.position).normalized() * CLOSEST
	if ground != null:
		next = ground.push_clear(next, BODY_RADIUS)
		# Nobody wades in over their chest.
		if ground.is_blocked(next) and not ground.is_blocked(f.position):
			next = f.position
	if f.fleeing and next.length() >= arena_radius:
		f._set_state(DuelFighter.State.FLED)
		f.velocity = Vector2.ZERO
		_event(&"fled", f, &"")
		return
	if next.length() > arena_radius:
		next = next.normalized() * arena_radius
	f.velocity = (next - f.position) / STEP
	f.position = next
