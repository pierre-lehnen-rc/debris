class_name Main
extends Control

## Application shell: menu bar, toolbar, a bottom-tabbed stack of open tabs, and a
## status bar. Tabs are Debris projects (ProjectTab) — each optionally binding one
## Mongo database and one Rocket.Chat API, saved as a .debris-project file. New
## Project / Open Project drive the lifecycle; a project attaches or edits its
## sources from within (activity-bar attach buttons and per-panel edit buttons),
## which open the connection/workspace pickers and dialogs. A start screen shows
## when no tab is open. Layout lives in main.tscn (theme too).

const PROJECT_TAB_SCENE := preload("res://source/ui/project/project_tab.tscn")
const ACTIVITY_LOG_TAB_SCENE := preload("res://source/ui/log/activity_log_tab.tscn")

@onready var _background: ColorRect = %Background
@onready var _file_menu: PopupMenu = %File
@onready var _view_menu: PopupMenu = %View
@onready var _help_menu: PopupMenu = %Help
@onready var _edit_menu: PopupMenu = %Edit
@onready var _toolbar: PanelContainer = %Toolbar
@onready var _status_bar: PanelContainer = %StatusBar
@onready var _status_label: Label = %StatusLabel
@onready var _tabs: TabContainer = %MainTabs
@onready var _connection_dialog: ConnectionDialog = $ConnectionDialog
@onready var _workspace_dialog: WorkspaceDialog = $WorkspaceDialog
@onready var _error_dialog: ErrorDialog = $ErrorDialog
@onready var _about_dialog: AboutDialog = $AboutDialog

# Auto-updater dialog, created in code (it has no .tscn) once the shell is up.
var _update_dialog: UpdateDialog

var _tab_counter := 0

# UI scale (View ▸ UI Scale). The chosen content-scale factor, or 0.0 for "Auto",
# which follows the display's reported DPI scale and updates live on dpi_changed.
# Persisted across launches via Store.
const UI_SCALE_OPTIONS := [
	{"id": 0, "label": "Auto (Match Display)", "factor": 0.0},
	{"id": 1, "label": "100%", "factor": 1.0},
	{"id": 2, "label": "125%", "factor": 1.25},
	{"id": 3, "label": "150%", "factor": 1.5},
	{"id": 4, "label": "200%", "factor": 2.0},
]
var _ui_scale_override := 0.0
var _scale_menu: PopupMenu


func _ready() -> void:
	_ui_scale_override = float(Store.get_preference("ui_scale", 0.0))
	_apply_ui_scale(true)
	# React to DPI changes (OS scaling change, or the window moving to a screen of a
	# different density) so an "Auto" scale stays correct without a restart.
	get_window().dpi_changed.connect(_on_dpi_changed)
	_apply_style()
	_build_project_dialogs()
	_build_start_screen()
	_populate_menus()

	var bar := _tabs.get_tab_bar()
	bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	bar.tab_close_pressed.connect(_on_tab_close_pressed)

	# Surface failures immediately: any failed action pops up a small error dialog
	# offering to open the activity log, rather than opening the log unprompted.
	ActivityLog.entry_added.connect(_on_activity_log_entry)

	# Show the bundled-server startup progress in the status bar.
	ServerManager.status_changed.connect(_on_status_changed)

	# Reopen the projects that were open at last shutdown; show the start screen
	# when there are none.
	_restore_open_projects()

	# Auto-updater: a quiet check for a newer GitHub release shortly after launch
	# (so it never delays the window appearing), plus Help ▸ Check for Updates….
	_update_dialog = UpdateDialog.new()
	add_child(_update_dialog)
	_check_for_updates_on_startup()


