class_name RcModelsSidebar
extends PanelContainer

## The Models sidebar view of a project's Rocket.Chat workspace: a tree of the
## server's @rocket.chat/models models, listed like the Database panel's collections
## (folder icon per model; functions will hang under them later). The model list is
## supplied by the host after the bridge is installed (set_models). "New Model Query"
## opens a blank console tab. When the workspace has no Meteor directory the bridge
## can't be reached, so a message replaces the tree until one is set.

## A function leaf was double-clicked — the host should open a query for
## model.method (without auto-running it).
signal function_activated(model: String, method: String)
## Asks the host to (re)install the Server Models bridge into the workspace's server.
signal refresh_requested()
## Asks the host to open the workspace editor (to set/change the server URL + meteor dir).
signal edit_requested()
## A model was expanded for the first time — the host should load its methods and
## return them via set_model_functions().
signal functions_requested(model: String)

const DESC_NEEDS_CONFIG := (
	"This workspace has no Meteor directory configured. Edit the workspace and set its "
	+ "Meteor dir — the local …/apps/meteor path — to use Server Models."
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
@onready var _tree: Tree = %Tree
@onready var _msg_wrap: MarginContainer = %MsgWrap
@onready var _desc: Label = %Desc

## Whether the workspace has a meteor dir; drives the message vs tree and buttons.
var _configured := true
## Model names to list (sorted by the server); rendered as folder items.
var _models: Array = []


func _ready() -> void:
	_apply_style()
	_refresh_btn.pressed.connect(func() -> void: refresh_requested.emit())
	_edit_btn.pressed.connect(func() -> void: edit_requested.emit())
	_tree.item_activated.connect(_on_item_activated)
	_tree.button_clicked.connect(_on_tree_button_clicked)
	_render()


## Set whether the workspace has a Meteor directory configured. Safe to call before
## the node is in the tree; applied on _ready.
func set_configured(configured: bool) -> void:
	_configured = configured
	if is_node_ready():
		_render()


## Set the model names to list (from the install response). Safe before _ready.
func set_models(names: Array) -> void:
	_models = names
	if is_node_ready():
		_render()


func _render() -> void:
	_msg_wrap.visible = not _configured
	_tree.visible = _configured
	# Refresh reinstalls the bridge; pointless without a meteor dir to install from.
	_refresh_btn.disabled = not _configured
	if not _configured:
		_desc.text = DESC_NEEDS_CONFIG
		return
	_populate_tree()


## Build the model tree: one folder-icon item per model, like the collection tree.
func _populate_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	if _models.is_empty():
		var ph := _tree.create_item(root)
		ph.set_text(0, "(no models — Refresh)")
		ph.set_custom_color(0, AppTheme.TEXT_DIM)
		ph.set_selectable(0, false)
		return
	for name in _models:
		var item := _tree.create_item(root)
		item.set_text(0, String(name))
		item.set_icon(0, ICON_MODEL)
		item.set_icon_max_width(0, ICON_SIZE)
		item.set_icon_modulate(0, AppTheme.TEXT_DIM)
		# state: idle -> loading -> loaded, so a model's methods load once on expand.
		item.set_metadata(0, {"type": "model", "model": String(name), "state": "idle"})


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
			function_activated.emit(String(d.get("model", "")), String(d.get("function", "")))
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
	d["state"] = "loading"
	item.set_metadata(0, d)
	_clear_children(item)
	var ph := _tree.create_item(item)
	ph.set_text(0, "(loading…)")
	ph.set_custom_color(0, AppTheme.TEXT_DIM)
	ph.set_selectable(0, false)
	item.set_collapsed(false)
	functions_requested.emit(String(d.get("model", "")))


## Fill a model's methods in as child leaves (called by the host after fetching).
func set_model_functions(model: String, methods: Array) -> void:
	var item := _find_model_item(model)
	if item == null:
		return
	var d: Dictionary = item.get_metadata(0)
	d["state"] = "loaded"
	item.set_metadata(0, d)
	_clear_children(item)
	# A per-model reload button on the right of the row, added once (it isn't a child,
	# so _clear_children leaves it in place across reloads).
	if item.get_button_count(0) == 0:
		item.add_button(0, ICON_REFRESH, BTN_RELOAD, false, "Reload functions")
		item.set_button_color(0, 0, AppTheme.TEXT_DIM)
	if methods.is_empty():
		var ph := _tree.create_item(item)
		ph.set_text(0, "(no functions)")
		ph.set_custom_color(0, AppTheme.TEXT_DIM)
		ph.set_selectable(0, false)
		return
	for fn in methods:
		var leaf := _tree.create_item(item)
		leaf.set_text(0, String(fn))
		leaf.set_icon(0, ICON_FUNCTION)
		leaf.set_icon_max_width(0, ICON_SIZE)
		leaf.set_icon_modulate(0, AppTheme.TEXT_DIM)
		leaf.set_metadata(0, {"type": "function", "model": model, "function": String(fn)})
	item.set_collapsed(false)


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
