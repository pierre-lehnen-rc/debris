class_name WorkspaceState
extends RefCounted

## The in-memory model of a project's `.debris-workspace` sidecar — the per-user,
## machine-local session state that sits next to the shared `.debris-project`
## file (mirroring Sublime's project/workspace split). Unlike WorkspaceDoc, this
## holds no connection configuration; it holds only what a session needs to pick
## up where it left off:
##
##   - the open query/endpoint tabs (their target + typed queries/params, never
##     their results), and which one was active, so a project reopens its layout;
##   - a cache of the API endpoints parsed from the workspace's OpenAPI document,
##     so the endpoint list still loads when the Rocket.Chat server is down.
##
## It is written automatically (see ProjectTab.persist_state) rather than through
## an explicit Save, and is safe to delete/ignore — the project is fully usable
## without it. WorkspaceStateFile handles the JSON on disk.

const VERSION := 1

## How many recent queries are kept per collection; older ones are evicted. Queries
## flagged as favorites live in the project file instead and are never capped here.
const RECENT_LIMIT := 20

# Persisted -------------------------------------------------------------------
## One entry per open source tab, in tab order. Each is a self-describing dict
## tagged by "kind" ("query" | "endpoint"); see QueryTab.to_state /
## EndpointTab.to_state for the exact shapes.
var tabs: Array = []
## Index of the tab that was focused, clamped on restore.
var active_tab: int = 0
## Cached endpoint catalog: { "url": String, "fetched_at": String,
## "endpoints": Array[Dictionary] }, or {} when nothing has been cached. Keyed by
## URL so a stale cache is ignored after the API's URL is changed.
var endpoints: Dictionary = {}
## Recent queries per collection: { collection: Array[query-entry] }, newest first,
## capped at RECENT_LIMIT. Each entry is a QueryHistory saved-query dict.
var query_history: Dictionary = {}


## Replace the endpoint cache with the given parsed endpoints (ApiEndpoint list)
## for `url`, stamping the fetch time.
func set_endpoint_cache(url: String, endpoint_list: Array, fetched_at: String) -> void:
	var dicts: Array = []
	for e in endpoint_list:
		if e is ApiEndpoint:
			dicts.append((e as ApiEndpoint).to_dict())
	endpoints = {"url": url, "fetched_at": fetched_at, "endpoints": dicts}


## The cached endpoints for `url` as ApiEndpoint objects, or [] when there is no
## cache or it belongs to a different URL.
func cached_endpoints(url: String) -> Array:
	if endpoints.get("url", "") != url:
		return []
	var out: Array = []
	for d in endpoints.get("endpoints", []):
		if d is Dictionary:
			out.append(ApiEndpoint.from_dict(d))
	return out


# Recent queries --------------------------------------------------------------
## Record `entry` as the newest recent for `collection`. Any earlier identical query
## (same operation/filter/options) is dropped first so the repeat resurfaces at the
## top, then the list is capped to RECENT_LIMIT.
func record_query(collection: String, entry: Dictionary) -> void:
	if collection.is_empty():
		return
	var kept: Array = []
	for e in recent_queries(collection):
		if not (e is Dictionary and QueryHistory.same_query(e, entry)):
			kept.append(e)
	kept.push_front(entry)
	while kept.size() > RECENT_LIMIT:
		kept.pop_back()
	query_history[collection] = kept


## The recent queries for `collection`, newest first, or [] when there are none.
func recent_queries(collection: String) -> Array:
	var list: Variant = query_history.get(collection, [])
	return list if list is Array else []


## Forget the recent at `index` for `collection`. Returns true when one was removed.
func remove_recent(collection: String, index: int) -> bool:
	var list := recent_queries(collection)
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	if list.is_empty():
		query_history.erase(collection)
	else:
		query_history[collection] = list
	return true


# Serialization ---------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"tabs": tabs,
		"active_tab": active_tab,
		"endpoints": endpoints,
		"query_history": query_history,
	}


static func from_dict(data: Dictionary) -> WorkspaceState:
	var s := WorkspaceState.new()
	var t: Variant = data.get("tabs", [])
	s.tabs = t if t is Array else []
	s.active_tab = int(data.get("active_tab", 0))
	var e: Variant = data.get("endpoints", {})
	s.endpoints = e if e is Dictionary else {}
	var h: Variant = data.get("query_history", {})
	s.query_history = h if h is Dictionary else {}
	return s
