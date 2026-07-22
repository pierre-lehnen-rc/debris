class_name ActivityLogTab
extends VBoxContainer

## A read-only view of the app's action history. Every MongoDB and Rocket.Chat
## call is recorded in the ActivityLog autoload; this tab renders those entries
## through the same ResultsView the query tabs use (newest first), so the user
## reviews logs exactly like they review query results. It refreshes live as new
## actions run, and offers Clear to empty the log.
## Layout lives in activity_log_tab.tscn.

signal status_changed(text: String)

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _title: Label = %Title
@onready var _results: ResultsView = %Results


func _ready() -> void:
	_apply_style()
	# The log isn't paginated Mongo data; it's a flat, bounded list.
	_results.set_pagination_enabled(false)
	_results.set_item_noun("entry")
	# Show each entry's source/action/target and result/error at the top level.
	_results.set_log_mode(true)
	ActivityLog.entry_added.connect(_on_entry_added)
	_refresh()


func tab_title() -> String:
	return "Activity Log"


## Exposes the results view so callers can drive its view mode if needed.
func results() -> ResultsView:
	return _results


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", sb)
	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Reload the whole page from the log, newest first.
func _refresh() -> void:
	var entries := ActivityLog.entries()
	entries.reverse()
	_results.show_page(entries)
	status_changed.emit("Activity log — %d entr%s" % [
		entries.size(), "y" if entries.size() == 1 else "ies",
	])


# Wired in activity_log_tab.tscn ----------------------------------------------
func _on_refresh_pressed() -> void:
	_refresh()


func _on_clear_pressed() -> void:
	ActivityLog.clear()
	_refresh()


## A new action was logged while this tab is open — re-render so it appears
## without the user having to refresh by hand.
func _on_entry_added(_entry: Dictionary) -> void:
	_refresh()
