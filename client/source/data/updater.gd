extends Node

## Auto-update for exported Debris builds. Checks GitHub Releases for a newer
## version, downloads this platform's asset on request, and — once the user
## confirms — swaps the running binary (Linux) or .app bundle (macOS) and
## relaunches. Registered as the `Updater` autoload.
##
## Division of labour:
##   • UpdateChecker (source/data/update_checker.gd) makes the pure decisions —
##     version parsing, comparison, asset selection — and is unit-tested.
##   • This autoload owns the live side: two HTTPRequests (one for the API check,
##     one for the file download), download progress, and the platform install
##     helper. The UI (UpdateDialog) drives it through check() / download() /
##     install() and reacts to the signals below; it never touches GitHub itself.
##
## The install works by writing a tiny shell helper, launching it detached, and
## quitting: the helper waits for this process to exit, moves the new build into
## place, and relaunches it. That's the only reliable way to replace a running
## executable in place.
##
## Self-replacement only makes sense for an exported build on Linux/macOS. In the
## editor, under the headless validation runner, or on any other OS,
## can_self_update() is false and the UI falls back to opening the release page.

## A check concluded — a newer release exists. `info` carries the fields from
## UpdateChecker.parse_release(): version, tag, notes, html_url, asset_*.
signal update_available(info: Dictionary)
## A check concluded — this build is current. Carries the running version.
signal up_to_date(current: String)
## A check couldn't complete. Carries a human-readable reason.
signal check_failed(reason: String)

## Download progress, emitted repeatedly while a download runs. `total` is 0
## until the server reports a content length.
signal download_progress(downloaded: int, total: int)
## The asset finished downloading. Carries the local (user://) path.
signal download_completed(path: String)
## The download couldn't complete. Carries a human-readable reason.
signal download_failed(reason: String)

## Where downloaded assets and the install helper are staged.
const STAGE_DIR := "user://updates"

var _check_http: HTTPRequest
var _dl_http: HTTPRequest
var _checking := false
var _downloading := false
var _dl_info: Dictionary = {}


func _ready() -> void:
	_check_http = HTTPRequest.new()
	add_child(_check_http)
	_check_http.request_completed.connect(_on_check_completed)

	_dl_http = HTTPRequest.new()
	add_child(_dl_http)
	_dl_http.request_completed.connect(_on_download_completed)

	# Only tick _process while a download is running (for progress polling).
	set_process(false)


## The running app version, e.g. "0.1.5".
func current_version() -> String:
	return UpdateChecker.current_version()


## True when this build can replace itself in place — an exported Linux or macOS
## build. False in the editor (get_executable_path is the editor, not the app),
## under headless validation, and on other platforms; the UI then offers only the
## release page.
func can_self_update() -> bool:
	if OS.has_feature("editor"):
		return false
	if not OS.get_environment("DEBRIS_HEADLESS").is_empty():
		return false
	return OS.get_name() in ["Linux", "macOS"]


# Checking --------------------------------------------------------------------

## Ask GitHub for the latest release. Concludes with update_available /
## up_to_date / check_failed. A no-op if a check is already in flight.
func check() -> void:
	if _checking:
		return
	_checking = true
	# GitHub rejects requests without a User-Agent.
	var headers := PackedStringArray([
		"User-Agent: Debris-Updater",
		"Accept: application/vnd.github+json",
	])
	var err := _check_http.request(UpdateChecker.LATEST_RELEASE_URL, headers)
	if err != OK:
		_checking = false
		check_failed.emit("Couldn't start the update check (error %d)." % err)


