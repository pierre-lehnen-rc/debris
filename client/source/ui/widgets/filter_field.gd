class_name FilterField
extends LineEdit

## The filter box at the top of a sidebar list. A LineEdit that coalesces typing
## into a single `filter_changed` after a short pause, so the list re-renders as
## you type without being rebuilt on every keystroke. Enter applies immediately and
## Escape clears; the built-in clear button works as usual (it emits text_changed).
##
## Matching is shared by every list through the two statics below: terms_of() to
## parse the typed text once per render, matches() per candidate row.

## The debounced filter text, stripped. Emitted only when it actually changed, so
## a keystroke that leaves the effective filter alone (trailing space, Enter on an
## unchanged box) doesn't rebuild the list.
signal filter_changed(text: String)

## Long enough to swallow a burst of typing, short enough to feel immediate.
const DEBOUNCE_SECONDS := 0.15

var _timer: Timer
## The last text handed to filter_changed, to suppress no-op re-emissions.
var _emitted := ""


func _ready() -> void:
	clear_button_enabled = true
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE_SECONDS
	_timer.timeout.connect(_emit)
	add_child(_timer)
	text_changed.connect(func(_new_text: String) -> void: _timer.start())
	text_submitted.connect(func(_submitted: String) -> void: flush())


## Apply the current text now instead of waiting out the debounce.
func flush() -> void:
	_timer.stop()
	_emit()


func _emit() -> void:
	var stripped := text.strip_edges()
	if stripped == _emitted:
		return
	_emitted = stripped
	filter_changed.emit(stripped)


## Escape clears a non-empty box (and applies that at once). An empty box lets the
## key through, so Escape still reaches whatever else would handle it.
func _gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE or text.is_empty():
		return
	clear()
	flush()
	accept_event()


# Matching --------------------------------------------------------------------
## Split filter text into lowercased terms. A row must contain every term, so
## "users update" finds "/api/v1/users.update" — one term behaves as a plain
## substring search. Returns an empty array for a blank filter (matches all).
static func terms_of(filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for term in filter.to_lower().split(" ", false):
		if not term.is_empty():
			out.append(term)
	return out


## Whether a leaf survives the filter: either its own text matches, or one of the
## folder labels above it does. A folder that matches carries its whole contents, so
## filtering by a group name shows the group intact instead of stripping it down to
## the rows that happen to repeat the name.
static func matches_in(haystack: String, groups: Array, terms: PackedStringArray) -> bool:
	if matches(haystack, terms):
		return true
	for label in groups:
		if matches(String(label), terms):
			return true
	return false


## Whether `haystack` contains every term (case-insensitive). No terms = no filter.
static func matches(haystack: String, terms: PackedStringArray) -> bool:
	if terms.is_empty():
		return true
	var lower := haystack.to_lower()
	for term in terms:
		if not lower.contains(term):
			return false
	return true
