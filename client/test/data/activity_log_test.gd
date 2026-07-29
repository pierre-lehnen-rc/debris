# GdUnit generated TestSuite
class_name ActivityLogTest
extends "res://test/test_suite.gd"

# Tests for ActivityLog — the in-memory record of backend actions.
# See res://source/data/activity_log.gd (extends Node, normally the ActivityLog autoload).
# A fresh instance is used per test for isolation instead of the global singleton.


func _fresh() -> Node:
	var log: Node = auto_free(preload("res://source/data/activity_log.gd").new())
	add_child(log)
	return log


# record() / entries() --------------------------------------------------------
func test_entries_empty_initially() -> void:
	assert_array(_fresh().entries()).is_empty()


func test_record_appends_and_is_retrievable() -> void:
	var log := _fresh()
	log.record({"source": "mongo", "action": "find", "target": "mydb.users"})
	var entries: Array = log.entries()
	assert_array(entries).has_size(1)
	assert_str(entries[0]["source"]).is_equal("mongo")
	assert_str(entries[0]["action"]).is_equal("find")
	assert_str(entries[0]["target"]).is_equal("mydb.users")


func test_record_preserves_insertion_order_oldest_first() -> void:
	var log := _fresh()
	log.record({"action": "first"})
	log.record({"action": "second"})
	log.record({"action": "third"})
	var entries: Array = log.entries()
	assert_array(entries).has_size(3)
	assert_str(entries[0]["action"]).is_equal("first")
	assert_str(entries[2]["action"]).is_equal("third")


func test_record_stamps_time_and_fills_defaults() -> void:
	var log := _fresh()
	log.record({"action": "GET /api/info"})
	var e: Dictionary = log.entries()[0]
	# time is stamped by record() itself; shape "HH:MM:SS".
	assert_array(e["time"].split(":")).has_size(3)
	# Missing keys are filled with sensible defaults.
	assert_str(e["source"]).is_equal("")
	assert_str(e["target"]).is_equal("")
	assert_dict(e["params"]).is_empty()
	assert_bool(e["ok"]).is_false()
	assert_str(e["result"]).is_equal("")
	assert_str(e["error"]).is_equal("")
	assert_int(e["ms"]).is_equal(0)


func test_record_keeps_caller_supplied_values() -> void:
	var log := _fresh()
	log.record({
		"source": "rocketchat",
		"action": "GET /api/v1/info",
		"target": "/api/v1/info",
		"params": {"query": {"a": 1}},
		"ok": true,
		"result": "28 results",
		"error": "",
		"ms": 42,
	})
	var e: Dictionary = log.entries()[0]
	assert_str(e["source"]).is_equal("rocketchat")
	assert_bool(e["ok"]).is_true()
	assert_str(e["result"]).is_equal("28 results")
	assert_int(e["ms"]).is_equal(42)
	assert_dict(e["params"]).is_equal({"query": {"a": 1}})


func test_entries_returns_a_copy() -> void:
	# Mutating the returned array must not disturb the log.
	var log := _fresh()
	log.record({"action": "find"})
	var returned: Array = log.entries()
	returned.clear()
	assert_array(log.entries()).has_size(1)


# entry_added signal ----------------------------------------------------------
func test_record_emits_entry_added_signal() -> void:
	var log := _fresh()
	monitor_signals(log)
	log.record({"source": "mongo", "action": "find"})
	# The emitted payload is the same stamped dict that lands in entries().
	var stamped: Dictionary = log.entries()[0]
	await assert_signal(log).is_emitted("entry_added", stamped)


func test_no_signal_before_record() -> void:
	var log := _fresh()
	monitor_signals(log)
	await assert_signal(log).wait_until(100).is_not_emitted("entry_added")


# clear() ---------------------------------------------------------------------
func test_clear_empties_entries() -> void:
	var log := _fresh()
	log.record({"action": "a"})
	log.record({"action": "b"})
	assert_array(log.entries()).has_size(2)
	log.clear()
	assert_array(log.entries()).is_empty()


# MAX_ENTRIES cap -------------------------------------------------------------
func test_max_entries_constant() -> void:
	assert_int(preload("res://source/data/activity_log.gd").MAX_ENTRIES).is_equal(1000)


func test_log_is_capped_and_drops_oldest() -> void:
	var log := _fresh()
	var cap: int = preload("res://source/data/activity_log.gd").MAX_ENTRIES
	for i in cap + 1:
		log.record({"action": str(i)})
	var entries: Array = log.entries()
	# Never exceeds the cap.
	assert_array(entries).has_size(cap)
	# The very first entry (action "0") was dropped; the next is now oldest.
	assert_str(entries[0]["action"]).is_equal("1")
	assert_str(entries[cap - 1]["action"]).is_equal(str(cap))
