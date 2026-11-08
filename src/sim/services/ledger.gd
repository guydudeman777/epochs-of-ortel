class_name Ledger
extends RefCounted
## Gold held by whoever owns a thing, whether a character or a faction.


static func gold_of(ctx: SimContext, kind: SimEnums.OwnerKind, id: int) -> int:
	match kind:
		SimEnums.OwnerKind.CHARACTER:
			var c: CharacterData = ctx.character(id)
			return c.inventory.gold if c != null else 0
		SimEnums.OwnerKind.FACTION:
			var f: FactionData = ctx.faction(id)
			return f.treasury if f != null else 0
	return 0


static func add_gold(ctx: SimContext, kind: SimEnums.OwnerKind, id: int, amount: int) -> void:
	match kind:
		SimEnums.OwnerKind.CHARACTER:
			var c: CharacterData = ctx.character(id)
			if c != null:
				c.inventory.gold = maxi(0, c.inventory.gold + amount)
		SimEnums.OwnerKind.FACTION:
			var f: FactionData = ctx.faction(id)
			if f != null:
				f.treasury = maxi(0, f.treasury + amount)
