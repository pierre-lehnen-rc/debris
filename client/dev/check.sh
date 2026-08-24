#!/usr/bin/env bash
# Parse/compile-check one or more GDScript files — fast feedback before running
# anything heavier. Exits non-zero if any script has a real compile error.
#
#   dev/check.sh source/classes/openapi_parser.gd
#   dev/check.sh source/data/*.gd
#
# NOTE: Godot's --check-only compiles each file in isolation, so it does NOT know
# the autoload globals (Backend, RocketChat, ActivityLog, ServerManager). A file
# that references one can't be fully checked this way — it's reported SKIP, and
# should be validated by booting it through dev/harness.sh instead.
#
# Override the engine with:  GODOT=/path/to/godot dev/check.sh <script>
set -u

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOLOADS='Identifier not found: (Backend|RocketChat|ActivityLog|ServerManager)'

[ "$#" -ge 1 ] || { echo "usage: dev/check.sh <script.gd> [more.gd ...]" >&2; exit 2; }

status=0
for TARGET in "$@"; do
	case "$TARGET" in
		res://*) RES="$TARGET" ;;
		/*)      RES="res://${TARGET#"$PROJECT/"}" ;;
		*)       RES="res://$TARGET" ;;
	esac

	# --check-only exits 0 even on compile errors and always prints a banner, so
	# detect failures from the error text, not the exit code.
	raw="$(DEBRIS_HEADLESS=1 "$GODOT" --headless --path "$PROJECT" --check-only -s "$RES" 2>&1 \
		| sed 's/\x1b\[[0-9;]*m//g')"
	errs="$(printf '%s\n' "$raw" | grep -E 'SCRIPT ERROR|Compile Error|Parse Error|ERROR:' || true)"
	if [ -z "$errs" ]; then
		echo "OK   $RES"
		continue
	fi

	# Real errors are anything that isn't the autoload false-positive or its
	# cascade (Compilation failed / Failed to load script).
	real="$(printf '%s\n' "$errs" \
		| grep -vE "$AUTOLOADS" \
		| grep -vE 'Failed to load script|Compilation failed' || true)"
	if [ -z "$real" ]; then
		echo "SKIP $RES (references an autoload — validate via dev/harness.sh)"
		continue
	fi

	echo "FAIL $RES"
	printf '%s\n' "$errs" | head -20
	status=1
done
exit "$status"
