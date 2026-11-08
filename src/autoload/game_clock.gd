extends Node
## Turns frame time into simulation days. Wall-clock time never enters the simulation;
## it only decides how many days to run this frame.

const MAX_DAYS_PER_FRAME: int = 8
const FRAME_BUDGET_MS: int = 8

var paused: bool = true
var days_per_second: float = 1.0
var _accumulator: float = 0.0


func _process(delta: float) -> void:
	if paused or Simulation.kernel == null:
		return
	_accumulator = minf(_accumulator + delta * days_per_second, float(MAX_DAYS_PER_FRAME))
	var start_ms: int = Time.get_ticks_msec()
	while _accumulator >= 1.0 and Time.get_ticks_msec() - start_ms < FRAME_BUDGET_MS:
		_accumulator -= 1.0
		Simulation.advance_day()


func advance_days(count: int) -> void:
	for i: int in range(count):
		Simulation.advance_day()
