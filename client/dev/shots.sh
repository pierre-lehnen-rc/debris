#!/usr/bin/env bash
# Capture the README screenshots from the real UI.
#
#   dev/shots.sh                              # every shot under dev/shots/
#   dev/shots.sh dev/shots/database_shot.gd   # just one
#
# Each shot is a script extending dev/shot_base.gd: it boots the app, drives it
# into a known state and writes a PNG into docs/screenshots/. The boot is the same
# as the rest of dev/ (DEBRIS_HEADLESS: ServerManager silent, Backend/RocketChat
# answering from dev/mocks/) with two differences:
#
#   * A window. The engine can only read back a frame it has rendered, so these
#     need a display — unlike the checks, this is not a headless run. A window
#     opens for a second or two per shot; don't type into it.
#   * A throwaway HOME, so user:// is empty: no recent projects, no reopened tabs,
#     no preferences of whoever ran it. Together with the fixtures and a fixed
#     window size, that is what makes the images reproducible.
#
# Overrides:  GODOT=/path/to/godot   DEBRIS_SHOT_SIZE=1400x900
#             DEBRIS_SHOTS_DIR=/somewhere/else
set -uo pipefail

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$PROJECT/.." && pwd)"
OUT="${DEBRIS_SHOTS_DIR:-$REPO/docs/screenshots}"
SIZE="${DEBRIS_SHOT_SIZE:-1400x900}"

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
	echo "dev/shots.sh needs a display: the engine has to render the frames it captures." >&2
	exit 2
fi

shots=("$@")
if [[ ${#shots[@]} -eq 0 ]]; then
	while IFS= read -r file; do
		shots+=("$file")
	done < <(find "$PROJECT/dev/shots" -name '*_shot.gd' | sort)
fi
if [[ ${#shots[@]} -eq 0 ]]; then
	echo "no shots found under dev/shots/" >&2
	exit 2
fi

# X11 finds its cookie through HOME when XAUTHORITY is unset, so resolve it before
# the HOME below replaces it.
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
SHOT_HOME="$(mktemp -d "${TMPDIR:-/tmp}/debris-shots.XXXXXX")"
trap 'rm -rf "$SHOT_HOME"' EXIT

mkdir -p "$OUT"
status=0
for shot in "${shots[@]}"; do
	case "$shot" in
		res://*) RES="$shot" ;;
		/*)      RES="res://${shot#"$PROJECT/"}" ;;
		*)       RES="res://$shot" ;;
	esac
	HOME="$SHOT_HOME" DEBRIS_HEADLESS=1 DEBRIS_SHOTS_DIR="$OUT" DEBRIS_SHOT_SIZE="$SIZE" \
		"$GODOT" --path "$PROJECT" --resolution "$SIZE" -s "$RES" 2>&1 \
		| sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^Godot Engine v|^$'
	code="${PIPESTATUS[0]}"
	if [[ "$code" -ne 0 ]]; then
		status="$code"
	fi
done
exit "$status"
