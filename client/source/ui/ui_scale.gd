class_name UiScale
extends Object

## Scales pop-up windows to match the app's UI scale.
##
## `content_scale_factor` scales only the window it is set on. With
## `window/subwindows/embed_subwindows` disabled (see project.godot) every dialog
## and pop-up is its own OS window, so the factor main.gd applies to the main
## window does NOT cascade — each pop-up renders at 1× (tiny on a HiDPI/Retina
## display) unless it is scaled here too. main.gd is the single source of truth:
## it stores the effective factor on the main window's `content_scale_factor`,
## which these helpers mirror.
##
## A window's physical `size` is independent of `content_scale_factor` (and
## `get_contents_minimum_size()` reports logical, unscaled units), so keeping a
## pop-up's layout intact also means multiplying its size by the scale — the same
## size×scale recipe main.gd uses when it grows the main window.


## The effective UI scale main.gd applied to the main window (never below 1.0).
static func current(node: Node) -> float:
	var tree := node.get_tree()
	if tree == null or tree.root == null:
		return 1.0
	return maxf(1.0, tree.root.content_scale_factor)


## Pop up `window` centered, scaling its contents to match the app and growing
## its physical size so `logical_size` (unscaled design units) lays out unchanged
## at any UI scale. Omit `logical_size` to size to the window's own contents
## (for auto-sizing dialogs such as ConfirmationDialog).
static func popup_centered(window: Window, logical_size := Vector2i.ZERO) -> void:
	var scale := current(window)
	window.content_scale_factor = scale
	var logical := logical_size
	if logical == Vector2i.ZERO:
		logical = Vector2i(window.get_contents_minimum_size())
	window.popup_centered(Vector2i(Vector2(logical) * scale))


## Prepare a self-positioning pop-up (context menu, calendar) that the caller
## shows itself: match the app scale and grow its auto-computed size by that
## scale so its contents aren't clipped. Call in place of `reset_size()`, then
## set `position` and call `popup()` as before.
static func prepare(window: Window) -> void:
	var scale := current(window)
	window.content_scale_factor = scale
	window.reset_size()
	if scale != 1.0:
		window.size = Vector2i(Vector2(window.size) * scale)
