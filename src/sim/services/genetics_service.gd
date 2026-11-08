class_name GeneticsService
extends RefCounted
## Ancestry, inherited potential and traits.

const ATTRIBUTE_IDS: Array[StringName] = [&"might", &"agility", &"wits", &"will"]
const GENE_NOISE: float = 0.8


static func dominant_race(c: CharacterData) -> StringName:
	var best: StringName = &""
	var best_share: float = -1.0
	for race: StringName in c.genetics.ancestry:
		var share: float = c.genetics.ancestry[race]
		# Ties break alphabetically, so the answer never depends on dictionary order.
		if share > best_share or (share == best_share and String(race) < String(best)):
			best = race
			best_share = share
	return best


static func can_have_children(ctx: SimContext, a: CharacterData, b: CharacterData) -> bool:
	var race_a: StringName = dominant_race(a)
	var race_b: StringName = dominant_race(b)
	if race_a == race_b:
		return true
	return ctx.defs.races[race_a].compatible_races.has(race_b) and ctx.defs.races[race_b].compatible_races.has(race_a)


static func child_ancestry(mother: CharacterData, father: CharacterData) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	for race: StringName in mother.genetics.ancestry:
		var share: float = mother.genetics.ancestry[race]
		out[race] = share * 0.5
	for race: StringName in father.genetics.ancestry:
		var share: float = father.genetics.ancestry[race]
		var existing: float = out.get(race, 0.0)
		out[race] = existing + share * 0.5
	return out


static func random_genes(rng: RandomNumberGenerator) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	for attribute: StringName in ATTRIBUTE_IDS:
		out[attribute] = clampf(rng.randfn(5.0, 1.5), 1.0, 10.0)
	return out


static func child_genes(rng: RandomNumberGenerator, mother: CharacterData, father: CharacterData) -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	for attribute: StringName in ATTRIBUTE_IDS:
		var from_mother: float = mother.genetics.genes.get(attribute, 5.0)
		var from_father: float = father.genetics.genes.get(attribute, 5.0)
		out[attribute] = clampf((from_mother + from_father) * 0.5 + rng.randfn(0.0, GENE_NOISE), 1.0, 10.0)
	return out


static func random_traits(ctx: SimContext, rng: RandomNumberGenerator, count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i: int in range(count):
		var pick: StringName = ctx.defs.trait_ids[rng.randi_range(0, ctx.defs.trait_ids.size() - 1)]
		add_trait_if_allowed(ctx, out, pick)
	return out


static func add_trait_if_allowed(ctx: SimContext, traits: Array[StringName], id: StringName) -> void:
	if traits.has(id):
		return
	for existing: StringName in traits:
		if ctx.defs.traits[existing].opposites.has(id):
			return
	traits.append(id)


static func inherit_traits(ctx: SimContext, rng: RandomNumberGenerator, mother: CharacterData, father: CharacterData) -> Array[StringName]:
	var out: Array[StringName] = []
	for parent: CharacterData in [mother, father]:
		for id: StringName in parent.traits:
			if rng.randf() < ctx.defs.traits[id].heritable_chance:
				add_trait_if_allowed(ctx, out, id)
	if rng.randf() < 0.15:
		add_trait_if_allowed(ctx, out, ctx.defs.trait_ids[rng.randi_range(0, ctx.defs.trait_ids.size() - 1)])
	return out


## Sets attributes from genes, weighted ancestry and traits.
static func apply_attributes(ctx: SimContext, c: CharacterData) -> void:
	for attribute: StringName in ATTRIBUTE_IDS:
		var gene: float = c.genetics.genes.get(attribute, 5.0)
		var value: float = gene
		for race: StringName in c.genetics.ancestry:
			var share: float = c.genetics.ancestry[race]
			var mod: int = ctx.defs.races[race].attribute_mods.get(attribute, 0)
			value += share * mod
		for id: StringName in c.traits:
			var trait_mod: int = ctx.defs.traits[id].attribute_mods.get(attribute, 0)
			value += trait_mod
		c.attributes.set(attribute, clampi(roundi(value), 1, 15))
