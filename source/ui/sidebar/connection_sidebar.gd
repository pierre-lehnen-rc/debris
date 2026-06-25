class_name ConnectionSidebar
extends PanelContainer

## Left-hand panel: a tree of connections > databases > collections, fed from
## MockData for now. Double-clicking a collection asks the workspace to open a
## query tab targeting it.

signal collection_activated(connection: String, database: String, collection: String)

const META_TYPE := "type"  # "connection" | "database" | "collection"

var _tree: Tree


func _ready() -> void:
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 0)
	add_child(root_box)

	root_box.add_child(_build_header())

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.allow_rmb_select = true
	_tree.item_activated.connect(_on_item_activated)
	root_box.add_child(_tree)

	_populate()


func _build_header() -> Control:
	var header := PanelContainer.new()
	var sb := AppTheme._flat(AppTheme.BG_DARKEST, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	header.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	header.add_child(row)

	var title := Label.new()
	title.text = "CONNECTIONS"
	title.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "New connection"
	add_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(add_btn)

	return header


func _populate() -> void:
	_tree.clear()
	var root := _tree.create_item()

	for conn in MockData.CONNECTIONS:
		var conn_item := _tree.create_item(root)
		var dot := "●" if conn.get("connected", false) else "○"
		conn_item.set_text(0, "%s  %s" % [dot, conn["name"]])
		conn_item.set_tooltip_text(0, conn["host"])
		conn_item.set_custom_color(0, AppTheme.TEXT_BRIGHT)
		conn_item.set_metadata(0, {META_TYPE: "connection", "connection": conn["name"]})
		conn_item.set_collapsed(not conn.get("connected", false))

		for db in conn["databases"]:
			var db_item := _tree.create_item(conn_item)
			db_item.set_text(0, db["name"])
			db_item.set_custom_color(0, AppTheme.TEXT)
			db_item.set_metadata(0, {
				META_TYPE: "database",
				"connection": conn["name"],
				"database": db["name"],
			})
			db_item.set_collapsed(true)

			for coll in db["collections"]:
				var coll_item := _tree.create_item(db_item)
				coll_item.set_text(0, coll)
				coll_item.set_custom_color(0, AppTheme.TEXT_DIM)
				coll_item.set_metadata(0, {
					META_TYPE: "collection",
					"connection": conn["name"],
					"database": db["name"],
					"collection": coll,
				})


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta.is_empty():
		return
	match meta[META_TYPE]:
		"collection":
			collection_activated.emit(meta["connection"], meta["database"], meta["collection"])
		_:
			item.set_collapsed(not item.is_collapsed())
