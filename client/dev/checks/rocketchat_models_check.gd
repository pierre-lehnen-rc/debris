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
const TARGET := {"meteorDir": "/x/Rocket.Chat/apps/meteor"}


func _run() -> void:
	await _check_backend()
	await _check_install()
	await _check_model_methods()
	await _check_panel()


func _check_model_methods() -> void:
	# Listing a model's methods is metadata (from model-typings), returned as an
	# array and — unlike calls/installs — not recorded in the Activity Log.
	var before: int = activity_log.entries().size()
	var result: Dictionary = await backend.rocketchat_model_methods(TARGET, "Users")
	expect(bool(result.get("ok", false)), "rocketchat_model_methods ok")
	var data: Dictionary = result.get("data", {}) if result.get("data") is Dictionary else {}
	expect(data.get("methods", []) is Array and (data["methods"] as Array).size() > 0,
		"model methods are returned")
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
	# args — but not the meteor dir, which only the install step uses.
	var entry: Dictionary = activity_log.entries().back()
	expect_eq(entry.get("source"), "rocketchat", "call logged under source rocketchat")
	expect_eq(entry.get("action"), "model call", "call logged as a model call")
	expect_eq(entry.get("target"), "Users.findOneByUsername", "log target is Model.method")
	var params: Dictionary = entry.get("params", {})
	expect(params.has("url"), "call log carries the url")
	expect(not params.has("meteorDir"), "call log omits the meteor dir (unused by the call)")


func _check_install() -> void:
	# The install step is its own logged action carrying the meteor dir as target.
	var result: Dictionary = await backend.rocketchat_install(TARGET)
	expect(bool(result.get("ok", false)), "rocketchat_install ok")
	var data: Dictionary = result.get("data", {})
	expect(data.get("models", []) is Array and (data["models"] as Array).size() > 0,
		"install returns the server's model list")
	var entry: Dictionary = activity_log.entries().back()
	expect_eq(entry.get("source"), "rocketchat", "install logged under source rocketchat")
	expect_eq(entry.get("action"), "install bridge", "install logged as install bridge")
	expect_eq(entry.get("target"), TARGET["meteorDir"], "install log target is the meteor dir")

	var counted: Dictionary = await backend.rocketchat_call(TARGET, "Users", "countByRole", ["admin"])
	var c_result: Variant = _result_of(counted)
	expect(c_result is Dictionary and (c_result as Dictionary).get("$numberInt") == "3",
		"countByRole result is the scalar 3")

	var failed: Dictionary = await backend.rocketchat_call(TARGET, "force-error", "boom", [])
	expect(not bool(failed.get("ok", true)), "the failure path reports ok=false")
	expect(not String(failed.get("error", "")).is_empty(), "a failure carries a message")


