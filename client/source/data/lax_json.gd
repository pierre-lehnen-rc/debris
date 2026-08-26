class_name LaxJson
extends RefCounted

## A lenient, JSON5-flavoured parser for query filters, so users can type
## JavaScript/Mongo-shell-style objects instead of strict JSON. It accepts:
##   - single- or double-quoted strings
##   - unquoted identifier keys, including operators like $gt
##   - trailing commas in objects and arrays
##   - // line and /* block */ comments
##   - Date(...) / ISODate(...) shorthands for dates (see _build_date), expanded to
##     the Extended JSON the server expects, so a date filter is easy to type:
##       { createdAt: Date(1787677893670) }
##     becomes { "createdAt": { "$date": { "$numberLong": "1787677893670" } } }.
## parse_string() returns { ok: bool, value: Variant, error: String }. An empty
## input parses to an empty object so a blank filter means "match everything".

var _text := ""
var _pos := 0
var _len := 0
var _error := ""


static func parse_string(text: String) -> Dictionary:
	return LaxJson.new()._parse(text)


func _parse(text: String) -> Dictionary:
	_text = text
	_pos = 0
	_len = text.length()
	_error = ""

	_skip_ws()
	if _pos >= _len:
		return {"ok": true, "value": {}, "error": ""}

	var value: Variant = _parse_value()
	if not _error.is_empty():
		return {"ok": false, "value": null, "error": _error}

	_skip_ws()
	if _pos < _len:
		return {"ok": false, "value": null, "error": "Unexpected trailing text at %d" % _pos}

	return {"ok": true, "value": value, "error": ""}


func _parse_value() -> Variant:
	_skip_ws()
	if _pos >= _len:
		_set_error("Unexpected end of input")
		return null
	var c := _text[_pos]
	if c == "{":
		return _parse_object()
	if c == "[":
		return _parse_array()
	if c == "\"" or c == "'":
		return _parse_string_literal(c)
	if c == "-" or c == "+" or c == "." or _is_digit(c):
		return _parse_number()
	return _parse_keyword()


func _parse_object() -> Variant:
	var obj := {}
	_pos += 1  # consume '{'
	_skip_ws()
	if _peek() == "}":
		_pos += 1
		return obj

	while true:
		_skip_ws()
		if _pos >= _len:
			_set_error("Unterminated object")
			return null

		var key := ""
		var ch := _text[_pos]
		if ch == "\"" or ch == "'":
			var parsed_key: Variant = _parse_string_literal(ch)
			if not _error.is_empty():
				return null
			key = parsed_key
		else:
			key = _read_identifier()
			if key.is_empty():
				_set_error("Expected a property name at %d" % _pos)
				return null

		_skip_ws()
		if _peek() != ":":
			_set_error("Expected ':' after key '%s' at %d" % [key, _pos])
			return null
		_pos += 1  # consume ':'

		var value: Variant = _parse_value()
		if not _error.is_empty():
			return null
		obj[key] = value

		_skip_ws()
		var n := _peek()
		if n == ",":
			_pos += 1
			_skip_ws()
			if _peek() == "}":  # trailing comma
				_pos += 1
				return obj
		elif n == "}":
			_pos += 1
			return obj
		else:
			_set_error("Expected ',' or '}' at %d" % _pos)
			return null

	return obj


func _parse_array() -> Variant:
	var arr: Array = []
	_pos += 1  # consume '['
	_skip_ws()
	if _peek() == "]":
		_pos += 1
		return arr

	while true:
		var value: Variant = _parse_value()
		if not _error.is_empty():
			return null
		arr.append(value)

		_skip_ws()
		var n := _peek()
		if n == ",":
			_pos += 1
			_skip_ws()
			if _peek() == "]":  # trailing comma
				_pos += 1
				return arr
		elif n == "]":
			_pos += 1
			return arr
		else:
			_set_error("Expected ',' or ']' at %d" % _pos)
			return null

	return arr


func _parse_string_literal(quote: String) -> Variant:
	_pos += 1  # consume opening quote
	var result := ""
	while _pos < _len:
		var c := _text[_pos]
		if c == "\\":
			_pos += 1
			if _pos >= _len:
				break
			var esc := _text[_pos]
			match esc:
				"n": result += "\n"
				"t": result += "\t"
				"r": result += "\r"
				"b": result += char(8)
				"f": result += char(12)
				"u":
					result += char(_text.substr(_pos + 1, 4).hex_to_int())
					_pos += 4
				_: result += esc  # covers \\ \" \' \/ and any other char
			_pos += 1
		elif c == quote:
			_pos += 1
			return result
		else:
			result += c
			_pos += 1
	_set_error("Unterminated string")
	return null


