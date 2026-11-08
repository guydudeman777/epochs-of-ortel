class_name PopService
extends RefCounted
## Queries and changes for commoner population groups.


static func find_group(s: SettlementData, race_id: StringName, status: SimEnums.LegalStatus) -> PopGroupData:
	for group: PopGroupData in s.pop_groups:
		if group.race_id == race_id and group.status == status:
			return group
	return null


static func get_or_create(s: SettlementData, race_id: StringName, status: SimEnums.LegalStatus) -> PopGroupData:
	var group: PopGroupData = find_group(s, race_id, status)
	if group != null:
		return group
	group = PopGroupData.new()
	group.race_id = race_id
	group.status = status
	s.pop_groups.append(group)
	return group


static func total(s: SettlementData) -> int:
	var sum: int = 0
	for group: PopGroupData in s.pop_groups:
		sum += group.count
	return sum


static func total_with_status(s: SettlementData, status: SimEnums.LegalStatus) -> int:
	var sum: int = 0
	for group: PopGroupData in s.pop_groups:
		if group.status == status:
			sum += group.count
	return sum


static func largest_group(s: SettlementData, status: SimEnums.LegalStatus) -> PopGroupData:
	var best: PopGroupData = null
	for group: PopGroupData in s.pop_groups:
		if group.status == status and group.count > 0 and (best == null or group.count > best.count):
			best = group
	return best


static func dominant_free_race(s: SettlementData) -> StringName:
	var group: PopGroupData = largest_group(s, SimEnums.LegalStatus.FREE)
	if group != null:
		return group.race_id
	var any_race: StringName = &""
	var best: int = -1
	for g: PopGroupData in s.pop_groups:
		if g.count > best:
			best = g.count
			any_race = g.race_id
	return any_race


## Rounds fractional people up or down at random, so small groups still change over time.
static func random_round(rng: RandomNumberGenerator, value: float) -> int:
	var whole: int = floori(value)
	return whole + (1 if rng.randf() < value - whole else 0)