# 2. The RcModelsTab console. --------------------------------------------------
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

	# No meteor dir configured: the Server Models sidebar shows the message and
	# disables Refresh; setting one clears both.
	var sidebar: Variant = load(SIDEBAR_PATH).instantiate()
	sidebar.set_configured(false)
	root.add_child(sidebar)
	await _settle()
	expect(sidebar._refresh_btn.disabled, "Refresh is disabled without a meteor dir")
	expect(not sidebar._edit_btn.disabled, "Edit workspace stays enabled without a meteor dir (to set one)")
	expect(sidebar._msg_wrap.visible, "config message is shown without a meteor dir")
	expect(not sidebar._tree.visible, "model tree is hidden without a meteor dir")
	expect(String(sidebar._desc.text).contains("Meteor"), "message mentions the Meteor directory")
	# The Edit button asks the host to open the workspace editor.
	var edited: Array = [false]
	sidebar.edit_requested.connect(func() -> void: edited[0] = true)
	sidebar._edit_btn.pressed.emit()
	expect(edited[0], "Edit button emits edit_requested")
	# Configured with a model list: the tree shows, with a folder item per model.
	sidebar.set_configured(true)
	sidebar.set_models(["Messages", "Rooms", "Users"])
	expect(sidebar._tree.visible, "model tree is shown once configured")
	expect(not sidebar._msg_wrap.visible, "config message is hidden once configured")
	var root_item: TreeItem = sidebar._tree.get_root()
	expect_eq(root_item.get_child_count(), 3, "the tree lists one item per model")
	var first: TreeItem = root_item.get_first_child()
	expect_eq(first.get_text(0), "Messages", "model items carry the model name")
	expect_eq((first.get_metadata(0) as Dictionary).get("type"), "model", "model items are tagged type=model")
	expect(first.get_icon(0) != null, "model items use a folder icon")
	# Double-clicking a model asks the host for its functions and shows a loader.
	var requested: Array = [""]
	sidebar.functions_requested.connect(func(m: String) -> void: requested[0] = m)
	first.select(0)
	sidebar._on_item_activated()
	expect_eq(requested[0], "Messages", "expanding a model requests its functions")
	expect_eq(first.get_child_count(), 1, "a loading placeholder shows while functions load")
	# The host returns the methods; they fill in as child leaves.
	sidebar.set_model_functions("Messages", ["countByRoomId", "findOneById"])
	expect_eq(first.get_child_count(), 2, "functions fill in as leaves")
	var leaf: TreeItem = first.get_first_child()
	expect_eq(leaf.get_text(0), "countByRoomId", "function leaves carry the method name")
	expect_eq((leaf.get_metadata(0) as Dictionary).get("type"), "function", "leaves are tagged type=function")
	expect(leaf.get_icon(0) != null, "function leaves have an icon")
	expect_eq(first.get_button_count(0), 1, "a loaded model shows a reload button")
	# Double-clicking a function asks the host to open a query for model.method.
	var activated: Array = ["", ""]
	sidebar.function_activated.connect(func(m: String, fn: String) -> void:
		activated[0] = m
		activated[1] = fn)
	leaf.select(0)
	sidebar._on_item_activated()
	expect_eq(activated[0], "Messages", "activating a function passes its model")
	expect_eq(activated[1], "countByRoomId", "activating a function passes its method")
	# The reload button drops and re-requests the model's functions.
	requested[0] = ""
	sidebar._on_tree_button_clicked(first, 0, 0, MOUSE_BUTTON_LEFT)
	expect_eq(requested[0], "Messages", "the reload button re-requests the functions")
	expect_eq(first.get_child_count(), 1, "reloading shows the loading placeholder again")
	sidebar.queue_free()

	# Fresh target: a tab opened before a meteor dir exists reads the target live on
	# every Run, so configuring one makes the SAME open tab work — no reopen needed.
	var live := {"meteor_dir": "", "url": "http://localhost:3000"}
	var events5: Array = []
	var tab5: Variant = load(TAB_PATH).instantiate()
	tab5.configure("Users", "findOneByUsername", "[\"rocket.cat\"]")
	tab5.bind_target(func() -> Dictionary: return live)
	tab5.status_changed.connect(func(t: String) -> void: events5.append(t))
	root.add_child(tab5)
	await _settle()
	tab5.run()
	await _settle()
	expect(String(events5.back()).contains("Meteor"), "run without a meteor dir prompts (got '%s')" % events5.back())
	# The workspace gets a meteor dir configured; the already-open tab now runs.
	live["meteor_dir"] = "/x/Rocket.Chat/apps/meteor"
	tab5.run()
	await _settle()
	expect(String(events5.back()).begins_with("Users.findOneByUsername"), "same tab runs once a meteor dir is set (got '%s')" % events5.back())
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
	tab.configure(model, method, args_text)
	tab.bind_target(func() -> Dictionary: return {"meteor_dir": "/x/Rocket.Chat/apps/meteor", "url": "http://localhost:3000"})
	tab.status_changed.connect(func(t: String) -> void: events.append(t))
	root.add_child(tab)
	return tab


## Let the async _run coroutine run to completion (the mock resolves within a
## handful of idle frames).
func _settle() -> void:
	for _i in 12:
		await process_frame
