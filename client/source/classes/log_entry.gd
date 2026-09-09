class_name LogEntry
extends RefCounted

## Parses one captured server-log line into a small record the log view uses:
##   { seq, raw, structured, level, doc }
## `doc` is the value shown in the shared Tree/Table/Text results view — the parsed
## pino record for a JSON line, or `{ "msg": <text> }` for anything else. `raw` is
## the original line (searched by the text filter) and `level` drives the level
## filter (0 for a level-less line, which the filter never hides).
##
## The line is the raw text the bridge's tap saw. From the injected pino tap it is
## an NDJSON record; from a future file source it may be pino-pretty text or any
## other line. So parsing is best-effort and never assumes JSON: a line that parses
## to a JSON object is shown as that object; anything else is shown as its raw text.
## That is the seam that lets a non-JSON source drop in unchanged.

## Numeric pino levels, for the view's min-level filter. Rocket.Chat adds custom
## levels (http/method/subscription at 35, startup at 51); the record carries the
## number, and the filter compares against these standard thresholds.
const LEVEL_TRACE := 10
const LEVEL_DEBUG := 20
const LEVEL_INFO := 30
const LEVEL_WARN := 40
const LEVEL_ERROR := 50
const LEVEL_FATAL := 60

## The level labels offered in the level filter, in severity order (startup last).
## Every level_label() result is one of these.
const LEVEL_FILTER_LABELS := ["trace", "debug", "info", "warn", "error", "fatal", "startup"]


## The text label a numeric pino level represents (trace/debug/info/warn/error/fatal),
## for the Level column and filter. Rocket.Chat's startup (51) keeps its own name; the
## custom 35 (http/method/subscription) reads as info; other numbers map to the nearest
## lower standard level.
static func level_label(level: int) -> String:
	if level == 51:
		return "startup"
	if level >= LEVEL_FATAL:
		return "fatal"
	if level >= LEVEL_ERROR:
		return "error"
	if level >= LEVEL_WARN:
		return "warn"
	if level >= LEVEL_INFO:
		return "info"
	if level >= LEVEL_DEBUG:
		return "debug"
	if level >= LEVEL_TRACE:
		return "trace"
	return str(level)


## The colour the Level column renders a numeric pino level in, shared by the Tree and
## Table views so they agree. A severity ramp — dim for trace/debug, blue for info,
## amber for warn, red for error, brightest red for fatal — with startup (51) kept a
## distinct green. Mirrors level_label's thresholds (startup checked first).
static func level_color(level: int) -> Color:
	if level == 51:
		return Color("#7fb86b")  # startup — green, a healthy boot
	if level >= LEVEL_FATAL:
		return Color("#ff5f5f")  # fatal — brightest red
	if level >= LEVEL_ERROR:
		return Color("#e06c6c")  # error — red
	if level >= LEVEL_WARN:
		return Color("#d8a657")  # warn — amber
	if level >= LEVEL_INFO:
		return Color("#4f9cf0")  # info — accent blue
	if level >= LEVEL_DEBUG:
		return Color("#8b919e")  # debug — dim
	return Color("#6b7280")      # trace / level-less — dimmest


## The time-of-day, in seconds since midnight, of an ISO timestamp or a bare time
## ("2026-09-01T16:22:05.500Z" or "16:22[:05[.5]]"), for the time-range filter. Returns
## -1 for an empty or unparseable value. Date-agnostic: only the time of day is compared.
static func time_of_day_seconds(text: String) -> float:
	var t := text.strip_edges()
	if t.is_empty():
		return -1.0
	var tpos := t.find("T")
	if tpos != -1:
		t = t.substr(tpos + 1)
	t = t.trim_suffix("Z")
	for zone_sep in ["+", "-"]:  # drop a timezone offset, keeping the time of day
		var p := t.find(zone_sep)
		if p != -1:
			t = t.substr(0, p)
	var parts := t.split(":")
	if parts.size() < 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1.0
	var h := parts[0].to_int()
	var m := parts[1].to_int()
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1.0
	var s := 0.0
	if parts.size() >= 3:
		if not (parts[2].is_valid_float() or parts[2].is_valid_int()):
			return -1.0
		s = parts[2].to_float()
	return h * 3600.0 + m * 60.0 + s


## Parse `raw` (with sequence `seq`) into the record described above. A JSON object
## with a numeric `level` is a pino record (`structured`); other JSON objects are
## shown as-is but level-less; a non-JSON line becomes `{ "msg": <trimmed text> }`.
static func parse(seq: int, raw: String) -> Dictionary:
	var trimmed := raw.strip_edges()
	# Parse with a JSON instance rather than JSON.parse_string: the static helper
	# pushes an error to the log on every failure, and a non-JSON line (a plain
	# banner, or a future file source's pretty-printed text) is an ordinary case
	# here, not something to spam the log for. The instance API just returns a code.
	var json := JSON.new()
	if json.parse(trimmed) == OK and json.data is Dictionary:
		# Godot's JSON parses every number as a float, so an integer like `level:30`
		# comes back as 30.0 and would render as "30.0" everywhere. Restore whole
		# numbers to ints so the record reads as it was written.
		var d := _normalize_numbers(json.data) as Dictionary
		var level_value: Variant = d.get("level")
		var has_level := level_value is int or level_value is float
		return {
			"seq": seq,
			"raw": raw,
			"structured": has_level,
			"level": int(level_value) if has_level else 0,
			"doc": d,
		}
	return {
		"seq": seq,
		"raw": raw,
		"structured": false,
		"level": 0,
		"doc": {"msg": trimmed},
	}


## Recursively convert whole-valued floats to ints (Godot parses all JSON numbers as
## floats). Fractional and out-of-int64-range values are left as floats.
static func _normalize_numbers(value: Variant) -> Variant:
	if value is float:
		if abs(value) < 9.0e18 and is_equal_approx(value, floor(value)):
			return int(value)
		return value
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _normalize_numbers(value[key])
		return out
	if value is Array:
		var out: Array = []
		for element in value:
			out.append(_normalize_numbers(element))
		return out
	return value
