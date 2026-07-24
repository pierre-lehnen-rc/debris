class_name EndpointSidebar
extends PanelContainer

## Per-workspace sidebar: lists the workspace's REST endpoints grouped by tag
## (Channels, Users, …). Endpoints are read live from the server's OpenAPI
## document (/api/docs/json); if that can't be fetched, it falls back to the
## curated ApiCatalog. Double-clicking an endpoint opens it in a tab;
## right-clicking offers quick actions. Mirrors the Mongo CollectionSidebar.

signal endpoint_activated(endpoint: ApiEndpoint)
signal status_changed(text: String)
## The header's edit button was pressed — the host should open the API/workspace
## editor for this workspace.
signal edit_requested()

const META_TYPE := "type"  # "endpoint" | "group" | "placeholder"
const META_ENDPOINT := "endpoint"
const ICON_GROUP := preload("res://source/ui/icons/group.svg")
const ICON_ENDPOINT := preload("res://source/ui/icons/collection.svg")
const ICON_SIZE := 16
# Many servers expose hundreds of endpoints, so start groups folded.
const COLLAPSE_GROUPS := true

enum Action { OPEN, COPY_PATH }

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _tree: Tree = %Tree
@onready var _context_menu: PopupMenu = %ContextMenu

var _workspace: Dictionary = {}
var _endpoints: Array = []
var _menu_target: ApiEndpoint = null
var _loading := false


func _ready() -> void:
	_apply_style()
	_render_message("(no workspace)")


## Point this sidebar at a workspace and load its endpoint catalog from the
## server's OpenAPI document.
func configure(workspace: Dictionary) -> void:
	_workspace = workspace
	if is_node_ready():
		_load()


func _on_edit_pressed() -> void:
	edit_requested.emit()


# Loading ---------------------------------------------------------------------
## Fetch and parse the workspace's OpenAPI spec, falling back to the curated
## catalog if the server can't be reached or returns something unusable.
func _load() -> void:
	if _loading or _workspace.is_empty():
		return
	_loading = true
	status_changed.emit("Loading endpoints from %s…" % _workspace.get("url", ""))
	_render_message("(loading…)")

	var result: Dictionary = await RocketChat.fetch_openapi(_workspace)
	_loading = false

	if result.get("ok", false) and result.get("data") is Dictionary:
		_endpoints = OpenApiParser.parse(result["data"])
		_endpoints.sort_custom(_compare_endpoints)
		if _endpoints.is_empty():
			_render_message("(no endpoints in spec)")
			status_changed.emit("OpenAPI spec contained no endpoints")
			return
		_render()
		status_changed.emit("Loaded %d endpoints from %s" % [
			_endpoints.size(), _workspace.get("url", ""),
		])
		return

	# Couldn't load the live spec — fall back to the shipped catalog.
	_endpoints = ApiCatalog.builtin()
	_endpoints.sort_custom(_compare_endpoints)
	_render()
	status_changed.emit("Couldn't load endpoints (%s) — showing built-in catalog" % result.get(
		"error", "unknown error",
	))


## Sort by full path segments, then method, so the nested folders and their
## leaves read alphabetically.
static func _compare_endpoints(a: ApiEndpoint, b: ApiEndpoint) -> bool:
	var ka := "/".join(a.segments())
	var kb := "/".join(b.segments())
	if ka == kb:
		return a.method.naturalnocasecmp_to(b.method) < 0
	return ka.naturalnocasecmp_to(kb) < 0


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_title.add_theme_font_size_override("font_size", 11)


# Rendering -------------------------------------------------------------------
## Build a nested endpoint tree from each endpoint's path segments, so siblings
## sharing a prefix (all "livechat/…", all "channels.*", …) fold under shared
## folders. The endpoints are pre-sorted, so folders and leaves read in order.
func _render() -> void:
	_tree.clear()
	var root := _tree.create_item()
	if _endpoints.is_empty():
		_add_placeholder(root, "(no endpoints)")
		return
	for endpoint in _endpoints:
		var ep := endpoint as ApiEndpoint
		var segs := ep.segments()
		var parent := root
		for i in segs.size() - 1:
			parent = _get_or_create_group(parent, segs[i])
		var leaf_label: String = segs[segs.size() - 1] if segs.size() > 0 else ep.label()
		_make_leaf(parent, ep, leaf_label)


