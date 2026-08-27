class_name UpdateDialog
extends Window

## The face of the auto-updater. Drives the staged flow the app follows when a
## newer release exists: notify → (open the release page or download in-app) →
## once downloaded, confirm → install & relaunch. It owns no update logic — it
## calls the Updater autoload (check / download / install) and moves between the
## states below as Updater's signals arrive.
##
## Two entry points, called by Main:
##   • check_silent() — a quiet startup check; the window only appears if an
##     update is available. Up-to-date and errors stay silent.
##   • check_manual() — a Help ▸ Check for Updates… check; the window opens
##     immediately showing progress, and reports up-to-date / errors too.
##
## Built entirely in code (no .tscn), consistent with the app's programmatic UI.

const THEME_PATH := "res://source/ui/theme/app_theme.tres"

enum State { CHECKING, AVAILABLE, UP_TO_DATE, ERROR, DOWNLOADING, READY }

var _manual := false
var _info: Dictionary = {}
var _downloaded_path := ""

var _heading: Label
var _subheading: Label
var _notes_scroll: ScrollContainer
var _notes: Label
var _progress: ProgressBar
var _progress_label: Label
var _later_btn: Button
var _release_btn: Button
var _download_btn: Button
var _install_btn: Button
var _cancel_btn: Button


func _init() -> void:
	title = "Software Update"
	visible = false
	transient = true
	transient_to_focused = true
	exclusive = true
	unresizable = true
	min_size = Vector2i(460, 300)
	var theme_res := load(THEME_PATH)
	if theme_res != null:
		theme = theme_res


func _ready() -> void:
	_build_ui()
	close_requested.connect(_on_close)

	Updater.update_available.connect(_on_update_available)
	Updater.up_to_date.connect(_on_up_to_date)
	Updater.check_failed.connect(_on_check_failed)
	Updater.download_progress.connect(_on_download_progress)
	Updater.download_completed.connect(_on_download_completed)
	Updater.download_failed.connect(_on_download_failed)


# Entry points ----------------------------------------------------------------

## Quiet check (startup): stay hidden unless an update turns up.
func check_silent() -> void:
	_manual = false
	Updater.check()


## Explicit check (Help menu): show progress now, report every outcome.
func check_manual() -> void:
	_manual = true
	_set_state(State.CHECKING)
	_open()
	Updater.check()


# Updater signal handlers -----------------------------------------------------

func _on_update_available(info: Dictionary) -> void:
	_info = info
	_set_state(State.AVAILABLE)
	_open()


func _on_up_to_date(current: String) -> void:
	if not _manual:
		return
	_subheading.text = "Debris %s is the latest version." % current
	_set_state(State.UP_TO_DATE)


func _on_check_failed(reason: String) -> void:
	if not _manual:
		return
	_subheading.text = reason
	_set_state(State.ERROR)


func _on_download_progress(downloaded: int, total: int) -> void:
	if total > 0:
		_progress.max_value = total
		_progress.value = downloaded
		_progress_label.text = "%s of %s" % [_fmt_bytes(downloaded), _fmt_bytes(total)]
	else:
		# Content length not known yet — keep the pre-seeded bar, just show bytes.
		_progress_label.text = "%s downloaded…" % _fmt_bytes(downloaded)


func _on_download_completed(path: String) -> void:
	_downloaded_path = path
	_set_state(State.READY)


func _on_download_failed(reason: String) -> void:
	_subheading.text = reason
	_set_state(State.ERROR)


# Button actions --------------------------------------------------------------

func _on_open_release() -> void:
	var url := str(_info.get("html_url", ""))
	if not url.is_empty():
		OS.shell_open(url)


func _on_download() -> void:
	_progress.value = 0
	_progress.max_value = int(_info.get("asset_size", 0))
	_progress_label.text = "Starting…"
	_set_state(State.DOWNLOADING)
	Updater.download(_info)


func _on_cancel_download() -> void:
	Updater.cancel_download()
	_set_state(State.AVAILABLE)


func _on_install() -> void:
	if not Updater.install(_downloaded_path):
		# Shouldn't happen (the button is only shown when self-update is possible),
		# but fall back gracefully rather than leaving the user stuck.
		_subheading.text = "Couldn't install the update automatically. Opening the release page."
		_set_state(State.ERROR)
		_on_open_release()


