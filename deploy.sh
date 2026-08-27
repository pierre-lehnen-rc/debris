#!/usr/bin/env bash
# Build the distributable Debris artifacts for a GitHub release.
#
# Steps: refresh the server bundle that gets packed into the app, then export the
# Linux and macOS builds — named exactly as the release assets the auto-updater
# looks for (debris-linux.x86_64 / debris-mac.app.zip). Both land in
# client/export/release/; upload those two files to the releases/<version>
# GitHub release yourself.
#
# The version is read from client/project.godot (config/version) — bump and
# commit it there before running, as usual. This script does not tag or publish.
#
#   ./deploy.sh
#   GODOT=/path/to/godot ./deploy.sh     # override the engine binary
#
# Requires: the matching Godot export templates installed, yarn (for the server
# bundle), and — for the macOS export's ad-hoc signing on Linux — nothing extra;
# Godot signs it built-in. The macOS .app is delivered zipped because a GitHub
# release asset must be a single file, and the updater unpacks the zip anyway.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT="$ROOT/client"
SERVER="$ROOT/server"
GODOT="${GODOT:-godot}"
OUT="$CLIENT/export/release"

LINUX_OUT="$OUT/debris-linux.x86_64"
MAC_OUT="$OUT/debris-mac.app.zip"

command -v "$GODOT" >/dev/null 2>&1 || { echo "ERROR: '$GODOT' not found (set GODOT=...)" >&2; exit 1; }

VERSION="$(grep -oP 'config/version="\K[^"]+' "$CLIENT/project.godot")"
echo "Debris $VERSION — building release artifacts"
echo

# 1. Refresh the bundled server, so the exported app ships the current backend.
echo "==> Bundling server (yarn bundle)"
( cd "$SERVER" && yarn bundle )
echo

# Godot needs the project imported once (the .godot cache is gitignored, so a
# fresh clone won't have it). Cheap to guard; skips when already present.
if [ ! -d "$CLIENT/.godot" ]; then
	echo "==> Importing project (first run)"
	"$GODOT" --headless --path "$CLIENT" --import
	echo
fi

# 2. Export both platforms. Godot writes the macOS .app straight into the .zip
#    because the output path ends in .zip (preserving bundle symlinks/perms).
mkdir -p "$OUT"
rm -f "$LINUX_OUT" "$MAC_OUT"

echo "==> Exporting Linux"
"$GODOT" --headless --path "$CLIENT" --export-release "Linux" "$LINUX_OUT"
echo
echo "==> Exporting macOS"
"$GODOT" --headless --path "$CLIENT" --export-release "macOS" "$MAC_OUT"
echo

# 3. Verify: --export-release can exit 0 even when it didn't produce a usable
#    file, so check the artifacts directly instead of trusting the exit code.
fail=0
[ -s "$LINUX_OUT" ] || { echo "ERROR: Linux build was not produced" >&2; fail=1; }
if [ -s "$MAC_OUT" ]; then
	# The zip must actually contain the .app bundle.
	if ! unzip -l "$MAC_OUT" 2>/dev/null | grep -q '\.app/'; then
		echo "ERROR: $MAC_OUT does not contain a .app bundle" >&2
		fail=1
	fi
else
	echo "ERROR: macOS build was not produced" >&2
	fail=1
fi
[ "$fail" -eq 0 ] || exit 1

echo "Done. Attach these to the releases/$VERSION GitHub release:"
for f in "$LINUX_OUT" "$MAC_OUT"; do
	printf '  %s  (%s)\n' "$f" "$(du -h "$f" | cut -f1)"
done
