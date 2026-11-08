class_name LimbService
extends RefCounted
## The rules of bodies: what a blow does to a part, what a hurt part costs, and how wounds heal or kill.
## Mechanical, so it binds the player and every NPC alike.

const BARE_HANDS_POWER: float = 9.0
const BARE_HANDS_KIND: StringName = &"crush"
const KIND_BLEED: Dictionary[StringName, float] = {&"cut": 1.0, &"pierce": 0.7, &"crush": 0.15}
## Severity at or above which part of a wound will never heal, and how much of the excess stays.
const SCARS_FROM: float = 0.55
const SCAR_SHARE: float = 0.8
## Minutes before someone staunches the bleeding, among people or out on the road.
const STAUNCH_MINUTES_TOWN: float = 4.0
const STAUNCH_MINUTES_ROAD: float = 7.0
const FAINT_BLOOD: float = 0.35
const BLOOD_REGROWN_PER_DAY: float = 0.04
const HEAL_PER_DAY: float = 0.012
const INFECTION_CHANCE_TOWN: float = 0.006
const INFECTION_CHANCE_ROAD: float = 0.014
## Only wounds at least this bad, or stumps, go bad.
const INFECTABLE_FROM: float = 0.3
const INFECTION_FOUGHT: float = 0.05
const INFECTION_GROWS: float = 0.075
## A stump's blood loss when a surgeon takes a limb off, against one lost to a blade.
const SURGERY_BLEED_SHARE: float = 0.3
## Hazard of dying of other things, per unit of total lasting damage.
const FRAILTY_PER_DAMAGE: float = 0.25
## Damage a blow does in a battle fought by the abstract resolver.
const BATTLE_BLOW_MIN: float = 10.0
const BATTLE_BLOW_MAX: float = 42.0
const BATTLE_KINDS: Array[StringName] = [&"cut", &"cut", &"pierce", &"crush"]


# --- What state a body is in -------------------------------------------------

static func is_lost(ctx: SimContext, c: CharacterData, part_id: StringName) -> bool:
	if c.body.lost_parts.is_empty():
		return false
	var at: StringName = part_id
	while at != &"":
		if c.body.lost_parts.has(at):
			return true
		at = ctx.defs.body_parts[at].parent
	return false


## 0 is whole, 1 is gone or destroyed.
static func part_damage(ctx: SimContext, c: CharacterData, part_id: StringName) -> float:
	if is_lost(ctx, c, part_id):
		return 1.0
	var sum: float = 0.0
	for wound: WoundData in c.body.wounds:
		if wound.part_id == part_id:
			sum += wound.severity
	return minf(sum, 1.0)


static func part_level(ctx: SimContext, c: CharacterData, part_id: StringName) -> SimEnums.WoundLevel:
	if is_lost(ctx, c, part_id):
		return SimEnums.WoundLevel.LOST
	return level_of(part_damage(ctx, c, part_id))


static func level_of(damage: float) -> SimEnums.WoundLevel:
	if damage <= 0.0:
		return SimEnums.WoundLevel.UNHURT
	if damage < 0.15:
		return SimEnums.WoundLevel.BRUISED
	if damage < 0.4:
		return SimEnums.WoundLevel.HURT
	if damage < 0.7:
		return SimEnums.WoundLevel.BADLY_HURT
	if damage < 1.0:
		return SimEnums.WoundLevel.CRIPPLED
	return SimEnums.WoundLevel.RUINED


## What one capacity is left at, from 0 to 1. Each part that carries it can only take away.
static func capacity(ctx: SimContext, c: CharacterData, capacity_id: StringName) -> float:
	if c.body.wounds.is_empty() and c.body.lost_parts.is_empty():
		return 1.0
	var left: float = 1.0
	for part_id: StringName in ctx.defs.body_part_ids:
		var def: BodyPartDef = ctx.defs.body_parts[part_id]
		var share: float = def.capacities.get(capacity_id, 0.0)
		if share > 0.0:
			left *= 1.0 - share * part_damage(ctx, c, part_id)
	return maxf(left, 0.0)


## How well someone gets about. One good leg still hops. No good leg crawls.
static func mobility(ctx: SimContext, c: CharacterData) -> float:
	var left: float = capacity(ctx, c, &"left_leg")
	var right: float = capacity(ctx, c, &"right_leg")
	return maxf(left, right) * 0.35 + minf(left, right) * 0.65


## The better arm, counting the left as clumsier. Everyone in this world learned on the right.
static func weapon_arm(ctx: SimContext, c: CharacterData) -> float:
	return maxf(capacity(ctx, c, &"right_arm"), capacity(ctx, c, &"left_arm") * 0.6)


## Hands that can do a day's work.
static func work_capacity(ctx: SimContext, c: CharacterData) -> float:
	var hands: float = maxf(capacity(ctx, c, &"right_arm"), capacity(ctx, c, &"left_arm")) * 0.6 + minf(capacity(ctx, c, &"right_arm"), capacity(ctx, c, &"left_arm")) * 0.4
	return hands * (0.5 + 0.5 * mobility(ctx, c)) * (0.4 + 0.6 * capacity(ctx, c, &"wind"))


