class_name SkillsData
extends Resource

## Skill id -> level (0..100). Ids: combat, trade, labor, leadership, stewardship.
@export var levels: Dictionary[StringName, int] = {}