# Keyboard shortcuts ----------------------------------------------------------
## App-wide shortcuts, handled in _input (not _shortcut_input) so they run *before*
## a focused control consumes the key — otherwise the query editor swallows Enter as
## a newline, and the File-menu accelerators only fire while their menu is open. Each
## match consumes the event; unmatched keys fall through untouched. The menu-item
## accelerators mirror these purely as visible hints (and cover the menu-open case,
## where the popup — not this window — owns the input).
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var proj := _current_project()

	# F5, or Cmd/Ctrl+Enter (the query-editor convention), re-runs the active tab.
	var enter := key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
	if key.keycode == KEY_F5 or (enter and key.is_command_or_control_pressed()):
		if proj != null:
			proj.run_current_tab()
		accept_event()
		return

	# Alt+1/2/3 → switch the activity-bar view (Collections / Endpoints / Users).
	if key.alt_pressed and not key.is_command_or_control_pressed() and not key.shift_pressed:
		var view_index := key.keycode - KEY_1
		if view_index >= 0 and view_index <= 2:
			if proj != null:
				proj.select_view(view_index)
			accept_event()
		return

	# Everything below is Cmd/Ctrl-based.
	if not key.is_command_or_control_pressed():
		return
	var shift := key.shift_pressed

	# Cmd/Ctrl+1..9 → jump to inner source tab N (9 = last).
	if not shift and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		if proj != null:
			proj.focus_tab(999 if key.keycode == KEY_9 else key.keycode - KEY_1)
		accept_event()
		return

	match key.keycode:
		KEY_N when not shift:
			_new_project()
			accept_event()
		KEY_O when not shift:
			_open_project_dialog()
			accept_event()
		KEY_S:
			if shift:
				_save_project_as()
			else:
				_save_project()
			accept_event()
		KEY_Q when not shift:
			ServerManager.quit()
			accept_event()
		KEY_W when not shift:
			_close_current_document()
			accept_event()
		KEY_TAB:
			# Ctrl+Tab / Ctrl+Shift+Tab cycle the inner source tabs.
			if proj != null:
				proj.cycle_tab(-1 if shift else 1)
			accept_event()
		KEY_PAGEUP when not shift:
			if proj != null:
				proj.cycle_tab(-1)
			accept_event()
		KEY_PAGEDOWN when not shift:
			if proj != null:
				proj.cycle_tab(1)
			accept_event()


## Cmd/Ctrl+W: close the active inner query/endpoint tab; when the project has none
## open (or the focused tab isn't a project), close the current main tab instead,
## through the same path as its close button so a dirty project still prompts to save.
func _close_current_document() -> void:
	var proj := _current_project()
	if proj != null and proj.close_current_tab():
		return
	var index := _tabs.current_tab
	if index >= 0:
		_on_tab_close_pressed(index)


## The content-scale factor to apply: the user's explicit override when set,
## otherwise the display's reported DPI scale (floored at 1.0). On a 2x screen
## (e.g. a macOS Retina display) the OS reports the full pixel resolution, so an
## unscaled UI is drawn at half its intended physical size — tiny and hard to
## read; matching this factor renders the UI at the right physical size, crisply.
func _effective_scale() -> float:
	if _ui_scale_override > 0.0:
		return _ui_scale_override
	return maxf(1.0, DisplayServer.screen_get_scale(get_window().current_screen))


## Apply the effective UI scale to the whole window. When `resize_window` is true
## (startup only) and the scale magnifies the UI, the window is grown so the
## logical working area is preserved, clamped to the usable screen and re-centred.
## Live re-applies (DPI change, menu selection) keep the current window size and
## just re-scale the content, so they never fight the user's own window sizing.
func _apply_ui_scale(resize_window: bool) -> void:
	var window := get_window()
	var scale := _effective_scale()
	window.content_scale_factor = scale
	if not resize_window or scale <= 1.0:
		return
	var base_w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 1280)
	var base_h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 800)
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var target := Vector2i(
		mini(int(base_w * scale), usable.size.x),
		mini(int(base_h * scale), usable.size.y),
	)
	window.size = target
	window.position = usable.position + (usable.size - target) / 2


## The display DPI changed (OS scaling change, or the window was dragged to a
## screen of a different density). Re-apply so an "Auto" scale tracks it live; a
## fixed override is unaffected but re-applying is harmless.
func _on_dpi_changed() -> void:
	_apply_ui_scale(false)


## Handle a UI Scale menu selection: record the chosen factor (0.0 = Auto),
## persist it, apply it, and refresh the menu's radio checks.
func _on_scale_menu(id: int) -> void:
	for opt in UI_SCALE_OPTIONS:
		if int(opt["id"]) == id:
			_ui_scale_override = float(opt["factor"])
			break
	Store.set_preference("ui_scale", _ui_scale_override)
	_apply_ui_scale(false)
	_refresh_scale_menu()


## Tick the UI Scale radio item matching the current override (0.0 = Auto).
func _refresh_scale_menu() -> void:
	if _scale_menu == null:
		return
	for opt in UI_SCALE_OPTIONS:
		var idx := _scale_menu.get_item_index(int(opt["id"]))
		_scale_menu.set_item_checked(idx, is_equal_approx(float(opt["factor"]), _ui_scale_override))


