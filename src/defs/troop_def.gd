class_name TroopDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var strength: float = 1.0
@export var wage: float = 0.5
@export var recruit_cost: int = 10
@export var required_tech: StringName = &""
## Goods taken from the recruiting settlement's stock, per recruit.
@export var required_goods: Dictionary[StringName, int] = {}
## What this kind of soldier carries and wears up close. No bows or guns yet, so shooters fight with what they have at the hip.
@export var weapon_id: StringName = &""
@export var has_shield: bool = false
@export var armour_ids: Array[StringName] = []
## Rank in its people's tree, 1 (fresh recruit) to 5.
@export var tier: int = 1
## The people whose tree this troop belongs to. Empty means any people may raise it.
@export var culture_id: StringName = &""
## What it can rise to. Two choices make a branch.
@export var upgrades_to: Array[StringName] = []
## Experience one soldier needs to rise.
@export var upgrade_xp: int = 0
## Gold paid for each soldier who rises.
@export var upgrade_cost: int = 0
## Weapons a troop of this kind may carry instead of weapon_id, so levies do not all hold spears. Empty means weapon_id.
@export var weapon_choices: Array[StringName] = []
## Which line of its people's tree it stands in: levy, line (the shield wall), shot (bows and crossbows), pole, shock,
## gun or guns (the great guns). Captains keep their bands mixed by it, and the party screen groups by it.
@export var branch: StringName = &"levy"
## Share of those with a one-handed weapon who carry a shield too, where has_shield does not give one to all of them.
@export var shield_share: float = 0.0
