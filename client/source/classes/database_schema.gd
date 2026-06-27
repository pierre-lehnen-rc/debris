class_name DatabaseSchema
extends RefCounted

## Base class for database schemas. A schema owns the (UI-free) grouping logic
## for collection lists: given a flat list of collection names it determines a
## folder tree by shared leading words (splitting on "_", "." and camelCase) and
## then maps each name to the tree path it should live at. It never touches the
## Tree; ordering defaults to the caller's input order, but a schema may opt to
## reorder via order_names (see RocketChatSchema).
##
## Subclasses (GenericSchema, RocketChatSchema) can override the grouping rules
## for schema-specific layouts. The base implementation is the generic default.
##
## Typical use:
##     var schema := GenericSchema.new()
##     var structure := schema.build_structure(names)
##     for name in names:
##         var path := schema.path_for(structure, name)
##         # path[0..-2] are folder labels, path[-1] is the leaf's display label.

# Tunable grouping knobs. Declared as members (not consts) so subclasses can
# override them by reassigning in their own _init().

# Grouping stops at this many levels deep; anything deeper is listed flat by the
# part of the name below the flatten point.
var max_group_depth := 3

# A group holding fewer than this many collections is shown as a flat list
# rather than being split into sub-groups.
var min_group_size := 8

# When a group holds both sub-groups and loose collections, bucket the loose
# collections into a "." sub-group so the two kinds aren't shown side by side.
var bucket_loose_collections := false

# Real collection names to visually highlight in the list so they're easy to
# spot at a glance. Subclasses populate this in their _init().
var highlighted_collections: Array = []


# Public API ------------------------------------------------------------------
## Determine the display tree for a list of collection names. Returns an ordered
## Array of display nodes, each a Dictionary {label, full, children}:
## `label` is the displayed segment, `children` an Array of child nodes (empty
## for a leaf), and `full` the real collection name for a leaf (else "").
## Order here is incidental — the result is only used for path lookup.
func build_structure(names: Array) -> Array:
	var trie := _build_trie(names)
	var display := _build_display(trie, 1, [])
	_apply_labels(display, [])
	return display


## Map a collection name to its intended tree path within `structure`. Returns
## an Array of labels from the top folder down to the leaf's display label, e.g.
## "rocketchat_apps_packages.chunk" -> ["rocketchat", "apps", "packages.chunk"].
## Falls back to [name] if the name isn't found in the structure.
func path_for(structure: Array, name: String) -> Array:
	var path: Array = []
	if _find_path(structure, name, path):
		return path
	return [name]


## Decide the order in which collections are added to the tree. The base schema
## preserves the caller's order, so the tree mirrors the input list. Subclasses
## may reorder — e.g. to sort folders and their leaves by grouped path.
## `structure` is the result of build_structure(names).
func order_names(_structure: Array, names: Array) -> Array:
	return names


## Whether a collection should be visually highlighted in the list. Matches the
## real collection name against highlighted_collections.
func is_highlighted(collection_name: String) -> bool:
	return collection_name in highlighted_collections


# Display-tree construction ---------------------------------------------------
## Turn a set of sibling trie nodes into display nodes, applying the bucketing,
## flatten and self-collection rules. `extra_colls` carries loose collection
## leaves from the caller (e.g. a folder's own same-named collection).
func _build_display(nodes: Array, depth: int, extra_colls: Array) -> Array:
	var groups: Array = []
	var colls: Array = extra_colls.duplicate()  # Array of leaf display nodes.
	for node in nodes:
		if node["children"].is_empty():
			colls.append(_leaf(node["label"], node["full"]))
		else:
			groups.append(node)

	# When both kinds are present, loose collections go into a "." sub-group so
	# folders and collections are never shown side by side.
	var bucket := bucket_loose_collections and not groups.is_empty() and not colls.is_empty()

	var result: Array = []
	if bucket:
		result.append({"label": ".", "full": "", "children": colls})
	else:
		for entry in colls:
			result.append(entry)
	for node in groups:
		result.append(_build_group(node, depth))
	return result


