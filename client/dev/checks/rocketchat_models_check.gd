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
const TARGET := {"meteorDir": "/x/Rocket.Chat/apps/meteor"}


func _run() -> void:
	await _check_backend()
	await _check_panel()


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

	# Missing model/method is caught locally too.
	var events3: Array = []
	var tab3: Variant = _tab("", "", "[]", events3)
	tab3.run()
	await _settle()
	expect(String(events3.back()).contains("model"), "missing model rejected locally (got '%s')" % events3.back())
	tab3.queue_free()


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
	tab.configure("/x/Rocket.Chat/apps/meteor", "http://localhost:3000", model, method, args_text)
	tab.status_changed.connect(func(t: String) -> void: events.append(t))
	root.add_child(tab)
	return tab


## Let the async _run coroutine run to completion (the mock resolves within a
## handful of idle frames).
func _settle() -> void:
	for _i in 12:
		await process_frame
