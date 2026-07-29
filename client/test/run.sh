#!/usr/bin/env bash
# Run the unit test suites headless.
#
#   test/run.sh                          # every *_test.gd under test/
#   test/run.sh test/data                # a folder
#   test/run.sh test/data/lax_json_test.gd   # one suite
#
# Suites extend test/test_suite.gd and are driven by test/runner.gd. The project
# boots with DEBRIS_HEADLESS=1 so ServerManager stays quiet and Backend/
# RocketChat answer from the dev mocks. Exit code is 0 only if all tests pass.
#
# Override the engine with:  GODOT=/path/to/godot test/run.sh
set -u

GODOT="${GODOT:-/home/pierre/Apps/Godot_v4.7.1-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEBRIS_HEADLESS=1 "$GODOT" --headless --path "$PROJECT" \
	-s res://test/runner.gd -- "$@"