## Build a single folder display node from a branching trie node.
func _build_group(node: Dictionary, depth: int) -> Dictionary:
	# A collection whose name is exactly this folder's path becomes a loose
	# collection within the folder (subject to the same bucketing rule).
	var self_colls: Array = []
	if node["full"] != "":
		self_colls.append(_leaf(node["label"], node["full"]))

	var children: Array
	# Flatten when nesting too deep or when too few collections to sub-group.
	# Flattened contents are all leaves, labelled by the name below this folder.
	if depth >= max_group_depth or _count_collections(node) < min_group_size:
		children = self_colls.duplicate()
		_collect_flat(node["children"], "", children)
	else:
		children = _build_display(node["children"], depth + 1, self_colls)
	return {"label": node["label"], "full": "", "children": children}


func _leaf(label: String, full: String) -> Dictionary:
	return {"label": label, "full": full, "children": []}


## Rewrite every collection leaf's label via mutate_collection_label, giving the
## hook the leaf's ancestor folder labels (root down to and including its parent
## folder). Folder labels are left untouched.
func _apply_labels(nodes: Array, ancestors: Array) -> void:
	for node in nodes:
		if node["children"].is_empty():
			node["label"] = mutate_collection_label(node["label"], node["full"], ancestors)
		else:
			_apply_labels(node["children"], ancestors + [node["label"]])


## Depth-first search for the leaf matching `name`, recording labels into `path`.
func _find_path(nodes: Array, name: String, path: Array) -> bool:
	for node in nodes:
		path.append(node["label"])
		if node["children"].is_empty():
			if node["full"] == name:
				return true
		elif _find_path(node["children"], name, path):
			return true
		path.pop_back()
	return false


# Prefix-tree construction ----------------------------------------------------
## Build a compressed prefix tree from collection names. Each node is a
## Dictionary {label, sep, full, children}: `label` is the displayed segment,
## `sep` the separator that joined it to its parent, `full` the real collection
## name when a collection ends exactly here (else ""), `children` an ordered
## Array of child nodes.
func _build_trie(names: Array) -> Array:
	var root := {"children": [], "keys": {}}
	for name in names:
		var node: Dictionary = root
		for seg in _tokenize(name):
			var tok: String = seg["token"]
			# Singular and plural forms of a word share one node, so "media_calls"
			# groups with "media_call_channels". The key is the singularized token;
			# the displayed label keeps the real spelling, preferring the plural
			# when both forms occur.
			var key := _singularize(tok)
			if not node["keys"].has(key):
				var child := {
					"label": tok,
					"sep": seg["sep"],
					"full": "",
					"children": [],
					"keys": {},
				}
				node["keys"][key] = child
				node["children"].append(child)
			elif tok != key:
				node["keys"][key]["label"] = tok  # A plural form; prefer it as the label.
			node = node["keys"][key]
		node["full"] = name
	_compress_nodes(root["children"])
	return root["children"]


## Reduce a word to a singular form for grouping purposes only (the displayed
## label keeps the original spelling). Handles basic English plurals; common
## non-plural "-s" endings ("status", "analysis", "class") are left untouched.
func _singularize(word: String) -> String:
	var lower := word.to_lower()
	if lower.length() <= 3 or not lower.ends_with("s"):
		return word
	if lower.ends_with("ies"):  # categories -> category
		return word.substr(0, word.length() - 3) + "y"
	if lower.ends_with("ses") or lower.ends_with("xes") or lower.ends_with("zes") \
			or lower.ends_with("ches") or lower.ends_with("shes"):  # boxes -> box
		return word.substr(0, word.length() - 2)
	# Leave "ss" (class), "us" (status), "is" (analysis) alone; otherwise drop the
	# trailing "s" (calls -> call, channels -> channel).
	if lower.ends_with("ss") or lower.ends_with("us") or lower.ends_with("is"):
		return word
	return word.substr(0, word.length() - 1)


