class_name CalendarData
extends Resource

const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12
const DAYS_PER_YEAR: int = 360

## Bands move and meet this many times a day, so that a journey can be watched and steered.
## A watch's step stays short next to WarbandSystem.TOUCH_RANGE, so bands cannot walk through each other.
const WATCHES_PER_DAY: int = 16

@export var day_index: int = 0
## Watches already spent of the coming day.
@export var watch: int = 0


func year() -> int:
	return floori(day_index / float(DAYS_PER_YEAR))


func month() -> int:
	return floori((day_index % DAYS_PER_YEAR) / float(DAYS_PER_MONTH))


func day_of_month() -> int:
	return day_index % DAYS_PER_MONTH
