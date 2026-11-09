class_name WardrobeSystem
extends SimSystem
## People dress as their fortune goes. Once a month, on a day of their own, everyone the AI runs who is dressed by
## their people's ways looks at their purse and their standing, and changes into what someone of their new
## standing wears: a pedlar grown rich puts on a fine coat, a lord's widow fallen on hard times her plainer gown,
## someone taken into bondage their rags. Soldiers in a band keep their kit. The player dresses themself.


func tick(ctx: SimContext) -> void:
	for id: int in ctx.todays_characters():
		var c: CharacterData = ctx.character(id)
		if c == null or c.warband_id >= 0 or not AgentPolicy.is_ai_controlled(ctx, id):
			continue
		Outfits.redress(ctx, c)