func _on_check_completed(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_checking = false
	if result != HTTPRequest.RESULT_SUCCESS:
		check_failed.emit("Couldn't reach GitHub (network error %d)." % result)
		return
	if code == 403:
		check_failed.emit("GitHub rate limit reached — try again later.")
		return
	if code != 200:
		check_failed.emit("GitHub returned HTTP %d." % code)
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(json) != TYPE_DICTIONARY:
		check_failed.emit("GitHub sent an unexpected response.")
		return
	var info := UpdateChecker.parse_release(json, OS.get_name())
	if info.is_empty():
		check_failed.emit("Couldn't read the latest release.")
		return
	if UpdateChecker.is_newer(str(info["version"]), current_version()):
		update_available.emit(info)
	else:
		up_to_date.emit(current_version())


# Downloading -----------------------------------------------------------------

## Download `info`'s platform asset into STAGE_DIR. Emits download_progress while
## it runs, then download_completed(path) or download_failed(reason). A no-op if
## a download is already running.
func download(info: Dictionary) -> void:
	if _downloading:
		return
	var url := str(info.get("asset_url", ""))
	if url.is_empty():
		download_failed.emit("No download is available for this platform.")
		return
	if not _prepare_stage_dir():
		download_failed.emit("Couldn't create a place to download to.")
		return

	var file_name := str(info.get("asset_name", "update.bin"))
	var dest := STAGE_DIR.path_join(file_name)
	_dl_http.download_file = dest
	_dl_info = info.duplicate()
	_dl_info["path"] = dest

	# Minimal headers for the asset download (which redirects to a CDN).
	var err := _dl_http.request(url, PackedStringArray(["User-Agent: Debris-Updater"]))
	if err != OK:
		download_failed.emit("Couldn't start the download (error %d)." % err)
		return
	_downloading = true
	set_process(true)


## Abort an in-progress download and delete the partial file.
func cancel_download() -> void:
	if not _downloading:
		return
	_dl_http.cancel_request()
	_downloading = false
	set_process(false)
	var path := str(_dl_info.get("path", ""))
	if not path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _process(_delta: float) -> void:
	if not _downloading:
		return
	download_progress.emit(_dl_http.get_downloaded_bytes(), _dl_http.get_body_size())


func _on_download_completed(
	result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray
) -> void:
	_downloading = false
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		download_failed.emit("Download failed (network error %d)." % result)
		return
	if code != 200:
		download_failed.emit("Download failed (HTTP %d)." % code)
		return
	download_completed.emit(str(_dl_info.get("path", "")))


# Installing ------------------------------------------------------------------

## Replace the running build with the file previously downloaded to `path`, then
## quit and relaunch via a detached helper. Returns false without side effects if
## self-update isn't supported here (editor / headless / other OS) or the file is
## missing — the UI then falls back to the release page. On success the app is on
## its way down; the helper finishes the swap once it exits.
func install(path: String) -> bool:
	if not can_self_update():
		return false
	var abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs):
		return false

	var spawned := false
	match OS.get_name():
		"Linux":
			spawned = _install_linux(abs)
		"macOS":
			spawned = _install_macos(abs)
	if not spawned:
		return false

	# Cleanly tell the managed server we're leaving, then quit. The helper is
	# already waiting on our PID and swaps + relaunches once we're down.
	ServerManager.quit()
	return true


# Launch a detached helper that waits for this app (PID) to exit, then moves the
# new binary over the running one and relaunches it.
func _install_linux(new_bin: String) -> bool:
	var script := """#!/bin/sh
# args: PID NEW_BINARY TARGET_BINARY
PID="$1"; NEW="$2"; TARGET="$3"
i=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 0.2; i=$((i+1)); [ "$i" -gt 150 ] && break
done
mv -f "$NEW" "$TARGET" 2>/dev/null || cp -f "$NEW" "$TARGET"
chmod +x "$TARGET"
nohup "$TARGET" >/dev/null 2>&1 &
"""
	return _spawn_helper(script, [str(OS.get_process_id()), new_bin, OS.get_executable_path()])


# macOS asset is a zipped .app. The helper waits us out, unpacks the zip, swaps
# the .app bundle, clears the download quarantine flag (so Gatekeeper doesn't
# block the freshly downloaded, unsigned build), and reopens it.
func _install_macos(zip_path: String) -> bool:
	var app := _macos_app_path()
	if app.is_empty():
		return false
	var work := ProjectSettings.globalize_path(STAGE_DIR)
	var script := """#!/bin/sh
# args: PID ZIP APP_BUNDLE WORK_DIR
PID="$1"; ZIP="$2"; APP="$3"; WORK="$4"
i=0
while kill -0 "$PID" 2>/dev/null; do
	sleep 0.2; i=$((i+1)); [ "$i" -gt 150 ] && break
done
rm -rf "$WORK/extract"
mkdir -p "$WORK/extract"
ditto -x -k "$ZIP" "$WORK/extract" 2>/dev/null || unzip -o "$ZIP" -d "$WORK/extract"
NEWAPP=$(find "$WORK/extract" -maxdepth 2 -name '*.app' | head -n1)
[ -z "$NEWAPP" ] && exit 1
rm -rf "$APP"
mv "$NEWAPP" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
open "$APP"
"""
	return _spawn_helper(script, [str(OS.get_process_id()), zip_path, app, work])


# Walk up from the executable (.../Debris.app/Contents/MacOS/Debris) to the
# enclosing *.app bundle. "" if the app isn't inside a bundle.
func _macos_app_path() -> String:
	var p := OS.get_executable_path()
	while not p.is_empty() and p != "/":
		if p.get_extension() == "app":
			return p
		p = p.get_base_dir()
	return ""


# Write the helper script to STAGE_DIR and launch it detached via /bin/sh (it
# outlives this process). Returns whether it started.
func _spawn_helper(script_body: String, args: Array) -> bool:
	var script_path := STAGE_DIR.path_join("apply-update.sh")
	var f := FileAccess.open(script_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(script_body)
	f.close()

	var sh_args: Array = [ProjectSettings.globalize_path(script_path)]
	sh_args.append_array(args)
	return OS.create_process("/bin/sh", sh_args) > 0


func _prepare_stage_dir() -> bool:
	var abs := ProjectSettings.globalize_path(STAGE_DIR)
	if DirAccess.make_dir_recursive_absolute(abs) != OK and not DirAccess.dir_exists_absolute(abs):
		return false
	return true
