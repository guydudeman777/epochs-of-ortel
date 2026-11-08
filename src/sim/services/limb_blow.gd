class_name LimbBlow
extends RefCounted
## What one blow did. A report only: the wound itself is in the target's state.

var part_id: StringName = &""
var kind: StringName = &""
## As a share of the part, before capping. 0 means armour stopped it or nothing was there to hit.
var severity: float = 0.0
var level: SimEnums.WoundLevel = SimEnums.WoundLevel.UNHURT
var severed: bool = false
var killed: bool = false
