class_name AgentPolicy
extends RefCounted
## The one place the simulation treats the player differently: AI decisions are
## skipped for the character the player pointer is attached to. Everything else
## about that character runs on the same rules as every NPC.


static func is_ai_controlled(ctx: SimContext, character_id: int) -> bool:
	return character_id != ctx.world.player_character_id