## Relays a child's status message to the status bar. Wired in main.tscn.
func _on_status_changed(text: String) -> void:
	_status_label.text = text


# The connection/workspace dialogs configure a project's source directly (there is
# no shared library). `_dialog_project` is the project a pending dialog targets and
# `_dialog_editing` is true for an edit (update in place) vs an attach (add new).
var _dialog_project: ProjectTab = null
var _dialog_editing := false

# Project file lifecycle (.debris-project). One shared FileDialog serves both Save
# and Open; `_file_dialog_mode` says which, and `_file_dialog_project` is the
# project a pending save writes to.
var _file_dialog: FileDialog
var _recent_menu: PopupMenu
var _file_dialog_mode := ""  # "save" | "open"
var _file_dialog_project: ProjectTab = null
# JSON scratch files (File ▸ New/Open/Save JSON). A second FileDialog, filtered to
# *.json; `_json_dialog_mode` says save vs open and `_json_save_tab` is the tab a
# pending save writes from.
var _json_dialog: FileDialog
var _json_dialog_mode := ""  # "save" | "open"
var _json_save_tab: JsonTab = null
# Save-before-close flow.
var _close_confirm: ConfirmationDialog
var _closing_project: ProjectTab = null   # tab awaiting a close decision
var _close_after_save: ProjectTab = null  # close this once its pending Save As lands
# Start screen shown when no tabs are open.
var _start_screen: Control


## Build the shared save/open FileDialog, the save-before-close prompt, and the
## Open Recent submenu.
func _build_project_dialogs() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.theme = AppTheme.shared()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.%s" % WorkspaceFile.EXTENSION, "Debris Project")
	_file_dialog.file_selected.connect(_on_file_dialog_selected)
	_file_dialog.canceled.connect(_on_file_dialog_canceled)
	add_child(_file_dialog)

	_close_confirm = ConfirmationDialog.new()
	_close_confirm.theme = AppTheme.shared()
	_close_confirm.title = "Unsaved Changes"
	_close_confirm.ok_button_text = "Save"
	_close_confirm.add_button("Discard", false, "discard")
	_close_confirm.confirmed.connect(_on_close_save)
	_close_confirm.custom_action.connect(_on_close_custom_action)
	_close_confirm.canceled.connect(func() -> void: _closing_project = null)
	add_child(_close_confirm)

	_recent_menu = PopupMenu.new()
	_recent_menu.name = "OpenRecent"
	_recent_menu.id_pressed.connect(_on_recent_selected)

	# A separate dialog for JSON scratch files, filtered to *.json.
	_json_dialog = FileDialog.new()
	_json_dialog.theme = AppTheme.shared()
	_json_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_json_dialog.add_filter("*.json", "JSON")
	_json_dialog.file_selected.connect(_on_json_dialog_selected)
	add_child(_json_dialog)


## The project tab currently in focus, or null if the active tab isn't a project.
func _current_project() -> ProjectTab:
	var control := _tabs.get_current_tab_control()
	return control as ProjectTab


# New / attach / edit ---------------------------------------------------------
## Open a fresh empty project (no sources yet); the user attaches a DB and/or API.
func _new_project() -> void:
	var doc := WorkspaceDoc.new()
	doc.name = "Untitled"
	_open_project_tab(doc)
	_status_label.text = "New project"


## Attach a database to the current project by configuring one in the connection
## dialog (there is no library — the config lives in the project).
func _attach_database() -> void:
	_begin_mongo_dialog(_current_project(), false)


## Attach an API to the current project via the workspace dialog.
func _attach_api() -> void:
	_begin_api_dialog(_current_project(), false)


## An unattached source icon was clicked in a project's activity bar.
func _on_project_attach_requested(source: String, proj: ProjectTab) -> void:
	if source == "mongo":
		_begin_mongo_dialog(proj, false)
	elif source == "api":
		_begin_api_dialog(proj, false)


## A source panel's edit button was pressed — edit that source in place.
func _on_project_edit_requested(source: String, proj: ProjectTab) -> void:
	if source == "mongo":
		_begin_mongo_dialog(proj, true)
	elif source == "api":
		_begin_api_dialog(proj, true)


