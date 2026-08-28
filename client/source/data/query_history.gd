class_name QueryHistory
extends RefCounted

## Coordinates a project's saved queries across the two stores that back them:
##
##   - "recents": the last few queries actually run against each collection, kept in
##     the machine-local `.debris-workspace` sidecar (WorkspaceState). Capped and
##     volatile — they turn over as new queries are run.
##   - "favorites": queries the user flagged to keep permanently, kept in the shared
##     `.debris-project` file (WorkspaceDoc) so they travel with the project and are
##     never evicted.
##
## One instance is owned by a ProjectTab and shared with every QueryTab it opens, so
## a query run in any tab is recorded once and any tab's history button can browse
## and re-apply the collection's past queries. A saved query is a plain dict:
##   { function, filter, options, options_visible, run_at } — see QueryTab.
##
## Server Models function calls share both stores and the same history UI. They are
## keyed by {model_key} rather than a collection name — a "model:" prefix no
## collection can collide with — and their entries carry a different shape:
##   { model, method, args, run_at } — see RcModelsTab. same_query() and preview()
## dispatch on that shape, so the stores and the popup handle both kinds unchanged.

## The recents store changed — the sidecar should be rewritten (wired to
## ProjectTab.persist_state).
signal recents_changed()
## The favorites store changed — the project document is now dirty and should be
## saved (wired to ProjectTab, which auto-saves a titled project in place).
signal favorites_changed()

var _state: WorkspaceState = null
var _doc: WorkspaceDoc = null


## Bind the two backing stores. Safe to call once per ProjectTab open.
func setup(state: WorkspaceState, doc: WorkspaceDoc) -> void:
	_state = state
	_doc = doc


# Recents (sidecar) -----------------------------------------------------------
## Record a just-run query as the newest recent for `collection`, deduped and capped
## by WorkspaceState. No-op without a collection or store.
func record(collection: String, entry: Dictionary) -> void:
	if _state == null or collection.is_empty():
		return
	_state.record_query(collection, entry)
	recents_changed.emit()


func recents(collection: String) -> Array:
	return _state.recent_queries(collection) if _state != null else []


func remove_recent(collection: String, index: int) -> void:
	if _state != null and _state.remove_recent(collection, index):
		recents_changed.emit()


# Favorites (project file) ----------------------------------------------------
func favorites(collection: String) -> Array:
	return _doc.favorite_queries_for(collection) if _doc != null else []


## Whether `entry` is already saved as a favorite of `collection` (drives the star
## state in the history list, including for a recent that has been favorited).
func is_favorite(collection: String, entry: Dictionary) -> bool:
	if _doc == null:
		return false
	for f in _doc.favorite_queries_for(collection):
		if f is Dictionary and same_query(f, entry):
			return true
	return false


func add_favorite(collection: String, entry: Dictionary) -> void:
	if _doc != null and _doc.add_favorite_query(collection, entry):
		favorites_changed.emit()


func remove_favorite(collection: String, entry: Dictionary) -> void:
	if _doc != null and _doc.remove_favorite_query(collection, entry):
		favorites_changed.emit()


# Identity / display ----------------------------------------------------------
## The store key for a Server Models function's history. Prefixed so it can never
## collide with a collection name, keeping model history beside query history in the
## same two stores without either seeing the other's entries.
static func model_key(model: String, method: String) -> String:
	return "model:%s.%s" % [model, method]


## Two saved queries are "the same" when their operation and (whitespace-trimmed)
## filter and options match, so re-running an identical query resurfaces the
## existing recent instead of stacking a duplicate, and it can't be favorited twice.
## A model-function entry is identified by its call instead: model, method and args.
static func same_query(a: Dictionary, b: Dictionary) -> bool:
	if a.has("model") or b.has("model"):
		return (
			String(a.get("model", "")) == String(b.get("model", ""))
			and String(a.get("method", "")) == String(b.get("method", ""))
			and String(a.get("args", "")).strip_edges() == String(b.get("args", "")).strip_edges()
		)
	return (
		String(a.get("function", "find")) == String(b.get("function", "find"))
		and String(a.get("filter", "")).strip_edges() == String(b.get("filter", "")).strip_edges()
		and String(a.get("options", "")).strip_edges() == String(b.get("options", "")).strip_edges()
	)


## A one-line label for a saved query, shown in the history list: the filter with
## its whitespace collapsed, prefixed by the operation when it isn't a plain find,
## and marked when it carries find options. A model-function entry shows its
## argument list — the model and method are implied by the tab the list opened from.
static func preview(entry: Dictionary) -> String:
	if entry.has("model"):
		var args := _collapse(String(entry.get("args", "")).strip_edges())
		return args if not args.is_empty() else "[]"
	var filter := _collapse(String(entry.get("filter", "")).strip_edges())
	if filter.is_empty():
		filter = "{}"
	var fn := String(entry.get("function", "find"))
	var text := filter if fn == "find" else "%s  %s" % [fn, filter]
	# Show the options object too — some entries carry only options over an empty
	# filter, and even with a filter the options change the query's meaning.
	var options := _collapse(String(entry.get("options", "")).strip_edges())
	if not options.is_empty():
		text += "   · options: %s" % options
	return text


static func _collapse(s: String) -> String:
	var out := s.replace("\n", " ").replace("\t", " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out
