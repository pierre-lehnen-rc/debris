class_name WorkspaceSession
extends RefCounted

## Live, in-RAM state for one open workspace tab. Wraps the persisted workspace
## config but adds runtime-only state that is never written back to it:
##   - session users added while the tab is open (source == "session"), and
##   - temporary access tokens acquired by logging in a password-based user.
## Closing the tab (dropping this object) discards all of it.
##
## The users panel and every endpoint tab share one instance so login/logout and
## user additions are reflected everywhere. Mutations emit `changed`.
##
## Each user entry is a Dictionary:
##   id        : int      stable handle (survives list reordering)
##   auth      : String   "token" | "password"
##   source    : String   "config" (from the workspace config) | "session"
##   user_id   : String   X-User-Id; always configurable, used as X-User-Id for token auth
##   username  : String   username/email; always configurable, the login identifier for password auth
##   token     : String   permanent X-Auth-Token, for token auth
##   password  : String   for password auth
##   session_user_id : String  userId returned by a successful login (password auth)
##   session_token   : String  authToken returned by login; "" when logged out
##
## A user has no separate display name: `display_label` derives one from the
## user_id and username identifiers.

signal changed

var workspace: Dictionary
var _users: Array = []
var _next_id := 1


func _init(ws: Dictionary) -> void:
	workspace = ws
	var configured: Variant = ws.get("users", [])
	if configured is Array:
		for entry in configured:
			if entry is Dictionary:
				_users.append(_make_entry(entry, "config"))


## The live user list (config users first, then session-added ones). Callers read
## it to render; treat entries as read-only and mutate through the methods here.
func users() -> Array:
	return _users


func find(id: int) -> Dictionary:
	for u in _users:
		if u["id"] == id:
			return u
	return {}


## Add a user for this session only (never persisted to the workspace config).
func add_user(entry: Dictionary) -> void:
	_users.append(_make_entry(entry, "session"))
	changed.emit()


func remove_user(id: int) -> void:
	for i in _users.size():
		if _users[i]["id"] == id:
			_users.remove_at(i)
			changed.emit()
			return


## True when the user currently has a usable access token: token-auth users always
## do (permanent); password-auth users only after a successful login.
func has_token(id: int) -> bool:
	var u := find(id)
	if u.is_empty():
		return false
	if u["auth"] == "token":
		return not String(u["token"]).is_empty()
	return not String(u["session_token"]).is_empty()


## Token-auth users carry a permanent token, so they never show a login/logout
## button; password-auth users do.
func needs_login(id: int) -> bool:
	var u := find(id)
	return not u.is_empty() and u["auth"] == "password"


## Exchange a password user's credentials for a temporary token via the login
## endpoint and remember it for this session. Returns { ok, error }.
func login(id: int) -> Dictionary:
	var u := find(id)
	if u.is_empty():
		return {"ok": false, "error": "no such user"}
	if u["auth"] != "password":
		return {"ok": false, "error": "user has a permanent token"}

	var result := await RocketChat.login(workspace, u["username"], u["password"])
	if not result.get("ok", false):
		return {"ok": false, "error": result.get("error", "login failed")}
	u["session_user_id"] = result["user_id"]
	u["session_token"] = result["token"]
	changed.emit()
	return {"ok": true, "error": ""}


## Discard a password user's temporary token (no logout API call is made).
func logout(id: int) -> void:
	var u := find(id)
	if u.is_empty():
		return
	u["session_user_id"] = ""
	u["session_token"] = ""
	changed.emit()


## The workspace dict to send a request as `id` with. Sets explicit user_id/token
## (empty when the user has no token, so no auth header goes out) and strips the
## users list so RocketChat._headers uses exactly these credentials. `id < 0`
## means the anonymous "(none)" choice.
func effective_workspace(id: int) -> Dictionary:
	var ws := workspace.duplicate(true)
	ws.erase("users")
	ws["user_id"] = ""
	ws["token"] = ""
	var creds := _credentials(id)
	ws["user_id"] = creds["user_id"]
	ws["token"] = creds["token"]
	return ws


# Helpers ---------------------------------------------------------------------
func _credentials(id: int) -> Dictionary:
	var u := find(id)
	if u.is_empty():
		return {"user_id": "", "token": ""}
	if u["auth"] == "token":
		return {"user_id": u["user_id"], "token": u["token"]}
	return {"user_id": u["session_user_id"], "token": u["session_token"]}


func _make_entry(raw: Dictionary, source: String) -> Dictionary:
	var token: String = raw.get("token", "")
	# Infer the auth mode when it wasn't stated: a token means token auth.
	var auth: String = raw.get("auth", "token" if not token.is_empty() else "password")
	if auth != "password":
		auth = "token"
	var entry := {
		"id": _next_id,
		"auth": auth,
		"source": source,
		"user_id": raw.get("user_id", ""),
		"username": raw.get("username", ""),
		"token": token,
		"password": raw.get("password", ""),
		"session_user_id": "",
		"session_token": "",
	}
	_next_id += 1
	return entry


## A human label for a user, built from the two identifiers: "username (user_id)"
## when both are set, otherwise whichever one is present.
static func display_label(user: Dictionary) -> String:
	var uid := String(user.get("user_id", ""))
	var uname := String(user.get("username", ""))
	if not uname.is_empty() and not uid.is_empty():
		return "%s (%s)" % [uname, uid]
	if not uname.is_empty():
		return uname
	if not uid.is_empty():
		return uid
	return "(user)"
