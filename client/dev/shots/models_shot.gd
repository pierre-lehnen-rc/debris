extends "res://dev/shot_base.gd"

## docs/screenshots/models.png — the Server Models view: the model tree with one
## model's functions expanded, a function tab showing what the bridge returned,
## and the two footer lines (the workspace, and the bridge injected into it).
##
## The functions come the way the tree gets them for real: expanding a model asks
## the host, which calls the bridge through the Debris server and hands the list
## back — here answered by dev/mocks/backend's model-methods fixture.

const MODEL := "Users"
const METHOD := "find"
const SIGNATURE := "(query: Filter<T>, options?: O) => FindCursor<T>"


func _run() -> void:
	var doc := demo_doc()
	var proj = await open_project(doc)
	proj.select_view(3)  # Server Models
	# The bridge is injected on project open; the model list arrives with it.
	await settle()

	var sidebar = find_one(proj, "RcModelsSidebar")
	sidebar.functions_requested.emit(MODEL)
	await settle()
	# The model's own methods, as opposed to the ones it inherits from IBaseModel.
	expand_rows(sidebar, ["others"])

	var center = find_one(proj, "WorkspaceCenter")
	center.open_rcmodels(MODEL, METHOD, "users", SIGNATURE)
	await frames(3)
	proj.run_current_tab()
	await settle()

	await shoot("models.png")
