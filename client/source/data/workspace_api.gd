class_name WorkspaceApi
extends RefCounted

## Mock Rocket.Chat REST client used by the endpoint explorer. It returns
## plausible, deterministic fake data so the UI can be built and exercised before
## the real HTTP layer exists. The result shape mirrors Backend's
## ({ ok, data, error, total }) so swapping in live requests later is a drop-in.
##
## For paginated endpoints the mock owns a fixed total per (workspace, endpoint)
## and returns the requested [offset, offset+count) slice, so the pager's
## prev/next and "short page means no more" logic behave realistically.

const STATUSES := ["online", "away", "busy", "offline"]
const CHANNEL_NAMES := [
	"general", "random", "support", "dev", "design", "ops", "sales",
	"marketing", "qa", "release", "incidents", "watercooler",
]


## Execute a request. `args` carries the user-entered form params; `offset`/`limit`
## come from the results pager. Returns { ok, data (Array), error, total }.
func request(
	workspace: Dictionary, endpoint: ApiEndpoint, args: Dictionary, offset: int, limit: int
) -> Dictionary:
	if endpoint == null:
		return {"ok": false, "data": [], "error": "no endpoint"}

	if endpoint.single:
		var item := _mock_item(workspace, endpoint, 0, args)
		return {"ok": true, "data": [item], "error": "", "total": 1}

	var total := _total_for(workspace, endpoint)
	if not endpoint.paginated:
		# A bounded list that ignores the pager.
		total = mini(total, 12)
		offset = 0
		limit = total

	var data: Array = []
	var stop := mini(offset + maxi(limit, 0), total)
	for i in range(offset, stop):
		data.append(_mock_item(workspace, endpoint, i, args))
	return {"ok": true, "data": data, "error": "", "total": total}


# Mock generation -------------------------------------------------------------
## A stable per-(workspace, endpoint) total so paging is consistent across calls.
func _total_for(workspace: Dictionary, endpoint: ApiEndpoint) -> int:
	var seed_str: String = String(workspace.get("url", "")) + "|" + endpoint.id
	return 18 + (absi(seed_str.hash()) % 130)


func _mock_item(workspace: Dictionary, endpoint: ApiEndpoint, index: int, args: Dictionary) -> Dictionary:
	match endpoint.result_key:
		"channels", "channel":
			return _mock_channel(index)
		"members":
			return _mock_user(index)
		"users", "user":
			return _mock_user(index)
		"ims":
			return _mock_im(index)
		"message":
			return _mock_message(index, args)
		_:
			return {"_id": _oid(index), "index": index}


func _mock_channel(index: int) -> Dictionary:
	var base: String = CHANNEL_NAMES[index % CHANNEL_NAMES.size()]
	var name := base if index < CHANNEL_NAMES.size() else "%s-%d" % [base, index]
	return {
		"_id": _oid(index),
		"name": name,
		"fname": name.capitalize(),
		"t": "c",
		"usersCount": 3 + (index * 7) % 240,
		"msgs": (index * 53) % 5000,
		"default": index % 9 == 0,
		"ts": _ts(index),
	}


func _mock_user(index: int) -> Dictionary:
	var username := "user%03d" % index
	return {
		"_id": _oid(index),
		"username": username,
		"name": "Test User %d" % index,
		"status": STATUSES[index % STATUSES.size()],
		"active": index % 11 != 0,
		"roles": ["user"] if index % 5 != 0 else ["user", "admin"],
		"createdAt": _ts(index),
	}


func _mock_im(index: int) -> Dictionary:
	return {
		"_id": _oid(index),
		"t": "d",
		"usernames": ["me", "user%03d" % index],
		"msgs": (index * 17) % 800,
		"ts": _ts(index),
	}


func _mock_message(index: int, args: Dictionary) -> Dictionary:
	var msg_id: String = args.get("msgId", "")
	if msg_id.is_empty():
		msg_id = _oid(index)
	return {
		"_id": msg_id,
		"rid": _oid(index + 100),
		"msg": "This is a mock message body.",
		"u": {"_id": _oid(index + 7), "username": "user%03d" % (index % 50)},
		"ts": _ts(index),
	}


## A fake-but-plausible 24-char hex object id, deterministic in `index`.
func _oid(index: int) -> String:
	var h := "%08x" % (absi(("oid-%d" % index).hash()))
	return (h + h + h).substr(0, 24)


## A fake ISO-ish timestamp string, deterministic in `index`.
func _ts(index: int) -> String:
	var day := 1 + (index % 27)
	var hour := index % 24
	var minute := (index * 7) % 60
	return "2026-06-%02dT%02d:%02d:00.000Z" % [day, hour, minute]