## How much of a fighter is left, from 0 to 1.
static func fighting_capacity(ctx: SimContext, c: CharacterData) -> float:
	var blood: float = clampf((c.body.blood - FAINT_BLOOD) / (1.0 - FAINT_BLOOD), 0.0, 1.0)
	return weapon_arm(ctx, c) * (0.35 + 0.65 * mobility(ctx, c)) * (0.4 + 0.6 * capacity(ctx, c, &"wind")) * capacity(ctx, c, &"mind") * (0.3 + 0.7 * blood)


static func is_conscious(ctx: SimContext, c: CharacterData) -> bool:
	return c.body.blood > FAINT_BLOOD and capacity(ctx, c, &"mind") > 0.25


## Sum of damage that will not heal, which wears a person down for the rest of their life.
static func lasting_damage(c: CharacterData) -> float:
	var sum: float = 0.0
	for wound: WoundData in c.body.wounds:
		sum += wound.lasting
	return sum + c.body.lost_parts.size() * 0.5


## True when no wound can still get better, so what is left is what the person will live with.
static func body_settled(c: CharacterData) -> bool:
	return not has_open_wounds(c)


## Multiplies the chance of dying of something else.
static func frailty(c: CharacterData) -> float:
	if c.body.wounds.is_empty() and c.body.lost_parts.is_empty():
		return 1.0
	var sum: float = lasting_damage(c)
	for wound: WoundData in c.body.wounds:
		sum += wound.infection * 2.0
	return 1.0 + sum * FRAILTY_PER_DAMAGE


static func has_open_wounds(c: CharacterData) -> bool:
	if c.body.blood < 1.0:
		return true
	for wound: WoundData in c.body.wounds:
		if wound.severity > wound.lasting or wound.infection > 0.0 or wound.bleed > 0.0:
			return true
	return false


# --- What a blow does ----------------------------------------------------------

## How much of a blow of this kind gets through what is worn over this part, from 0 to 1.
static func gets_through(ctx: SimContext, c: CharacterData, part_id: StringName, kind: StringName) -> float:
	var through: float = 1.0
	for armour_id: StringName in c.equipment.armour_ids:
		var armour: ArmourDef = ctx.defs.armours[armour_id]
		if armour.covers.has(part_id):
			var stopped: float = armour.stops.get(kind, 0.0)
			through *= 1.0 - stopped
	return through


## Lands damage on a part. May wound, take the part off, or kill.
static func apply_blow(ctx: SimContext, c: CharacterData, part_id: StringName, kind: StringName, power: float) -> LimbBlow:
	var blow: LimbBlow = LimbBlow.new()
	blow.part_id = part_id
	blow.kind = kind
	if c == null or is_lost(ctx, c, part_id):
		return blow
	var def: BodyPartDef = ctx.defs.body_parts[part_id]
	var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(c)]
	blow.severity = power * gets_through(ctx, c, part_id, kind) / (def.toughness * race.toughness)
	if blow.severity <= 0.0:
		return blow
	var wound: WoundData = WoundData.new()
	wound.part_id = part_id
	wound.kind = kind
	wound.severity = minf(blow.severity, 1.0)
	wound.lasting = maxf(wound.severity - SCARS_FROM, 0.0) * SCAR_SHARE
	wound.bleed = wound.severity * def.bleed_rate * (KIND_BLEED.get(kind, 0.5) as float)
	wound.day = ctx.today()
	c.body.wounds.append(wound)
	ctx.wounded_ids[c.id] = true
	blow.level = part_level(ctx, c, part_id)
	ctx.events.character_wounded.emit(c.id, part_id, blow.level)
	if def.sever_at > 0.0 and kind == &"cut" and blow.severity >= def.sever_at:
		sever(ctx, c, part_id, 1.0)
		blow.severed = true
		blow.level = SimEnums.WoundLevel.LOST
	# A part beaten past whole never comes back, even with nothing cut off.
	if part_damage(ctx, c, part_id) >= 1.0 and not blow.severed:
		var ruin: WoundData = wound
		ruin.lasting = maxf(ruin.lasting, ruin.severity)
	if def.vital and part_damage(ctx, c, part_id) >= 1.0:
		blow.killed = true
		Mortality.kill(ctx, c, &"wounds")
	return blow


