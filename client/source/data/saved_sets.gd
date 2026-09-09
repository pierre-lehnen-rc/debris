class_name SavedSets
extends RefCounted

## A project's saved filter sets of one `kind` ("names" | "columns"), shared across
## all Server Logs tabs. A set is a named snapshot of a CheckFilter's selection
## ({ key -> bool }); one may be flagged the default that seeds new tabs. Backed by
## the WorkspaceDoc (the project file), so sets travel with the project; `changed`
## fires on every mutation so every open tab's filter refreshes and the host persists.

signal changed()

var _doc: WorkspaceDoc = null
var _kind := ""


func setup(doc: WorkspaceDoc, kind: String) -> void:
	_doc = doc
	_kind = kind


## The saved sets, each { name, selection, default }.
func list() -> Array:
	return _doc.filter_set_list(_kind) if _doc != null else []


## Save (or replace by name) a set with `selection`. No-op for a blank name.
func save(set_name: String, selection: Dictionary) -> void:
	if _doc == null or set_name.strip_edges().is_empty():
		return
	_doc.save_filter_set(_kind, set_name.strip_edges(), selection)
	changed.emit()


func remove(set_name: String) -> void:
	if _doc == null:
		return
	_doc.remove_filter_set(_kind, set_name)
	changed.emit()


## Flag `set_name` as the default for new tabs (or clear it); at most one is default.
func set_default(set_name: String, is_default: bool) -> void:
	if _doc == null:
		return
	_doc.set_default_filter_set(_kind, set_name, is_default)
	changed.emit()


func is_default(set_name: String) -> bool:
	for s in list():
		if s is Dictionary and str(s.get("name", "")) == set_name:
			return bool(s.get("default", false))
	return false


## The selection of the set flagged default, or {} when none is.
func default_selection() -> Dictionary:
	return _doc.default_filter_selection(_kind) if _doc != null else {}


## The selection stored under `set_name`, or {}.
func selection_of(set_name: String) -> Dictionary:
	for s in list():
		if s is Dictionary and str(s.get("name", "")) == set_name:
			var sel: Variant = s.get("selection", {})
			return (sel as Dictionary).duplicate() if sel is Dictionary else {}
	return {}
