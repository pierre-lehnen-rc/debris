extends "res://dev/check_base.gd"

## Validates that a source config confirmed in the connection/workspace dialogs is
## persisted, not just held in memory:
##
##   1. saved project + edited workspace  -> written to its file, tab title clean;
##   2. saved project + attached database -> written to its file too;
##   3. never-saved project               -> no prompt, but the tab title shows the
##                                           unsaved dot so an explicit Save is due;
##   4. saved project + added user        -> the Users panel's change is written too;
##   5. save-before-close that fails      -> the tab stays open, nothing is lost.
##
## See main.gd::_persist_source_change and project_tab.gd::_persist_or_flag_dirty

const MAIN_SCENE := "res://source/ui/main.tscn"

var _main: Control


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	root.add_child(_main)
	await process_frame

	await _case_edit_workspace_writes_through()
	await _case_attach_mongo_writes_through()
	await _case_unsaved_project_shows_dot()
	await _case_add_user_writes_through()
	await _case_failed_save_keeps_tab_open()

	_main.queue_free()


# 1. Editing the workspace URL of a saved project writes the file immediately.
func _case_edit_workspace_writes_through() -> void:
	var path := "user://autosave_edit.debris-project"
	var doc := _saved_project(path)
	var proj: Variant = _main._open_project_tab(doc)
	await process_frame

	_apply_api(proj, true, {"url": "http://localhost:4000", "repo_path": ""})
	await process_frame

	expect(not doc.dirty, "edit workspace: the document is no longer dirty")
	expect(_title(proj).begins_with("•") == false, "edit workspace: no unsaved dot in the tab title")
	expect(_read(path).contains("localhost:4000"), "edit workspace: the new URL is on disk")
	_close(proj, path)


# 2. Attaching a database to a saved project writes the file immediately.
func _case_attach_mongo_writes_through() -> void:
	var path := "user://autosave_attach.debris-project"
	var doc := _saved_project(path)
	var proj: Variant = _main._open_project_tab(doc)
	await process_frame

	_main._dialog_project = proj
	_main._dialog_editing = false
	_main._apply_mongo_config({"host": "localhost", "port": 27017, "database": "probe_db"})
	await process_frame

	expect(not doc.dirty, "attach database: the document is no longer dirty")
	expect(_read(path).contains("probe_db"), "attach database: the database is on disk")
	_close(proj, path)


# 3. A project with no file can't be written silently — it must show the dot instead.
func _case_unsaved_project_shows_dot() -> void:
	var doc := WorkspaceDoc.new()
	doc.name = "Untitled"
	doc.set_rocketchat("http://localhost:3000", [], "")
	doc.dirty = false
	var proj: Variant = _main._open_project_tab(doc)
	await process_frame

	_apply_api(proj, true, {"url": "http://localhost:4000", "repo_path": ""})
	await process_frame

	expect(doc.dirty, "unsaved project: the document stays dirty")
	expect(_title(proj).begins_with("•"), "unsaved project: the tab title shows the unsaved dot")
	expect(doc.file_path.is_empty(), "unsaved project: no file was invented for it")
	_close(proj, "")


# 4. Adding a workspace user to a saved project writes the file immediately.
func _case_add_user_writes_through() -> void:
	var path := "user://autosave_user.debris-project"
	var doc := _saved_project(path)
	var proj: Variant = _main._open_project_tab(doc)
	await process_frame

	proj._ensure_session()
	proj._session.add_user({"auth": "token", "username": "probe.user", "token": "tok"})
	await process_frame

	expect(not doc.dirty, "add user: the document is no longer dirty")
	expect(_read(path).contains("probe.user"), "add user: the user is on disk")
	_close(proj, path)


# 5. A save-before-close whose write fails must not close the tab it was preserving.
func _case_failed_save_keeps_tab_open() -> void:
	var doc := WorkspaceDoc.new()
	doc.name = "Doomed"
	doc.set_rocketchat("http://localhost:3000", [], "")
	var proj: Variant = _main._open_project_tab(doc)
	await process_frame
	var tabs_before: int = _main._tabs.get_tab_count()

	# Save As, routed to a directory that doesn't exist so the write fails.
	_main._file_dialog_mode = "save"
	_main._file_dialog_project = proj
	_main._close_after_save = proj
	_main._on_file_dialog_selected("user://no_such_dir/doomed.debris-project")
	await process_frame

	expect_eq(_main._tabs.get_tab_count(), tabs_before, "failed save: the tab is still open")
	expect(_main._tab_index_of(proj) >= 0, "failed save: it is still the same project tab")
	expect(
		_main._status_label.text.begins_with("Save failed"),
		"failed save: the failure is reported in the status bar"
	)
	_close(proj, "")


# Helpers ---------------------------------------------------------------------
## A project document with a Rocket.Chat workspace, already written to `path`.
func _saved_project(path: String) -> WorkspaceDoc:
	var doc := WorkspaceDoc.new()
	doc.name = path.get_file().get_basename()
	doc.set_rocketchat("http://localhost:3000", [], "")
	WorkspaceFile.save(doc, path)
	return doc


func _apply_api(proj: Variant, editing: bool, config: Dictionary) -> void:
	_main._dialog_project = proj
	_main._dialog_editing = editing
	_main._apply_api_config(config)


func _title(proj: Variant) -> String:
	var index: int = _main._tab_index_of(proj)
	return _main._tabs.get_tab_title(index) if index >= 0 else ""


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _close(proj: Variant, path: String) -> void:
	_main._close_tab(proj)
	if not path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
