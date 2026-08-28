#!/usr/bin/env bash
# Reimport the project's resources, registering any newly added class_name scripts
# (and their .uid files) in .godot/. Needed after adding a script with a global
# class name while the editor is closed — otherwise the harness and the test runner
# fail to resolve the new class.
#
#   dev/import.sh
#
# Override the engine with:  GODOT=/path/to/godot dev/import.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$GODOT" --headless --path "$PROJECT" --import 2>&1 \
	| sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^Godot Engine v|^$'
exit "${PIPESTATUS[0]}"
