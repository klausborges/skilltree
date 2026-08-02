#!/usr/bin/env nu

# check-effect.nu — read-only Effect v4 preset checker.
#
# Runs three gates against a target project using the preset assets that live
# next to this script, never writing into the target:
#   1. effect-tsgo diagnostics, preset injected at runtime via --lspconfig
#   2. oxlint with assets/oxlintrc.json
#   3. ast-grep scan with assets/sgconfig.yml
#
# Usage: nu check-effect.nu <target-dir> [source-path ...] [--tsconfig <rel>]
#
# Exit 0: all gates ok or skipped (including "not an Effect project").
# Exit 1: findings or a setup error in any gate.

const script_dir = (path self | path dirname)
const assets_dir = ($script_dir | path dirname | path join "assets")

const workspace_markers = [
  "pnpm-workspace.yaml" "pnpm-lock.yaml" "package-lock.json"
  "yarn.lock" "bun.lock" "bun.lockb" "deno.lock"
]

def read-package-json [dir: path] {
  let pkg = ($dir | path join "package.json")
  if not ($pkg | path exists) { return null }
  let parsed = (try { open --raw $pkg | from json } catch { null })
  if ($parsed | describe | str starts-with "record") { $parsed } else { null }
}

def is-workspace-root [dir: path] {
  if ($workspace_markers | any {|m| $dir | path join $m | path exists }) {
    return true
  }
  let parsed = (read-package-json $dir)
  $parsed != null and ($parsed | get -o workspaces) != null
}

# Directories from the target upward, stopping at the workspace root (first
# dir with a lockfile or workspace manifest) or the filesystem root.
export def ancestor-chain [target: path] {
  mut chain = []
  mut dir = ($target | path expand)
  loop {
    $chain = ($chain | append $dir)
    if (is-workspace-root $dir) { break }
    let parent = ($dir | path dirname)
    if $parent == $dir { break }
    $dir = $parent
  }
  $chain
}

export def has-effect-dep [chain: list<string>] {
  $chain | any {|dir|
    let parsed = (read-package-json $dir)
    if $parsed == null {
      false
    } else {
      ["dependencies" "devDependencies" "peerDependencies" "optionalDependencies"] | any {|key|
        "effect" in ($parsed | get -o $key | default {} | columns)
      }
    }
  }
}

# Resolve a tool from the target's own install: <dir>/node_modules/.bin along
# the ancestor chain. Root .bin alone is not enough (pnpm/bun do not hoist
# workspace-package bins), hence the whole chain. `--from-path` adds a PATH
# fallback for standalone binaries like ast-grep.
export def resolve-tool [name: string, chain: list<string>, --from-path] {
  let hits = ($chain
    | each {|dir| $dir | path join "node_modules" ".bin" $name }
    | where {|p| $p | path exists })
  if ($hits | is-not-empty) { return ($hits | first) }
  if $from_path {
    # Aliases/custom commands can shadow the binary; only real executables run.
    let found = (which --all $name | where type == "external")
    if ($found | is-not-empty) { return ($found | first | get path) }
  }
  null
}

# First stderr line only: multi-line dumps (Go panics) wreck the summary table.
def first-line [text: string] {
  $text | str trim | lines | get -o 0 | default "" | str substring 0..200
}

# --- gate classification (pure; unit-tested) -------------------------------
# Each takes a `complete` record {stdout, stderr, exit_code} and returns
# {status, detail} with status: ok | findings | skipped | setup-error.
# Classification parses output rather than trusting raw exit codes: the three
# tools disagree (oxlint exits 1 on "no files", effect-tsgo exits 0 after
# checking nothing).

