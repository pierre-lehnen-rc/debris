extends "res://dev/shot_base.gd"

## docs/screenshots/database.png — the Collections view: the connection sidebar on
## the left, two query tabs open, the active one showing rocketchat.users in the
## results tree, and the server panel along the bottom of the sidebar.
##
## Query tabs run themselves when they open, so the results below are what the
## fixture backend actually returned (dev/mocks/backend/find/users.json).


func _run() -> void:
	var doc := demo_doc()
	var proj = await open_project(doc)
	proj.select_view(0)  # Collections
	# The sidebar lists the database's collections on its own; give it the round
	# trip before opening tabs over it.
	await settle()

	var center = find_one(proj, "WorkspaceCenter")
	center.open_collection(doc.mongo_connection(), doc.mongo_database(), "rooms")
	center.open_collection(doc.mongo_connection(), doc.mongo_database(), "users")
	await settle()

	stage_server_panel(proj)
	await shoot("database.png")
