class_name ErrorDialog
extends Window

## A small popup surfaced when a logged action fails. It shows the failing
## action and its error message, and offers two choices: dismiss it, or jump to
## the Activity Log for the full history. It never opens the log on its own —
## that's the user's call. Layout lives in error_dialog.tscn.

signal open_log_requested()

@onready var _heading: Label = %Heading
@onready var _message: Label = %Message


func _ready() -> void:
	_apply_style()


func _apply_style() -> void:
	_heading.add_theme_color_override("font_color", AppTheme.ERROR)
	_message.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)


## Populate from a failed ActivityLog entry and show the popup.
func show_error(entry: Dictionary) -> void:
	var source: String = str(entry.get("source", ""))
	var action: String = str(entry.get("action", ""))
	var target: String = str(entry.get("target", ""))
	var heading := action if source.is_empty() else "%s · %s" % [source, action]
	if not target.is_empty():
		heading += " · %s" % target
	_heading.text = heading if not heading.strip_edges().is_empty() else "Action failed"

	var error: String = str(entry.get("error", ""))
	_message.text = error if not error.is_empty() else "The action failed without an error message."

	popup_centered(Vector2i(440, 200))


# Wired in error_dialog.tscn ---------------------------------------------------
func _on_open_log() -> void:
	hide()
	open_log_requested.emit()