## Open the connection dialog for a project's database — as an edit (prefilled from
## the project's connection) or an attach (blank). The result is applied in
## _on_connection_saved / _on_connection_updated.
func _begin_mongo_dialog(proj: ProjectTab, editing: bool) -> void:
	if proj == null or not is_instance_valid(proj):
		return
	if editing and not proj.has_mongo():
		return
	if not editing and proj.has_mongo():
		return
	_dialog_project = proj
	_dialog_editing = editing
	if editing:
		# Carry the project's actual bound database into the dialog so it pre-selects
		# even before the database list is fetched.
		var config := proj.doc().mongo_connection().duplicate(true)
		config["database"] = proj.doc().mongo_database()
		_connection_dialog.open_edit(0, config)
	else:
		_connection_dialog.open_new()


func _begin_api_dialog(proj: ProjectTab, editing: bool) -> void:
	if proj == null or not is_instance_valid(proj):
		return
	if editing and not proj.has_rocketchat():
		return
	if not editing and proj.has_rocketchat():
		return
	_dialog_project = proj
	_dialog_editing = editing
	if editing:
		_workspace_dialog.open_edit(0, proj.doc().rocketchat_config())
	else:
		_workspace_dialog.open_new()


# Project tabs ----------------------------------------------------------------
func _open_project_tab(doc: WorkspaceDoc) -> ProjectTab:
	var tab: ProjectTab = PROJECT_TAB_SCENE.instantiate()
	tab.configure(doc)
	tab.status_changed.connect(_on_status_changed)
	tab.attach_requested.connect(_on_project_attach_requested.bind(tab))
	tab.edit_source_requested.connect(_on_project_edit_requested.bind(tab))
	tab.dirty_changed.connect(_update_project_tab_title.bind(tab))
	tab.save_requested.connect(_save_project.bind(tab))
	tab.name = "proj_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	_tabs.current_tab = _tabs.get_tab_count() - 1
	_update_project_tab_title(tab)
	_after_tabs_changed()
	return tab


# Save / open project files ---------------------------------------------------
## Save a project (default: the current one) to its file, or fall through to Save
## As when it has never been saved.
func _save_project(proj: ProjectTab = null) -> void:
	if proj == null:
		proj = _current_project()
	if proj == null:
		return
	if proj.doc().file_path.is_empty():
		_save_project_as(proj)
		return
	_write_project(proj, proj.doc().file_path)


## Prompt for a path and save a project (default: the current one) there.
func _save_project_as(proj: ProjectTab = null) -> void:
	if proj == null:
		proj = _current_project()
	if proj == null:
		return
	_file_dialog_mode = "save"
	_file_dialog_project = proj
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = "Save Project"
	_file_dialog.ok_button_text = "Save"
	var doc := proj.doc()
	if not doc.file_path.is_empty():
		_file_dialog.current_path = doc.file_path
	else:
		_file_dialog.current_file = "%s.%s" % [_project_basename(doc), WorkspaceFile.EXTENSION]
	UiScale.popup_centered(_file_dialog, Vector2i(720, 520))


## Prompt for a project file to open.
func _open_project_dialog() -> void:
	_file_dialog_mode = "open"
	_file_dialog_project = null
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Open Project"
	_file_dialog.ok_button_text = "Open"
	UiScale.popup_centered(_file_dialog, Vector2i(720, 520))


func _on_file_dialog_selected(path: String) -> void:
	if _file_dialog_mode == "save":
		if not path.ends_with("." + WorkspaceFile.EXTENSION):
			path += "." + WorkspaceFile.EXTENSION
		var proj := _file_dialog_project
		_file_dialog_project = null
		if proj != null and is_instance_valid(proj):
			_write_project(proj, path)
			# A Save triggered by the save-before-close prompt closes the tab now.
			if _close_after_save == proj:
				_close_tab(proj)
		_close_after_save = null
	elif _file_dialog_mode == "open":
		_open_project_file(path)


## The user dismissed the Save As dialog — cancel any pending close-after-save.
func _on_file_dialog_canceled() -> void:
	_file_dialog_project = null
	_close_after_save = null


## Write a project to `path`, deriving a name from the filename when the project is
## still Untitled, then refresh its tab title and the recent list.
func _write_project(proj: ProjectTab, path: String) -> void:
	var doc := proj.doc()
	if doc.name.is_empty() or doc.name == "Untitled":
		doc.name = path.get_file().get_basename()
	var result := WorkspaceFile.save(doc, path)
	if not result.get("ok", false):
		_status_label.text = "Save failed: %s" % result.get("error", "unknown error")
		return
	Store.add_recent_workspace(path)
	_update_project_tab_title(proj)
	# The project now has a path (or a new one), so refresh the restore list and
	# write the session sidecar (open tabs + endpoint cache) next to the project.
	_save_open_projects()
	proj.persist_state()
	_status_label.text = "Saved %s" % doc.name