func _on_close() -> void:
	hide()


# State machine ---------------------------------------------------------------

func _set_state(state: State) -> void:
	# Defaults; each state turns on what it needs.
	_notes_scroll.visible = false
	_progress.visible = false
	_progress_label.visible = false
	_later_btn.visible = false
	_release_btn.visible = false
	_download_btn.visible = false
	_install_btn.visible = false
	_cancel_btn.visible = false

	var can_download: bool = Updater.can_self_update() and not str(_info.get("asset_url", "")).is_empty()

	match state:
		State.CHECKING:
			_heading.text = "Checking for updates…"
			_subheading.text = "Contacting GitHub."
		State.AVAILABLE:
			_heading.text = "Update available"
			_subheading.text = "Debris %s is available — you have %s." % [
				str(_info.get("version", "?")), Updater.current_version()
			]
			var notes := str(_info.get("notes", ""))
			_notes.text = notes
			_notes_scroll.visible = not notes.is_empty()
			_later_btn.text = "Later"
			_later_btn.visible = true
			_release_btn.visible = true
			_download_btn.visible = can_download
		State.DOWNLOADING:
			_heading.text = "Downloading update…"
			_subheading.text = "Debris %s" % str(_info.get("version", "?"))
			_progress.visible = true
			_progress_label.visible = true
			_cancel_btn.visible = true
		State.READY:
			_heading.text = "Ready to install"
			_subheading.text = "Debris %s has been downloaded. Install it now? The app will restart." % \
				str(_info.get("version", "?"))
			_later_btn.text = "Later"
			_later_btn.visible = true
			_install_btn.visible = true
		State.UP_TO_DATE:
			_heading.text = "You're up to date"
			_later_btn.text = "Close"
			_later_btn.visible = true
		State.ERROR:
			_heading.text = "Update check failed"
			_later_btn.text = "Close"
			_later_btn.visible = true
			# Offer the page as a manual fallback if we know where it is.
			_release_btn.visible = not str(_info.get("html_url", "")).is_empty()


# UI construction -------------------------------------------------------------

func _build_ui() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", AppTheme._flat(AppTheme.BG_DARKEST, 0))
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 20)
	_heading.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	col.add_child(_heading)

	_subheading = Label.new()
	_subheading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subheading.add_theme_color_override("font_color", AppTheme.TEXT)
	col.add_child(_subheading)

	_notes_scroll = ScrollContainer.new()
	_notes_scroll.custom_minimum_size = Vector2(0, 180)
	_notes_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_notes_scroll.add_theme_stylebox_override("panel", AppTheme._flat(AppTheme.BG_DARK, 4, 1))
	col.add_child(_notes_scroll)

	var notes_margin := MarginContainer.new()
	notes_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		notes_margin.add_theme_constant_override("margin_" + side, 10)
	_notes_scroll.add_child(notes_margin)

	_notes = Label.new()
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	notes_margin.add_child(_notes)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 10)
	col.add_child(_progress)

	_progress_label = Label.new()
	_progress_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_progress_label.add_theme_font_size_override("font_size", 12)
	col.add_child(_progress_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)

	_later_btn = _make_button("Later", buttons)
	_later_btn.pressed.connect(_on_close)
	_cancel_btn = _make_button("Cancel", buttons)
	_cancel_btn.pressed.connect(_on_cancel_download)
	_release_btn = _make_button("Open Release Page", buttons)
	_release_btn.pressed.connect(_on_open_release)
	_download_btn = _make_button("Download Update", buttons)
	_download_btn.pressed.connect(_on_download)
	_install_btn = _make_button("Install & Restart", buttons)
	_install_btn.pressed.connect(_on_install)


func _make_button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	parent.add_child(b)
	return b


func _open() -> void:
	UiScale.popup_centered(self, Vector2i(460, 420))


# Human-readable byte count: 1536000 -> "1.5 MB".
func _fmt_bytes(n: int) -> String:
	var mb := float(n) / (1024.0 * 1024.0)
	if mb >= 1.0:
		return "%.1f MB" % mb
	return "%.0f KB" % (float(n) / 1024.0)
