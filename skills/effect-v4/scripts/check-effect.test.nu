#!/usr/bin/env nu

# Tests for check-effect.nu. Integration fixtures come from examples/fencecheck
# (exact-pinned known-good src/ and known-bad fixtures/); run `pnpm install`
# there first.

const test_dir = (path self | path dirname)
const runner = ($test_dir | path join "check-effect.nu")
const fencecheck = ($test_dir | path dirname | path dirname | path dirname
  | path join "examples" "fencecheck")

use ($test_dir | path join "check-effect.nu") [
  classify-tsgo classify-oxlint classify-astgrep
  ancestor-chain has-effect-dep resolve-tool
]

def check [condition: bool, message: string] {
  if not $condition {
    error make {msg: $message}
  }
}

def check-equal [actual: any, expected: any, message: string] {
  if $actual != $expected {
    error make {msg: $"($message): expected ($expected), got ($actual)"}
  }
}

def run-checker [target: path, arguments: list<string>] {
  do { "" | ^nu --no-config-file $runner $target ...$arguments } | complete
}

def gate-row [output: string, gate: string] {
  # The summary table renders one row per gate: │ gate │ status │ detail │
  $output | lines | where {|l| $l =~ $"│ ($gate)\\s" } | first
}

# --- unit: classifiers ------------------------------------------------------

def test-classify-tsgo [] {
  let clean = {stdout: "Checked 3 files out of 3 files. \n0 errors, 0 warnings and 0 messages.\n", stderr: "", exit_code: 0}
  check-equal (classify-tsgo $clean).status "ok" "tsgo clean run classifies ok"

  let findings = {stdout: "a.ts(1,1): error effect(floatingEffect): msg\nChecked 2 files out of 2 files. \n4 errors, 0 warnings and 0 messages.\n", stderr: "", exit_code: 1}
  let r = (classify-tsgo $findings)
  check-equal $r.status "findings" "tsgo errors classify as findings"
  check ($r.detail | str contains "4 errors") "tsgo findings detail carries the error count"

  # The false green: no working plugin config -> checked 0 files, exit 0.
  let green = {stdout: "Checked 0 files out of 1 files. \n0 errors, 0 warnings and 0 messages.\n", stderr: "", exit_code: 0}
  check-equal (classify-tsgo $green).status "setup-error" "checked 0 of N must never pass"

  let empty = {stdout: "Checked 0 files out of 0 files. \n0 errors, 0 warnings and 0 messages.\n", stderr: "", exit_code: 0}
  check-equal (classify-tsgo $empty).status "skipped" "tsconfig matching no files classifies skipped"

  let eacces = {stdout: "", stderr: "spawnSync .../tsgo-darwin-arm64/lib/tsc EACCES", exit_code: 1}
  let e = (classify-tsgo $eacces)
  check-equal $e.status "setup-error" "EACCES classifies setup-error"
  check ($e.detail | str contains "chmod") "EACCES detail carries the fix"

  let garbage = {stdout: "unexpected", stderr: "", exit_code: 2}
  check-equal (classify-tsgo $garbage).status "setup-error" "unrecognized output classifies setup-error"
}

def test-classify-oxlint [] {
  check-equal (classify-oxlint {stdout: "", stderr: "", exit_code: 0}).status "ok" "oxlint exit 0 classifies ok"

  let nofiles = {stdout: "No files found to lint. Please check your paths and ignore patterns.\n", stderr: "", exit_code: 1}
  check-equal (classify-oxlint $nofiles).status "skipped" "oxlint no-files exit 1 classifies skipped, not findings"

  let findings = {stdout: "a.ts:1:1: error eslint(no-restricted-imports): bad\nb.ts:2:2: warning eslint(x): meh\n", stderr: "", exit_code: 1}
  let r = (classify-oxlint $findings)
  check-equal $r.status "findings" "oxlint diagnostics classify as findings"
  check-equal $r.detail "1 errors, 1 warnings" "oxlint counts parsed from diagnostic lines"

  let spaced = {stdout: "src dir/known bad.ts:1:1: error eslint(x): bad\n", stderr: "", exit_code: 1}
  check-equal (classify-oxlint $spaced).status "findings" "diagnostic paths with spaces still count as findings"

  check-equal (classify-oxlint {stdout: "", stderr: "boom", exit_code: 2}).status "setup-error" "oxlint failure without diagnostics classifies setup-error"
}

def test-classify-astgrep [] {
  check-equal (classify-astgrep {stdout: "", stderr: "", exit_code: 0}).status "ok" "ast-grep exit 0 classifies ok"

  let findings = {stdout: "error[no-live-suffix]: bad\n  | context\nerror[no-v3-service-tag]: bad\n", stderr: "", exit_code: 1}
  let r = (classify-astgrep $findings)
  check-equal $r.status "findings" "ast-grep findings classify as findings"
  check-equal $r.detail "2 findings" "ast-grep finding count from rule lines only"

  check-equal (classify-astgrep {stdout: "", stderr: "bad sgconfig", exit_code: 2}).status "setup-error" "ast-grep failure without findings classifies setup-error"
}

