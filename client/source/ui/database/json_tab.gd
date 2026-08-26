class_name JsonTab
extends VBoxContainer

## A scratch JSON workspace: the user types or pastes JSON into the editor on top
## and "Show" (or F5) parses it and renders it in the results view below, exactly
## as endpoint responses do — the Tree and Text views over the raw value, with no
## backend involved. Any JSON value is accepted (object, array or scalar); an
## array's element count drives the results count label. A tab can be seeded from a
## file (File ▸ Open JSON…) and written back out (File ▸ Save JSON…).
## Layout lives in json_tab.tscn; configure()/configure_restore() must be called
## before the node enters the tree so _ready() can seed and parse the editor.

signal status_changed(text: String)
## Emitted when the tab's title should change (a file was opened into or saved from
## it), so the workspace center can relabel the tab.
signal title_changed(title: String)
## Emitted when persistable state changes (the JSON was (re)shown, or a file was
## opened/saved), so the project can save the .debris-workspace sidecar.
signal state_changed()
## Bubbled up from the results view when "View JSON in New Tab" is chosen on a
## nested object/array, asking the owner to open a further JSON tab seeded with `text`.
signal open_json_requested(text: String)

## Editor text to seed when the tab first opens (set via configure()/restore).
var _initial_text := ""
## The tab's display title: "JSON" for a scratch tab, or a file's basename once one
## has been opened into or saved from it.
var _title := "JSON"
## Set by configure_restore() to reopen a saved tab from the sidecar; empty on a
## normal open.
var _restore_state: Dictionary = {}

@onready var _toolbar: PanelContainer = %Toolbar
@onready var _show_btn: Button = %ShowBtn
@onready var _title_label: Label = %TitleLabel
@onready var _json_edit: CodeEdit = %JsonEdit
@onready var _results: ResultsView = %Results


## Open a JSON tab, optionally seeded with `text` (e.g. a file's contents) and a
## display `title`. Call before the node enters the tree.
func configure(text := "", title := "JSON") -> void:
	_initial_text = text
	_title = title if not title.is_empty() else "JSON"


## Reopen a saved JSON tab (from the .debris-workspace sidecar): its text and title
## are seeded and parsed by _ready. `state` is a dict from to_state(). Call before
## the node enters the tree.
func configure_restore(state: Dictionary) -> void:
	_restore_state = state
	_initial_text = String(state.get("text", ""))
	_title = String(state.get("title", "JSON"))
	if _title.is_empty():
		_title = "JSON"


## Snapshot this tab for the sidecar: its title and the current editor text. Unlike
## query/endpoint tabs the results are cheap to reproduce from the text, so a
## restore re-parses them; nothing else is stored.
func to_state() -> Dictionary:
	return {
		"kind": "json",
		"text": _json_edit.text,
		"title": _title,
	}


func tab_title() -> String:
	return _title


## The current editor text (for File ▸ Save JSON…).
func json_text() -> String:
	return _json_edit.text


## Re-parse and display the current editor text (from a keyboard shortcut). Public
## entry point mirroring the "Show" button, so the host can trigger it for the
## active tab.
func show_json() -> void:
	_show()


## A file was written from this tab (File ▸ Save JSON…): adopt its basename as the
## title so the tab reflects its on-disk source. The content is already the editor
## text, so nothing else changes.
func mark_saved(path: String) -> void:
	_set_title(path.get_file())


## Exposes the results view (mirrors QueryTab/EndpointTab).
func results() -> ResultsView:
	return _results


func _ready() -> void:
	_apply_style()
	# Local JSON isn't paginated and carries no schema, so the Table mode is hidden
	# and the Tree/Text render the value verbatim (raw mode), just like endpoints.
	_results.set_raw_mode(true)
	_results.set_pagination_enabled(false)
	_results.set_item_noun("item")
	# A nested object/array can itself be opened in a further JSON tab.
	_results.open_json_requested.connect(func(text: String) -> void: open_json_requested.emit(text))
	_json_edit.text = _initial_text
	_title_label.text = _title
	# Seeded with text (opened from a file, or restored from the sidecar): parse and
	# display right away. Parsing is local and free, so unlike query/endpoint tabs
	# there's no request to defer — showing immediately is the friendlier default.
	if not _json_edit.text.strip_edges().is_empty():
		_show()
	else:
		status_changed.emit("Type or paste JSON, then press Show (F5)")


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARK, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_toolbar.add_theme_stylebox_override("panel", sb)
	_show_btn.add_theme_color_override("font_color", AppTheme.ACCENT_GREEN)
	_show_btn.tooltip_text = "Parse and show the JSON (F5)"
	_title_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


## Parse the editor text and render it in the results view. Parsing goes through
## LaxJson — the same lenient JSON5-flavoured parser the query filter/options
## editors use — so pasted data can use unquoted keys, single quotes, trailing
## commas, // and /* */ comments and Date()/ISODate() shorthands. Empty input clears
## the results; a parse error is reported without disturbing what's already shown.
func _show() -> void:
	var text := _json_edit.text.strip_edges()
	if text.is_empty():
		_results.show_raw(null, [], 0)
		status_changed.emit("Nothing to show — the editor is empty")
		state_changed.emit()
		return
	var parsed: Dictionary = LaxJson.parse_string(text)
	if not parsed.get("ok", false):
		status_changed.emit("Invalid JSON: %s" % parsed.get("error", "parse error"))
		return
	var value: Variant = parsed["value"]
	# No schema, so no entity roots to type; an array's size drives the count label
	# (a top-level object/scalar hides it, matching endpoint results).
	var count := (value as Array).size() if value is Array else 0
	_results.show_raw(value, [], count)
	if value is Array:
		status_changed.emit("Parsed JSON — %d item%s" % [count, "" if count == 1 else "s"])
	else:
		status_changed.emit("Parsed JSON")
	state_changed.emit()


## Update the tab title (and the toolbar label), announcing the change so the
## center relabels the tab. No-op when the title is unchanged or blank.
func _set_title(title: String) -> void:
	if title.is_empty() or title == _title:
		return
	_title = title
	_title_label.text = _title
	title_changed.emit(_title)
	state_changed.emit()