## Collapse single-child chains into one node ("freeswitch" > "channel" becomes
## "freeswitch_channel"), stopping at branches and at real collections.
func _compress_nodes(nodes: Array) -> void:
	for node in nodes:
		while node["children"].size() == 1 and node["full"] == "":
			var child: Dictionary = node["children"][0]
			node["label"] = node["label"] + child["sep"] + child["label"]
			node["full"] = child["full"]
			node["children"] = child["children"]
		_compress_nodes(node["children"])


## Hook for schema-specific rewriting of a collection name before it is tokenized
## for grouping. The base schema returns the name unchanged; subclasses can remap
## names to drive a different folder layout. Only affects grouping/display — the
## real collection name (used to open queries) is preserved separately.
func mutate_collection_name(collection_name: String) -> String:
	return collection_name


## Hook for schema-specific rewriting of a collection leaf's display LABEL. The
## grouping algorithm passes the label it chose, the real collection name, and
## the leaf's ancestor folder labels (root down to and including its parent
## folder). The base returns the label unchanged. Subclasses can derive a
## different label (e.g. from the full name and its place in the tree). Only
## affects display — the real collection name (used to open queries) is preserved.
func mutate_collection_label(label: String, _collection_name: String, _ancestors: Array) -> String:
	return label


## Split a name into {sep, token} segments on "_", "." and camelCase boundaries.
## `sep` is the separator preceding the token ("" for the first / camelCase).
## A separator only splits when a word precedes it; a leading or doubled
## separator has no preceding word, so it stays as literal text on the next
## token ("_queue" stays "_queue", "x__trash" becomes "x" + "_trash").
## camelCase splitting is only applied when the name has no "_" or "." separator,
## so explicitly-separated names ("read_receipt") aren't further split inside
## their words.
func _tokenize(name: String) -> Array:
	name = mutate_collection_name(name)
	# Names that already use "_" or "." express their own word boundaries, so
	# don't also split them on camelCase.
	var split_camel := not ("_" in name or "." in name)
	var segs: Array = []
	var cur := ""
	var pending_sep := ""
	for i in name.length():
		var ch := name[i]
		if ch == "_" or ch == ".":
			if cur.is_empty():
				cur += ch  # No word before it; keep as literal prefix.
			else:
				segs.append({"sep": pending_sep, "token": cur})
				cur = ""
				pending_sep = ch
		else:
			# camelCase: a capital following a lowercase letter or digit starts a
			# new word (but not after a literal "_"/"." prefix).
			if split_camel and not cur.is_empty() and _is_upper(ch) and _is_lower_or_digit(cur[cur.length() - 1]):
				segs.append({"sep": pending_sep, "token": cur})
				cur = ""
				pending_sep = ""
			cur += ch
	if not cur.is_empty():
		segs.append({"sep": pending_sep, "token": cur})
	return segs


func _is_upper(c: String) -> bool:
	return c >= "A" and c <= "Z"


func _is_lower_or_digit(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "0" and c <= "9")


## Total number of real collections within a node (including the node itself).
func _count_collections(node: Dictionary) -> int:
	var n := 1 if node["full"] != "" else 0
	for child in node["children"]:
		n += _count_collections(child)
	return n


## Flatten subtrees into leaf display nodes, where `label` is the name below the
## flatten point (segments joined by their separators), so a deeply nested
## "rc_apps_packages.chunks" under the "packages" folder shows as "chunks".
func _collect_flat(nodes: Array, prefix: String, out: Array) -> void:
	for node in nodes:
		var label: String = node["label"] if prefix == "" else prefix + node["sep"] + node["label"]
		if node["full"] != "":
			out.append(_leaf(label, node["full"]))
		_collect_flat(node["children"], label, out)