## Open a project file into a new tab, focusing it if it's already open.
func _open_project_file(path: String) -> void:
	for i in _tabs.get_tab_count():
		var control := _tabs.get_tab_control(i)
		if control is ProjectTab and (control as ProjectTab).doc().file_path == path:
			_tabs.current_tab = i
			return
	var result := WorkspaceFile.load(path)
	if not result.get("ok", false):
		_status_label.text = "Open failed: %s" % result.get("error", "unknown error")
		return
	var doc: WorkspaceDoc = result["doc"]
	_open_project_tab(doc)
	Store.add_recent_workspace(path)
	_status_label.text = "Opened %s" % path.get_file()


func _on_recent_selected(index: int) -> void:
	var recent := Store.recent_workspaces()
	if index >= 0 and index < recent.size():
		_open_project_file(String(recent[index]))


# JSON scratch tabs -----------------------------------------------------------
## The project a JSON tab should open in: the current one, or a fresh Untitled
## project when the active tab isn't a project (a JSON tab needs a project center to
## live in, but no DB/API of its own).
func _project_for_json() -> ProjectTab:
	var proj := _current_project()
	if proj == null:
		var doc := WorkspaceDoc.new()
		doc.name = "Untitled"
		proj = _open_project_tab(doc)
	return proj


## New JSON: open an empty JSON scratch tab in the current (or a new) project.
func _new_json() -> void:
	_project_for_json().open_json()
	_status_label.text = "New JSON tab"


## Open JSON…: prompt for a .json file to load into a new JSON tab.
func _open_json_dialog() -> void:
	_json_dialog_mode = "open"
	_json_save_tab = null
	_json_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_json_dialog.title = "Open JSON"
	_json_dialog.ok_button_text = "Open"
	UiScale.popup_centered(_json_dialog, Vector2i(720, 520))


## Save JSON…: prompt for a path and write the active JSON tab's text there. No-op
## when the focused tab isn't a JSON tab (the menu item is disabled then anyway).
func _save_json_dialog() -> void:
	var proj := _current_project()
	var tab: JsonTab = proj.active_json_tab() if proj != null else null
	if tab == null:
		return
	_json_dialog_mode = "save"
	_json_save_tab = tab
	_json_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_json_dialog.title = "Save JSON"
	_json_dialog.ok_button_text = "Save"
	_json_dialog.current_file = tab.tab_title() if tab.tab_title().ends_with(".json") else "data.json"
	UiScale.popup_centered(_json_dialog, Vector2i(720, 520))


func _on_json_dialog_selected(path: String) -> void:
	if _json_dialog_mode == "open":
		_open_json_file(path)
	elif _json_dialog_mode == "save":
		var tab := _json_save_tab
		_json_save_tab = null
		if tab != null and is_instance_valid(tab):
			_write_json_file(tab, path)


## Read `path` and open its contents in a new JSON tab, titled by the filename.
func _open_json_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_status_label.text = "Open failed: %s" % error_string(FileAccess.get_open_error())
		return
	var text := file.get_as_text()
	file.close()
	_project_for_json().open_json(text, path.get_file())
	_status_label.text = "Opened %s" % path.get_file()


## Write a JSON tab's editor text to `path` (defaulting the extension to .json) and
## adopt the filename as the tab's title.
func _write_json_file(tab: JsonTab, path: String) -> void:
	if not path.ends_with(".json"):
		path += ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status_label.text = "Save failed: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(tab.json_text())
	file.close()
	tab.mark_saved(path)
	_status_label.text = "Saved %s" % path.get_file()


# Tab title / helpers ---------------------------------------------------------
## Set a project tab's title from its name, prefixed with a dot when it has unsaved
## changes, and its tooltip to the file path.
func _update_project_tab_title(proj: ProjectTab) -> void:
	var index := _tab_index_of(proj)
	if index < 0:
		return
	var doc := proj.doc()
	var title := proj.tab_title()
	if doc.dirty:
		title = "• " + title
	_tabs.set_tab_title(index, title)
	_tabs.set_tab_tooltip(index, doc.file_path)


func _tab_index_of(control: Control) -> int:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i) == control:
			return i
	return -1


