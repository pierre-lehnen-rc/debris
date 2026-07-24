class_name AboutDialog
extends Window

## A small "About" popup shown from Help ▸ About. The app name and version come
## from ProjectSettings (application/config/name and application/config/version)
## so the version updates automatically with the exported build — bump
## config/version in project.godot before exporting and it shows up here.
## Layout lives in about_dialog.tscn.

@onready var _name: Label = %AppName
@onready var _version: Label = %Version
@onready var _description: Label = %Description


func _ready() -> void:
	_name.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	_version.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_description.add_theme_color_override("font_color", AppTheme.TEXT)

	var app_name := str(ProjectSettings.get_setting("application/config/name", "Debris"))
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	title = "About %s" % app_name
	_name.text = app_name
	_version.text = "Version %s" % version if not version.is_empty() else "Development build"


## Center the popup, scaled to the current UI scale, and show it.
func open() -> void:
	UiScale.popup_centered(self, Vector2i(360, 300))
