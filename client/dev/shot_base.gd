extends SceneTree

## Base for the screenshot scripts under dev/shots/: boots the real app, lets the
## shot drive it into a known state, and writes the rendered frame to
## docs/screenshots/.
##
## Run one with:  dev/shots.sh dev/shots/<name>_shot.gd
##
## Unlike the rest of dev/, this boots *with a window*: the engine only hands back
## a frame it actually rendered, so these run on a real display (dev/shots.sh
## checks for one) instead of --headless. Everything else is the same boot as the
## checks — DEBRIS_HEADLESS=1, so ServerManager stays quiet and Backend/RocketChat
## answer from the fixtures under dev/mocks/, and user:// is redirected to a
## throwaway HOME. So the images are reproducible: same fixtures, same window
## size, same UI scale, no trace of whoever ran it.
##
## A shot extends this, implements _run(), and calls shoot("name.png") once the UI
## looks the way it should. Drive the app through the helpers below; they use the
## same public entry points the mouse does (a sidebar's *_activated signal, the
## center's open_* methods), so a shot exercises the real code paths rather than
## reaching into widgets.

const MAIN_SCENE := "res://source/ui/main.tscn"
const DEFAULT_SIZE := Vector2i(1400, 900)

## The Main node, once booted. Untyped so shots can call into the app without the
## compiler resolving app classes at parse time (same reason check_base.gd keeps
## its autoload handles untyped).
var main = null
## Absolute directory the PNGs are written to (DEBRIS_SHOTS_DIR).
var out_dir := ""

var _saved: Array[String] = []
var _failures: Array[String] = []
var _started := false


func _process(_delta: float) -> bool:
	# Boot once, on the first frame — every autoload's _ready() has fired by now,
	# so Backend/RocketChat have picked up their mocks.
	if _started:
		return false
	_started = true
	_boot()
	return false