func _parse_number() -> Variant:
	var start := _pos
	if _peek() == "+" or _peek() == "-":
		_pos += 1
	var is_float := false
	while _pos < _len:
		var c := _text[_pos]
		if _is_digit(c):
			_pos += 1
		elif c == "." or c == "e" or c == "E":
			is_float = true
			_pos += 1
		elif (c == "+" or c == "-") and _pos > start and (_text[_pos - 1] == "e" or _text[_pos - 1] == "E"):
			_pos += 1  # exponent sign
		else:
			break
	var num_str := _text.substr(start, _pos - start)
	return num_str.to_float() if is_float else num_str.to_int()


func _parse_keyword() -> Variant:
	var word := _read_identifier()
	match word:
		"true":
			return true
		"false":
			return false
		"null":
			return null
	# Constructor shorthands: an identifier immediately followed by '(' (whitespace
	# allowed), e.g. Date(...) / ISODate(...).
	if word == "Date" or word == "ISODate":
		var save := _pos
		_skip_ws()
		if _peek() == "(":
			return _parse_date_call(word)
		_pos = save
	if word.is_empty():
		_set_error("Unexpected character '%s' at %d" % [_peek(), _pos])
	else:
		_set_error("Unexpected token '%s' at %d" % [word, _pos])
	return null


## Parse a Date(...) / ISODate(...) call (the opening '(' is the next char) and
## return its Extended JSON form. `name` is the constructor name for error text.
func _parse_date_call(name: String) -> Variant:
	_pos += 1  # consume '('
	_skip_ws()
	var arg: Variant = null
	var has_arg := false
	if _peek() != ")":
		arg = _parse_value()
		if not _error.is_empty():
			return null
		has_arg = true
		_skip_ws()
	if _peek() != ")":
		_set_error("Expected ')' to close %s() at %d" % [name, _pos])
		return null
	_pos += 1  # consume ')'
	return _build_date(arg, has_arg)


## Build the Extended JSON for a date from a Date()/ISODate() argument:
##   - no argument           -> the current time
##   - a number (ms)         -> { "$date": { "$numberLong": "<ms>" } }
##   - a string (ISO-8601)   -> { "$date": "<string>" }  (the server Date.parses it)
## The numeric form uses $numberLong (not a bare number), since the server rejects
## a bare number under $date in canonical mode.
func _build_date(arg: Variant, has_arg: bool) -> Variant:
	if not has_arg:
		var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
		return {"$date": {"$numberLong": str(now_ms)}}
	if arg is int:
		return {"$date": {"$numberLong": str(arg)}}
	if arg is float:
		return {"$date": {"$numberLong": str(int(arg))}}
	if arg is String:
		return {"$date": arg}
	_set_error("Date() expects a number (milliseconds) or an ISO date string")
	return null


func _read_identifier() -> String:
	var start := _pos
	while _pos < _len and _is_ident_char(_text[_pos]):
		_pos += 1
	return _text.substr(start, _pos - start)


# Helpers ---------------------------------------------------------------------
func _skip_ws() -> void:
	while _pos < _len:
		var c := _text[_pos]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			_pos += 1
		elif c == "/" and _pos + 1 < _len and _text[_pos + 1] == "/":
			_pos += 2
			while _pos < _len and _text[_pos] != "\n":
				_pos += 1
		elif c == "/" and _pos + 1 < _len and _text[_pos + 1] == "*":
			_pos += 2
			while _pos + 1 < _len and not (_text[_pos] == "*" and _text[_pos + 1] == "/"):
				_pos += 1
			_pos += 2
		else:
			break


func _peek() -> String:
	return _text[_pos] if _pos < _len else ""


func _set_error(msg: String) -> void:
	if _error.is_empty():
		_error = msg


func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


func _is_ident_char(c: String) -> bool:
	return (
		c == "_"
		or c == "$"
		or (c >= "a" and c <= "z")
		or (c >= "A" and c <= "Z")
		or _is_digit(c)
	)
