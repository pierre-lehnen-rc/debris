class_name ConnectionPicker
extends Window

## Popup that lists connections and their databases. Opened from the toolbar (or
## automatically when no workspace tabs are open). Picking a database emits
## `database_selected` so Main can open a workspace tab for it. Connection
## management (add/edit/remove, connect/disconnect) is delegated to the embedded
## ConnectionBrowser.

signal database_selected(connection: Dictionary, database: String)
signal add_connection_requested()
signal edit_connection_requested(index: int, config: Dictionary)
signal status_changed(text: String)

@onready var _browser: ConnectionBrowser = %Browser
@onready var _open_btn: Button = %OpenBtn


func open() -> void:
	popup_centered(Vector2i(420, 480))
	# Reflect whatever (if anything) is currently selected in the tree.
	_open_btn.disabled = _browser.selected_database().is_empty()


# Forwarded from Main after the connection dialog saves/updates ---------------
func add_connection(config: Dictionary) -> void:
	_browser.add_connection(config)


func update_connection(index: int, config: Dictionary) -> void:
	_browser.update_connection(index, config)


# Wired in connection_picker.tscn from the embedded browser ------------------
func _on_database_activated(connection: Dictionary, database: String) -> void:
	database_selected.emit(connection, database)
	hide()


func _on_selection_changed(has_database: bool) -> void:
	_open_btn.disabled = not has_database


func _on_open_pressed() -> void:
	var selection := _browser.selected_database()
	if selection.is_empty():
		return
	database_selected.emit(selection["connection"], selection["database"])
	hide()


func _on_add_connection_requested() -> void:
	add_connection_requested.emit()


func _on_edit_connection_requested(index: int, config: Dictionary) -> void:
	edit_connection_requested.emit(index, config)


func _on_status_changed(text: String) -> void:
	status_changed.emit(text)
