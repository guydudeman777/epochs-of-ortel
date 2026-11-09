class_name BattleSiteDef
extends Resource
## One battle ground: a fixed spot on the land with the field cut from the land around it. Any fight whose place is
## nearer this spot than any other site's is fought here, so the same spot always gives the same field. tools/battle/
## bake_sites.gd lays these out; BattleGround makes the field from the land at the time of the fight.

## What the ground mostly is, as the baker read it from the land: field, forest, hills, ford, beach, lake, marsh or
## outskirts. The field itself comes from the land, not from this; it names the site and tells the baker it has one of
## each.
@export var kind: StringName = &"field"
@export var id: int = 0
## The spot, in map units. The middle of the field.
@export var position: Vector2 = Vector2.ZERO
## LandDef.Biome at the spot.
@export var biome: int = 0
## The way the battle runs across the field, on the map: from the first side's line towards the second's. Across a
## ford, along a road, up from the water on a beach.
@export var facing: Vector2 = Vector2(0.0, 1.0)
## Which way open water lies from the spot, on the map, or zero inland. A landing comes from that side.
@export var shore_dir: Vector2 = Vector2.ZERO
## Picks the small things the land does not say: where each rock and bush stands.
@export var ground_seed: int = 0
