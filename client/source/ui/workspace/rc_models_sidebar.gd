class_name RcModelsSidebar
extends PanelContainer

## The Models sidebar view of a project's Rocket.Chat workspace: a tree of the
## server's @rocket.chat/models models, listed like the Database panel's collections
## (folder icon per model; functions will hang under them later). The model list is
## supplied by the host after the bridge is injected (set_models). Double-clicking a
## function opens a query for it. The header's filter box narrows the list as you
## type, matching model names and the functions already loaded under them. When the
## workspace has no Rocket.Chat repository path the bridge can't be reached, so a
## message replaces the tree until one is set.

## A function leaf was double-clicked — the host should open a query for
## model.method (without auto-running it). `collection` is the Mongo collection the
## model reads, so the query's results can be typed against the database schema;
## `signature` is the method's declared parameter list, shown in the query tab.
signal function_activated(model: String, method: String, collection: String, signature: String)
## Asks the host to (re)inject the Server Models bridge into the workspace's server.
signal refresh_requested()
## Asks the host to open the workspace editor (to set the server URL / repo path).
signal edit_requested()
## A model was expanded for the first time — the host should load its methods and
## return them via set_model_functions().
signal functions_requested(model: String)

const DESC_NEEDS_CONFIG := (
	"This workspace has no Rocket.Chat repository configured. Edit the workspace and "
	+ "set its Rocket.Chat Repository path — where the server is checked out — to use "
	+ "Server Models."
)
## Same folder icon the Database panel uses for its collection groups.
const ICON_MODEL := preload("res://source/ui/icons/group.svg")
const ICON_FUNCTION := preload("res://source/ui/icons/function.svg")
const ICON_REFRESH := preload("res://source/ui/icons/refresh.svg")
const ICON_SIZE := 16
## Cell-button id for a model row's "reload functions" button.
const BTN_RELOAD := 0

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _edit_btn: Button = %EditBtn
@onready var _refresh_btn: Button = %RefreshBtn
@onready var _filter: FilterField = %Filter
@onready var _tree: Tree = %Tree
@onready var _msg_wrap: MarginContainer = %MsgWrap
@onready var _desc: Label = %Desc

## Whether the workspace has a repository path; drives message-vs-tree and buttons.
var _configured := true
## Model names to list (sorted by the server); rendered as folder items.
var _models: Array = []
## model -> its loaded methods ({ name, signature } dicts). Kept outside the tree so
## a rebuild (a filter change) restores what was already fetched instead of dropping
## every expanded model back to unloaded.
var _functions: Dictionary = {}
## Models with a fetch in flight, so a rebuild keeps showing their "(loading…)" row.
var _pending: Dictionary = {}
## model -> true while its folder is open, so a rebuild leaves it as the user had it.
var _expanded: Dictionary = {}
## Terms from the header's filter box (see FilterField). Empty = show every model.
var _filter_terms := PackedStringArray()
## True while _populate_tree builds, so the collapse signals it fires aren't taken
## for the user folding a model.
var _populating := false


func _ready() -> void:
	_apply_style()
	_refresh_btn.pressed.connect(func() -> void: refresh_requested.emit())
	_edit_btn.pressed.connect(func() -> void: edit_requested.emit())
	_filter.filter_changed.connect(set_filter)
	_tree.item_activated.connect(_on_item_activated)
	_tree.button_clicked.connect(_on_tree_button_clicked)
	_tree.item_collapsed.connect(_on_item_collapsed)
	_render()


## Set whether the workspace has a Rocket.Chat repository path configured. Safe to
## call before the node is in the tree; applied on _ready.
func set_configured(configured: bool) -> void:
	_configured = configured
	if is_node_ready():
		_render()


## Set the models to list (from the install response), each a dictionary of
## { name, collection }. Safe before _ready.
func set_models(models: Array) -> void:
	_models = models
	# A new list means the bridge was (re)installed, so anything cached about the
	# previous one is stale.
	_functions.clear()
	_pending.clear()
	_expanded.clear()
	if is_node_ready():
		_render()


## Show only the models matching `text` — wired to the header's filter box, which
## debounces typing. Functions already loaded are matched too (as "model.method"),
## so a model surfaces by any of its methods and then lists just the matching ones.
## Nothing is refetched, and the filter sticks across expands and reloads.
func set_filter(text: String) -> void:
	_filter_terms = FilterField.terms_of(text)
	if is_node_ready():
		_render()


func _render() -> void:
	_msg_wrap.visible = not _configured
	_tree.visible = _configured
	# Refresh reinjects the bridge; pointless without a repository to inject from.
	_refresh_btn.disabled = not _configured
	if not _configured:
		_desc.text = DESC_NEEDS_CONFIG
		return
	_populate_tree()


