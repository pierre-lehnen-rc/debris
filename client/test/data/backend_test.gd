class_name BackendTest
extends "res://test/test_suite.gd"

# Tests for Backend.to_spec — the pure conversion from a stored connection config
# ("host:port" + optional auth) into the discrete spec the server expects.
# The rest of Backend is networking (covered via the dev mocks, not unit tests).
# See res://source/data/backend.gd

const BackendScript := preload("res://source/data/backend.gd")


func test_host_and_port_split() -> void:
	var spec := BackendScript.to_spec({"host": "localhost:27017"})
	assert_str(spec["host"]).is_equal("localhost")
	assert_int(spec["port"]).is_equal(27017)
	assert_bool(spec["directConnection"]).is_true()


func test_missing_port_defaults_to_27017() -> void:
	var spec := BackendScript.to_spec({"host": "db.example.com"})
	assert_str(spec["host"]).is_equal("db.example.com")
	assert_int(spec["port"]).is_equal(27017)


func test_zero_port_defaults_to_27017() -> void:
	assert_int(BackendScript.to_spec({"host": "h:0"})["port"]).is_equal(27017)


func test_non_numeric_port_defaults_to_27017() -> void:
	assert_int(BackendScript.to_spec({"host": "h:abc"})["port"]).is_equal(27017)


func test_empty_host() -> void:
	var spec := BackendScript.to_spec({})
	assert_str(spec["host"]).is_equal("")
	assert_int(spec["port"]).is_equal(27017)


func test_auth_disabled_omits_credentials() -> void:
	var spec := BackendScript.to_spec({"host": "h:1", "auth": {"enabled": false}})
	assert_bool(spec.has("username")).is_false()
	assert_bool(spec.has("authMechanism")).is_false()


func test_auth_enabled_carries_credentials() -> void:
	var spec := BackendScript.to_spec({
		"host": "h:1",
		"auth": {
			"enabled": true,
			"username": "admin",
			"password": "pw",
			"database": "records",
			"mechanism": "SCRAM-SHA-1",
		},
	})
	assert_str(spec["username"]).is_equal("admin")
	assert_str(spec["password"]).is_equal("pw")
	assert_str(spec["authSource"]).is_equal("records")
	assert_str(spec["authMechanism"]).is_equal("SCRAM-SHA-1")


func test_auth_enabled_uses_sensible_defaults() -> void:
	var spec := BackendScript.to_spec({"host": "h:1", "auth": {"enabled": true}})
	assert_str(spec["authSource"]).is_equal("admin")
	assert_str(spec["authMechanism"]).is_equal("SCRAM-SHA-256")
	assert_str(spec["username"]).is_equal("")


# _transport_error — how a request that never reached the Debris server is worded.
# Only a refused connection means the server isn't running; every other transport
# failure is a different fault and must not be reported as a stopped server.

func test_refused_connection_names_the_stopped_server() -> void:
	var backend: Node = auto_free(BackendScript.new())
	var message: String = backend._transport_error(HTTPRequest.RESULT_CANT_CONNECT)
	assert_str(message).contains("not running")
	assert_str(message).contains("Connect")


func test_unresolvable_host_keeps_the_generic_message() -> void:
	var backend: Node = auto_free(BackendScript.new())
	assert_str(backend._transport_error(HTTPRequest.RESULT_CANT_RESOLVE)).is_equal(
		"Cannot reach server at %s" % backend.base_url
	)


func test_timeout_keeps_the_generic_message() -> void:
	# A server that accepted the connection and then went quiet is there — saying
	# it isn't running would send the user to press Connect on a running server.
	var backend: Node = auto_free(BackendScript.new())
	assert_str(backend._transport_error(HTTPRequest.RESULT_TIMEOUT)).is_equal(
		"Cannot reach server at %s" % backend.base_url
	)
