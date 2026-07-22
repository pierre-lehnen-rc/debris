class_name WorkspacePicker
extends Window

## Popup that lists the configured Rocket.Chat workspaces and lets the user open
## one. Opened from the toolbar. Owns the runtime workspace list; add/edit are
## delegated to the workspace dialog (routed through Main), remove is handled
## inline. Picking a workspace emits `workspace_selected` so Main can open a
## workspace tab for it.

signal workspace_selected(workspace: Dictionary)
signal add_workspace_requested()
signal edit_workspace_requested(index: int, config: Dictionary)
signal status_changed(text: String)

const META_INDEX := "ws_index"
const ICON_WORKSPACE := preload("res://source/ui/icons/database.svg")
const ICON_SIZE := 16

enum Action { OPEN, EDIT, REMOVE }

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _tree: Tree = %Tree
@onready var _context_menu: PopupMenu = %ContextMenu
@onready var _open_btn: Button = %OpenBtn

var _menu_target := -1
# Runtime list of workspace configs (added/edited via the workspace dialog).
var _workspaces: Array = []


func _ready() -> void:
	_load_workspaces()
	_apply_style()
	_populate()


## Load the saved workspaces. On the very first run (nothing ever saved) seed a
## localhost workspace so there's something to start from, and persist it.
func _load_workspaces() -> void:
	if not Store.has("workspaces"):
		_workspaces = [{
			"name": "Local",
			"url": "http://localhost:3000",
			"user_id": "",
			"token": "",
		}]
		Store.save_workspaces(_workspaces)
		return
	_workspaces = []
	for saved in Store.workspaces():
		_workspaces.append({
			"name": saved.get("name", ""),
			"url": saved.get("url", ""),
			"user_id": saved.get("user_id", ""),
			"token": saved.get("token", ""),
		})


func open() -> void:
	popup_centered(Vector2i(420, 420))
	_open_btn.disabled = _selected_index() < 0


# Public mutations (called by Main after the workspace dialog) -----------------
func add_workspace(config: Dictionary) -> void:
	_workspaces.append({
		"name": config.get("name", "New Workspace"),
		"url": config.get("url", ""),
		"user_id": config.get("user_id", ""),
		"token": config.get("token", ""),
	})
	Store.save_workspaces(_workspaces)
	_populate()


func update_workspace(index: int, config: Dictionary) -> void:
	if index < 0 or index >= _workspaces.size():
		return
	_workspaces[index] = {
		"name": config.get("name", _workspaces[index]["name"]),
		"url": config.get("url", _workspaces[index]["url"]),
		"user_id": config.get("user_id", _workspaces[index].get("user_id", "")),
		"token": config.get("token", _workspaces[index].get("token", "")),
	}
	Store.save_workspaces(_workspaces)
	_populate()


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_title.add_theme_font_size_override("font_size", 11)


func _populate() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for wi in _workspaces.size():
		var ws: Dictionary = _workspaces[wi]
		var item := _tree.create_item(root)
		item.set_text(0, ws["name"])
		item.set_tooltip_text(0, ws["url"])
		item.set_custom_color(0, AppTheme.TEXT_BRIGHT)
		item.set_icon(0, ICON_WORKSPACE)
		item.set_icon_max_width(0, ICON_SIZE)
		item.set_icon_modulate(0, AppTheme.TEXT)
		item.set_metadata(0, {META_INDEX: wi})


## Wired in workspace_picker.tscn from the header "+" button.
func _on_add_pressed() -> void:
	add_workspace_requested.emit()


# Selection / activation ------------------------------------------------------
## The index of the workspace currently selected in the tree, or -1.
func _selected_index() -> int:
	var item := _tree.get_selected()
	if item == null:
		return -1
	var meta: Dictionary = item.get_metadata(0)
	return meta.get(META_INDEX, -1)


func _on_item_selected() -> void:
	_open_btn.disabled = _selected_index() < 0


func _on_nothing_selected() -> void:
	_open_btn.disabled = true


func _on_item_activated() -> void:
	_open_selected()


func _on_open_pressed() -> void:
	_open_selected()


func _open_selected() -> void:
	var index := _selected_index()
	if index < 0:
		return
	workspace_selected.emit(_workspaces[index])
	hide()


# Context menu ----------------------------------------------------------------
func _on_item_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	_menu_target = _selected_index()
	if _menu_target < 0:
		return
	_context_menu.clear()
	_context_menu.add_item("Open Workspace", Action.OPEN)
	_context_menu.add_item("Edit Workspace…", Action.EDIT)
	_context_menu.add_separator()
	_context_menu.add_item("Remove Workspace", Action.REMOVE)
	_context_menu.reset_size()
	# Embedded sub-windows position popups in the parent viewport's space.
	_context_menu.position = Vector2i(_tree.get_global_mouse_position())
	_context_menu.popup()


func _on_context_action(id: int) -> void:
	if _menu_target < 0 or _menu_target >= _workspaces.size():
		return
	match id:
		Action.OPEN:
			workspace_selected.emit(_workspaces[_menu_target])
			hide()
		Action.EDIT:
			edit_workspace_requested.emit(_menu_target, _workspaces[_menu_target].duplicate(true))
		Action.REMOVE:
			var removed: String = _workspaces[_menu_target].get("name", "")
			_workspaces.remove_at(_menu_target)
			Store.save_workspaces(_workspaces)
			_populate()
			_open_btn.disabled = true
			status_changed.emit("Removed workspace '%s'" % removed)
