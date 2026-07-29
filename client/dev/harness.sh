#!/usr/bin/env bash
# Run a headless validation check.
#
#   dev/harness.sh dev/checks/mock_smoke_check.gd
#   dev/harness.sh res://dev/checks/mock_smoke_check.gd
#
# The check script must extend res://dev/check_base.gd. The project boots with
# DEBRIS_HEADLESS=1, so ServerManager stays quiet and Backend/RocketChat answer
# from the fixture mocks under dev/mocks/. Exit code is the check's (0 = pass).
#
# Override the engine with:  GODOT=/path/to/godot dev/harness.sh <check>
set -euo pipefail

GODOT="${GODOT:-/home/pierre/Apps/Godot_v4.7.1-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK="${1:?usage: dev/harness.sh <check-script.gd>}"
case "$CHECK" in
	res://*) RES="$CHECK" ;;
	/*)      RES="res://${CHECK#"$PROJECT/"}" ;;
	*)       RES="res://$CHECK" ;;
esac

DEBRIS_HEADLESS=1 exec "$GODOT" --headless --path "$PROJECT" -s "$RES"
