class_name RocketChatSchema
extends DatabaseSchema

## Schema tuned for Rocket.Chat databases. It rewrites collection names before
## grouping so related collections land under meaningful feature folders
## (omnichannel, federation, media calls, admin, …). The rewrite affects only the
## grouping/display — the real collection name used to run queries is preserved.

# Collections grouped under a feature folder by an exact name match.
const MEDIA_COLLECTIONS := ["call_history", "video_conference"]
const OMNICHANNEL_COLLECTIONS := ["canned_response"]
const SKIPPED_LABEL_PREFIXES := ["rocketchat_", "omnichannel_", "livechat_", "meteor_"]

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


## Label a collection by its name relative to its parent's parent: take the
## (grouping-)mutated name and strip the prefix contributed by every folder above
## the parent. So "rocketchat_cron_history" nested under rocketchat > cron shows
## as "cron_history", while a collection only one folder deep keeps its full name.
func mutate_collection_label(_label: String, collection_name: String, ancestors: Array) -> String:
	var name := collection_name
	# Grandparent folders = every ancestor except the immediate parent (the last).
	var grandparents: Array = ancestors.slice(0, ancestors.size() - 1) if ancestors.size() > 1 else []
	var pos := 0
	for folder in grandparents:
		var label: String = folder
		if name.substr(pos, label.length()) != label:
			break  # Defensive: name/structure mismatch — stop stripping.
		pos += label.length()
		if pos < name.length() and (name[pos] == "_" or name[pos] == "."):
			pos += 1
	var auto_name = name.substr(pos)
	for prefix in SKIPPED_LABEL_PREFIXES:
		if auto_name.begins_with(prefix):
			auto_name = auto_name.substr(prefix.length())
	return auto_name
