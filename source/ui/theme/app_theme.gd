class_name AppTheme
extends RefCounted

## Programmatic dark theme for the app. Build once at startup and assign to the
## root Control's `theme` so every child inherits it. Tweak the palette below to
## restyle the whole app; this can later be replaced by a hand-authored .tres.

# Palette ---------------------------------------------------------------------
const BG_DARKEST := Color("#1b1d23")   # window background
const BG_DARK := Color("#22252c")      # panels
const BG_PANEL := Color("#282c34")     # raised panels / editor
const BG_HOVER := Color("#323742")
const BG_PRESSED := Color("#3a4250")
const BG_SELECTED := Color("#3b4252")
const BORDER := Color("#11131a")
const ACCENT := Color("#4f9cf0")       # selection / highlight
const ACCENT_GREEN := Color("#7fb86b") # run button / strings
const TEXT := Color("#c7ccd6")
const TEXT_DIM := Color("#8b919e")
const TEXT_BRIGHT := Color("#e8ebf0")

static var _cached: Theme

## Returns a single shared theme instance, built on first use. Use this for the
## root Control and every dialog so the whole app shares one palette.
static func shared() -> Theme:
	if _cached == null:
		_cached = build()
	return _cached


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14

	_style_panels(theme)
	_style_labels(theme)
	_style_buttons(theme)
	_style_tree(theme)
	_style_tabs(theme)
	_style_text_edits(theme)
	_style_line_edit(theme)
	_style_option_button(theme)
	_style_popup(theme)
	_style_splits(theme)
	_style_scrollbars(theme)
	_style_window(theme)
	_style_misc(theme)
	return theme


static func _flat(bg: Color, radius := 4, border_w := 0, border := BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _flat(BG_DARK, 0))
	var pc := _flat(BG_DARK, 0)
	pc.content_margin_left = 0
	pc.content_margin_right = 0
	pc.content_margin_top = 0
	pc.content_margin_bottom = 0
	theme.set_stylebox("panel", "PanelContainer", pc)


static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)


static func _style_buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _flat(BG_PANEL, 4, 1))
	theme.set_stylebox("hover", "Button", _flat(BG_HOVER, 4, 1))
	theme.set_stylebox("pressed", "Button", _flat(BG_PRESSED, 4, 1, ACCENT))
	theme.set_stylebox("disabled", "Button", _flat(BG_DARK, 4, 1))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT_BRIGHT)
	theme.set_color("font_pressed_color", "Button", TEXT_BRIGHT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)


static func _style_tree(theme: Theme) -> void:
	theme.set_stylebox("panel", "Tree", _flat(BG_DARK, 0))
	theme.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	theme.set_color("font_color", "Tree", TEXT)
	theme.set_color("font_selected_color", "Tree", TEXT_BRIGHT)
	theme.set_color("guide_color", "Tree", Color(1, 1, 1, 0.04))
	var sel := _flat(BG_SELECTED, 3)
	theme.set_stylebox("selected", "Tree", sel)
	theme.set_stylebox("selected_focus", "Tree", _flat(BG_SELECTED.lightened(0.05), 3))
	theme.set_stylebox("hovered", "Tree", _flat(BG_HOVER, 3))
	theme.set_constant("v_separation", "Tree", 6)
	theme.set_constant("item_margin", "Tree", 16)


static func _style_tabs(theme: Theme) -> void:
	var selected := _flat(BG_PANEL, 0)
	selected.border_width_top = 2
	selected.border_color = ACCENT
	selected.content_margin_left = 12
	selected.content_margin_right = 12
	selected.content_margin_top = 6
	selected.content_margin_bottom = 6
	var unselected := _flat(BG_DARK, 0)
	unselected.content_margin_left = 12
	unselected.content_margin_right = 12
	unselected.content_margin_top = 6
	unselected.content_margin_bottom = 6
	theme.set_stylebox("tab_selected", "TabContainer", selected)
	theme.set_stylebox("tab_unselected", "TabContainer", unselected)
	theme.set_stylebox("tab_hovered", "TabContainer", _flat(BG_HOVER, 0))
	theme.set_stylebox("panel", "TabContainer", _flat(BG_PANEL, 0))
	theme.set_stylebox("tabbar_background", "TabContainer", _flat(BG_DARKEST, 0))
	theme.set_color("font_selected_color", "TabContainer", TEXT_BRIGHT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)

	# Mirror onto TabBar for standalone use.
	theme.set_stylebox("tab_selected", "TabBar", selected)
	theme.set_stylebox("tab_unselected", "TabBar", unselected)
	theme.set_color("font_selected_color", "TabBar", TEXT_BRIGHT)
	theme.set_color("font_unselected_color", "TabBar", TEXT_DIM)


