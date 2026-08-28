extends "res://dev/check_base.gd"

## Validates the Rocket.Chat server-models bridge wiring, both layers:
##   1. Backend.rocketchat_call against the mock — result unwrapping, Extended JSON
##      passthrough, and the failure path.
##   2. RcModelsTab end-to-end — inputs -> call -> a success status, local
##      validation of bad args / missing fields, and to_state() round-tripping.
## The mock lives in dev/mocks/backend_mock.gd (_rc_call) with fixture
## dev/mocks/backend/rocketchat_user.json.

# Loaded at runtime, not preloaded: the tab's script references the Backend
# autoload, which isn't registered when this -s main-loop script is compiled.
const TAB_PATH := "res://source/ui/workspace/rc_models_tab.tscn"
const SIDEBAR_PATH := "res://source/ui/workspace/rc_models_sidebar.tscn"
const TARGET := {"repoPath": "/x/Rocket.Chat"}


func _run() -> void:
	await _check_backend()
	await _check_install()
	await _check_model_methods()
	await _check_typing()
	await _check_duplicate_tabs()
	await _check_type_action_opens_query()
	await _check_history()
	await _check_history_compatibility()
	await _check_panel()


func _check_model_methods() -> void:
	# Listing a model's methods is metadata (from model-typings), returned as an
	# array and — unlike calls/installs — not recorded in the Activity Log.
	var before: int = activity_log.entries().size()
	var result: Dictionary = await backend.rocketchat_model_methods(TARGET, "Users")
	expect(bool(result.get("ok", false)), "rocketchat_model_methods ok")
	var data: Dictionary = result.get("data", {}) if result.get("data") is Dictionary else {}
	var methods: Array = data.get("methods", [])
	expect(methods is Array and methods.size() > 0, "model methods are returned")
	# Each method carries its declared signature, shown in the query tab.
	var first: Dictionary = methods[0] if not methods.is_empty() and methods[0] is Dictionary else {}
	expect(not String(first.get("name", "")).is_empty(), "a method carries its name")
	expect(String(first.get("signature", "")).begins_with("("), "a method carries its signature")
	expect_eq(activity_log.entries().size(), before, "listing methods isn't logged")


# 1. The Backend client + mock. ------------------------------------------------
func _check_backend() -> void:
	var doc: Dictionary = await backend.rocketchat_call(TARGET, "Users", "findOneByUsername", ["rocket.cat"])
	expect(bool(doc.get("ok", false)), "rocketchat_call ok")
	var result: Variant = _result_of(doc)
	expect(result is Dictionary and (result as Dictionary).get("username") == "rocket.cat",
		"result unwraps { result } to the rocket.cat doc")
	# Extended JSON survives as plain nested dicts (no special client decoding).
	var created: Variant = (result as Dictionary).get("createdAt") if result is Dictionary else null
	expect(created is Dictionary and (created as Dictionary).has("$date"), "createdAt kept as an Extended JSON $date")

	# The call is logged under source "rocketchat" with the URL it posted to and the
	# args — but not the repository path, which only the injection step uses.
	var entry: Dictionary = activity_log.entries().back()
	expect_eq(entry.get("source"), "rocketchat", "call logged under source rocketchat")
	expect_eq(entry.get("action"), "model call", "call logged as a model call")
	expect_eq(entry.get("target"), "Users.findOneByUsername", "log target is Model.method")
	var params: Dictionary = entry.get("params", {})
	expect(params.has("url"), "call log carries the url")
	expect(not params.has("repoPath"), "call log omits the repository path (unused by the call)")


func _check_install() -> void:
	# Injection is its own logged action carrying the repository path as target.
	var result: Dictionary = await backend.rocketchat_install(TARGET)
	expect(bool(result.get("ok", false)), "rocketchat_install ok")
	var data: Dictionary = result.get("data", {})
	expect(data.get("models", []) is Array and (data["models"] as Array).size() > 0,
		"install returns the server's model list")
	var entry: Dictionary = activity_log.entries().back()
	expect_eq(entry.get("source"), "rocketchat", "install logged under source rocketchat")
	expect_eq(entry.get("action"), "inject bridge", "injection logged as inject bridge")
	expect_eq(entry.get("target"), TARGET["repoPath"], "injection log target is the repository path")

	var counted: Dictionary = await backend.rocketchat_call(TARGET, "Users", "countByRole", ["admin"])
	var c_result: Variant = _result_of(counted)
	expect(c_result is Dictionary and (c_result as Dictionary).get("$numberInt") == "3",
		"countByRole result is the scalar 3")

	var failed: Dictionary = await backend.rocketchat_call(TARGET, "force-error", "boom", [])
	expect(not bool(failed.get("ok", true)), "the failure path reports ok=false")
	expect(not String(failed.get("error", "")).is_empty(), "a failure carries a message")


