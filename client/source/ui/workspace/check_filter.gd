class_name CheckFilter
extends Button

## A reusable multi-select filter: a button opening a PopupPanel with a checkbox per
## item, Select all / none, a configurable row of "special" checkboxes above the list
## (e.g. an auto-display-new catch-all, or a "(other)" toggle), and a Sets section —
## save the current selection as a named set, load one, flag one the default for new
## tabs, or delete one. Used for the Server Logs Names and Columns filters.
##
## Items are dynamic (added as they're discovered); the selection is { key -> bool }
## over the items plus the special keys. `changed` fires on any selection change.

signal changed()

const POPUP_WIDTH := 300
const MAX_LIST_HEIGHT := 220
const STAR_FILLED := "★"
const STAR_EMPTY := "☆"

# Config (via setup): the special items shown above the list ([{key,label,tooltip}]),
# and which special key is the catch-all governing items not explicitly listed.
var _special_items: Array = []
var _special_keys: Dictionary = {}
var _catch_all_key := ""

var _sets: SavedSets = null
var _selection: Dictionary = {}
var _checks: Dictionary = {}  # key -> CheckBox (specials + currently-rendered items)
# The known item keys (excludes specials), as an ordered set. The source of truth for
# what exists; the rendered checkboxes are derived from these + _selection.
var _item_keys: Dictionary = {}
# The fresh-state selection template (see set_default_selection): a key's default
# checked state, with the catch-all's value used for keys it doesn't mention. Empty
# means everything on (the Names filter's behaviour).
var _default_selection: Dictionary = {}
# Optional grouping (see set_grouping): the ordered group titles and a provider that
# returns { title -> [keys] } for the current state. When unset the list is flat (the
# Names filter); when set the list renders as a collapsible tree (the Columns filter),
# re-grouped each time the popup opens so the arrangement tracks what's on screen.
var _group_titles: Array = []
var _group_provider: Callable = Callable()

var _popup: PopupPanel = null
var _names_box: VBoxContainer = null
var _sets_box: VBoxContainer = null
var _new_set_edit: LineEdit = null


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_open)


## Configure and build. `special_items` is [{key,label,tooltip}]; `catch_all_key` is
## the special that governs items not listed (or "" for none). Call once, after add.
func setup(button_text: String, special_items: Array, catch_all_key: String) -> void:
	text = button_text
	_special_items = special_items
	_catch_all_key = catch_all_key
	for s in special_items:
		_special_keys[str(s.get("key", ""))] = true
	_build_popup()


# Host API --------------------------------------------------------------------
func bind_sets(sets: SavedSets) -> void:
	_sets = sets
	if sets != null:
		sets.changed.connect(_rebuild_sets)


## The fresh-state selection template applied when (re)building items and on discovery
## (before any saved set is loaded). Empty (the default) means every item is shown.
func set_default_selection(sel: Dictionary) -> void:
	_default_selection = sel.duplicate()


## Render the item list as a collapsible tree grouped under `titles` (in order), the
## membership supplied by `provider` (a Callable returning { title -> [keys] }) and
## recomputed each time the popup opens. Call once, after setup. Leaving it unset keeps
## the flat list (the Names filter).
func set_grouping(titles: Array, provider: Callable) -> void:
	_group_titles = titles.duplicate()
	_group_provider = provider


## The known item keys (specials excluded) — used by a grouping provider to classify them.
func item_keys() -> Array:
	return _item_keys.keys()


## (Re)build the item list and reset the special checkboxes to the fresh-state default.
func set_items(keys: Array) -> void:
	_item_keys.clear()
	for key in _checks.keys():
		if not _special_keys.has(key):
			_selection.erase(key)
	for s in _special_items:
		var key := str(s.get("key", ""))
		var checked := _default_for(key)
		(_checks[key] as CheckBox).set_pressed_no_signal(checked)
		_selection[key] = checked
	for key in keys:
		var k := str(key)
		_item_keys[k] = true
		_selection[k] = _default_for(k)
	_rebuild_list()


## Add a newly-discovered item: its default if the template names it, else the
## catch-all's current state (so toggling auto-display governs later discoveries).
## Returns true when the item was new (added), false when it already existed.
func add_item(key: String) -> bool:
	if _item_keys.has(key):
		return false
	_item_keys[key] = true
	_selection[key] = bool(_default_selection[key]) if _default_selection.has(key) else _catch_all_on()
	# Flat lists append the one new checkbox in place; grouped lists are rebuilt on open
	# (the grouping tracks what's on screen), so there's nothing to render now.
	if not _is_grouped():
		_names_box.add_child(_make_item_checkbox(key))
	return true


## The fresh-state checked value for `key`: the template's value, or its catch-all for
## keys the template doesn't mention (or true when there's no template).
func _default_for(key: String) -> bool:
	if _default_selection.is_empty():
		return true
	if _default_selection.has(key):
		return bool(_default_selection[key])
	return bool(_default_selection.get(_catch_all_key, true))


