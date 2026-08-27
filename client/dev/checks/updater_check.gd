extends "res://dev/check_base.gd"

## Headless behaviour check for the Updater autoload — only the parts that don't
## touch the network (those can't run deterministically here). The version/asset
## decisions have their own unit tests (test/data/update_checker_test.gd); this
## covers the autoload's guard rails: it exists, refuses to self-update under
## headless, reports the project version, and fails a download with no asset
## through the download_failed signal rather than crashing.


func _run() -> void:
	var updater := root.get_node_or_null("Updater")
	expect(updater != null, "Updater autoload is present")
	if updater == null:
		return

	# Version comes from project settings (same source as the About dialog).
	expect_eq(updater.current_version(), UpdateChecker.current_version(), "current_version matches UpdateChecker")
	expect(not String(updater.current_version()).is_empty(), "current_version is non-empty")

	# Under the headless runner self-replacement must be refused so a validation
	# run can never swap the binary or relaunch.
	expect(not updater.can_self_update(), "can_self_update() is false under headless")

	# install() on a bogus path is a safe no-op here (can_self_update is false).
	expect(not updater.install("user://updates/nope.bin"), "install() refuses when self-update unsupported")

	# A download with no asset URL reports failure via the signal, not a crash.
	var failed := [false]
	var cb := func(_reason: String) -> void: failed[0] = true
	updater.download_failed.connect(cb)
	updater.download({"asset_url": ""})
	await _idle()
	updater.download_failed.disconnect(cb)
	expect(failed[0], "download() with no asset emits download_failed")


func _idle() -> void:
	# self is the SceneTree; let a frame pass so any deferred work settles.
	await process_frame
