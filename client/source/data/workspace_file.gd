class_name WorkspaceFile
extends RefCounted

## Reads and writes a WorkspaceDoc as a `.debris-project` JSON file. Only the
## document's configuration is persisted (see WorkspaceDoc.to_dict); runtime state
## and login-acquired tokens are never written. Both operations return a result
## dictionary { ok: bool, error: String[, doc: WorkspaceDoc] } so callers can
## surface failures (bad path, unreadable/ën-parseable file) instead of guessing.

const EXTENSION := "debris-project"


## Write `doc` to `path` as pretty JSON. On success, updates the doc's file_path
## and clears its dirty flag so it reflects the saved state.
static func save(doc: WorkspaceDoc, path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "could not open '%s' for writing" % path}
	f.store_string(JSON.stringify(doc.to_dict(), "\t"))
	f.close()
	doc.file_path = path
	doc.dirty = false
	return {"ok": true, "error": ""}


## Read a project file into a fresh WorkspaceDoc. The returned doc has its
## file_path set and dirty cleared.
static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no such file: '%s'" % path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "could not open '%s'" % path}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return {"ok": false, "error": "'%s' is not a valid project file" % path}
	var doc := WorkspaceDoc.from_dict(parsed as Dictionary)
	doc.file_path = path
	doc.dirty = false
	return {"ok": true, "error": "", "doc": doc}