## Return the child folder of `parent` with the given label, creating it if it
## doesn't exist yet, so endpoints sharing a path prefix reuse the same folders.
func _get_or_create_group(parent: TreeItem, label: String) -> TreeItem:
	for child in parent.get_children():
		var meta: Dictionary = child.get_metadata(0)
		if meta.get(META_TYPE) == "group" and child.get_text(0) == label:
			return child
	return _make_group(parent, label)


func _make_group(parent: TreeItem, label: String) -> TreeItem:
	var group := _tree.create_item(parent)
	group.set_text(0, label)
	group.set_custom_color(0, AppTheme.TEXT)
	group.set_icon(0, ICON_GROUP)
	group.set_icon_max_width(0, ICON_SIZE)
	group.set_icon_modulate(0, AppTheme.TEXT_DIM)
	group.set_collapsed(COLLAPSE_GROUPS)
	group.set_metadata(0, {META_TYPE: "group"})
	return group


func _make_leaf(parent: TreeItem, endpoint: ApiEndpoint, label: String) -> void:
	var leaf := _tree.create_item(parent)
	# The HTTP method leads the label so GET/POST on the same path stay distinct.
	leaf.set_text(0, "%s  %s" % [endpoint.method, label])
	leaf.set_custom_color(0, _method_color(endpoint.method))
	leaf.set_icon(0, ICON_ENDPOINT)
	leaf.set_icon_max_width(0, ICON_SIZE)
	leaf.set_icon_modulate(0, AppTheme.TEXT_DIM)
	var tip := "%s %s" % [endpoint.method, endpoint.path]
	if not endpoint.summary.is_empty():
		tip += "\n" + endpoint.summary
	leaf.set_tooltip_text(0, tip)
	leaf.set_metadata(0, {META_TYPE: "endpoint", META_ENDPOINT: endpoint})


## Colour endpoints by verb so reads and writes are distinguishable at a glance.
func _method_color(method: String) -> Color:
	match method:
		"GET":
			return AppTheme.ACCENT_GREEN
		"POST", "PUT", "PATCH":
			return AppTheme.ACCENT
		"DELETE":
			return AppTheme.TEXT_BRIGHT
		_:
			return AppTheme.TEXT_DIM


func _render_message(text: String) -> void:
	_tree.clear()
	var root := _tree.create_item()
	_add_placeholder(root, text)


func _add_placeholder(parent: TreeItem, text: String) -> void:
	var ph := _tree.create_item(parent)
	ph.set_text(0, text)
	ph.set_selectable(0, false)
	ph.set_custom_color(0, AppTheme.TEXT_DIM)
	ph.set_metadata(0, {META_TYPE: "placeholder"})


# Selection / activation ------------------------------------------------------
func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	if meta[META_TYPE] == "endpoint":
		endpoint_activated.emit(meta[META_ENDPOINT])
	else:
		item.set_collapsed(not item.is_collapsed())


# Context menu ----------------------------------------------------------------
func _on_item_mouse_selected(_pos: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty() or meta[META_TYPE] != "endpoint":
		return
	_menu_target = meta[META_ENDPOINT]
	_context_menu.clear()
	_context_menu.add_item("Open Endpoint", Action.OPEN)
	_context_menu.add_separator()
	_context_menu.add_item("Copy path", Action.COPY_PATH)
	_context_menu.reset_size()
	# Native pop-ups position in absolute screen coordinates.
	_context_menu.position = DisplayServer.mouse_get_position()
	_context_menu.popup()


func _on_context_action(id: int) -> void:
	if _menu_target == null:
		return
	match id:
		Action.OPEN:
			endpoint_activated.emit(_menu_target)
		Action.COPY_PATH:
			DisplayServer.clipboard_set(_menu_target.path)
			status_changed.emit("Copied '%s' to clipboard" % _menu_target.path)
