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

# Custom document/field "types" keyed to collections, plus the context-menu
# actions each type offers. Both are plain data (JSON-serialisable) so they can
# later be loaded from a user-editable file; subclasses populate them in _init().
#
# type_rules: Array of { "collection": String, "field": String, "type": String }.
#   field == "" (or absent) matches the whole document; otherwise it's a dotted
#   field path within the document ("u._id").
# type_actions: Dictionary of type name -> Array of extra action Dictionaries,
#   each { "id", "label", "target_collection", "filter": Dictionary, "function" }.
#   In `filter`, a String value shaped like "$dotted.path" is replaced at trigger
#   time with the value at that path in the selected document (or field value).
#   "$" on its own resolves to the selected value itself (useful for field-level
#   types whose source is a scalar, e.g. "$" == the clicked _id string).
#   Most actions don't need to be listed here: actions_for_type() also derives one
#   "list" action per field-level rule that references the type (see there), so a
#   type used as a filterable field anywhere is listable everywhere it appears.
var type_rules: Array = []
var type_actions: Dictionary = {}


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


# Custom types & actions ------------------------------------------------------
## Resolve the custom "type" name for a value at `field_path` within a document
## of `collection`. field_path == "" means the whole document. Returns "" when no
## rule matches. `_value` is available for future value-dependent rules.
func type_for(collection: String, field_path: String, _value: Variant = null) -> String:
	for rule in type_rules:
		if str(rule.get("collection", "")) != collection:
			continue
		if str(rule.get("field", "")) == field_path:
			return str(rule.get("type", ""))
	return ""


## The context-menu actions offered by a custom type. Beyond any actions listed
## explicitly in type_actions, one "list" action is auto-generated per field-level
## rule that references this type: it opens that rule's collection filtered by the
## rule's field set to the clicked value ("$"). So because a "UserId" is used at
## rocketchat_video_conference.createdBy._id, any UserId value gains a
## "List Video Conferences" action filtering that collection by createdBy._id.
## The field name is appended to the label only when a collection has more than
## one field of the type (to disambiguate). Returns [] when the type has neither
## explicit actions nor field usages.
func actions_for_type(type_name: String) -> Array:
	var actions: Array = []
	var manual: Variant = type_actions.get(type_name, [])
	if manual is Array:
		actions.append_array(manual)
	for rule in type_rules:
		if str(rule.get("type", "")) != type_name:
			continue
		var field := str(rule.get("field", ""))
		if field.is_empty():
			continue  # Whole-document types can't be used as a filter value.
		var collection := str(rule.get("collection", ""))
		var label := "List %ss" % _collection_label(collection)
		if _type_field_count(type_name, collection) > 1:
			label += " by %s" % field
		actions.append({
			"id": "list_%s_by_%s" % [collection, field],
			"label": label,
			"target_collection": collection,
			"filter": {field: "$"},
			"function": "find",
		})
	return actions


## A readable singular label for a collection: its whole-document type name split
## into words ("VideoConference" -> "Video Conference"), or the raw collection
## name when the collection has no document-level type.
func _collection_label(collection: String) -> String:
	var doc_type := type_for(collection, "", null)
	return _humanize(doc_type) if not doc_type.is_empty() else collection


## Split a CamelCase identifier into space-separated words.
func _humanize(name: String) -> String:
	var out := ""
	for i in name.length():
		var ch := name[i]
		if i > 0 and _is_upper(ch) and _is_lower_or_digit(name[i - 1]):
			out += " "
		out += ch
	return out


## How many field-level rules give `collection` an attribute of `type_name`; used
## to decide whether a generated action's label needs the field name to be unique.
func _type_field_count(type_name: String, collection: String) -> int:
	var n := 0
	for rule in type_rules:
		if str(rule.get("type", "")) == type_name \
				and str(rule.get("collection", "")) == collection \
				and not str(rule.get("field", "")).is_empty():
			n += 1
	return n


## The distinct attribute fields of `collection` that carry a custom type (i.e.
## every rule with a non-empty field), each as { "field": String, "type": String }
## in rule order. Used to build per-attribute sub-menus on a document's context
## menu. The whole-document rule (field == "") is excluded.
func typed_fields(collection: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for rule in type_rules:
		if str(rule.get("collection", "")) != collection:
			continue
		var field := str(rule.get("field", ""))
		if field.is_empty() or seen.has(field):
			continue
		seen[field] = true
		out.append({"field": field, "type": str(rule.get("type", ""))})
	return out


## Public accessor for the value at a dotted `path` within `source` (a document),
## or null when any segment is missing. "" returns the source itself.
static func value_at_path(source: Variant, path: String) -> Variant:
	return _value_at_path(source, path)


## Produce a concrete query filter from an action's `filter` template by replacing
## every "$dotted.path" String with the value at that path in `source` (the
## selected document or field value).
static func resolve_filter(filter: Dictionary, source: Variant) -> Dictionary:
	var out: Dictionary = {}
	for key in filter:
		out[key] = _substitute(filter[key], source)
	return out


static func _substitute(value: Variant, source: Variant) -> Variant:
	if value is Dictionary:
		var d: Dictionary = {}
		for k in value:
			d[k] = _substitute(value[k], source)
		return d
	if value is Array:
		var a: Array = []
		for e in value:
			a.append(_substitute(e, source))
		return a
	if value is String and (value as String).begins_with("$"):
		return _value_at_path(source, (value as String).substr(1))
	return value


static func _value_at_path(source: Variant, path: String) -> Variant:
	# An empty path ("$" on its own) means the source value itself — handy when the
	# source is a scalar (e.g. a field value) rather than a document.
	if path.is_empty():
		return source
	var cur: Variant = source
	for seg in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(seg):
			cur = (cur as Dictionary)[seg]
		else:
			return null
	return cur


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