static func _style_text_edits(theme: Theme) -> void:
	for type in ["TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type, _flat(BG_PANEL, 0))
		theme.set_stylebox("focus", type, _flat(BG_PANEL, 0, 1, ACCENT))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_readonly_color", type, TEXT_DIM)
		theme.set_color("caret_color", type, TEXT_BRIGHT)
		theme.set_color("selection_color", type, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))
		theme.set_color("current_line_color", type, Color(1, 1, 1, 0.03))


static func _style_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _flat(BG_PANEL, 4, 1))
	theme.set_stylebox("focus", "LineEdit", _flat(BG_PANEL, 4, 1, ACCENT))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", TEXT_BRIGHT)


static func _style_option_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "OptionButton", _flat(BG_PANEL, 4, 1))
	theme.set_stylebox("hover", "OptionButton", _flat(BG_HOVER, 4, 1))
	theme.set_stylebox("pressed", "OptionButton", _flat(BG_PRESSED, 4, 1, ACCENT))
	theme.set_color("font_color", "OptionButton", TEXT)


static func _style_popup(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu", _flat(BG_PANEL, 4, 1))
	theme.set_stylebox("hover", "PopupMenu", _flat(BG_HOVER, 3))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT_BRIGHT)
	theme.set_color("font_accelerator_color", "PopupMenu", TEXT_DIM)
	theme.set_constant("v_separation", "PopupMenu", 6)

	theme.set_color("font_color", "MenuBar", TEXT)
	theme.set_color("font_hover_color", "MenuBar", TEXT_BRIGHT)
	theme.set_stylebox("normal", "MenuBar", StyleBoxEmpty.new())
	theme.set_stylebox("hover", "MenuBar", _flat(BG_HOVER, 3))
	theme.set_stylebox("pressed", "MenuBar", _flat(BG_PRESSED, 3))


static func _style_splits(theme: Theme) -> void:
	for type in ["HSplitContainer", "VSplitContainer"]:
		theme.set_constant("separation", type, 6)
		var grabber := _flat(BORDER, 0)
		theme.set_stylebox("split_bar_background", type, grabber)


static func _style_scrollbars(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _flat(BG_DARKEST, 6))
		theme.set_stylebox("grabber", type, _flat(Color("#454b58"), 6))
		theme.set_stylebox("grabber_highlight", type, _flat(Color("#525a6a"), 6))
		theme.set_stylebox("grabber_pressed", type, _flat(ACCENT, 6))


static func _style_window(theme: Theme) -> void:
	# Embedded sub-windows (dialogs) draw a frame whose top content margin holds
	# the title; leave room for it so dialog content doesn't overlap the title.
	var border := _flat(BG_DARK, 6, 1)
	border.content_margin_left = 1
	border.content_margin_right = 1
	border.content_margin_bottom = 1
	border.content_margin_top = 34
	border.shadow_color = Color(0, 0, 0, 0.4)
	border.shadow_size = 8
	theme.set_stylebox("embedded_border", "Window", border)
	var unfocused: StyleBoxFlat = border.duplicate()
	unfocused.border_color = BORDER
	theme.set_stylebox("embedded_unfocused_border", "Window", unfocused)
	theme.set_color("title_color", "Window", TEXT_BRIGHT)
	theme.set_color("title_outline_modulate", "Window", BG_DARK)
	theme.set_constant("title_height", "Window", 30)
	theme.set_constant("resize_margin", "Window", 4)


static func _style_misc(theme: Theme) -> void:
	for type in ["CheckBox", "CheckButton"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, TEXT_BRIGHT)
		theme.set_color("font_pressed_color", type, TEXT_BRIGHT)
		theme.set_color("font_disabled_color", type, TEXT_DIM)
		theme.set_stylebox("normal", type, StyleBoxEmpty.new())
		theme.set_stylebox("hover", type, StyleBoxEmpty.new())
		theme.set_stylebox("pressed", type, StyleBoxEmpty.new())
	theme.set_color("font_color", "SpinBox", TEXT)
