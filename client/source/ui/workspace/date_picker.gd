class_name DatePicker
extends HBoxContainer

## A lightweight date / date-time picker for the endpoint form: an ISO-text
## LineEdit plus a button that drops a month-grid calendar, and (for date-time
## fields) inline hour/minute spinners. get_value() returns an ISO 8601 string —
## "YYYY-MM-DD" for dates, "YYYY-MM-DDTHH:MM:SS.000Z" for date-times — or "" when
## the date field is blank, so optional params stay omittable like text fields.
## Build with DatePicker.create() before adding it to the tree.

## Mirrors LineEdit.text_submitted so the form can send the request on Enter.
signal submitted

const WEEKDAYS := ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
const MONTHS := [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]
const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var _with_time := false
var _placeholder := ""
## Set via set_value() before the node is ready; applied once children exist.
var _pending := ""

var _edit: LineEdit
var _hour: SpinBox
var _minute: SpinBox
var _popup: PopupPanel
var _month_label: Label
var _grid: GridContainer
# The month the calendar popup is currently showing (month is 1-12).
var _view_year := 1970
var _view_month := 1


## Make a picker. `with_time` adds hour/minute spinners and emits a full
## date-time string; `placeholder` is shown in the empty text field.
static func create(with_time: bool, placeholder := "") -> DatePicker:
	var p := DatePicker.new()
	p._with_time = with_time
	p._placeholder = placeholder
	return p


func _ready() -> void:
	add_theme_constant_override("separation", 4)

	_edit = LineEdit.new()
	_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_edit.placeholder_text = _placeholder if not _placeholder.is_empty() else (
		"YYYY-MM-DD" + ("THH:MM" if _with_time else "")
	)
	_edit.text_submitted.connect(func(_t: String) -> void: submitted.emit())
	add_child(_edit)

	if _with_time:
		_hour = _make_spin(0, 23)
		add_child(_hour)
		var colon := Label.new()
		colon.text = ":"
		add_child(colon)
		_minute = _make_spin(0, 59)
		add_child(_minute)

	var btn := Button.new()
	btn.text = "▾"
	btn.tooltip_text = "Pick a date"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_open_popup)
	add_child(btn)

	_build_popup()

	if not _pending.is_empty():
		set_value(_pending)
		_pending = ""


# Public value ----------------------------------------------------------------
## The selected date as an ISO 8601 string, or "" when blank/unparseable.
func get_value() -> String:
	var date := _parse_date(_edit.text.strip_edges())
	if date.is_empty():
		return ""
	var base := "%04d-%02d-%02d" % [date["year"], date["month"], date["day"]]
	if not _with_time:
		return base
	return "%sT%02d:%02d:00.000Z" % [base, int(_hour.value), int(_minute.value)]


## Seed the field from an ISO string. Safe to call before the node is ready.
func set_value(text: String) -> void:
	if _edit == null:
		_pending = text
		return
	_edit.text = text
	if _with_time and text.contains("T"):
		var time_part: String = text.split("T")[1]
		var hm := time_part.split(":")
		if hm.size() >= 2 and hm[0].is_valid_int() and hm[1].is_valid_int():
			_hour.value = int(hm[0])
			_minute.value = int(hm[1])


# Calendar popup --------------------------------------------------------------
func _build_popup() -> void:
	_popup = PopupPanel.new()
	_popup.theme = AppTheme.shared()
	add_child(_popup)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_popup.add_child(vb)

	var header := HBoxContainer.new()
	var prev := Button.new()
	prev.text = "◀"
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(func() -> void: _shift_month(-1))
	_month_label = Label.new()
	_month_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_month_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := Button.new()
	next.text = "▶"
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(func() -> void: _shift_month(1))
	header.add_child(prev)
	header.add_child(_month_label)
	header.add_child(next)
	vb.add_child(header)

	_grid = GridContainer.new()
	_grid.columns = 7
	vb.add_child(_grid)

	var today := Button.new()
	today.text = "Today"
	today.focus_mode = Control.FOCUS_NONE
	today.pressed.connect(_pick_today)
	vb.add_child(today)


func _open_popup() -> void:
	# Start on the month already typed, else the current month.
	var date := _parse_date(_edit.text.strip_edges())
	if date.is_empty():
		var now := Time.get_datetime_dict_from_system()
		_view_year = now["year"]
		_view_month = now["month"]
	else:
		_view_year = date["year"]
		_view_month = date["month"]
	_render_calendar()
	_popup.reset_size()
	# Embedded sub-windows position popups in the parent viewport's space.
	_popup.position = Vector2i(global_position + Vector2(0, size.y))
	_popup.popup()


func _render_calendar() -> void:
	for child in _grid.get_children():
		child.queue_free()

	for wd in WEEKDAYS:
		var head := Label.new()
		head.text = wd
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		_grid.add_child(head)

	_month_label.text = "%s %d" % [MONTHS[_view_month - 1], _view_year]

	# Pad the first row up to the weekday the 1st falls on (0 = Sunday).
	for _i in _day_of_week(_view_year, _view_month, 1):
		_grid.add_child(Control.new())

	var selected := _parse_date(_edit.text.strip_edges())
	for day in range(1, _days_in_month(_view_year, _view_month) + 1):
		var b := Button.new()
		b.text = str(day)
		b.custom_minimum_size = Vector2(34, 28)
		b.focus_mode = Control.FOCUS_NONE
		var picked := day  # capture per-iteration value for the closure
		b.pressed.connect(func() -> void: _pick_day(picked))
		if (not selected.is_empty() and selected["year"] == _view_year
				and selected["month"] == _view_month and selected["day"] == day):
			b.add_theme_color_override("font_color", AppTheme.ACCENT)
		_grid.add_child(b)


func _pick_day(day: int) -> void:
	_edit.text = "%04d-%02d-%02d" % [_view_year, _view_month, day]
	_popup.hide()


func _pick_today() -> void:
	var now := Time.get_datetime_dict_from_system()
	_view_year = now["year"]
	_view_month = now["month"]
	_pick_day(now["day"])


func _shift_month(delta: int) -> void:
	_view_month += delta
	while _view_month < 1:
		_view_month += 12
		_view_year -= 1
	while _view_month > 12:
		_view_month -= 12
		_view_year += 1
	_render_calendar()


# Date helpers ----------------------------------------------------------------
## Parse a leading "YYYY-MM-DD" out of `text`; {} when it isn't present.
func _parse_date(text: String) -> Dictionary:
	if text.length() < 10:
		return {}
	var bits := text.substr(0, 10).split("-")
	if bits.size() != 3:
		return {}
	if not (bits[0].is_valid_int() and bits[1].is_valid_int() and bits[2].is_valid_int()):
		return {}
	var month := int(bits[1])
	var day := int(bits[2])
	if month < 1 or month > 12 or day < 1 or day > 31:
		return {}
	return {"year": int(bits[0]), "month": month, "day": day}


func _days_in_month(year: int, month: int) -> int:
	if month == 2 and _is_leap_year(year):
		return 29
	return DAYS_IN_MONTH[month - 1]


func _is_leap_year(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


## Weekday of the given date, 0 = Sunday … 6 = Saturday.
func _day_of_week(year: int, month: int, day: int) -> int:
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": 0, "minute": 0, "second": 0,
	})
	return Time.get_datetime_dict_from_unix_time(unix)["weekday"]


func _make_spin(low: int, high: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 1
	spin.custom_minimum_size = Vector2(52, 0)
	return spin
