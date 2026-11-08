class_name DuelEvent
extends RefCounted
## Something that happened in a duel, for the view to show. Kinds: swing, guard, miss, hit, severed, blocked,
## parried, guard_broken, shield_lost, down, yielded, dead, fled, over, spared.

var kind: StringName = &""
## Who did it, or -1.
var by_id: int = -1
## Who it happened to.
var character_id: int = -1
var part_id: StringName = &""
var level: SimEnums.WoundLevel = SimEnums.WoundLevel.UNHURT