## A filename-safe base for an Untitled project's default save name.
func _project_basename(doc: WorkspaceDoc) -> String:
	var name := doc.name
	if name.is_empty() or name == "Untitled":
		return "project"
	return name.replace("·", "-").replace("/", "-").strip_edges()


# Start screen / empty state --------------------------------------------------
## Build the placeholder shown in the tab area while no project is open: a title
## and New / Open buttons. It shares the tab area (toggled with MainTabs).
func _build_start_screen() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "Debris"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Create a new project or open an existing one to get started."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var new_btn := Button.new()
	new_btn.text = "New Project"
	new_btn.focus_mode = Control.FOCUS_NONE
	new_btn.pressed.connect(_new_project)
	row.add_child(new_btn)

	var open_btn := Button.new()
	open_btn.text = "Open Project…"
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.pressed.connect(_open_project_dialog)
	row.add_child(open_btn)

	_start_screen = center
	var parent := _tabs.get_parent()
	parent.add_child(_start_screen)
	parent.move_child(_start_screen, _tabs.get_index() + 1)
	_start_screen.visible = false


## Toggle between the tab area and the start screen based on how many tabs are open.
## The tab strip only appears once there's more than one tab to switch between.
func _update_empty_state() -> void:
	var count := _tabs.get_tab_count()
	_tabs.visible = count > 0
	_tabs.tabs_visible = count > 1
	if _start_screen != null:
		_start_screen.visible = count == 0


## Run after any tab open/close: refresh the empty state and persist which saved
## projects are open so they can be restored next launch.
func _after_tabs_changed() -> void:
	_update_empty_state()
	_save_open_projects()


## Persist the file paths of the currently-open (saved) projects.
func _save_open_projects() -> void:
	var paths: Array = []
	for i in _tabs.get_tab_count():
		var control := _tabs.get_tab_control(i)
		if control is ProjectTab:
			var path := (control as ProjectTab).doc().file_path
			if not path.is_empty():
				paths.append(path)
	Store.save_open_workspaces(paths)


## Reopen the projects that were open at last shutdown (skipping any whose files
## have since gone), then settle the empty state.
func _restore_open_projects() -> void:
	for entry in Store.open_workspaces():
		var path := String(entry)
		if FileAccess.file_exists(path):
			_open_project_file(path)
	_update_empty_state()


# Activity log tab ------------------------------------------------------------
## A logged action failed — surface a small error popup. The user can dismiss it
## or open the activity log from there; we never open the log on our own.
func _on_activity_log_entry(entry: Dictionary) -> void:
	if not entry.get("ok", false):
		_error_dialog.show_error(entry)


## Open the activity log, or focus it if it's already open (only one is useful).
func _open_activity_log_tab() -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i) is ActivityLogTab:
			_tabs.current_tab = i
			return
	var tab: ActivityLogTab = ACTIVITY_LOG_TAB_SCENE.instantiate()
	tab.status_changed.connect(_on_status_changed)
	tab.name = "log_%d" % _tab_counter
	_tab_counter += 1
	_tabs.add_child(tab)
	var index := _tabs.get_tab_count() - 1
	_tabs.set_tab_title(index, tab.tab_title())
	_tabs.current_tab = index
	_after_tabs_changed()
	_status_label.text = "Opened activity log"


# Closing tabs ----------------------------------------------------------------
## A tab's close button was pressed. A project with unsaved changes prompts first;
## everything else closes immediately.
func _on_tab_close_pressed(tab_index: int) -> void:
	var control := _tabs.get_tab_control(tab_index)
	if control == null:
		return
	var proj := control as ProjectTab
	if proj != null and proj.doc().dirty:
		_closing_project = proj
		_close_confirm.dialog_text = "Save changes to \"%s\" before closing?" % proj.tab_title()
		UiScale.popup_centered(_close_confirm)
		return
	_close_tab(control)


## Remove a tab and settle the empty state / restore list.
func _close_tab(control: Control) -> void:
	if not is_instance_valid(control):
		return
	_tabs.remove_child(control)
	control.queue_free()
	_after_tabs_changed()


## Save chosen in the close prompt: write the project (via Save As when it has no
## path yet, closing once that lands) and then close it.
func _on_close_save() -> void:
	var proj := _closing_project
	_closing_project = null
	if proj == null:
		return
	if proj.doc().file_path.is_empty():
		_close_after_save = proj
		_save_project_as(proj)
		return
	_write_project(proj, proj.doc().file_path)
	_close_tab(proj)


