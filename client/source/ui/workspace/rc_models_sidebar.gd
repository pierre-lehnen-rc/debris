class_name RcModelsSidebar
extends PanelContainer

## The Models sidebar view of a project's Rocket.Chat API. A launcher for the
## server-models console: "New Model Query" opens an RcModelsTab in the shared
## center. Kept deliberately small for now — this is where a browsable model/method
## catalog (from @rocket.chat/model-typings) would later live.

## Asks the host to open a new models console tab.
signal new_query_requested()

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _desc: Label = %Desc
@onready var _new_btn: Button = %NewBtn


func _ready() -> void:
	_apply_style()
	_new_btn.pressed.connect(func() -> void: new_query_requested.emit())


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
