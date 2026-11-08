class_name ErrorCounter
extends Logger
## Counts engine and script errors, so a test cannot pass while errors are being raised.

var count: int = 0
var last: String = ""


func _log_error(function: String, _file: String, line: int, _code: String, rationale: String, _editor_notify: bool,
		error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	count += 1
	last = "%s:%d %s" % [function, line, rationale]
