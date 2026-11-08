class_name FactionLawsData
extends Resource

## Race id -> SimEnums.RaceStanding. Missing races count as TOLERATED.
@export var race_standing: Dictionary[StringName, int] = {}
@export var bondage_law: SimEnums.BondageLaw = SimEnums.BondageLaw.BANNED
## What this realm's people hold to be normal. Law drifts back toward it unless a ruler pushes against it.
@export var customary_bondage_law: SimEnums.BondageLaw = SimEnums.BondageLaw.BANNED
@export var hereditary_bondage: bool = false
@export var mixed_heritage_rule: SimEnums.MixedHeritageRule = SimEnums.MixedHeritageRule.DOMINANT
@export var tax_rate: float = 0.1
