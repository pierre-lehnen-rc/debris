extends "res://dev/check_base.gd"

## End-to-end check for per-collection query history, exercised through a live
## ProjectTab graph (so project_tab / workspace_center / query_tab compile and boot
## with their autoloads, which --check-only can't verify):
##
##   1. running a query in a collection records it as a recent in the sidecar state;
##   2. re-running the same query doesn't stack a duplicate;
##   3. favoriting a query writes it to the project doc, marks it dirty, and — for a
##      titled project — asks the host to save (the auto-save hook);
##   4. applying a saved query fills a tab's editors without running it.
##
## Loaded at runtime (not preloaded): the project graph references the Backend
## autoload, absent when this -s main-loop script is compiled. See
## source/data/query_history.gd and source/ui/database/query_tab.gd

const PROJECT_TAB := "res://source/ui/project/project_tab.tscn"
const CONNECTION := {"name": "local", "host": "localhost:27017"}


func _run() -> void:
	var doc := WorkspaceDoc.new()
	doc.set_name("hist-check")
	doc.set_mongo(CONNECTION, "mydb")
	# A file path enables the persistence/auto-save paths (nothing is asserted about
	# the file contents here — the data-layer round-trips cover that).
	doc.file_path = "user://__hist_check.debris-project"
	doc.dirty = false

	var proj: Variant = load(PROJECT_TAB).instantiate()
	proj.configure(doc)
	root.add_child(proj)
	await _settle()

	var center: Variant = proj._center
	var history: Variant = proj._history
	var state: Variant = proj._state
	expect(history != null, "history store is built during setup")
	expect(state != null, "sidecar state is loaded during setup")

	# 1. Running a query records a recent for that collection. open_collection auto-runs
	#    the seeded "{}" find against the mock backend.
	center.open_collection(CONNECTION, "mydb", "users")
	await _settle()
	var recents: Array = history.recents("users")
	expect(recents.size() == 1, "a run records one recent for the collection")
	if recents.size() == 1:
		expect_eq(String(recents[0].get("function", "")), "find", "recorded operation is the one run")

	# 2. Re-running the identical query doesn't stack a duplicate.
	var tab: Variant = center.get_node("%Tabs").get_current_tab_control()
	tab.run_query()
	await _settle()
	expect(history.recents("users").size() == 1, "re-running an identical query doesn't duplicate")

	# 3. Favoriting writes to the doc, dirties it, and requests a save (auto-save hook).
	var save_asks := [0]
	proj.save_requested.connect(func() -> void: save_asks[0] += 1)
	var entry := {"function": "find", "filter": "{\"active\": true}", "options": "", "options_visible": false}
	history.add_favorite("users", entry)
	await _settle()
	expect(doc.favorite_queries_for("users").size() == 1, "favorite is stored on the project doc")
	expect(doc.dirty, "favoriting marks the project dirty")
	expect(save_asks[0] == 1, "a titled project asks the host to auto-save on favorite")
	expect(history.is_favorite("users", entry), "the favorited query reports as a favorite")

	# 4. Applying a saved query fills the editors without running (no new recent).
	var before: int = history.recents("users").size()
	tab.apply_entry({"function": "findOne", "filter": "{\"x\": 1}", "options": "", "options_visible": false})
	await _settle()
	expect_eq(String(tab.to_state().get("filter", "")), "{\"x\": 1}", "apply fills the filter editor")
	expect_eq(String(tab.to_state().get("function", "")), "findOne", "apply sets the operation")
	expect(history.recents("users").size() == before, "applying a saved query does not run or record it")

	# Clean up the sidecar file the persistence path wrote next to the temp project.
	DirAccess.remove_absolute("user://__hist_check.debris-workspace")


func _settle() -> void:
	for _i in 12:
		await process_frame