func _boot() -> void:
	print("── %s ──" % get_script().resource_path.get_file())
	out_dir = OS.get_environment("DEBRIS_SHOTS_DIR")
	if out_dir.is_empty():
		out_dir = ProjectSettings.globalize_path("res://../docs/screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)

	main = load(MAIN_SCENE).instantiate()
	root.add_child(main)
	# main.gd sizes the window to the display's DPI scale on startup, which would
	# make the image depend on the screen it was captured from. Pin both back to
	# the shot's own size at 1:1 so every machine produces the same picture.
	root.content_scale_factor = 1.0
	root.size = _size_from_env()
	await frames(2)

	await _run()

	print("  %d saved, %d failed" % [_saved.size(), _failures.size()])
	if _failures.is_empty():
		print("OK")
		quit(0)
	else:
		print("FAIL")
		quit(1)


## Override in the shot: drive the UI, then call shoot(). May await freely.
func _run() -> void:
	push_error("shot did not override _run()")


# Capture ---------------------------------------------------------------------
## Save the current frame as `file_name` in the screenshots directory. Waits for
## the frame to be drawn before reading it back, so it never captures a half-laid
## out UI.
func shoot(file_name: String) -> void:
	await frames(1)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		fail("%s: the viewport handed back no image" % file_name)
		return
	var path := out_dir.path_join(file_name)
	var err := image.save_png(path)
	if err != OK:
		fail("%s: could not write %s (error %d)" % [file_name, path, err])
		return
	_saved.append(file_name)
	print("  saved %s (%dx%d)" % [file_name, image.get_width(), image.get_height()])


func fail(message: String) -> void:
	_failures.append(message)
	printerr("  FAIL: %s" % message)


# Waiting ---------------------------------------------------------------------
## Await `n` rendered frames.
func frames(n := 1) -> void:
	for _i in n:
		await process_frame


## Let the UI catch up with work in flight — a mocked request lands within a frame
## or two, but tree rebuilds, debounced filters and tab layout trail it. Shots wait
## on this rather than on any one signal, so no shot depends on which of several
## panels answers last.
func settle(seconds := 0.5) -> void:
	await create_timer(seconds).timeout
	await frames(1)


# Driving the app -------------------------------------------------------------
## The project every shot opens: a Mongo database and a Rocket.Chat workspace in
## one document, both answered by the fixtures. Names and users are made up; the
## URL is the usual local dev server.
func demo_doc() -> WorkspaceDoc:
	var doc := WorkspaceDoc.new()
	doc.name = "rocketchat"
	doc.set_mongo(
		{
			"name": "localhost:27017",
			"host": "localhost:27017",
			"connected": true,
			"databases": [],
			"database": "rocketchat",
			"auth": {"enabled": false},
		},
		"rocketchat",
	)
	doc.set_rocketchat(
		"http://localhost:3000",
		[
			{"auth": "token", "user_id": "aBcD1234efGh5678", "username": "admin",
				"token": "shot-fixture-token"},
			{"auth": "password", "username": "jdoe", "password": "shot-fixture"},
		],
		"/home/dev/Rocket.Chat",
	)
	doc.dirty = false
	return doc


## Open `doc` as a project tab and return it. The one place a shot reaches into
## Main: opening is otherwise driven by a file dialog, and a shot's project is
## built in memory rather than read from disk.
func open_project(doc: WorkspaceDoc):
	var tab = main._open_project_tab(doc)
	await frames(2)
	return tab


## The first descendant of `node` of class (or script class name) `type_name`, or
## null. How a shot reaches a sidebar or the center strip: the project's panels are
## built in code, so they have no fixed node paths.
## Left untyped so shots can call the panel's own methods on the result.
func find_one(node, type_name: String):
	var found: Array = node.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null


## The endpoint with `id` from an EndpointSidebar's catalog, or null.
func endpoint_by_id(sidebar, id: String):
	for entry in sidebar.endpoints():
		if (entry as ApiEndpoint).id == id:
			return entry
	fail("no endpoint '%s' in the catalog" % id)
	return null


## Unfold the rows of `node`'s tree whose label is one of `labels` — what clicking
## a fold arrow does, for shots that want a branch open. Only the first Tree under
## `node` is walked, which is the one a sidebar owns.
func expand_rows(node, labels: Array) -> void:
	var tree = find_one(node, "Tree")
	if tree == null:
		fail("no tree under %s to expand" % node.name)
		return
	var pending: Array = [tree.get_root()]
	while not pending.is_empty():
		var item = pending.pop_back()
		if item == null:
			continue
		if labels.has(item.get_text(0)):
			item.set_collapsed(false)
		var child = item.get_first_child()
		while child != null:
			pending.append(child)
			child = child.get_next()


## Paint the Collections footer with the state of an ordinary session.
##
## The one staged widget in these shots. The bundled Node server is never launched
## under the mocks (DEBRIS_HEADLESS silences ServerManager), so the panel would
## truthfully report "Server not running" — a state of the harness, not of the app,
## and a misleading thing to put in the README. The numbers below are a plain
## running server with this app attached; everything else in every shot is what the
## app actually did with the fixtures.
func stage_server_panel(node) -> void:
	var bar = find_one(node, "ServerStatusBar")
	if bar == null:
		fail("no ServerStatusBar under %s" % node.name)
		return
	var backend = root.get_node_or_null("Backend")
	bar._apply_state({
		"running": true,
		"connected": true,
		"apps": 1,
		"connections": 1,
		"managed": true,
		"pid": 51284,
		"uptime_ms": 213000,
		"url": backend.base_url if backend != null else "",
		"error": "",
	})


func _size_from_env() -> Vector2i:
	var raw := OS.get_environment("DEBRIS_SHOT_SIZE")
	var parts := raw.split("x", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return DEFAULT_SIZE
	return Vector2i(int(parts[0]), int(parts[1]))