# --- unit: project detection ------------------------------------------------

def test-project-detection [fixture_root: path] {
  let ws = ($fixture_root | path join "ws")
  let pkg = ($ws | path join "packages" "app")
  mkdir $pkg
  "lockfile" | save --force ($ws | path join "pnpm-lock.yaml")
  '{"devDependencies": {"effect": "4.0.0"}}' | save --force ($ws | path join "package.json")
  '{"name": "app"}' | save --force ($pkg | path join "package.json")

  let chain = (ancestor-chain $pkg)
  check-equal ($chain | last) $ws "ancestor chain stops at the lockfile root"
  check (has-effect-dep $chain) "effect dep at the workspace root is found from a member package"
  check (not (has-effect-dep [$pkg])) "member package alone has no effect dep"

  let bin = ($pkg | path join "node_modules" ".bin")
  mkdir $bin
  "#!/bin/sh" | save --force ($bin | path join "sometool")
  check-equal (resolve-tool "sometool" $chain) ($bin | path join "sometool") "tool resolves from a member .bin"
  check-equal (resolve-tool "missingtool" $chain) null "missing tool resolves to null without a PATH fallback"
  check ((resolve-tool "git" [$pkg] --from-path) != null) "--from-path falls back to PATH"
}

# --- integration: skip paths ------------------------------------------------

def test-skips [fixture_root: path] {
  let plain = ($fixture_root | path join "plain")
  mkdir $plain
  let res = (run-checker $plain [])
  check-equal $res.exit_code 0 "no package.json exits 0"
  check ($res.stdout | str contains "not a Node project") "no package.json reports not-a-Node-project"

  let node = ($fixture_root | path join "node-only")
  mkdir $node
  '{"dependencies": {"react": "19.0.0"}}' | save --force ($node | path join "package.json")
  "lockfile" | save --force ($node | path join "package-lock.json")
  let res = (run-checker $node [])
  check-equal $res.exit_code 0 "non-Effect project exits 0"
  check ($res.stdout | str contains "not an Effect project") "non-Effect project reports why it skipped"

  let broken = ($fixture_root | path join "broken-manifest")
  mkdir $broken
  "{ not json" | save --force ($broken | path join "package.json")
  let res = (run-checker $broken [])
  check-equal $res.exit_code 1 "unparseable package.json exits 1, never silently green"
  check ($res.stdout | str contains "not a parseable JSON record") "unparseable package.json reports the real problem"

  let list_manifest = ($fixture_root | path join "list-manifest")
  mkdir $list_manifest
  "[1, 2, 3]" | save --force ($list_manifest | path join "package.json")
  let res = (run-checker $list_manifest [])
  check-equal $res.exit_code 1 "non-record package.json exits 1 without a nushell crash"
  check ($res.stdout | str contains "not a parseable JSON record") "non-record package.json reports cleanly"
}

# --- integration: fencecheck ------------------------------------------------

def test-fencecheck-clean [] {
  let res = (run-checker $fencecheck ["src" "--tsconfig" "tsconfig.src-only.json"])
  if $res.exit_code != 0 {
    error make {msg: $"clean fencecheck run failed:\n($res.stdout)\n($res.stderr)"}
  }
  for gate in ["effect-tsgo" "oxlint" "ast-grep"] {
    check ((gate-row $res.stdout $gate) | str contains "ok") $"($gate) is ok on known-good src"
  }
}

def test-fencecheck-findings [] {
  # Known-bad fixtures, per-tool expected counts from the fencecheck README.
  let res = (run-checker $fencecheck ["src" "fixtures/oxlint"])
  check-equal $res.exit_code 1 "findings run exits 1"
  check ((gate-row $res.stdout "effect-tsgo") | str contains "5 errors") "tsgo reports the 5 known fixture errors"
  check ((gate-row $res.stdout "oxlint") | str contains "8 errors") "oxlint reports the 8 known fixture errors"
  check ((gate-row $res.stdout "ast-grep") | str contains "ok") "ast-grep is clean on src + oxlint fixtures"

  let res = (run-checker $fencecheck ["src" "fixtures/astgrep"])
  check-equal $res.exit_code 1 "ast-grep findings run exits 1"
  check ((gate-row $res.stdout "ast-grep") | str contains "6 findings") "ast-grep reports the 6 known fixture findings"
}

def main [] {
  if not ($fencecheck | path join "node_modules" | path exists) {
    error make {msg: $"missing ($fencecheck)/node_modules — run pnpm install in examples/fencecheck first"}
  }

  test-classify-tsgo
  test-classify-oxlint
  test-classify-astgrep

  let fixture_root = (^mktemp -d | str trim | path expand)
  try {
    test-project-detection $fixture_root
    test-skips $fixture_root
  } catch {|error|
    rm --recursive --force $fixture_root
    error make {msg: $error.msg}
  }
  rm --recursive --force $fixture_root

  test-fencecheck-clean
  test-fencecheck-findings

  print "check-effect tests passed"
}
