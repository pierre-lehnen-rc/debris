class_name UpdateChecker
extends RefCounted

## Pure, network-free helpers behind the auto-updater: reading the running app's
## version, distilling a GitHub "latest release" payload into the fields the UI
## needs, picking the right download for this platform, and comparing semantic
## versions. Kept free of autoloads, HTTP, and the filesystem so it can be
## unit-tested in isolation (test/data/update_checker_test.gd). The live side —
## the network check, the download, and the in-place install — lives in the
## Updater autoload (source/data/updater.gd), which delegates every decision here.

## The GitHub repo releases are published to, and the API endpoint for the most
## recent non-draft, non-prerelease release.
const REPO := "pierre-lehnen-rc/debris"
const LATEST_RELEASE_URL := "https://api.github.com/repos/pierre-lehnen-rc/debris/releases/latest"


## The running app's version string (e.g. "0.1.5"), from project settings — the
## same source the About dialog reads, so it tracks the exported build.
static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()


## The release-asset filename this platform downloads. "" when no build is
## published for it (e.g. Windows), which makes the UI fall back to the web page.
static func asset_name_for(platform: String) -> String:
	match platform:
		"Linux":
			return "debris-linux.x86_64"
		"macOS":
			return "debris-mac.app.zip"
	return ""


## Extract a "MAJOR.MINOR.PATCH" version out of an arbitrary tag or release name
## — "releases/0.1.5", "v0.1.4", "0.1.5" all yield "0.1.5". "" if none is found.
static func extract_version(text: String) -> String:
	var re := RegEx.new()
	re.compile("(\\d+)\\.(\\d+)\\.(\\d+)")
	var m := re.search(text)
	return m.get_string() if m != null else ""


## Compare two dotted numeric versions component-by-component: -1 if a < b, 0 if
## equal, 1 if a > b. Comparison is numeric (so 0.1.10 > 0.1.9, not lexical), and
## missing trailing components count as 0 (so "0.1" == "0.1.0").
static func compare_versions(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	var n := maxi(pa.size(), pb.size())
	for i in n:
		var va: int = pa[i] if i < pa.size() else 0
		var vb: int = pb[i] if i < pb.size() else 0
		if va < vb:
			return -1
		if va > vb:
			return 1
	return 0


## True when `release_version` is strictly newer than `current`.
static func is_newer(release_version: String, current: String) -> bool:
	return compare_versions(release_version, current) > 0


## True when `path` is a macOS App Translocation mount — the read-only randomized
## copy macOS runs when a quarantined app is launched from an untrusted spot
## (typically Downloads). An app running from there can't replace itself: its
## executable path points at the throwaway copy, not the real bundle. Detecting
## this lets the updater tell the user to move the app to Applications instead of
## silently "updating" a copy that gets discarded.
static func is_translocated(path: String) -> bool:
	return path.contains("/AppTranslocation/")


## Find this platform's asset in a release's `assets` array (each entry a
## Dictionary with at least "name" and "browser_download_url"). Prefers an exact
## filename match, then falls back to the platform's suffix so a future rename
## doesn't silently break updates. Returns {} when nothing matches.
static func select_asset(assets: Array, platform: String) -> Dictionary:
	var want := asset_name_for(platform)
	if want.is_empty():
		return {}
	for a in assets:
		if str(a.get("name", "")) == want:
			return a
	var suffix := ""
	match platform:
		"Linux":
			suffix = ".x86_64"
		"macOS":
			suffix = ".app.zip"
	if not suffix.is_empty():
		for a in assets:
			if str(a.get("name", "")).ends_with(suffix):
				return a
	return {}


## Distill GitHub's /releases/latest JSON into the fields the updater UI needs,
## selecting the download for `platform`. Returns {} when the payload carries no
## readable version. `asset_url` is empty when no build exists for this platform
## (the UI then offers only the release page).
static func parse_release(json: Dictionary, platform: String) -> Dictionary:
	var version := extract_version(str(json.get("tag_name", "")))
	if version.is_empty():
		version = extract_version(str(json.get("name", "")))
	if version.is_empty():
		return {}
	var asset := select_asset(json.get("assets", []), platform)
	return {
		"version": version,
		"tag": str(json.get("tag_name", "")),
		"notes": str(json.get("body", "")).strip_edges(),
		"html_url": str(json.get("html_url", "")),
		"asset_name": str(asset.get("name", "")),
		"asset_url": str(asset.get("browser_download_url", "")),
		"asset_size": int(asset.get("size", 0)),
	}


# Split "0.1.10" -> [0, 1, 10]. int() reads the leading digits of each segment
# and yields 0 for non-numeric junk, so stray suffixes don't crash the compare.
static func _parts(v: String) -> Array:
	var out: Array = []
	for seg in v.split("."):
		out.append(int(seg))
	return out
