class_name ChroniclePanel
extends GamePanel
## What has happened in Ortel, newest first.

const SHOWN: int = 120


func fill(_me: CharacterData) -> void:
	var entries: Array[ChronicleEntry] = ctx.world.chronicle
	if entries.is_empty():
		text(dim("Nothing worth writing down, yet."))
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(entries.size() - 1, maxi(entries.size() - SHOWN, 0) - 1, -1):
		var e: ChronicleEntry = entries[i]
		var cal: String = "Y%d M%d D%d" % [floori(float(e.day) / CalendarData.DAYS_PER_YEAR),
				floori(float(e.day % CalendarData.DAYS_PER_YEAR) / CalendarData.DAYS_PER_MONTH) + 1, e.day % CalendarData.DAYS_PER_MONTH + 1]
		lines.append("%s  %s" % [dim(cal), e.text])
	text("\n".join(lines))
