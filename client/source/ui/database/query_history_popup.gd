class_name QueryHistoryPopup
extends PopupPanel

## The dropdown a QueryTab's history button opens: the current collection's favorite
## queries (kept in the project file) above its recent queries (kept in the sidecar).
## Each row applies its saved operation/filter/options to the editors when clicked; a
## star toggles the query's favorite flag in place, and recents carry an ✕ to forget
## them. Reads and mutates through the shared QueryHistory; the tab only reacts to
## apply_requested. Rebuilt each time it opens so it reflects the latest history.

## The user picked a saved query to load into the editors (fill only; never runs).
signal apply_requested(entry: Dictionary)

const WIDTH := 460
const MAX_HEIGHT := 460
const STAR_FILLED := "★"
const STAR_EMPTY := "☆"
const FORGET := "✕"

var _history: QueryHistory = null
var _collection := ""
var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	# Subwindows are native OS windows here (embed_subwindows off), so the theme
	# doesn't cascade across the window boundary — set it explicitly, like DatePicker.
	theme = AppTheme.shared()
	var sb := AppTheme._flat(AppTheme.BG_PANEL, 6, 1, AppTheme.BORDER)
	sb.set_content_margin_all(4)
	add_theme_stylebox_override("panel", sb)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(WIDTH, 0)
	_list.add_theme_constant_override("separation", 1)
	_scroll.add_child(_list)


func configure(history: QueryHistory, collection: String) -> void:
	_history = history
	_collection = collection


## Rebuild the list from current history and pop up flush under `anchor`. Positions
## in absolute screen coordinates (native subwindow) and scales to the app's UI
## scale, matching DatePicker. Height is capped at MAX_HEIGHT; overflow scrolls.
func open_under(anchor: Control) -> void:
	_rebuild()
	# A ScrollContainer's own minimum size is tiny, so size the viewport from the
	# inner list's real content height (capped), then let reset_size fit the window.
	var content_h := _list.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(WIDTH, minf(content_h, MAX_HEIGHT))
	var scale := UiScale.current(self)
	content_scale_factor = scale
	reset_size()
	if scale != 1.0:
		size = Vector2i(Vector2(size) * scale)
	position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.size.y))
	popup()


## Repopulate the list from current history (favorites above recents).
func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	var favorites := _history.favorites(_collection) if _history != null else []
	var recents := _history.recents(_collection) if _history != null else []

	if favorites.is_empty() and recents.is_empty():
		_list.add_child(_empty_label())
		return

	if not favorites.is_empty():
		_list.add_child(_section_header("Favorites"))
		for entry in favorites:
			if entry is Dictionary:
				_list.add_child(_query_row(entry, false, -1))
	if not recents.is_empty():
		_list.add_child(_section_header("Recent"))
		var index := 0
		for entry in recents:
			if entry is Dictionary:
				_list.add_child(_query_row(entry, true, index))
			index += 1


func _empty_label() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	var label := Label.new()
	label.text = "No saved queries yet — run a query to build history."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	margin.add_child(label)
	return margin


func _section_header(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	label.add_theme_constant_override("line_spacing", 0)
	return label


## One clickable history row: [ star | preview (applies) | ✕ (recents only) ].
func _query_row(entry: Dictionary, is_recent: bool, recent_index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var starred := _history != null and _history.is_favorite(_collection, entry)
	var star := _flat_button(STAR_FILLED if starred else STAR_EMPTY)
	star.custom_minimum_size = Vector2(26, 0)
	star.tooltip_text = "Remove from favorites" if starred else "Save to favorites (kept in the project file)"
	star.add_theme_color_override("font_color", AppTheme.ACCENT if starred else AppTheme.TEXT_DIM)
	star.pressed.connect(_on_star_pressed.bind(entry))
	row.add_child(star)

	var apply := _flat_button(QueryHistory.preview(entry))
	apply.alignment = HORIZONTAL_ALIGNMENT_LEFT
	apply.clip_text = true
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply.tooltip_text = "Load this query into the editors"
	apply.pressed.connect(_on_apply_pressed.bind(entry))
	row.add_child(apply)

	if is_recent:
		var forget := _flat_button(FORGET)
		forget.custom_minimum_size = Vector2(26, 0)
		forget.tooltip_text = "Forget this recent query"
		forget.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		forget.pressed.connect(_on_forget_pressed.bind(recent_index))
		row.add_child(forget)

	return row


func _flat_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _on_apply_pressed(entry: Dictionary) -> void:
	apply_requested.emit(entry)
	hide()


## Toggle the query's favorite flag and rebuild so its star and section placement
## update without closing the popup.
func _on_star_pressed(entry: Dictionary) -> void:
	if _history == null:
		return
	if _history.is_favorite(_collection, entry):
		_history.remove_favorite(_collection, entry)
	else:
		_history.add_favorite(_collection, entry)
	_rebuild()


func _on_forget_pressed(recent_index: int) -> void:
	if _history != null:
		_history.remove_recent(_collection, recent_index)
		_rebuild()
