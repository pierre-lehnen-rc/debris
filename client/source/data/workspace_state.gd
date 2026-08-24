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


# Serialization ---------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"tabs": tabs,
		"active_tab": active_tab,
		"endpoints": endpoints,
	}


static func from_dict(data: Dictionary) -> WorkspaceState:
	var s := WorkspaceState.new()
	var t: Variant = data.get("tabs", [])
	s.tabs = t if t is Array else []
	s.active_tab = int(data.get("active_tab", 0))
	var e: Variant = data.get("endpoints", {})
	s.endpoints = e if e is Dictionary else {}
	return s
