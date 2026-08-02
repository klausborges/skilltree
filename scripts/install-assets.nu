#!/usr/bin/env nu

use install-assets/catalog.nu [install-map valid-kinds valid-targets]
use install-assets/engine.nu [
  build-actions
  configured-install-roots
  confirm-replacements
  report-actions
  tracked-assets
  write-actions
]

const repo_root = (path self .. | path expand)

def main [
  --kind: string
  --target: string
  --dry-run
  --force
] {
  let valid_kinds = (valid-kinds)
  let valid_targets = (valid-targets)

  if $kind == null {
    error make {msg: $"--kind is required; expected one of: ($valid_kinds | str join ', ')"}
  }
  if $kind not-in $valid_kinds {
    error make {msg: $"invalid --kind '($kind)'; expected one of: ($valid_kinds | str join ', ')"}
  }
  if $target != null and $kind != "all" {
    error make {msg: "--target is accepted only with --kind all"}
  }
  if $target != null and $target not-in $valid_targets {
    error make {msg: $"invalid --target '($target)'; expected one of: ($valid_targets | str join ', ')"}
  }
  if $env.HOME? == null {
    error make {msg: "HOME is required to build fixed install destinations"}
  }

  let home = try {
    $env.HOME | path expand --strict
  } catch {
    error make {msg: $"HOME is missing or cannot be resolved: ($env.HOME)"}
  }
  if ($home | path type) != "dir" {
    error make {msg: $"HOME is not a directory: ($home)"}
  }

  let all_mappings = (install-map $home)
  let selected_mappings = if $target != null {
    $all_mappings | where {|mapping| $mapping.harness == $target }
  } else if $kind == "all" {
    $all_mappings
  } else {
    $all_mappings | where {|mapping| $mapping.kind == $kind }
  }

  let tracked = (tracked-assets $repo_root)
  let install_roots = (configured-install-roots $all_mappings)
  let actions = (build-actions $repo_root $selected_mappings $tracked $install_roots)

  report-actions $actions
  if $dry_run {
    return
  }

  confirm-replacements $actions $force
  write-actions $actions
}
