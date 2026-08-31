extends "res://dev/shot_base.gd"

## docs/screenshots/api.png — the Endpoints view: the endpoint sidebar built from
## the workspace's OpenAPI spec, a query tab from the same project's database next
## to an endpoint tab, and the workspace status line under the sidebar.
##
## The endpoint tab is opened with params already filled (the same restore path the
## .debris-workspace sidecar uses when reopening a project) and then sent, so the
## screenshot shows a request and its response rather than an empty form.

const ENDPOINT := "users.info"
## Restore state in EndpointTab.to_state()'s shape: which user is selected, and
## the form values. User 1 is the first of the project's configured users.
const REQUEST := {
	"kind": "endpoint",
	"endpoint_id": ENDPOINT,
	"user_id": 1,
	"raw": false,
	"form": {"query": "{ \"username\": \"rocket.cat\" }"},
	"json_text": "",
}


func _run() -> void:
	var doc := demo_doc()
	var proj = await open_project(doc)
	proj.select_view(1)  # Endpoints
	var center = find_one(proj, "WorkspaceCenter")

	# A database tab alongside the API one: the two halves of the project sharing a
	# center strip is the point of the view.
	center.open_collection(doc.mongo_connection(), doc.mongo_database(), "users")
	# The sidebar fetches and parses the workspace's OpenAPI document (a real
	# captured spec, ~350 endpoints), which takes longer than a mocked round trip.
	await settle(1.5)

	var sidebar = find_one(proj, "EndpointSidebar")
	var endpoint = endpoint_by_id(sidebar, ENDPOINT)
	if endpoint == null:
		return
	center.open_endpoint(endpoint, REQUEST)
	await frames(3)
	proj.run_current_tab()
	await settle()

	await shoot("api.png")
