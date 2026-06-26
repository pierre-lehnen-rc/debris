class_name WorkspaceTab
extends Control

## One workspace tab, scoped to a single pre-selected database. Lays out the
## database's collection sidebar next to the query/results workspace, the same
## as the old single-window layout but bound to one database.

signal status_changed(text: String)

@onready var _sidebar: CollectionSidebar = %CollectionSidebar
@onready var _workspace: Workspace = %Workspace

var _connection: Dictionary = {}
var _database := ""


func _ready() -> void:
	if not _database.is_empty():
		_setup()


## Bind this tab to a connection + database. Safe to call before the node is in
## the tree; the sidebar is configured once the tab is ready.
func configure(connection: Dictionary, database: String) -> void:
	_connection = connection
	_database = database
	if is_node_ready():
		_setup()


## Point the sidebar at the database and open an initial (empty) query tab so the
## workspace is immediately usable.
func _setup() -> void:
	_sidebar.configure(_connection, _database)
	_workspace.open_collection(_connection, _database, "")


func connection() -> Dictionary:
	return _connection


func database() -> String:
	return _database


func tab_title() -> String:
	if _database.is_empty():
		return "(database)"
	var conn_name := String(_connection.get("name", ""))
	return "%s · %s" % [conn_name, _database] if not conn_name.is_empty() else _database


func open_collection(connection: Dictionary, database: String, collection: String) -> QueryTab:
	return _workspace.open_collection(connection, database, collection)


# Wired in workspace_tab.tscn -------------------------------------------------
func _on_collection_activated(connection: Dictionary, database: String, collection: String) -> void:
	_workspace.open_collection(connection, database, collection)
	status_changed.emit("Opened %s.%s" % [database, collection])


func _on_insert_document_requested(
	connection: Dictionary, database: String, collection: String
) -> void:
	var tab := _workspace.open_collection(connection, database, collection)
	tab.results().request_insert()
	status_changed.emit("Insert document into %s.%s" % [database, collection])


func _on_status_changed(text: String) -> void:
	status_changed.emit(text)