## Discard chosen in the close prompt: close without saving.
func _on_close_custom_action(action: StringName) -> void:
	if action != &"discard":
		return
	_close_confirm.hide()
	var proj := _closing_project
	_closing_project = null
	if proj != null:
		_close_tab(proj)


# Connection picker / dialog --------------------------------------------------
# The connection dialog produces the database config for `_dialog_project`. Both
# signals route to the same apply — `saved` from an attach (open_new), `updated`
# from an edit (open_edit); `_dialog_editing` says which.
func _on_connection_saved(config: Dictionary) -> void:
	_apply_mongo_config(config)


func _on_connection_updated(_index: int, config: Dictionary) -> void:
	_apply_mongo_config(config)


func _apply_mongo_config(config: Dictionary) -> void:
	var proj := _dialog_project
	_dialog_project = null
	if proj == null or not is_instance_valid(proj):
		return
	if _dialog_editing:
		proj.update_mongo_connection(config)
		_status_label.text = "Updated database connection"
	else:
		proj.attach_mongo(config, String(config.get("database", "")))
		_status_label.text = "Attached database"
	_update_project_tab_title(proj)


# Same pattern for the API config.
func _on_workspace_saved(config: Dictionary) -> void:
	_apply_api_config(config)


func _on_workspace_updated(_index: int, config: Dictionary) -> void:
	_apply_api_config(config)


func _apply_api_config(config: Dictionary) -> void:
	var proj := _dialog_project
	_dialog_project = null
	if proj == null or not is_instance_valid(proj):
		return
	if _dialog_editing:
		proj.update_rocketchat(config)
		_status_label.text = "Updated workspace"
	else:
		proj.attach_rocketchat(config)
		_status_label.text = "Attached workspace"
	_update_project_tab_title(proj)


# Menus / styling -------------------------------------------------------------
# File menu item ids.
const FILE_QUIT := 3
const FILE_ACTIVITY_LOG := 4
const FILE_NEW_PROJECT := 5
const FILE_ATTACH_DATABASE := 6
const FILE_ATTACH_API := 7
const FILE_SAVE_PROJECT := 8
const FILE_SAVE_PROJECT_AS := 9
const FILE_OPEN_PROJECT := 10
const FILE_NEW_JSON := 11
const FILE_OPEN_JSON := 12
const FILE_SAVE_JSON := 13

# Help menu item ids.
const HELP_ABOUT := 0
const HELP_CHECK_UPDATES := 1


func _on_file_menu(id: int) -> void:
	match id:
		FILE_NEW_PROJECT:
			_new_project()
		FILE_OPEN_PROJECT:
			_open_project_dialog()
		FILE_SAVE_PROJECT:
			_save_project()
		FILE_SAVE_PROJECT_AS:
			_save_project_as()
		FILE_NEW_JSON:
			_new_json()
		FILE_OPEN_JSON:
			_open_json_dialog()
		FILE_SAVE_JSON:
			_save_json_dialog()
		FILE_ATTACH_DATABASE:
			_attach_database()
		FILE_ATTACH_API:
			_attach_api()
		FILE_ACTIVITY_LOG:
			_open_activity_log_tab()
		FILE_QUIT:
			ServerManager.quit()


## Handle Help menu selections.
func _on_help_menu(id: int) -> void:
	match id:
		HELP_ABOUT:
			_about_dialog.open()
		HELP_CHECK_UPDATES:
			_update_dialog.check_manual()


## Quietly check GitHub for a newer release a few seconds after launch — late
## enough that it never delays the window, silent unless an update turns up.
## Skipped under the headless validation runner (which must not touch the network).
func _check_for_updates_on_startup() -> void:
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty():
		return
	await get_tree().create_timer(3.0).timeout
	_update_dialog.check_silent()


## Enable project-scoped items only when a project is active, and the Attach items
## only when it can take that source (enforcing the ≤1-DB / ≤1-API rule). Also
## refresh the Open Recent submenu.
func _refresh_file_menu() -> void:
	var proj := _current_project()
	_file_menu.set_item_disabled(
		_file_menu.get_item_index(FILE_ATTACH_DATABASE), proj == null or proj.has_mongo()
	)
	_file_menu.set_item_disabled(
		_file_menu.get_item_index(FILE_ATTACH_API), proj == null or proj.has_rocketchat()
	)
	_file_menu.set_item_disabled(_file_menu.get_item_index(FILE_SAVE_PROJECT), proj == null)
	_file_menu.set_item_disabled(_file_menu.get_item_index(FILE_SAVE_PROJECT_AS), proj == null)
	# Save JSON… only makes sense when the focused inner tab is a JSON tab.
	_file_menu.set_item_disabled(
		_file_menu.get_item_index(FILE_SAVE_JSON), proj == null or proj.active_json_tab() == null
	)
	_refresh_recent_menu()


