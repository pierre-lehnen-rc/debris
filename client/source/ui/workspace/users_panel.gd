class_name UsersPanel
extends PanelContainer

## The Users sidebar view of a project's API. The sole place users are managed:
## Add User and the ✕ remove button add/remove any user, and those changes are
## persisted to the project file (ProjectTab observes the session's `changed`).
## Token-auth users carry a permanent access token (shown, no button); password-
## auth users get a Login/Logout button — Login exchanges their password for a
## temporary token kept in the session only (never saved), Logout discards it.

signal status_changed(text: String)

const SESSION_USER_DIALOG := preload("res://source/ui/dialogs/session_user_dialog.tscn")

@onready var _header: PanelContainer = %Header
@onready var _title: Label = %Title
@onready var _list: VBoxContainer = %List
@onready var _empty: Label = %Empty
# Typed as PanelContainer, not by the widget's class name: naming it would make
# this script compile-time-dependent on a script that reaches for an autoload,
# which the isolated-compile checks (dev/check.sh, `-s` harness scripts) can't
# resolve. See client/dev/README.md.
@onready var _footer: PanelContainer = %Footer

var _session: WorkspaceSession = null
var _dialog: SessionUserDialog = null


func _ready() -> void:
	_apply_style()


func configure(session: WorkspaceSession) -> void:
	_session = session
	if is_node_ready():
		# The users listed here belong to this workspace, so the footer reports
		# whether it's up — logging in against a workspace that's down is the
		# confusing case this answers. Set before the early return below: a
		# re-configure carries a session that may point at a different URL.
		_footer.configure(session.workspace)
	if _session.changed.is_connected(_render):
		return
	_session.changed.connect(_render)
	if is_node_ready():
		_render()


func _apply_style() -> void:
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_header.add_theme_stylebox_override("panel", sb)
	_title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_title.add_theme_font_size_override("font_size", 11)
	_empty.add_theme_color_override("font_color", AppTheme.TEXT_DIM)


# Rendering -------------------------------------------------------------------
func _render() -> void:
	for child in _list.get_children():
		if child == _empty:
			continue  # the placeholder label lives in the list; keep it, just toggle it
		child.queue_free()
	var users: Array = _session.users() if _session != null else []
	_empty.visible = users.is_empty()
	for user in users:
		_list.add_child(_make_row(user))


func _make_row(user: Dictionary) -> Control:
	var id: int = user["id"]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", AppTheme._flat(AppTheme.BG_DARK, 4))

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	box.add_child(text)

	var name_label := Label.new()
	name_label.text = WorkspaceSession.display_label(user)
	name_label.add_theme_color_override("font_color", AppTheme.TEXT_BRIGHT)
	text.add_child(name_label)

	var status := Label.new()
	status.text = _status_text(user)
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override(
		"font_color", AppTheme.ACCENT_GREEN if _session.has_token(id) else AppTheme.TEXT_DIM
	)
	text.add_child(status)

	if _session.needs_login(id):
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		if _session.has_token(id):
			btn.text = "Logout"
			btn.pressed.connect(func() -> void: _on_logout(id))
		else:
			btn.text = "Login"
			btn.pressed.connect(func() -> void: _on_login(id, btn))
		box.add_child(btn)

	var remove := Button.new()
	remove.text = "✕"
	remove.tooltip_text = "Remove this user"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func() -> void: _session.remove_user(id))
	box.add_child(remove)

	return row


func _status_text(user: Dictionary) -> String:
	if user.get("auth", "token") == "token":
		return "Access token" if _session.has_token(user["id"]) else "No token"
	return "Logged in" if _session.has_token(user["id"]) else "Password — logged out"


# Actions ---------------------------------------------------------------------
func _on_login(id: int, btn: Button) -> void:
	btn.disabled = true
	btn.text = "…"
	var user := _session.find(id)
	status_changed.emit("Logging in %s…" % WorkspaceSession.display_label(user))
	var result: Dictionary = await _session.login(id)
	# Success emits `changed`, which re-renders (replacing this button); only touch
	# the button on failure, where no re-render happens.
	if not result.get("ok", false):
		btn.disabled = false
		btn.text = "Login"
		status_changed.emit("Login failed: %s" % result.get("error", "unknown error"))
	else:
		status_changed.emit("Logged in %s" % WorkspaceSession.display_label(user))


func _on_logout(id: int) -> void:
	var user := _session.find(id)
	_session.logout(id)
	status_changed.emit("Logged out %s" % WorkspaceSession.display_label(user))


func _on_add_user() -> void:
	if _dialog == null:
		_dialog = SESSION_USER_DIALOG.instantiate()
		add_child(_dialog)
		_dialog.submitted.connect(_on_user_submitted)
	_dialog.open()


func _on_user_submitted(entry: Dictionary) -> void:
	_session.add_user(entry)
	status_changed.emit("Added user '%s'" % WorkspaceSession.display_label(entry))
