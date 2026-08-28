class_name RcModelsSidebar
extends PanelContainer

## The Models sidebar view of a project's Rocket.Chat workspace: a tree of the
## server's @rocket.chat/models models, listed like the Database panel's collections
## (folder icon per model; functions will hang under them later). The model list is
## supplied by the host after the bridge is installed (set_models). "New Model Query"
## opens a blank console tab. When the workspace has no Meteor directory the bridge
## can't be reached, so a message replaces the tree until one is set.

## Asks the host to open a new models console tab.
signal new_query_requested()
## Asks the host to (re)install the Server Models bridge into the workspace's server.
signal refresh_requested()
## Asks the host to open the workspace editor (to set/change the server URL + meteor dir).
signal edit_requested()

const DESC_NEEDS_CONFIG := (
	"This workspace has no Meteor directory configured. Edit the workspace and set its "
	+ "Meteor dir — the local …/apps/meteor path — to use Server Models."
)
## Same folder icon the Database panel uses for its collection groups.
const ICON_MODEL := preload("res://source/ui/icons/group.svg")
const ICON_SIZE := 16

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _edit_btn: Button = %EditBtn
@onready var _refresh_btn: Button = %RefreshBtn
@onready var _tree: Tree = %Tree
@onready var _msg_wrap: MarginContainer = %MsgWrap
@onready var _desc: Label = %Desc
@onready var _new_btn: Button = %NewBtn

## Whether the workspace has a meteor dir; drives the message vs tree and buttons.
var _configured := true
## Model names to list (sorted by the server); rendered as folder items.
var _models: Array = []


func _ready() -> void:
	_apply_style()
	_new_btn.pressed.connect(func() -> void: new_query_requested.emit())
	_refresh_btn.pressed.connect(func() -> void: refresh_requested.emit())
	_edit_btn.pressed.connect(func() -> void: edit_requested.emit())
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
	_new_btn.disabled = not _configured
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
		item.set_metadata(0, {"type": "model", "model": String(name)})


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