# 2. The RcModelsTab console. --------------------------------------------------
## Which result values get typed as documents of the model's collection. Documents
## and arrays of documents do; write results (acknowledged), scalars, Extended JSON
## scalar wrappers and non-objects don't.
func _check_typing() -> void:
	var tab: Variant = _tab("Users", "findOneByUsername", "[]", [])
	tab.set_collection("users")
	expect_eq(tab._collection, "users", "the tab adopts the model's collection")
	# A schema is always available: the project's, else a stock Rocket.Chat one.
	expect(tab._effective_schema() != null, "a schema is available even without a DB")

	var doc := {"_id": "u1", "username": "rocket.cat"}
	expect_eq(tab._entity_roots(doc), [doc], "a returned document is typed")
	expect_eq(tab._entity_roots([doc, doc]).size(), 2, "each document in an array is typed")
	# Write results carry `acknowledged` — command output, not stored documents.
	expect_eq(tab._entity_roots({"acknowledged": true, "modifiedCount": 2}), [],
		"an UpdateResult is not typed")
	expect_eq(tab._entity_roots([{"acknowledged": true}]), [],
		"UpdateResults inside an array are not typed")
	# Scalars keep their own types.
	expect_eq(tab._entity_roots("rocket.cat"), [], "a string result is not typed")
	expect_eq(tab._entity_roots(42), [], "a number result is not typed")
	expect_eq(tab._entity_roots(true), [], "a boolean result is not typed")
	expect_eq(tab._entity_roots({"$numberInt": "28"}), [],
		"an Extended JSON scalar is not typed")
	expect_eq(tab._entity_roots(["a", "b"]), [], "an array of strings is not typed")
	# A cursor-with-count result types the documents it carries.
	expect_eq(tab._entity_roots({"documents": [doc], "totalCount": 1}), [doc],
		"a paginated result types its documents")
	tab.queue_free()


## Opening the same function twice stacks two independent tabs, so it can be run
## side by side with different arguments.
func _check_duplicate_tabs() -> void:
	var center: Variant = load("res://source/ui/project/workspace_center.tscn").instantiate()
	root.add_child(center)
	var a: Variant = center.open_rcmodels("Users", "findOneByUsername", "users", "(u: string)")
	var b: Variant = center.open_rcmodels("Users", "findOneByUsername", "users", "(u: string)")
	expect(a != b, "opening the same function again makes a second tab")
	expect_eq(center.capture_tabs().size(), 2, "both tabs are open")
	# Each keeps its own arguments.
	a._args_edit.text = "[\"alice\"]"
	b._args_edit.text = "[\"bob\"]"
	expect_eq(a.to_state().get("args"), "[\"alice\"]", "the first tab keeps its own args")
	expect_eq(b.to_state().get("args"), "[\"bob\"]", "the second tab keeps its own args")
	center.queue_free()


## A schema type action ("List Messages", …) on a result row must reach the center
## and open a query tab on the database — the models tab has to relay the signal.
func _check_type_action_opens_query() -> void:
	var center: Variant = load("res://source/ui/project/workspace_center.tscn").instantiate()
	root.add_child(center)
	center.bind_mongo({"host": "localhost:27017"}, "rocketchat")
	var tab: Variant = center.open_rcmodels("Users", "findOneByUsername", "users", "(u: string)")
	var before: int = center.capture_tabs().size()
	# Stand in for the results view's action: the tab must bubble it to the center.
	tab._results.open_query_requested.emit("rocketchat_message", {"u._id": "u1"}, "find")
	await _settle()
	expect_eq(center.capture_tabs().size(), before + 1,
		"a type action on a model result opens a query tab")
	center.queue_free()


