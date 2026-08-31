class_name UpdateCheckerTest
extends "res://test/test_suite.gd"

# Tests for UpdateChecker — the pure version/asset logic behind the auto-updater.
# See res://source/data/update_checker.gd


# Version extraction ----------------------------------------------------------
func test_extract_version_from_tag() -> void:
	assert_str(UpdateChecker.extract_version("releases/0.1.5")).is_equal("0.1.5")
	assert_str(UpdateChecker.extract_version("v0.1.4")).is_equal("0.1.4")
	assert_str(UpdateChecker.extract_version("0.2.10")).is_equal("0.2.10")


func test_extract_version_none() -> void:
	assert_str(UpdateChecker.extract_version("nightly")).is_equal("")
	assert_str(UpdateChecker.extract_version("")).is_equal("")


# Comparison ------------------------------------------------------------------
func test_compare_versions() -> void:
	assert_int(UpdateChecker.compare_versions("0.1.5", "0.1.4")).is_equal(1)
	assert_int(UpdateChecker.compare_versions("0.1.4", "0.1.5")).is_equal(-1)
	assert_int(UpdateChecker.compare_versions("0.1.5", "0.1.5")).is_equal(0)
	assert_int(UpdateChecker.compare_versions("0.2.0", "0.1.9")).is_equal(1)
	assert_int(UpdateChecker.compare_versions("1.0.0", "0.9.9")).is_equal(1)


func test_compare_versions_numeric_not_lexical() -> void:
	# 10 > 9 numerically, even though "10" < "9" as strings.
	assert_int(UpdateChecker.compare_versions("0.1.10", "0.1.9")).is_equal(1)


func test_compare_versions_missing_components() -> void:
	assert_int(UpdateChecker.compare_versions("0.1", "0.1.0")).is_equal(0)
	assert_int(UpdateChecker.compare_versions("1", "1.0.0")).is_equal(0)


func test_is_newer() -> void:
	assert_bool(UpdateChecker.is_newer("0.1.6", "0.1.5")).is_true()
	assert_bool(UpdateChecker.is_newer("0.1.5", "0.1.5")).is_false()
	assert_bool(UpdateChecker.is_newer("0.1.4", "0.1.5")).is_false()


# Translocation ---------------------------------------------------------------
func test_is_translocated() -> void:
	# The read-only copy macOS runs when launched from Downloads.
	assert_bool(UpdateChecker.is_translocated(
		"/private/var/folders/a9/abc123/AppTranslocation/E1B2-.../d/Debris.app/Contents/MacOS/Debris"
	)).is_true()
	# Real bundle locations are not translocated.
	assert_bool(UpdateChecker.is_translocated("/Applications/Debris.app/Contents/MacOS/Debris")).is_false()
	assert_bool(UpdateChecker.is_translocated("/Users/x/Downloads/Debris.app/Contents/MacOS/Debris")).is_false()


# Asset selection -------------------------------------------------------------
func _assets() -> Array:
	return [
		{"name": "debris-linux.x86_64", "browser_download_url": "http://x/lin", "size": 100},
		{"name": "debris-mac.app.zip", "browser_download_url": "http://x/mac", "size": 200},
	]


func test_select_asset_by_platform() -> void:
	assert_str(str(UpdateChecker.select_asset(_assets(), "Linux").get("browser_download_url"))) \
		.is_equal("http://x/lin")
	assert_str(str(UpdateChecker.select_asset(_assets(), "macOS").get("browser_download_url"))) \
		.is_equal("http://x/mac")


func test_select_asset_suffix_fallback() -> void:
	# Exact name changed, but the platform suffix still matches.
	var renamed := [{"name": "debris-linux-v2.x86_64", "browser_download_url": "http://x/lin2"}]
	assert_str(str(UpdateChecker.select_asset(renamed, "Linux").get("browser_download_url"))) \
		.is_equal("http://x/lin2")


func test_select_asset_none() -> void:
	assert_dict(UpdateChecker.select_asset(_assets(), "Windows")).is_empty()
	assert_dict(UpdateChecker.select_asset([], "Linux")).is_empty()


# Release parsing -------------------------------------------------------------
func test_parse_release() -> void:
	var json := {
		"tag_name": "releases/0.1.6",
		"name": "releases/0.1.6",
		"body": " changelog here \n",
		"html_url": "https://github.com/pierre-lehnen-rc/debris/releases/tag/releases/0.1.6",
		"assets": _assets(),
	}
	var info := UpdateChecker.parse_release(json, "Linux")
	assert_str(str(info.get("version"))).is_equal("0.1.6")
	assert_str(str(info.get("notes"))).is_equal("changelog here")
	assert_str(str(info.get("asset_name"))).is_equal("debris-linux.x86_64")
	assert_str(str(info.get("asset_url"))).is_equal("http://x/lin")
	assert_int(int(info.get("asset_size"))).is_equal(100)


func test_parse_release_unsupported_platform_has_no_asset() -> void:
	var json := {"tag_name": "releases/0.1.6", "assets": _assets()}
	var info := UpdateChecker.parse_release(json, "Windows")
	assert_str(str(info.get("version"))).is_equal("0.1.6")
	assert_str(str(info.get("asset_url"))).is_equal("")


func test_parse_release_no_version() -> void:
	assert_dict(UpdateChecker.parse_release({"tag_name": "nightly", "name": "nightly"}, "Linux")) \
		.is_empty()