export def classify-tsgo [res: record] {
  let out = ($res.stdout + "\n" + $res.stderr)
  if ($out | str contains "EACCES") {
    return {status: "setup-error", detail: ("effect-tsgo platform binary lost its exec bit; run: "
      + "find <workspace>/node_modules/.pnpm -path '*tsgo-*/lib/tsc' -exec chmod +x {} +")}
  }
  if ($out | str contains "NativeBackendNotInstalled") {
    return {status: "setup-error", detail: "effect-tsgo found no TypeScript backend; the target needs typescript >= 7 installed"}
  }
  if ($out | str contains "PackagedBinaryVersionMismatch") {
    return {status: "setup-error", detail: "typescript version has no matching @effect/tsgo binary; pin typescript and @effect/tsgo as an exact pair"}
  }
  let checked = ($res.stdout | parse -r 'Checked (?<checked>\d+) files? out of (?<total>\d+) files?')
  if ($checked | is-empty) {
    return {status: "setup-error", detail: $"unrecognized diagnostics output \(exit ($res.exit_code)\)"}
  }
  let c = ($checked | first | get checked | into int)
  let t = ($checked | first | get total | into int)
  if $t == 0 { return {status: "skipped", detail: "tsconfig matched no files"} }
  if $c == 0 {
    # Without a working plugin config, diagnostics checks nothing and still
    # exits 0 — a silent false green. Never report it as a pass.
    return {status: "setup-error", detail: $"checked 0 of ($t) files — diagnostics did not run"}
  }
  if $res.exit_code == 0 {
    {status: "ok", detail: $"checked ($c) files"}
  } else {
    let counts = ($res.stdout | parse -r '(?<errors>\d+) errors?, (?<warnings>\d+) warnings?')
    let errors = (if ($counts | is-empty) { "?" } else { $counts | first | get errors })
    {status: "findings", detail: $"($errors) errors across ($c) files"}
  }
}

export def classify-oxlint [res: record] {
  let out = ($res.stdout + "\n" + $res.stderr)
  if ($out | str contains "No files found to lint") {
    return {status: "skipped", detail: "no lintable files in the given paths"}
  }
  if $res.exit_code == 0 { return {status: "ok", detail: "clean"} }
  # Piped (non-TTY) oxlint prints one line per diagnostic and no summary.
  # Unanchored: the leading path may contain spaces.
  let errors = ($out | lines | where {|l| $l =~ '\d+:\d+: error ' } | length)
  let warnings = ($out | lines | where {|l| $l =~ '\d+:\d+: warning ' } | length)
  if ($errors + $warnings) == 0 {
    return {status: "setup-error", detail: $"oxlint failed \(exit ($res.exit_code)\): (first-line $res.stderr)"}
  }
  {status: "findings", detail: $"($errors) errors, ($warnings) warnings"}
}

export def classify-astgrep [res: record] {
  if $res.exit_code == 0 { return {status: "ok", detail: "clean"} }
  let hits = ($res.stdout + "\n" + $res.stderr | lines
    | where {|line| $line =~ '^(error|warning|hint|info)\[' } | length)
  if $hits > 0 {
    {status: "findings", detail: $"($hits) findings"}
  } else {
    {status: "setup-error", detail: $"ast-grep failed \(exit ($res.exit_code)\): (first-line $res.stderr)"}
  }
}

# --- gate runners -----------------------------------------------------------

def run-tsgo-gate [target: path, tsconfig_rel: string, chain: list<string>] {
  let bin = (resolve-tool "effect-tsgo" $chain)
  if $bin == null {
    return {gate: "effect-tsgo", status: "skipped", detail: "effect-tsgo not installed in the target", output: ""}
  }
  let ts_path = ($target | path join $tsconfig_rel)
  if not ($ts_path | path exists) {
    return {gate: "effect-tsgo", status: "skipped", detail: $"no ($tsconfig_rel) in target", output: ""}
  }
  let lspconfig = (open ($assets_dir | path join "tsconfig-language-service.json")
    | get compilerOptions.plugins.0 | reject name | to json -r)
  # cwd must be the target: effect-tsgo resolves its TypeScript backend from
  # cwd, not from --project.
  # Known gap: on a syntactically broken tsconfig, effect-tsgo silently falls
  # back to default compilerOptions and reports ok; only oxlint's
  # tsconfig-error rule surfaces it.
  let res = (do { cd $target; ^$bin diagnostics --project $ts_path --format text --lspconfig $lspconfig } | complete)
  classify-tsgo $res | merge {gate: "effect-tsgo", output: ($res.stdout + $res.stderr)}
}

