extends "res://dev/check_base.gd"

## Validates the filter boxes on the two data-backed sidebars, driven through their
## real load paths (the Backend / RocketChat mocks supply the lists):
##
##   1. collections  -> narrowed by name, matched against the full name so a prefix
##                      folded into a group folder still counts;
##   2. endpoints    -> narrowed by "METHOD /path", so the verb filters too;
##   3. collections  -> the grouping is untouched: a surviving row keeps the folder
##                      and label it had before the filter (the folders are NOT
##                      re-derived from the survivors);
##   4. both         -> the header's box is actually wired to the list, the filter
##                      survives a reload, and clearing it restores the full list.
##
## See source/ui/widgets/filter_field.gd and the sidebars' set_filter().

# Loaded at runtime, not preloaded: these scripts reference the Backend/RocketChat
# autoloads, which aren't registered yet when this -s main-loop script compiles.
const COLLECTIONS_PATH := "res://source/ui/sidebar/collection_sidebar.tscn"
const ENDPOINTS_PATH := "res://source/ui/workspace/endpoint_sidebar.tscn"
const CONNECTION := {"host": "localhost", "port": 27017}
const WORKSPACE := {"url": "https://chat.example", "users": []}


func _run() -> void:
	await _case_collections()
	await _case_grouping_is_untouched()
	await _case_endpoints()


# 1 + 3. Collections: filter, reload, clear.
func _case_collections() -> void:
	var sb: Variant = load(COLLECTIONS_PATH).instantiate()
	root.add_child(sb)
	sb.configure(CONNECTION, "debris")
	await _settle()
	var all: Array = sb.listed_collections()
	expect(all.size() > 1, "collections: the mock list loaded")

	sb.set_filter("room")
	expect_eq(sb.listed_collections(), ["rooms"], "collections: filtered by name")

	# "rocketchat_" is folded into a group folder, but the filter sees the full name.
	sb.set_filter("rocketchat")
	expect_eq(
		sb.listed_collections(),
		["rocketchat_message", "rocketchat_settings"],
		"collections: matched on the full name, not the displayed label"
	)

	sb.set_filter("nope")
	expect(sb.listed_collections().is_empty(), "collections: no matches lists nothing")

	# A reload keeps the filter — it's the user's view, not part of the data.
	sb.configure(CONNECTION, "debris")
	await _settle()
	expect(sb.listed_collections().is_empty(), "collections: the filter survives a reload")

	sb.set_filter("")
	expect_eq(sb.listed_collections().size(), all.size(), "collections: clearing restores all")

	# End to end through the header widget — set_filter() working on its own says
	# nothing about whether the box is connected to it.
	var box: Variant = sb.get_node("%Filter")
	box.text = "rooms"
	box.flush()
	expect_eq(sb.listed_collections(), ["rooms"], "collections: the filter box drives the list")
	sb.queue_free()


# 3. The filter removes rows without regrouping what's left.
func _case_grouping_is_untouched() -> void:
	var sb: Variant = load(COLLECTIONS_PATH).instantiate()
	root.add_child(sb)
	sb.configure(CONNECTION, "debris")
	await _settle()
	var before := _tree_paths(sb)
	expect(
		before.has("rocketchat/message"),
		"grouping: the mock's rocketchat_ collections are grouped under a folder"
	)

	# One survivor, and it keeps the folder and label it had. Regrouping the
	# survivors would strip the folder (a one-name trie has nothing to group) and
	# show the full "rocketchat_message" at the root instead.
	sb.set_filter("message")
	expect_eq(_tree_paths(sb), ["rocketchat/message"], "grouping: the row keeps its folder")

	# A folder whose own label matches keeps everything under it.
	sb.set_filter("rocketchat")
	expect_eq(
		_tree_paths(sb),
		["rocketchat/message", "rocketchat/settings"],
		"grouping: a matching folder lists all of its collections"
	)

	sb.set_filter("")
	expect_eq(_tree_paths(sb), before, "grouping: clearing restores the original tree")
	sb.queue_free()


# 2. Endpoints: filter by path and by verb, then clear.
func _case_endpoints() -> void:
	var sb: Variant = load(ENDPOINTS_PATH).instantiate()
	root.add_child(sb)
	sb.configure(WORKSPACE)
	await _settle()
	var all: int = sb.listed_endpoints().size()
	expect(all > 1, "endpoints: the mock OpenAPI spec loaded")

	sb.set_filter("rooms")
	var by_path: Array = sb.listed_endpoints()
	expect(by_path.size() > 0, "endpoints: filtered by path segment")
	expect(by_path.size() < all, "endpoints: the filter actually narrowed the list")
	expect(_all_match(by_path, "rooms"), "endpoints: every listed endpoint matches")

	# The verb is part of the haystack, so "get channels" narrows to reads.
	sb.set_filter("get rooms")
	var reads: Array = sb.listed_endpoints()
	expect(reads.size() > 0, "endpoints: verb + path lists something")
	expect(reads.size() <= by_path.size(), "endpoints: adding a term only narrows")
	var all_get := true
	for ep in reads:
		if ep.method != "GET":
			all_get = false
	expect(all_get, "endpoints: every listed endpoint is a GET")

	sb.set_filter("zzz nothing")
	expect(sb.listed_endpoints().is_empty(), "endpoints: no matches lists nothing")

	sb.set_filter("")
	expect_eq(sb.listed_endpoints().size(), all, "endpoints: clearing restores all")
	sb.queue_free()


# Helpers ---------------------------------------------------------------------
## The sidebar's rendered collection rows as "folder/…/label" paths, in tree order.
func _tree_paths(sb: Variant) -> Array:
	var out: Array = []
	_walk(sb.get_node("Box/Tree").get_root(), "", out)
	return out


func _walk(item: TreeItem, prefix: String, out: Array) -> void:
	var child := item.get_first_child()
	while child != null:
		var path: String = prefix + child.get_text(0)
		if child.get_first_child() == null:
			out.append(path)
		else:
			_walk(child, path + "/", out)
		child = child.get_next()


func _all_match(endpoints: Array, term: String) -> bool:
	for ep in endpoints:
		if not ("%s %s" % [ep.method, ep.path]).to_lower().contains(term):
			return false
	return true


## Let the async _load coroutines run to completion (the mocks resolve within a
## handful of idle frames).
func _settle() -> void:
	for _i in 12:
		await process_frame