## The current selection ({ key -> bool }, specials included).
func selection() -> Dictionary:
	return _selection.duplicate()


## Apply a saved selection: items take their value or follow the catch-all; specials
## take their value or keep current. Emits changed.
func apply_selection(sel: Dictionary) -> void:
	var default_on := bool(sel.get(_catch_all_key, true)) if not _catch_all_key.is_empty() else true
	for key in _special_keys:
		var on := bool(sel.get(key, _selection.get(key, true)))
		_selection[key] = on
		if _checks.has(key):
			(_checks[key] as CheckBox).set_pressed_no_signal(on)
	for key in _item_keys:
		var item_on := bool(sel.get(key, default_on))
		_selection[key] = item_on
		if _checks.has(key):
			(_checks[key] as CheckBox).set_pressed_no_signal(item_on)
	changed.emit()


## Whether an item `key` is on: its own switch if listed, else the catch-all.
func allows(key: String) -> bool:
	if _selection.has(key):
		return bool(_selection[key])
	return _catch_all_on()


## The raw value of a key (e.g. a special like "(other)"); false when absent.
func value(key: String) -> bool:
	return bool(_selection.get(key, false))


func _catch_all_on() -> bool:
	if _catch_all_key.is_empty():
		return true
	return bool(_selection.get(_catch_all_key, true))


# Item list -------------------------------------------------------------------
func _is_grouped() -> bool:
	return not _group_titles.is_empty() and _group_provider.is_valid()


## Rebuild the item checkboxes from _item_keys + _selection: grouped into a collapsible
## tree when a grouping is set, otherwise a flat list.
func _rebuild_list() -> void:
	if _is_grouped():
		_rebuild_grouped()
	else:
		_rebuild_flat()


func _rebuild_flat() -> void:
	_clear_item_widgets()
	for key in _item_keys:
		_names_box.add_child(_make_item_checkbox(str(key)))


## Grouped rendering: one collapsible header per group title, its items indented below.
## Membership comes from the provider; the checkbox state stays driven by _selection, so
## regrouping never disturbs what's ticked.
func _rebuild_grouped() -> void:
	_clear_item_widgets()
	var groups: Dictionary = _group_provider.call() if _group_provider.is_valid() else {}
	for title in _group_titles:
		var keys: Array = groups.get(title, []) if groups.get(title) is Array else []
		var body := VBoxContainer.new()
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", 16)
		indent.add_child(body)
		_names_box.add_child(_group_header(str(title), keys.size(), indent))
		_names_box.add_child(indent)
		for key in keys:
			body.add_child(_make_item_checkbox(str(key)))
		if keys.is_empty():
			var empty := Label.new()
			empty.text = "—"
			empty.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
			body.add_child(empty)


## A collapsible group header: a flat toggle button that folds/unfolds its `body`.
func _group_header(title: String, count: int, body: Control) -> Button:
	var header := Button.new()
	header.toggle_mode = true
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "▾ %s (%d)" % [title, count]
	header.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	header.toggled.connect(func(collapsed: bool) -> void:
		body.visible = not collapsed
		header.text = "%s %s (%d)" % ["▸" if collapsed else "▾", title, count]
	)
	return header


