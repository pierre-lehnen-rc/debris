# dev/ — headless validation kit

Tools for validating logic changes without a real backend or the editor. Two
layers, fastest first.

## 1. Compile check — `dev/check.sh`

Parse/type-check GDScript files in ~2s each. Catches typos and type errors
before running anything.

```bash
dev/check.sh source/classes/openapi_parser.gd
dev/check.sh source/data/*.gd
```

Per file it reports `OK`, `FAIL` (with the error), or `SKIP`. `SKIP` means the
file references an autoload (`Backend`, `RocketChat`, `ActivityLog`,
`ServerManager`) — Godot's `--check-only` compiles files in isolation and can't
see autoload globals, so those files must be validated by booting them through
the harness instead. Exit code is non-zero if any file really fails.

## 2. Behavior check — `dev/harness.sh`

Boots the project headless and runs a check script, so it exercises real code
(including autoloads) against mocked servers. Prints `PASS`/`FAIL` and exits
0/1.

```bash
dev/harness.sh dev/checks/mock_smoke_check.gd
```

A check extends [`check_base.gd`](check_base.gd), implements `_run()`, and uses
`expect(cond, msg)` / `expect_eq(actual, expected, msg)`. Reach the autoloads
through `backend` / `rocketchat` / `activity_log` (resolved at runtime — the
bare global names aren't available to a `-s` main-loop script). See
[`checks/mock_smoke_check.gd`](checks/mock_smoke_check.gd) for a worked example.

### Probing — `dev/probe.sh`

For exploratory checks of real behavior before writing assertions (what does
`_pluralize("Bus")` actually return? what shape does `build_structure` emit?),
run a throwaway `extends SceneTree` script that prints and quits:

```bash
dev/probe.sh dev/checks/_scratch.gd
```

Same headless+mocks boot as everything else. For exploration only — capture the
real output, then encode it as a `test/` assertion or a harness check.

## 3. Unit tests — `test/run.sh`

The logic-layer unit tests live under [`test/`](../test/) and run on the same
headless+mocks boot, without the GdUnit4 addon.

```bash
test/run.sh                          # every *_test.gd under test/
test/run.sh test/data                # a folder
test/run.sh test/data/lax_json_test.gd   # one suite
```

Suites extend [`test/test_suite.gd`](../test/test_suite.gd) — a small drop-in
`GdUnitTestSuite` replacement offering the assertion API (`assert_str(x)
.is_equal(y)`, `has_size`, `contains`, …), the `before_test`/`after_test`
lifecycle, `auto_free`, `create_temp_dir`, and `monitor_signals` /
`assert_signal`. [`test/runner.gd`](../test/runner.gd) discovers the suites,
runs each `test_*` method, and exits non-zero if anything fails (a suite that
fails to compile is reported and skipped rather than aborting the run).

## Mocks

The `dev/` scripts and `test/run.sh` all export `DEBRIS_HEADLESS=1`. On boot
with that set:

- `ServerManager` skips its startup entirely (no `/health`, no spawned server).
- `Backend._mock` and `RocketChat._mock` are set, so every request is answered
  from fixtures under [`mocks/`](mocks/) instead of the network — see
  [`mocks/backend_mock.gd`](mocks/backend_mock.gd) and
  [`mocks/rocketchat_mock.gd`](mocks/rocketchat_mock.gd).

The seam in production is tiny: a `_mock` field plus one guard at each client's
single request choke point (`Backend._do_post`, `RocketChat._do_request`).
Nothing changes when `_mock` is null (the normal app).

### Fixtures

- `mocks/backend/` — `databases.json`, `collections.json`, `indexes.json`,
  `explain.json`, and `find/<collection>.json` (dedicated: `users`, `rooms`,
  `subscriptions`) with `find/_generic.json` as the fallback for any other
  collection. Set a connection's `host` to `force-error` to exercise failures.
- `mocks/rocketchat/` — `openapi.json` (a real captured spec, drives the
  endpoint catalog), plus `endpoints/<path>.json` (e.g. `users.list.json`) with
  `endpoints/_generic.json` as the fallback. `login` returns canned credentials.

Add a dedicated fixture by dropping a JSON file at the right path — no code
change needed.

## Engine path

The scripts invoke `godot` from your `PATH`. Override with
`GODOT=/path/to/godot dev/harness.sh …` if your binary is named or located
differently.
