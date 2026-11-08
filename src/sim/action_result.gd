class_name ActionResult
extends RefCounted

var success: bool = false
var reason: StringName = &""
## Id of whatever the action created, or the amount it moved, when relevant.
var value: int = -1
## A fuller report, for actions that have one.
var detail: RefCounted = null


static func ok(result_value: int = -1) -> ActionResult:
	var r: ActionResult = ActionResult.new()
	r.success = true
	r.value = result_value
	return r


static func fail(why: StringName) -> ActionResult:
	var r: ActionResult = ActionResult.new()
	r.reason = why
	return r