## Takes a part off, with whatever hangs from it. The stump bleeds and can go bad.
static func sever(ctx: SimContext, c: CharacterData, part_id: StringName, bleed_share: float) -> void:
	if is_lost(ctx, c, part_id):
		return
	var def: BodyPartDef = ctx.defs.body_parts[part_id]
	var kept: Array[WoundData] = []
	for wound: WoundData in c.body.wounds:
		if not _hangs_from(ctx, wound.part_id, part_id):
			kept.append(wound)
	c.body.wounds = kept
	var remaining: Array[StringName] = []
	for lost: StringName in c.body.lost_parts:
		if not _hangs_from(ctx, lost, part_id):
			remaining.append(lost)
	remaining.append(part_id)
	c.body.lost_parts = remaining
	if def.parent != &"":
		var stump: WoundData = WoundData.new()
		stump.part_id = def.parent
		stump.kind = &"cut"
		stump.severity = 0.35
		stump.bleed = def.stump_bleed * bleed_share
		stump.day = ctx.today()
		c.body.wounds.append(stump)
	ctx.wounded_ids[c.id] = true
	ctx.bump(&"limbs_lost")
	ctx.events.limb_lost.emit(c.id, part_id)


static func _hangs_from(ctx: SimContext, part_id: StringName, ancestor: StringName) -> bool:
	var at: StringName = part_id
	while at != &"":
		if at == ancestor:
			return true
		at = ctx.defs.body_parts[at].parent
	return false


## A named fighter's share of an abstract battle: some blows, on parts picked as blows fall.
static func battle_wounds(ctx: SimContext, c: CharacterData, blows: int, rng: RandomNumberGenerator) -> void:
	for i: int in range(blows):
		if ctx.character(c.id) == null:
			return
		var part_id: StringName = random_part(ctx, c, rng)
		var kind: StringName = BATTLE_KINDS[rng.randi_range(0, BATTLE_KINDS.size() - 1)]
		apply_blow(ctx, c, part_id, kind, rng.randf_range(BATTLE_BLOW_MIN, BATTLE_BLOW_MAX))


static func random_part(ctx: SimContext, c: CharacterData, rng: RandomNumberGenerator) -> StringName:
	var total: float = 0.0
	for part_id: StringName in ctx.defs.body_part_ids:
		if not is_lost(ctx, c, part_id):
			total += ctx.defs.body_parts[part_id].hit_weight
	var roll: float = rng.randf() * total
	var last: StringName = &"torso"
	for part_id: StringName in ctx.defs.body_part_ids:
		if is_lost(ctx, c, part_id):
			continue
		last = part_id
		roll -= ctx.defs.body_parts[part_id].hit_weight
		if roll <= 0.0:
			return part_id
	return last


## Blood lost over some minutes of bleeding. Returns false if it killed.
static func bleed_for(ctx: SimContext, c: CharacterData, minutes: float) -> bool:
	var rate: float = 0.0
	for wound: WoundData in c.body.wounds:
		rate += wound.bleed
	if rate <= 0.0:
		return true
	c.body.blood = maxf(c.body.blood - rate * minutes, 0.0)
	if c.body.blood <= 0.0:
		Mortality.kill(ctx, c, &"bled_out")
		return false
	return true


# --- How wounds go, day by day ------------------------------------------------

## One day for one wounded person. Returns false if it killed them.
static func tend_day(ctx: SimContext, c: CharacterData, rng: RandomNumberGenerator) -> bool:
	var in_town: bool = c.settlement_id >= 0 and c.warband_id < 0
	# Whatever was still bleeding is staunched by the end of the day, if the person lives that long.
	if not bleed_for(ctx, c, STAUNCH_MINUTES_TOWN if in_town else STAUNCH_MINUTES_ROAD):
		return false
	var chance: float = INFECTION_CHANCE_TOWN if in_town else INFECTION_CHANCE_ROAD
	var kept: Array[WoundData] = []
	for wound: WoundData in c.body.wounds:
		wound.bleed = 0.0
		if wound.infection > 0.0:
			wound.infection = maxf(wound.infection + rng.randf_range(-INFECTION_FOUGHT, INFECTION_GROWS), 0.0)
			if wound.infection >= 1.0:
				Mortality.kill(ctx, c, &"infection")
				return false
		elif wound.kind != &"crush" and wound.severity >= INFECTABLE_FROM and wound.severity > wound.lasting and rng.randf() < chance:
			wound.infection = 0.05
		if wound.infection <= 0.0:
			wound.severity = maxf(wound.severity - HEAL_PER_DAY * c.attributes.health, wound.lasting)
		# A healed wound with nothing lasting is forgotten. One that left its mark stays as a scar.
		if wound.severity > 0.0 or wound.infection > 0.0:
			kept.append(wound)
	c.body.wounds = kept
	c.body.blood = minf(c.body.blood + BLOOD_REGROWN_PER_DAY, 1.0)
	return true


## The worst infected limb that a surgeon could take off, or nothing.
static func limb_to_save_from(ctx: SimContext, c: CharacterData, at_infection: float) -> StringName:
	var worst: StringName = &""
	var worst_infection: float = at_infection
	for wound: WoundData in c.body.wounds:
		if wound.infection >= worst_infection and ctx.defs.body_parts[wound.part_id].sever_at > 0.0 and not ctx.defs.body_parts[wound.part_id].vital:
			worst = wound.part_id
			worst_infection = wound.infection
	return worst