## Build the model tree: one folder-icon item per model, like the collection tree.
## Each row is restored from what's already known about it (in flight, loaded, open),
## so rebuilding for a filter change costs nothing the user has to redo.
func _populate_tree() -> void:
	_populating = true
	_tree.clear()
	var root := _tree.create_item()
	if _models.is_empty():
		_add_placeholder(root, "(no models — Refresh)")
		_populating = false
		return
	var shown := 0
	for entry in _models:
		var model := _model_name(entry)
		if model.is_empty() or not _is_listed(model):
			continue
		shown += 1
		_add_model_item(root, model, _model_collection(entry))
	if shown == 0:
		_add_placeholder(root, "(no matching models)")
	_populating = false


## One model row, put back into the state it was in: its "(loading…)" row, or its
## loaded functions, and the folder open/closed as the user left it. A filtered view
## opens matching models so their hits show without unfolding by hand.
func _add_model_item(root: TreeItem, model: String, collection: String) -> void:
	var item := _tree.create_item(root)
	item.set_text(0, model)
	item.set_icon(0, ICON_MODEL)
	item.set_icon_max_width(0, ICON_SIZE)
	item.set_icon_modulate(0, AppTheme.TEXT_DIM)
	if not collection.is_empty():
		item.set_tooltip_text(0, collection)
	# state: idle -> loading -> loaded, so a model's methods load once on expand.
	var state := "idle"
	if _pending.has(model):
		state = "loading"
	elif _functions.has(model):
		state = "loaded"
	item.set_metadata(0, {
		"type": "model", "model": model, "collection": collection, "state": state,
	})
	match state:
		"loading":
			_add_loading_row(item)
			item.set_collapsed(false)
		"loaded":
			_fill_functions(item, model, collection, _listed_methods(model))
			var open: bool = _expanded.get(model, false) or not _filter_terms.is_empty()
			item.set_collapsed(not open)
		_:
			item.set_collapsed(true)


## The model names currently listed — every model, less those the filter excludes.
func listed_models() -> Array:
	var out: Array = []
	for entry in _models:
		var model := _model_name(entry)
		if not model.is_empty() and _is_listed(model):
			out.append(model)
	return out


## The function names currently listed under `model`. Empty until its functions are
## loaded, or when the filter leaves none of them.
func listed_functions(model: String) -> Array:
	var out: Array = []
	for entry in _listed_methods(model):
		out.append(_method_name(entry))
	return out


## Whether `model` survives the filter: by its own name, or by one of the functions
## already loaded under it.
func _is_listed(model: String) -> bool:
	return FilterField.matches(model, _filter_terms) or not _listed_methods(model).is_empty()


## The loaded method entries of `model` to list: all of them when the model's own
## name matches the filter (or there is none), otherwise only the matching ones.
func _listed_methods(model: String) -> Array:
	var methods: Array = _functions.get(model, [])
	if FilterField.matches(model, _filter_terms):
		return methods
	var out: Array = []
	for entry in methods:
		if FilterField.matches("%s.%s" % [model, _method_name(entry)], _filter_terms):
			out.append(entry)
	return out


## A model list entry's name and Mongo collection. Entries are { name, collection };
## a bare model name is tolerated.
static func _model_name(entry: Variant) -> String:
	if entry is Dictionary:
		return String((entry as Dictionary).get("name", ""))
	return String(entry)


static func _model_collection(entry: Variant) -> String:
	if entry is Dictionary:
		return String((entry as Dictionary).get("collection", ""))
	return ""


## A method entry's name. Entries are { name, signature }; a bare name is tolerated.
static func _method_name(entry: Variant) -> String:
	if entry is Dictionary:
		return String((entry as Dictionary).get("name", ""))
	return String(entry)


## Remember whether a model's folder is open, so the next rebuild restores it.
func _on_item_collapsed(item: TreeItem) -> void:
	if _populating:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary and (meta as Dictionary).get("type") == "model":
		_expanded[String((meta as Dictionary).get("model", ""))] = not item.is_collapsed()


## Double-click / Enter on a tree item. Expanding a model the first time asks the
## host to load its functions; afterwards it just toggles the folder.
func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	var d := meta as Dictionary
	match String(d.get("type", "")):
		"function":
			# Open a query for this model.method (the host doesn't auto-run it).
			function_activated.emit(
				String(d.get("model", "")),
				String(d.get("function", "")),
				String(d.get("collection", "")),
				String(d.get("signature", "")),
			)
		"model":
			_activate_model(item, d)


