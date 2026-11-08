class_name BodySystem
extends SimSystem
## Wounds heal, fester or kill, a day at a time. Only people with open wounds cost anything here.


func tick(ctx: SimContext) -> void:
	var rng: RandomNumberGenerator = ctx.rng(&"body")
	var ids: Array[int] = []
	ids.assign(ctx.wounded_ids.keys())
	ids.sort()
	for id: int in ids:
		var c: CharacterData = ctx.character(id)
		if c == null:
			ctx.wounded_ids.erase(id)
			continue
		if LimbService.tend_day(ctx, c, rng) and not LimbService.has_open_wounds(c):
			ctx.wounded_ids.erase(id)