## Build an item checkbox bound to `key`, reflecting its current selection, and register
## it as the key's live widget.
func _make_item_checkbox(key: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = key
	check.focus_mode = Control.FOCUS_NONE
	check.set_pressed_no_signal(bool(_selection.get(key, _default_for(key))))
	check.toggled.connect(_on_check_toggled.bind(key))
	_checks[key] = check
	return check


## Free the rendered item widgets (headers, indents, checkboxes) and drop the item
## entries from the live-widget map — the specials, rendered separately above the list,
## are left untouched.
func _clear_item_widgets() -> void:
	for child in _names_box.get_children():
		child.queue_free()
	for key in _checks.keys():
		if not _special_keys.has(key):
			_checks.erase(key)


func _on_check_toggled(pressed: bool, key: String) -> void:
	_selection[key] = pressed
	changed.emit()


## Select all / none applies to the listed items only — the special toggles are a
## separate concern and are left as the user set them.
func _set_all(on: bool) -> void:
	for key in _item_keys:
		_selection[key] = on
		if _checks.has(key):
			(_checks[key] as CheckBox).set_pressed_no_signal(on)
	changed.emit()


# Sets ------------------------------------------------------------------------
func _rebuild_sets() -> void:
	if _sets_box == null:
		return
	for child in _sets_box.get_children():
		child.queue_free()
	var sets: Array = _sets.list() if _sets != null else []
	if sets.is_empty():
		var empty := Label.new()
		empty.text = "No saved sets."
		empty.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		_sets_box.add_child(empty)
		return
	for s in sets:
		if s is Dictionary:
			_sets_box.add_child(_set_row(s as Dictionary))


func _set_row(s: Dictionary) -> Control:
	var set_name := str(s.get("name", ""))
	var row := HBoxContainer.new()

	var load_btn := Button.new()
	load_btn.text = set_name
	load_btn.tooltip_text = "Load this set"
	load_btn.focus_mode = Control.FOCUS_NONE
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	load_btn.pressed.connect(func() -> void: apply_selection(_sets.selection_of(set_name)))
	row.add_child(load_btn)

	var is_default := bool(s.get("default", false))
	var default_btn := Button.new()
	default_btn.text = STAR_FILLED if is_default else STAR_EMPTY
	default_btn.tooltip_text = "Default set for new log tabs"
	default_btn.focus_mode = Control.FOCUS_NONE
	if is_default:
		default_btn.add_theme_color_override("font_color", AppTheme.ACCENT)
	default_btn.pressed.connect(func() -> void: _sets.set_default(set_name, not is_default))
	row.add_child(default_btn)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.tooltip_text = "Delete this set"
	del_btn.focus_mode = Control.FOCUS_NONE
	del_btn.pressed.connect(func() -> void: _sets.remove(set_name))
	row.add_child(del_btn)
	return row


func _on_save_pressed() -> void:
	if _sets == null:
		return
	var name := _new_set_edit.text.strip_edges()
	if name.is_empty():
		return
	_sets.save(name, selection())
	_new_set_edit.clear()


# Popup -----------------------------------------------------------------------
func _build_popup() -> void:
	_popup = PopupPanel.new()
	# Subwindows are native windows here (embed off), so the app theme doesn't cascade
	# across the boundary — set it explicitly, like QueryHistoryPopup / DatePicker.
	_popup.theme = AppTheme.shared()
	var sb := AppTheme._flat(AppTheme.BG_PANEL, 6, 1, AppTheme.BORDER)
	sb.set_content_margin_all(6)
	_popup.add_theme_stylebox_override("panel", sb)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(POPUP_WIDTH, 0)
	column.add_theme_constant_override("separation", 6)
	_popup.add_child(column)

	# Special checkboxes above the list, so they read as distinct from the items.
	for s in _special_items:
		var key := str(s.get("key", ""))
		var checked := bool(s.get("checked", true))
		var check := CheckBox.new()
		check.text = str(s.get("label", key))
		check.tooltip_text = str(s.get("tooltip", ""))
		check.focus_mode = Control.FOCUS_NONE
		check.set_pressed_no_signal(checked)
		check.toggled.connect(_on_check_toggled.bind(key))
		column.add_child(check)
		_checks[key] = check
		_selection[key] = checked
	if not _special_items.is_empty():
		column.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	var all_btn := Button.new()
	all_btn.text = "Select all"
	all_btn.focus_mode = Control.FOCUS_NONE
	all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_btn.pressed.connect(_set_all.bind(true))
	actions.add_child(all_btn)
	var none_btn := Button.new()
	none_btn.text = "Select none"
	none_btn.focus_mode = Control.FOCUS_NONE
	none_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	none_btn.pressed.connect(_set_all.bind(false))
	actions.add_child(none_btn)
	column.add_child(actions)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(POPUP_WIDTH, MAX_LIST_HEIGHT)
	_names_box = VBoxContainer.new()
	_names_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_names_box)
	column.add_child(scroll)

	column.add_child(HSeparator.new())

	var sets_title := Label.new()
	sets_title.text = "Sets"
	sets_title.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	column.add_child(sets_title)

	_sets_box = VBoxContainer.new()
	_sets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_sets_box)

	var save_row := HBoxContainer.new()
	_new_set_edit = LineEdit.new()
	_new_set_edit.placeholder_text = "Save selection as…"
	_new_set_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_set_edit.text_submitted.connect(func(_t: String) -> void: _on_save_pressed())
	save_row.add_child(_new_set_edit)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(save_btn)
	column.add_child(save_row)

	add_child(_popup)


func _open() -> void:
	_popup_at(Vector2i(get_screen_position() + Vector2(0, size.y)))


## Open the popup at an arbitrary absolute screen position — used when the filter has no
## button of its own (the Columns filter, opened from a Table column-title right-click).
func open_at(screen_position: Vector2) -> void:
	_popup_at(Vector2i(screen_position))


func _popup_at(pos: Vector2i) -> void:
	if _popup == null:
		return
	_rebuild_sets()
	# The grouped list tracks what's currently on screen, so re-group each time it opens.
	if _is_grouped():
		_rebuild_grouped()
	var scale := UiScale.current(self)
	_popup.content_scale_factor = scale
	_popup.reset_size()
	if scale != 1.0:
		_popup.size = Vector2i(Vector2(_popup.size) * scale)
	_popup.position = pos
	_popup.popup()
