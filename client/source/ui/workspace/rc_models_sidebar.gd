class_name RcModelsSidebar
extends PanelContainer

## The Models sidebar view of a project's Rocket.Chat workspace. A launcher for the
## server-models console: "New Model Query" opens an RcModelsTab in the shared
## center. When the workspace has no Meteor directory configured the console can't
## reach the bridge, so this shows a message and disables the button until one is
## set (in the workspace settings). Kept deliberately small for now — this is where
## a browsable model/method catalog (from @rocket.chat/model-typings) would later live.

## Asks the host to open a new models console tab.
signal new_query_requested()
## Asks the host to (re)install the Server Models bridge into the workspace's server.
signal refresh_requested()
## Asks the host to open the workspace editor (to set/change the server URL + meteor dir).
signal edit_requested()

const DESC_READY := (
	"Call @rocket.chat/models methods on the running Rocket.Chat server and view the results."
)
const DESC_NEEDS_CONFIG := (
	"This workspace has no Meteor directory configured. Edit the workspace and set its "
	+ "Meteor dir — the local …/apps/meteor path — to use Server Models."
)

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _edit_btn: Button = %EditBtn
@onready var _refresh_btn: Button = %RefreshBtn
@onready var _desc: Label = %Desc
@onready var _new_btn: Button = %NewBtn

## Whether the workspace has a meteor dir; drives the message and button state.
var _configured := true


func _ready() -> void:
	_apply_style()
	_new_btn.pressed.connect(func() -> void: new_query_requested.emit())
	_refresh_btn.pressed.connect(func() -> void: refresh_requested.emit())
	_edit_btn.pressed.connect(func() -> void: edit_requested.emit())
	_render()


## Set whether the workspace has a Meteor directory configured. Safe to call before
## the node is in the tree; the state is applied on _ready.
func set_configured(configured: bool) -> void:
	_configured = configured
	if is_node_ready():
		_render()


func _render() -> void:
	_desc.text = DESC_READY if _configured else DESC_NEEDS_CONFIG
	_new_btn.disabled = not _configured
	_new_btn.tooltip_text = "" if _configured else "Set a Meteor directory in the workspace settings first"
	# Refresh reinstalls the bridge; pointless without a meteor dir to install from.
	_refresh_btn.disabled = not _configured


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