def run-oxlint-gate [target: path, paths: list<string>, chain: list<string>, tsconfig_rel: string] {
  let bin = (resolve-tool "oxlint" $chain)
  if $bin == null {
    return {gate: "oxlint", status: "skipped", detail: "oxlint not installed in the target", output: ""}
  }
  if ($paths | is-empty) {
    return {gate: "oxlint", status: "skipped", detail: "no source paths exist in the target", output: ""}
  }
  let config = ($assets_dir | path join "oxlintrc.json")
  # Point type-aware rules at the same tsconfig as the tsgo gate; `--` keeps a
  # dash-named path from becoming a flag (--fix would mutate the target).
  let ts_args = (if ($target | path join $tsconfig_rel | path exists) {
    ["--tsconfig" $tsconfig_rel]
  } else { [] })
  let res = (do { cd $target; ^$bin -c $config ...$ts_args -- ...$paths } | complete)
  classify-oxlint $res | merge {gate: "oxlint", output: ($res.stdout + $res.stderr)}
}

def run-astgrep-gate [target: path, paths: list<string>, chain: list<string>] {
  let bin = (resolve-tool "ast-grep" $chain --from-path)
  if $bin == null {
    return {gate: "ast-grep", status: "skipped", detail: "ast-grep not found in the target or on PATH", output: ""}
  }
  if ($paths | is-empty) {
    return {gate: "ast-grep", status: "skipped", detail: "no source paths exist in the target", output: ""}
  }
  let config = ($assets_dir | path join "sgconfig.yml")
  let res = (do { cd $target; ^$bin scan -c $config -- ...$paths } | complete)
  classify-astgrep $res | merge {gate: "ast-grep", output: ($res.stdout + $res.stderr)}
}

# --- entry point ------------------------------------------------------------

def main [
  target: path              # project directory to check
  ...paths: string          # lint-gate source paths relative to target (default: src); the tsgo gate is scoped by the tsconfig's include, not by these
  --tsconfig: string = "tsconfig.json"  # tsconfig path relative to target
] {
  let target = ($target | path expand)
  if ($target | path type) != "dir" {
    error make {msg: $"target is not a directory: ($target)"}
  }

  if not ($target | path join "package.json" | path exists) {
    print $"($target): no package.json — not a Node project; nothing to check"
    return
  }
  if (read-package-json $target) == null {
    print $"($target): package.json exists but is not a parseable JSON record"
    exit 1
  }

  let chain = (ancestor-chain $target)
  if not (has-effect-dep $chain) {
    print $"($target): no `effect` dependency in the target or its workspace root — not an Effect project; nothing to check"
    return
  }

  let requested = (if ($paths | is-empty) { ["src"] } else { $paths })
  let existing = ($requested | where {|p| $target | path join $p | path exists })
  let missing = ($requested | where {|p| not ($target | path join $p | path exists) })
  if ($missing | is-not-empty) {
    print $"note: skipping missing paths: ($missing | str join ', ')"
  }

  let results = [
    (run-tsgo-gate $target $tsconfig $chain)
    (run-oxlint-gate $target $existing $chain $tsconfig)
    (run-astgrep-gate $target $existing $chain)
  ]

  for r in ($results | where status in ["findings" "setup-error"]) {
    print $"--- ($r.gate) ---"
    print ($r.output | str trim)
  }
  print ($results | select gate status detail | table --index false)

  if ($results | any {|r| $r.status in ["findings" "setup-error"] }) {
    exit 1
  }
}