## Rebuild the Open Recent submenu from the stored recent-project paths.
func _refresh_recent_menu() -> void:
	_recent_menu.clear()
	var recent := Store.recent_workspaces()
	if recent.is_empty():
		_recent_menu.add_item("(no recent projects)")
		_recent_menu.set_item_disabled(0, true)
		return
	for i in recent.size():
		var path := String(recent[i])
		_recent_menu.add_item(path.get_file(), i)
		_recent_menu.set_item_tooltip(i, path)


func _apply_style() -> void:
	_background.color = AppTheme.BG_DARKEST

	var tool_sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	tool_sb.border_width_bottom = 1
	tool_sb.border_color = AppTheme.BORDER
	tool_sb.content_margin_left = 8
	tool_sb.content_margin_right = 8
	tool_sb.content_margin_top = 5
	tool_sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", tool_sb)

	var status_sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	status_sb.border_width_top = 1
	status_sb.border_color = AppTheme.BORDER
	status_sb.content_margin_left = 8
	status_sb.content_margin_right = 8
	status_sb.content_margin_top = 3
	status_sb.content_margin_bottom = 3
	_status_bar.add_theme_stylebox_override("panel", status_sb)

	_status_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status_label.add_theme_font_size_override("font_size", 12)


func _populate_menus() -> void:
	# Accelerators use CMD_OR_CTRL so they read as ⌘ on macOS and Ctrl elsewhere; the
	# PopupMenu both displays the hint and fires the shortcut globally while in tree.
	_file_menu.add_item("New Project", FILE_NEW_PROJECT, KEY_MASK_CMD_OR_CTRL | KEY_N)
	_file_menu.add_item("Open Project…", FILE_OPEN_PROJECT, KEY_MASK_CMD_OR_CTRL | KEY_O)
	_file_menu.add_submenu_node_item("Open Recent", _recent_menu)
	_file_menu.add_separator()
	_file_menu.add_item("Save Project", FILE_SAVE_PROJECT, KEY_MASK_CMD_OR_CTRL | KEY_S)
	_file_menu.add_item(
		"Save Project As…", FILE_SAVE_PROJECT_AS, KEY_MASK_CMD_OR_CTRL | KEY_MASK_SHIFT | KEY_S
	)
	_file_menu.add_separator()
	_file_menu.add_item("New JSON", FILE_NEW_JSON)
	_file_menu.add_item("Open JSON…", FILE_OPEN_JSON)
	_file_menu.add_item("Save JSON…", FILE_SAVE_JSON)
	_file_menu.add_separator()
	_file_menu.add_item("Attach Database…", FILE_ATTACH_DATABASE)
	_file_menu.add_item("Attach Workspace…", FILE_ATTACH_API)
	_file_menu.add_separator()
	_file_menu.add_item("Activity Log", FILE_ACTIVITY_LOG)
	_file_menu.add_separator()
	_file_menu.add_item("Quit", FILE_QUIT, KEY_MASK_CMD_OR_CTRL | KEY_Q)
	# Enable/disable project items and refresh Open Recent each time the menu opens.
	_file_menu.about_to_popup.connect(_refresh_file_menu)

	_edit_menu.add_item("Copy", 0)
	_edit_menu.add_item("Paste", 1)

	_view_menu.add_item("Tree", 0)
	_view_menu.add_item("Table", 1)
	_view_menu.add_item("Text", 2)
	_view_menu.add_separator()
	_scale_menu = PopupMenu.new()
	_scale_menu.name = "UIScale"
	for opt in UI_SCALE_OPTIONS:
		_scale_menu.add_radio_check_item(str(opt["label"]), int(opt["id"]))
	_scale_menu.id_pressed.connect(_on_scale_menu)
	_view_menu.add_submenu_node_item("UI Scale", _scale_menu)
	_refresh_scale_menu()

	_help_menu.add_item("Check for Updates…", HELP_CHECK_UPDATES)
	_help_menu.add_separator()
	_help_menu.add_item("About Debris", HELP_ABOUT)
