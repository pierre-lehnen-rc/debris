class_name OpenApiParser
extends RefCounted

## Turns an OpenAPI 3 document (e.g. Rocket.Chat's /api/docs/json) into a list of
## ApiEndpoint objects for the endpoint explorer. The Rocket.Chat spec omits
## operationId/tags/summary and bundles GET query params into a single `query`
## object schema, so this derives ids/tags from the path and flattens the param
## shapes. Result keys and pagination are inferred from the 200 response schema.

const HTTP_METHODS := ["get", "post", "put", "delete", "patch"]
# Response-envelope keys that aren't the actual payload.
const META_KEYS := ["success", "offset", "count", "total"]
const PATH_PREFIXES := ["/api/v1/", "/api/"]


## Parse a whole document into ApiEndpoint objects. Returns [] if `doc` has no
## usable paths.
static func parse(doc: Dictionary) -> Array:
	var out: Array = []
	var paths: Variant = doc.get("paths")
	if not (paths is Dictionary):
		return out
	for path in paths:
		var item: Variant = paths[path]
		if not (item is Dictionary):
			continue
		for method in HTTP_METHODS:
			if item.has(method):
				out.append(_endpoint(path, method, item[method]))
	return out


static func _endpoint(path: String, method: String, op: Dictionary) -> ApiEndpoint:
	var id := _id_from_path(path)
	var params := _params(method, op)
	var pagination := _pagination(params)
	var result := _result(op)
	return ApiEndpoint.from_dict({
		"id": id,
		"tag": _tag_from_id(id, path),
		"summary": op.get("summary", op.get("description", "")),
		"method": method.to_upper(),
		"path": path,
		"params": params,
		"result_key": result["key"],
		"single": result["single"],
		"paginated": pagination["paginated"],
		"offset_param": pagination["offset"],
		"count_param": pagination["count"],
	})


# Path → id / tag -------------------------------------------------------------
static func _id_from_path(path: String) -> String:
	var id := path
	for prefix in PATH_PREFIXES:
		if id.begins_with(prefix):
			id = id.substr(prefix.length())
			break
	return id.trim_prefix("/")


## Group endpoints by the part before the first "." (e.g. "channels.list" →
## "Channels"), falling back to the first path segment for dot-less ids.
static func _tag_from_id(id: String, path: String) -> String:
	var dot := id.find(".")
	if dot > 0:
		return id.substr(0, dot).capitalize()
	var trimmed := _id_from_path(path)
	var slash := trimmed.find("/")
	var head := trimmed.substr(0, slash) if slash > 0 else trimmed
	return head.capitalize() if not head.is_empty() else "General"


# Parameters ------------------------------------------------------------------
static func _params(method: String, op: Dictionary) -> Array:
	var params: Array = []

	# Explicit parameters (path/query/header). Rocket.Chat GETs usually carry a
	# single object-typed `query` param whose properties are the real fields.
	for p in (op.get("parameters") if op.get("parameters") is Array else []):
		if not (p is Dictionary):
			continue
		var schema: Dictionary = p.get("schema", {}) if p.get("schema") is Dictionary else {}
		if _type_name(schema) == "object" and schema.has("properties"):
			params.append_array(_flatten_object(schema, p.get("in", "query")))
		else:
			params.append(_param(p.get("name", ""), p.get("in", "query"),
				schema, p.get("required", false), p.get("description", "")))

	# Request body (POST/PUT/PATCH): flatten the JSON object schema into fields.
	var body: Dictionary = op.get("requestBody", {})
	var content: Dictionary = body.get("content", {})
	var json: Dictionary = content.get("application/json", {})
	if json.has("schema"):
		params.append_array(_flatten_object(json["schema"], "body"))

	return params


## Expand an object schema's `properties` into individual param dicts.
static func _flatten_object(schema: Dictionary, location: String) -> Array:
	var out: Array = []
	var props: Dictionary = schema.get("properties", {}) if schema.get("properties") is Dictionary else {}
	var required: Array = schema.get("required", []) if schema.get("required") is Array else []
	for name in props:
		var prop: Dictionary = props[name] if props[name] is Dictionary else {}
		out.append(_param(name, location, prop, name in required,
			prop.get("description", "")))
	return out


static func _param(name: String, location: String, schema: Dictionary,
		required: bool, description: String) -> Dictionary:
	return {
		"name": name,
		"in": location,
		"type": _type(schema),
		"required": required,
		"description": description,
	}


## Map a JSON-schema type to the form's input kinds. Nested objects/arrays fall
## back to "string" so the user can type raw JSON.
static func _type(schema: Dictionary) -> String:
	match _type_name(schema):
		"integer", "number":
			return "int"
		"boolean":
			return "bool"
		_:
			return "string"


## The schema's declared type as a plain string. OpenAPI usually uses a string,
## but a schema may omit it or (3.1) use an array of types — normalise both.
static func _type_name(schema: Dictionary) -> String:
	var t: Variant = schema.get("type", "")
	if t is Array:
		return str((t as Array)[0]) if (t as Array).size() > 0 else ""
	return str(t)


# Pagination / result inference ----------------------------------------------
## An endpoint paginates when its params include both an offset and a count.
static func _pagination(params: Array) -> Dictionary:
	var names: Array = []
	for p in params:
		names.append(p.get("name", ""))
	var has_offset := "offset" in names
	var has_count := "count" in names
	return {
		"paginated": has_offset and has_count,
		"offset": "offset",
		"count": "count",
	}


## Infer where the payload lives in the 200 response: the first array-typed,
## non-meta property is a list result; else the first non-meta property is a
## single object; else there's no obvious payload.
static func _result(op: Dictionary) -> Dictionary:
	var schema := _ok_response_schema(op)
	var props: Dictionary = schema.get("properties", {}) if schema.get("properties") is Dictionary else {}
	# Prefer an array property (a list endpoint).
	for name in props:
		if name in META_KEYS:
			continue
		var prop: Dictionary = props[name] if props[name] is Dictionary else {}
		if _type_name(prop) == "array":
			return {"key": name, "single": false}
	# Else the first non-meta property is the single payload.
	for name in props:
		if name in META_KEYS:
			continue
		return {"key": name, "single": true}
	return {"key": "", "single": false}


static func _ok_response_schema(op: Dictionary) -> Dictionary:
	var responses: Dictionary = op.get("responses", {})
	var ok: Dictionary = responses.get("200", {})
	var content: Dictionary = ok.get("content", {})
	var json: Dictionary = content.get("application/json", {})
	return json.get("schema", {}) if json.get("schema") is Dictionary else {}