## History for model functions: recents + favorites in the same two stores the
## query history uses, keyed per function and never colliding with a collection.
func _check_history() -> void:
	var state := WorkspaceState.new()
	var doc := WorkspaceDoc.new()
	var history := QueryHistory.new()
	history.setup(state, doc)

	var center: Variant = load("res://source/ui/project/workspace_center.tscn").instantiate()
	root.add_child(center)
	center.bind_history(history)
	center.bind_rocketchat_target("http://localhost:3000", "/x/Rocket.Chat")
	var tab: Variant = center.open_rcmodels("Users", "findOneByUsername", "users", "(u: string)")

	var key := QueryHistory.model_key("Users", "findOneByUsername")
	expect_eq(key, "model:Users.findOneByUsername", "the store key is namespaced per function")

	# Running records the call as a recent for this function.
	tab._args_edit.text = "[\"rocket.cat\"]"
	tab.run()
	await _settle()
	var recents: Array = history.recents(key)
	expect_eq(recents.size(), 1, "a run is recorded as a recent")
	expect_eq(String((recents[0] as Dictionary).get("args", "")), "[\"rocket.cat\"]",
		"the recent keeps the args")
	# Re-running the identical call resurfaces it instead of stacking a duplicate.
	tab.run()
	await _settle()
	expect_eq(history.recents(key).size(), 1, "an identical re-run doesn't stack a duplicate")
	# A different argument list is a distinct entry.
	tab._args_edit.text = "[\"admin\"]"
	tab.run()
	await _settle()
	expect_eq(history.recents(key).size(), 2, "a different call is a separate recent")

	# Favorites round-trip through the project document.
	var entry: Dictionary = history.recents(key)[0]
	expect(not history.is_favorite(key, entry), "a fresh recent isn't a favorite")
	history.add_favorite(key, entry)
	expect(history.is_favorite(key, entry), "the call can be favorited")
	expect_eq(history.favorites(key).size(), 1, "the favorite is stored")
	history.remove_favorite(key, entry)
	expect(not history.is_favorite(key, entry), "the favorite can be removed")

	# Applying an entry fills the args without running.
	tab.apply_entry({"model": "Users", "method": "findOneByUsername", "args": "[\"loaded\"]"})
	expect_eq(tab._args_edit.text, "[\"loaded\"]", "applying an entry fills the args editor")

	# The list label shows the args (model/method are implied by the tab).
	expect_eq(QueryHistory.preview(entry), "[\"admin\"]", "the history row previews the args")
	center.queue_free()


## Model history must not disturb the existing collection query history: the two
## kinds live in the same stores under different keys and identify independently.
func _check_history_compatibility() -> void:
	var state := WorkspaceState.new()
	var doc := WorkspaceDoc.new()
	var history := QueryHistory.new()
	history.setup(state, doc)

	var query_entry := {"function": "find", "filter": "{\"a\": 1}", "options": ""}
	var model_entry := {"model": "Users", "method": "findOneByUsername", "args": "[\"x\"]"}
	history.record("users", query_entry)
	history.record(QueryHistory.model_key("Users", "findOneByUsername"), model_entry)

	expect_eq(history.recents("users").size(), 1, "the collection keeps its own recents")
	expect_eq(history.recents(QueryHistory.model_key("Users", "findOneByUsername")).size(), 1,
		"the function keeps its own recents")
	# Existing entries keep their old identity and preview.
	expect(QueryHistory.same_query(query_entry, {"function": "find", "filter": " {\"a\": 1} "}),
		"collection queries still compare by function/filter/options")
	expect(not QueryHistory.same_query(query_entry, model_entry),
		"a collection query never equals a model call")
	expect_eq(QueryHistory.preview(query_entry), "{\"a\": 1}",
		"collection queries still preview their filter")


