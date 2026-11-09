extends Node
## Runs every test_* method of every test case. Exit code 0 only if every script
## compiles, every test passes, and no engine or script error was raised.

const SUITES: Array[String] = [
	"res://tests/test_foundation.gd",
	"res://tests/test_land.gd",
	"res://tests/test_people.gd",
	"res://tests/test_economy.gd",
	"res://tests/test_rules.gd",
	"res://tests/test_bondage.gd",
	"res://tests/test_war.gd",
	"res://tests/test_limbs.gd",
	"res://tests/test_overworld.gd",
	"res://tests/test_persistence.gd",
	"res://tests/test_player_start.gd",
	"res://tests/test_lead.gd",
	"res://tests/test_town_site.gd",
	"res://tests/test_garments.gd",
	"res://tests/test_wardrobe.gd",
	"res://tests/test_world.gd",
	"res://tests/test_troops.gd",
	"res://tests/test_battle_ground.gd",
]
const SOAK_SCRIPT: String = "res://tests/soak.gd"

var _errors: ErrorCounter = ErrorCounter.new()


func _ready() -> void:
	# Deferred, so the scene tree is free for tests that add nodes to it.
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(_errors)
	var failures: int = _check_scripts_compile("res://src") + _check_scripts_compile("res://tests")
	var passed: int = 0
	if failures == 0:
		var args: PackedStringArray = OS.get_cmdline_user_args()
		if args.has("--soak"):
			failures += _run_soak(args)
		else:
			for path: String in SUITES:
				# --only=troops runs the suites whose file names hold that word.
				var only: String = _arg(args, "only")
				if not only.is_empty() and not path.get_file().contains(only):
					continue
				var result: Vector2i = _run_suite(path)
				passed += result.x
				failures += result.y
			print("\n%d passed, %d failed" % [passed, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check_scripts_compile(dir_path: String) -> int:
	var broken: int = 0
	for file_name: String in ResourceLoader.list_directory(dir_path):
		var full: String = dir_path + "/" + file_name
		if file_name.ends_with("/"):
			broken += _check_scripts_compile(full.trim_suffix("/"))
		elif file_name.ends_with(".gd"):
			var script: GDScript = load(full) as GDScript
			if script == null or not script.can_instantiate():
				print("COMPILE FAILED  " + full)
				broken += 1
	return broken


func _run_suite(path: String) -> Vector2i:
	var passed: int = 0
	var failed: int = 0
	var script: GDScript = load(path) as GDScript
	var case: TestCase = script.new() as TestCase
	for method: Dictionary in case.get_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with("test_"):
			continue
		var errors_before: int = _errors.count
		var began: int = Time.get_ticks_msec()
		case.begin(method_name)
		case.call(method_name)
		case.end()
		if _errors.count > errors_before:
			case.assert_true(false, "%d engine errors, last: %s" % [_errors.count - errors_before, _errors.last])
		if case.current_failed():
			failed += 1
			print("FAIL  %s::%s  (%d ms)" % [path.get_file(), method_name, Time.get_ticks_msec() - began])
			for message: String in case.messages():
				print("        " + message)
		else:
			passed += 1
			print("ok    %s::%s  (%d ms)" % [path.get_file(), method_name, Time.get_ticks_msec() - began])
	return Vector2i(passed, failed)


func _run_soak(args: PackedStringArray) -> int:
	var script: GDScript = load(SOAK_SCRIPT) as GDScript
	var soak: Soak = script.new() as Soak
	var failures: int = soak.run(args)
	if _errors.count > 0:
		print("FAIL  %d engine errors, last: %s" % [_errors.count, _errors.last])
		failures += 1
	return failures


func _arg(args: PackedStringArray, key: String) -> String:
	for arg: String in args:
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return ""
