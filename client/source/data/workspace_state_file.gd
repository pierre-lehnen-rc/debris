class_name WorkspaceStateFile
extends RefCounted

## Reads and writes a WorkspaceState as a `.debris-workspace` JSON file — the
## machine-local session sidecar that lives next to a project's `.debris-project`
## file (same basename, different extension). This is the counterpart to
## WorkspaceFile, which handles the shared project document.
##
## The sidecar is best-effort: a missing file is not an error (a project simply
## opens without restored tabs / cache), so load() distinguishes "absent" from
## "corrupt" via the returned `error`, and callers treat both as "no state".

const EXTENSION := "debris-workspace"


## The sidecar path for a given project file path: same directory and basename,
## with the workspace extension. Returns "" for an empty path (an Untitled,
## never-saved project has no sidecar location).
static func path_for(project_path: String) -> String:
	if project_path.is_empty():
		return ""
	return "%s.%s" % [project_path.get_basename(), EXTENSION]


## Write `state` to `path` as pretty JSON. Returns { ok, error }.
static func save(state: WorkspaceState, path: String) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "error": "no sidecar path"}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "could not open '%s' for writing" % path}
	f.store_string(JSON.stringify(state.to_dict(), "\t"))
	f.close()
	return {"ok": true, "error": ""}


## Read a sidecar into a WorkspaceState. A missing file returns { ok: false }
## with an "absent" marker so the caller can silently proceed; a present but
## unparseable file returns an error the caller may choose to surface.
static func load(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "absent"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "could not open '%s'" % path}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return {"ok": false, "error": "'%s' is not a valid workspace file" % path}
	return {"ok": true, "error": "", "state": WorkspaceState.from_dict(parsed as Dictionary)}