func _check_panel() -> void:
	# Happy path: fill inputs, Run, expect a success status naming the call.
	var events: Array = []
	var tab: Variant = _tab("Users", "findOneByUsername", "[\"rocket.cat\"]", events)
	tab.run()
	await _settle()
	var last := String(events.back()) if not events.is_empty() else ""
	expect(last.begins_with("Users.findOneByUsername"), "status names the call (got '%s')" % last)
	expect(not last.contains("failed"), "the happy path did not fail")
	# to_state() persists the inputs (never results) for the .debris-workspace sidecar.
	var st: Dictionary = tab.to_state()
	expect_eq(st.get("kind"), "rcmodels", "state kind is rcmodels")
	expect_eq(st.get("model"), "Users", "state keeps the model")
	expect_eq(st.get("method"), "findOneByUsername", "state keeps the method")
	expect_eq(st.get("args"), "[\"rocket.cat\"]", "state keeps the args text")
	tab.queue_free()

	# The declared signature is shown above the args editor (and persisted, so a
	# restored tab still shows it); a tab without one hides the label.
	var sig := "(username: string, options?: O) => Promise<IUser | null>"
	var tabs: Variant = load(TAB_PATH).instantiate()
	tabs.configure("Users", "findOneByUsername", "users", sig, "[]")
	root.add_child(tabs)
	expect_eq(tabs._signature_label.text, sig, "the signature is shown above the args editor")
	expect(tabs._signature_label.visible, "the signature label is visible when there is one")
	expect_eq(tabs.to_state().get("signature"), sig, "the signature is persisted for restore")
	tabs.queue_free()

	var tabn: Variant = load(TAB_PATH).instantiate()
	tabn.configure("Users", "findOneByUsername", "users", "", "[]")
	root.add_child(tabn)
	expect(not tabn._signature_label.visible, "the signature label hides without a signature")
	tabn.queue_free()

	# Non-array args are caught locally: a clear message, no backend call.
	var events2: Array = []
	var tab2: Variant = _tab("Users", "findOneByUsername", "\"rocket.cat\"", events2)
	tab2.run()
	await _settle()
	expect(String(events2.back()).contains("array"), "non-array args rejected locally (got '%s')" % events2.back())
	tab2.queue_free()

	# An array result (a cursor method) counts its rows and offers the Table mode.
	var events4: Array = []
	var tab4: Variant = _tab("Users", "findUsersInRoles", "[\"admin\"]", events4)
	tab4.run()
	await _settle()
	expect(String(events4.back()).contains("2 result"), "array result counts rows (got '%s')" % events4.back())
	expect(tab4.results()._table_button_shown(), "Table mode is available on the models tab")
	tab4.queue_free()

	# No repository path configured: the Server Models sidebar shows the message and
	# disables Refresh; setting one clears both.
	var sidebar: Variant = load(SIDEBAR_PATH).instantiate()
	sidebar.set_configured(false)
	root.add_child(sidebar)
	await _settle()
	expect(sidebar._refresh_btn.disabled, "Refresh is disabled without a repo path")
	expect(not sidebar._edit_btn.disabled, "Edit workspace stays enabled without a repo path (to set one)")
	expect(sidebar._msg_wrap.visible, "config message is shown without a repo path")
	expect(not sidebar._tree.visible, "model tree is hidden without a repo path")
	expect(String(sidebar._desc.text).contains("Repository"), "message mentions the Repository path")
	# The Edit button asks the host to open the workspace editor.
	var edited: Array = [false]
	sidebar.edit_requested.connect(func() -> void: edited[0] = true)
	sidebar._edit_btn.pressed.emit()
	expect(edited[0], "Edit button emits edit_requested")
	# Configured with a model list: the tree shows, with a folder item per model.
	sidebar.set_configured(true)
	sidebar.set_models([
		{"name": "Messages", "collection": "rocketchat_message"},
		{"name": "Rooms", "collection": "rocketchat_room"},
		{"name": "Users", "collection": "users"},
	])
	expect(sidebar._tree.visible, "model tree is shown once configured")
	expect(not sidebar._msg_wrap.visible, "config message is hidden once configured")
	var root_item: TreeItem = sidebar._tree.get_root()
	expect_eq(root_item.get_child_count(), 3, "the tree lists one item per model")
	var first: TreeItem = root_item.get_first_child()
	expect_eq(first.get_text(0), "Messages", "model items carry the model name")
	expect_eq((first.get_metadata(0) as Dictionary).get("type"), "model", "model items are tagged type=model")
	expect_eq(first.get_icon(0), RcModelsSidebar.ICON_MODEL, "model items use the models icon")
	# Double-clicking a model asks the host for its functions and shows a loader.
	var requested: Array = [""]
	sidebar.functions_requested.connect(func(m: String) -> void: requested[0] = m)
	first.select(0)
	sidebar._on_item_activated()
	expect_eq(requested[0], "Messages", "expanding a model requests its functions")
	expect_eq(first.get_child_count(), 1, "a loading placeholder shows while functions load")
	# The host returns the methods; they fill in under sub-group folders — "base" for
	# the one inherited from IBaseModel, then "others" for the model's own methods
	# (neither word reaches GROUP_MIN here).
	sidebar.set_model_functions("Messages", [
		{"name": "countByRoomId", "signature": "(rid: string) => Promise<number>"},
		{"name": "findOneById", "signature": "(_id: string) => Promise<IMessage | null>", "base": true},
	])
	expect_eq(first.get_child_count(), 2, "functions fill in under sub-groups")
	var base_group: TreeItem = first.get_first_child()
	expect_eq(base_group.get_text(0), "base", "the inherited API groups first")
	expect_eq((base_group.get_metadata(0) as Dictionary).get("type"), "function_group",
		"sub-groups are tagged type=function_group")
	expect_eq(base_group.get_icon(0), RcModelsSidebar.ICON_GROUP,
		"sub-groups use the folder icon, not the model one")
	expect_eq(base_group.get_child_count(), 1, "the base group holds the inherited method")
	var others: TreeItem = base_group.get_next()
	expect_eq(others.get_text(0), "others", "the model's own methods follow")
	var leaf: TreeItem = others.get_first_child()
	expect_eq(leaf.get_text(0), "countByRoomId", "function leaves carry the method name")
	expect_eq((leaf.get_metadata(0) as Dictionary).get("type"), "function", "leaves are tagged type=function")
	expect(leaf.get_icon(0) != null, "function leaves have an icon")
	expect_eq(first.get_button_count(0), 1, "a loaded model shows a reload button")
	# Sub-groups start folded (that's the point of grouping) and toggle on activation.
	expect(others.is_collapsed(), "sub-groups start folded")
	others.select(0)
	sidebar._on_item_activated()
	expect(not others.is_collapsed(), "activating a sub-group unfolds it")
	others.select(0)
	sidebar._on_item_activated()
	expect(others.is_collapsed(), "activating it again folds it")
	# Double-clicking a function asks the host to open a query for model.method,
	# carrying the model's collection so the results can be typed.
	var activated: Array = ["", "", "", ""]
	sidebar.function_activated.connect(func(m: String, fn: String, coll: String, sig: String) -> void:
		activated[0] = m
		activated[1] = fn
		activated[2] = coll
		activated[3] = sig)
	leaf.select(0)
	sidebar._on_item_activated()
	expect_eq(activated[0], "Messages", "activating a function passes its model")
	expect_eq(activated[1], "countByRoomId", "activating a function passes its method")
	expect_eq(activated[2], "rocketchat_message", "activating a function passes its collection")
	expect_eq(activated[3], "(rid: string) => Promise<number>",
		"activating a function passes its signature")
	# The reload button drops and re-requests the model's functions.
	requested[0] = ""
	sidebar._on_tree_button_clicked(first, 0, 0, MOUSE_BUTTON_LEFT)
	expect_eq(requested[0], "Messages", "the reload button re-requests the functions")
	expect_eq(first.get_child_count(), 1, "reloading shows the loading placeholder again")
	sidebar.queue_free()

	# Fresh target: a tab opened before a repo path exists reads the target live on
	# every Run, so configuring one makes the SAME open tab work — no reopen needed.
	var live := {"repo_path": "", "url": "http://localhost:3000"}
	var events5: Array = []
	var tab5: Variant = load(TAB_PATH).instantiate()
	tab5.configure("Users", "findOneByUsername", "", "", "[\"rocket.cat\"]")
	tab5.bind_target(func() -> Dictionary: return live)
	tab5.status_changed.connect(func(t: String) -> void: events5.append(t))
	root.add_child(tab5)
	await _settle()
	tab5.run()
	await _settle()
	expect(String(events5.back()).contains("Repository"), "run without a repo path prompts (got '%s')" % events5.back())
	# The workspace gets a repository path configured; the already-open tab now runs.
	live["repo_path"] = "/x/Rocket.Chat"
	tab5.run()
	await _settle()
	expect(String(events5.back()).begins_with("Users.findOneByUsername"), "same tab runs once a repo path is set (got '%s')" % events5.back())
	expect(not String(events5.back()).contains("failed"), "the post-config run succeeded")
	tab5.queue_free()


# Helpers ---------------------------------------------------------------------
## Unwrap Backend's { ok, data } where data is the bridge's { result } envelope.
func _result_of(outcome: Dictionary) -> Variant:
	var data: Variant = outcome.get("data")
	return (data as Dictionary).get("result") if data is Dictionary else null


## Instantiate a configured RcModelsTab and capture its status line into `events`.
## Untyped (RcModelsTab as a type would pull its Backend-referencing script into
## this script's compile, which fails before autoloads register).
func _tab(model: String, method: String, args_text: String, events: Array) -> Variant:
	var tab = load(TAB_PATH).instantiate()
	tab.configure(model, method, "", "", args_text)
	tab.bind_target(func() -> Dictionary: return {"repo_path": "/x/Rocket.Chat", "url": "http://localhost:3000"})
	tab.status_changed.connect(func(t: String) -> void: events.append(t))
	root.add_child(tab)
	return tab


## Let the async _run coroutine run to completion (the mock resolves within a
## handful of idle frames).
func _settle() -> void:
	for _i in 12:
		await process_frame
