extends "res://dev/check_base.gd"

## End-to-end check for the JSON scratch tab, exercised through a live ProjectTab
## graph so project_tab / workspace_center / main compile and boot with their
## autoloads (which --check-only can't verify):
##
##   1. main.gd / workspace_center.gd / project_tab.gd load (compile) cleanly;
##   2. opening a JSON tab in the center adds one tab, reported as the active JSON
##      tab, and it persists (its sidecar snapshot is a "json" entry with the text
##      and title);
##   3. those snapshots restore into a fresh center as a JSON tab with the same
##      text/title, without disturbing the other tab kinds.
##
## Loaded at runtime (not preloaded): the project graph references the Backend
## autoload, absent when this -s main-loop script is compiled.

const MAIN := "res://source/ui/main.gd"
const CENTER := "res://source/ui/project/workspace_center.gd"
const PROJECT_TAB_SCRIPT := "res://source/ui/project/project_tab.gd"
const PROJECT_TAB := "res://source/ui/project/project_tab.tscn"

const SAMPLE := "[{\"a\": 1}, {\"a\": 2}]"


func _run() -> void:
	# 1. The host graph compiles with its autoloads resolved.
	expect(load(MAIN) != null, "main.gd compiles")
	expect(load(CENTER) != null, "workspace_center.gd compiles")
	expect(load(PROJECT_TAB_SCRIPT) != null, "project_tab.gd compiles")

	var doc := WorkspaceDoc.new()
	doc.set_name("json-check")
	# A file path enables the persistence path (setup restores empty tabs, arming it).
	doc.file_path = "user://__json_check.debris-project"

	var proj: Variant = load(PROJECT_TAB).instantiate()
	proj.configure(doc)
	root.add_child(proj)
	await _settle()

	var center: Variant = proj._center
	expect(center != null, "the center exists after setup")

	# 2. Opening a JSON tab through the project adds exactly one tab, reported as the
	#    active JSON tab.
	var tab: Variant = proj.open_json(SAMPLE, "sample.json")
	await _settle()
	expect(tab != null, "open_json returns the tab")
	expect(proj.active_json_tab() == tab, "the JSON tab is the active JSON tab")
	expect_eq(String(tab.tab_title()), "sample.json", "the tab title is the file name")
	expect_eq(String(tab.json_text()), SAMPLE, "the editor holds the seeded text")

	var snaps: Array = center.capture_tabs()
	expect_eq(snaps.size(), 1, "one tab is captured")
	if snaps.size() == 1:
		var snap: Dictionary = snaps[0]
		expect_eq(String(snap.get("kind", "")), "json", "the snapshot is tagged json")
		expect_eq(String(snap.get("text", "")), SAMPLE, "the snapshot carries the editor text")
		expect_eq(String(snap.get("title", "")), "sample.json", "the snapshot carries the title")

	# 3. Restoring the snapshots into a fresh center reopens the JSON tab intact.
	var doc2 := WorkspaceDoc.new()
	doc2.set_name("json-check-2")
	var proj2: Variant = load(PROJECT_TAB).instantiate()
	proj2.configure(doc2)
	root.add_child(proj2)
	await _settle()
	proj2._center.restore_tabs(snaps, 0, {})
	await _settle()
	var restored: Variant = proj2._center.active_json_tab()
	expect(restored != null, "restore reopens a JSON tab")
	if restored != null:
		expect_eq(String(restored.tab_title()), "sample.json", "restored title matches")
		expect_eq(String(restored.json_text()), SAMPLE, "restored text matches")

	# 4. A results view's "open in a JSON tab" signal travels the full chain
	#    (sub-view → results view → owning tab → center) and opens a JSON tab. Drive
	#    it by emitting on a query tab's tree sub-view, exercising the tscn relay too.
	var qtab: Variant = center.open_collection(
		{"name": "local", "host": "localhost:27017"}, "mydb", "users"
	)
	await _settle()
	qtab.results()._tree_view.open_json_requested.emit("{\"picked\": true}")
	await _settle()
	var opened: Variant = center.active_json_tab()
	expect(opened != null, "the results-view signal opens a JSON tab")
	if opened != null:
		expect_eq(String(opened.json_text()), "{\"picked\": true}", "the JSON tab holds the emitted text")

	# Clean up the sidecar the persistence path wrote next to the temp project.
	DirAccess.remove_absolute("user://__json_check.debris-workspace")


func _settle() -> void:
	for _i in 12:
		await process_frame
