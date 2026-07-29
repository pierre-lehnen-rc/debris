extends SceneTree

## Headless runner for the test/ suites (which extend test/test_suite.gd).
## Discovers every *_test.gd under the given targets (default: all of test/),
## runs each test_* method with before_test/after_test around it, and reports.
## Exits 0 when everything passes, 1 otherwise.
##
## Invoked by test/run.sh; the project boots with DEBRIS_HEADLESS=1 so the
## ServerManager autoload stays quiet and Backend/RocketChat use the dev mocks.

var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_main()
	return false


func _main() -> void:
	var files := _collect(OS.get_cmdline_user_args())
	if files.is_empty():
		printerr("no *_test.gd suites found")
		quit(1)
		return

	var total_pass := 0
	var total_fail := 0
	var suites_failed := 0

	for path in files:
		var script: Variant = load(path)
		if script == null:
			printerr("could not load %s" % path)
			suites_failed += 1
			continue
		if not (script is GDScript) or not (script as GDScript).can_instantiate():
			# A suite with parse errors loads as an uninstantiable GDScript;
			# report it and move on rather than crashing the whole run.
			printerr("── %s ──" % path.trim_prefix("res://"))
			printerr("  FAIL: suite failed to compile (see errors above)")
			suites_failed += 1
			total_fail += 1
			continue
		var suite: Node = script.new()
		root.add_child(suite)

		var methods: Array = []
		for m in suite.get_method_list():
			var n: String = m["name"]
			if n.begins_with("test_"):
				methods.append(n)
		methods.sort()

		print("── %s (%d) ──" % [path.trim_prefix("res://"), methods.size()])
		var s_pass := 0
		for name in methods:
			suite._reset_test()
			suite.before_test()
			await suite.call(name)
			suite.after_test()
			suite._cleanup()
			var fails: Array = suite.__failures
			if fails.is_empty():
				s_pass += 1
			else:
				for f in fails:
					printerr("  FAIL %s: %s" % [name, f])
		var s_fail := methods.size() - s_pass
		total_pass += s_pass
		total_fail += s_fail
		if s_fail > 0:
			suites_failed += 1
		print("  %d passed, %d failed" % [s_pass, s_fail])
		suite.queue_free()

	print("")
	print("═══ %d passed, %d failed across %d suite(s) ═══" % [
		total_pass, total_fail, files.size()])
	quit(1 if total_fail > 0 else 0)


## Turn cmdline targets (files or dirs) into a sorted list of suite res:// paths.
func _collect(targets: Array) -> Array:
	var roots: Array = []
	if targets.is_empty():
		roots = ["res://test"]
	else:
		for t in targets:
			roots.append(_to_res(t))

	var files: Array = []
	for r in roots:
		if r.ends_with(".gd"):
			files.append(r)
		else:
			_scan(r, files)
	files.sort()
	return files


func _to_res(target: String) -> String:
	if target.begins_with("res://"):
		return target
	return "res://" + target.trim_prefix("./").trim_prefix("/")


func _scan(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_scan(full, out)
		elif name.ends_with("_test.gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
