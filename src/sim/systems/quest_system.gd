class_name QuestSystem
extends SimSystem
## Makes quests from real wants in the world, lets them lapse, and checks whether taken ones are done. The lead owns it.
## Stub for now: it only lets old ones lapse.


func tick(ctx: SimContext) -> void:
	var today: int = ctx.today()
	var ids: Array[int] = []
	ids.assign(ctx.world.quests.keys())
	ids.sort()
	for id: int in ids:
		var q: QuestData = ctx.world.quests[id]
		if q.due_day >= 0 and today > q.due_day:
			if q.state == QuestData.State.OFFERED:
				q.state = QuestData.State.LAPSED
			elif q.state == QuestData.State.TAKEN:
				q.state = QuestData.State.FAILED
