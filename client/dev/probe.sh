#!/usr/bin/env bash
# Run a throwaway SceneTree probe script headless and stream its output.
#
#   dev/probe.sh dev/checks/_probe.gd
#
# Same boot as the rest of dev/ (DEBRIS_HEADLESS: ServerManager silent, the
# Backend/RocketChat mocks active), so a probe can inspect real behavior of the
# logic or the mocked clients. The script must `extends SceneTree` and call
# quit() when done. For exploratory use only — real assertions belong in a
# dev/checks/ harness check or a test/ suite.
#
# Override the engine with:  GODOT=/path/to/godot dev/probe.sh <script>
set -u

GODOT="${GODOT:-/home/pierre/Apps/Godot_v4.7.1-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECK="${1:?usage: dev/probe.sh <script.gd>}"
case "$CHECK" in
	res://*) RES="$CHECK" ;;
	/*)      RES="res://${CHECK#"$PROJECT/"}" ;;
	*)       RES="res://$CHECK" ;;
esac

DEBRIS_HEADLESS=1 "$GODOT" --headless --path "$PROJECT" -s "$RES" 2>&1 \
	| sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^Godot Engine v|^$'
exit "${PIPESTATUS[0]}"
