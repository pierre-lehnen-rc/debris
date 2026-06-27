class_name RocketChatSchema
extends DatabaseSchema

## Schema tuned for Rocket.Chat databases. It rewrites collection names before
## grouping so related collections land under meaningful feature folders
## (omnichannel, federation, media calls, admin, …). The rewrite affects only the
## grouping/display — the real collection name used to run queries is preserved.

# Collections grouped under a feature folder by an exact name match.
const MEDIA_COLLECTIONS := ["call_history", "video_conference"]
const OMNICHANNEL_COLLECTIONS := ["canned_response"]


## Rocket.Chat databases have many small feature folders, so subdivide groups
## more eagerly than the generic default.
func _init() -> void:
	min_group_size = 3


## Sort the tree by each collection's grouped path, so it appears ordered by its
## (mutated) display layout. At every level a folder's own same-named collection
## comes first, then sub-folders, then loose collections — each band sorted by
## label. Precomputes a key per name so the sort doesn't re-walk the structure
## on every comparison.
func order_names(structure: Array, names: Array) -> Array:
	var keyed: Array = []
	for name in names:
		keyed.append({"name": name, "key": _sort_key(path_for(structure, name))})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
	var ordered: Array = []
	for entry in keyed:
		ordered.append(entry["name"])
	return ordered


## Build a comparable key for a tree path. Each path segment becomes a
## [rank, label] pair so lexicographic Array comparison orders, at every level:
## the parent's self-collection (rank 0), then sub-folders (rank 1), then loose
## collections (rank 2) — alphabetically within each band.
func _sort_key(path: Array) -> Array:
	var key: Array = []
	var last := path.size() - 1
	for i in path.size():
		var rank := 1  # A folder: this segment has deeper segments below it.
		if i == last:
			# A leaf: the folder's own same-named collection sorts first, any other
			# collection sorts last.
			rank = 0 if i > 0 and path[i] == path[i - 1] else 2
		key.append([rank, path[i]])
	return key


func mutate_collection_name(collection_name: String) -> String:
	var name := collection_name
	var has_prefix := false

	# 1. Drop the common "rocketchat_" prefix.
	if name.begins_with("rocketchat_"):
		has_prefix = true
		name = name.substr("rocketchat_".length())
	elif name.begins_with("omnichannel_"):
		has_prefix = true
	elif name.begins_with("custom_emoji"):
		has_prefix = true

	# 2-4. Re-home feature prefixes under a parent feature folder.
	if name.begins_with("livechat_"):
		name = "omnichannel_" + name
	elif name.begins_with("matrix_"):
		name = "federation_" + name
	elif name.begins_with("freeswitch_"):
		name = "media_" + name
	elif name.begins_with("read_receipt"):
		name = "message_" + name

	# 5-7. Group well-known standalone collections under a feature folder.
	if name in MEDIA_COLLECTIONS:
		name = "media_" + name
	elif name in OMNICHANNEL_COLLECTIONS:
		name = "omnichannel_" + name

	if has_prefix:
		return "rocketchat_" + name

	return name


## Label a collection by a cleaned version of its full name: drop the
## "rocketchat_", then "omnichannel_", then "livechat_" prefixes in turn.
func mutate_collection_label(_label: String, collection_name: String) -> String:
	var name := collection_name
	if name.begins_with("rocketchat_"):
		name = name.substr("rocketchat_".length())
	if name.begins_with("omnichannel_"):
		name = name.substr("omnichannel_".length())
	if name.begins_with("livechat_"):
		name = name.substr("livechat_".length())
	return name
