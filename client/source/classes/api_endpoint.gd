class_name ApiEndpoint
extends RefCounted

## One Rocket.Chat REST endpoint, modelled after an OpenAPI operation so a future
## OpenAPI importer can produce the same shape. The endpoint explorer reads these
## to build the sidebar tree, the per-tab parameter form and the results view.
##
## A param is a Dictionary: { name, in ("query"|"body"), type ("string"|"int"|
## "bool"), required, default, description }. Pagination is expressed with
## `offset_param`/`count_param`, which name the params the pager drives directly
## (so they are excluded from the user-facing form).

var id := ""            # operationId, e.g. "channels.list"
var tag := ""           # grouping category, e.g. "Channels"
var summary := ""       # short human description
var method := "GET"     # HTTP verb
var path := ""          # request path, e.g. "/api/v1/channels.list"
var params: Array = []  # see header for the param shape
var result_key := ""    # where the payload lives in the response body
var single := false     # true when the result is one object, not a list
var paginated := false  # true when the endpoint supports offset/count paging
var offset_param := "offset"
var count_param := "count"
var item_noun := ""     # singular noun for the count label (derived if empty)


## Build an endpoint from a plain Dictionary (the catalog format, and the shape a
## future OpenAPI reader would emit). Unknown keys are ignored; missing keys fall
## back to sensible defaults.
static func from_dict(d: Dictionary) -> ApiEndpoint:
	var e := ApiEndpoint.new()
	e.id = d.get("id", "")
	e.tag = d.get("tag", "General")
	e.summary = d.get("summary", "")
	e.method = d.get("method", "GET")
	e.path = d.get("path", "/api/v1/%s" % e.id)
	e.params = d.get("params", [])
	e.result_key = d.get("result_key", "")
	e.single = d.get("single", false)
	e.paginated = d.get("paginated", false)
	e.offset_param = d.get("offset_param", "offset")
	e.count_param = d.get("count_param", "count")
	e.item_noun = d.get("item_noun", "")
	return e


## The params the user fills in: everything except the pagination params, which
## the results pager controls on its own.
func form_params() -> Array:
	var out: Array = []
	for p in params:
		var pname: String = p.get("name", "")
		if paginated and (pname == offset_param or pname == count_param):
			continue
		out.append(p)
	return out


## Singular noun for the results count label (e.g. "channel"). Uses item_noun if
## set, else derives it from result_key by trimming a trailing "s".
func noun() -> String:
	if not item_noun.is_empty():
		return item_noun
	if result_key.is_empty():
		return "result"
	if result_key.ends_with("s"):
		return result_key.substr(0, result_key.length() - 1)
	return result_key


## A short label for the sidebar/tab. The operationId reads well on its own.
func label() -> String:
	return id if not id.is_empty() else path