## Expanding a model the first time asks the host to load its functions; afterwards
## it just toggles the folder.
func _activate_model(item: TreeItem, d: Dictionary) -> void:
	match String(d.get("state", "idle")):
		"loaded":
			item.set_collapsed(not item.is_collapsed())
		"loading":
			pass  # a request is already in flight
		_:
			_load_functions(item, d)


## A model row's cell button was clicked (the reload button): drop its functions and
## fetch them again from the server.
func _on_tree_button_clicked(item: TreeItem, _column: int, id: int, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT or id != BTN_RELOAD:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary and (meta as Dictionary).get("type") == "model":
		_load_functions(item, meta as Dictionary)


## Put a model into the loading state (placeholder child) and ask the host for its
## methods. Used on first expand and on reload.
func _load_functions(item: TreeItem, d: Dictionary) -> void:
	var model := String(d.get("model", ""))
	d["state"] = "loading"
	item.set_metadata(0, d)
	_pending[model] = true
	_functions.erase(model)  # a reload drops the list it replaces
	_expanded[model] = true
	_clear_children(item)
	_add_loading_row(item)
	item.set_collapsed(false)
	functions_requested.emit(model)


## Fill a model's methods in as child leaves (called by the host after fetching).
## `methods` are { name, signature } dictionaries. They're cached, so a later rebuild
## doesn't have to ask for them again.
func set_model_functions(model: String, methods: Array) -> void:
	_functions[model] = methods
	_pending.erase(model)
	_expanded[model] = true
	# Under a filter these methods can decide whether the model is listed at all, so
	# rebuild the tree rather than patching the row.
	if not _filter_terms.is_empty():
		_populate_tree()
		return
	var item := _find_model_item(model)
	if item == null:
		return
	var d: Dictionary = item.get_metadata(0)
	d["state"] = "loaded"
	item.set_metadata(0, d)
	_fill_functions(item, model, String(d.get("collection", "")), methods)
	item.set_collapsed(false)


## Replace a model row's children with one leaf per method, and give it the reload
## button (added once — it isn't a child, so _clear_children leaves it in place).
func _fill_functions(item: TreeItem, model: String, collection: String, methods: Array) -> void:
	_clear_children(item)
	if item.get_button_count(0) == 0:
		item.add_button(0, ICON_REFRESH, BTN_RELOAD, false, "Reload functions")
		item.set_button_color(0, 0, AppTheme.TEXT_DIM)
	if methods.is_empty():
		# With a filter on, an empty list means its functions were filtered out —
		# the model itself is only listed because its name matched.
		_add_placeholder(item, "(no functions)" if _filter_terms.is_empty() else "(no matching functions)")
		return
	for entry in methods:
		var fn := _method_name(entry)
		if fn.is_empty():
			continue
		var signature := ""
		if entry is Dictionary:
			signature = String((entry as Dictionary).get("signature", ""))
		var leaf := _tree.create_item(item)
		leaf.set_text(0, fn)
		leaf.set_icon(0, ICON_FUNCTION)
		leaf.set_icon_max_width(0, ICON_SIZE)
		leaf.set_icon_modulate(0, AppTheme.TEXT_DIM)
		if not signature.is_empty():
			leaf.set_tooltip_text(0, fn + signature)
		leaf.set_metadata(0, {
			"type": "function", "model": model, "function": fn,
			"collection": collection, "signature": signature,
		})


## The top-level tree item for `model`, or null.
func _find_model_item(model: String) -> TreeItem:
	var root := _tree.get_root()
	if root == null:
		return null
	var c := root.get_first_child()
	while c != null:
		var meta: Variant = c.get_metadata(0)
		if meta is Dictionary and (meta as Dictionary).get("type") == "model" and (meta as Dictionary).get("model") == model:
			return c
		c = c.get_next()
	return null


func _add_loading_row(item: TreeItem) -> void:
	_add_placeholder(item, "(loading…)")


## A greyed, unselectable child row standing in for a list (empty, loading, or
## filtered away).
func _add_placeholder(parent: TreeItem, text: String) -> void:
	var ph := _tree.create_item(parent)
	ph.set_text(0, text)
	ph.set_custom_color(0, AppTheme.TEXT_DIM)
	ph.set_selectable(0, false)


func _clear_children(item: TreeItem) -> void:
	var c := item.get_first_child()
	while c != null:
		var nxt := c.get_next()
		# remove_child detaches without freeing, so free the item to avoid leaking it.
		item.remove_child(c)
		c.free()
		c = nxt


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", sb)
	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_title.add_theme_font_size_override("font_size", 11)
	_desc.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
