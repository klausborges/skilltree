export def tracked-assets [repo_root: path] {
  let result = (do { ^git -C $repo_root ls-files -- skills agents instructions } | complete)
  if $result.exit_code != 0 {
    error make {msg: $"failed to enumerate Git-tracked assets: ($result.stderr | str trim)"}
  }

  $result.stdout | lines | where {|line| not ($line | is-empty) } | sort
}

def is-within [candidate: string, root: string] {
  try {
    let ignored = ($candidate | path relative-to $root)
    true
  } catch {
    false
  }
}

def resolve-existing-prefix [candidate: string] {
  let lexical = ($candidate | path expand --no-symlink)
  let exact_type = ($lexical | path type | default null)
  mut current = $lexical
  mut suffix = []

  loop {
    let current_type = ($current | path type | default null)
    if $current_type != null {
      let current_path = $current
      let current_kind = $current_type
      let expanded = try {
        $current_path | path expand --strict
      } catch {
        if $current_kind == "symlink" {
          error make {msg: $"broken symlink in destination path: ($current_path)"}
        }
        error make {msg: $"could not resolve destination path: ($current_path)"}
      }

      let resolved_type = ($expanded | path type)
      if (not ($suffix | is-empty)) and $resolved_type != "dir" {
        error make {msg: $"type mismatch: destination parent is ($resolved_type), not a directory: ($current)"}
      }

      let resolved = ($suffix | reduce --fold $expanded {|part, parent|
        [$parent $part] | path join
      })

      return {
        lexical: $lexical
        resolved: ($resolved | path expand --no-symlink)
        exact_type: $exact_type
        through_symlink: (($resolved | path expand --no-symlink) != $lexical)
      }
    }

    let parent = ($current | path dirname)
    if $parent == $current {
      error make {msg: $"could not find an existing destination ancestor: ($lexical)"}
    }

    $suffix = ($suffix | prepend ($current | path basename))
    $current = $parent
  }
}

export def configured-install-roots [mappings: list<record>] {
  $mappings
    | where {|mapping| not $mapping.guidance }
    | get destination_root
    | uniq
    | each {|root| $root | path expand --no-symlink }
}

def sources-for-mapping [mapping: record, tracked: list<string>] {
  let matches = if $mapping.source_exact != null {
    $tracked | where {|source| $source == $mapping.source_exact }
  } else {
    $tracked | where {|source|
      let prefix_matches = ($source | str starts-with $mapping.source_prefix)
      let extension_matches = ($mapping.extension == null or ($source | str ends-with $mapping.extension))
      let relative = ($source | str replace $mapping.source_prefix "")
      let depth_matches = ($mapping.relative_mode != "basename" or not ($relative | str contains "/"))
      $prefix_matches and $extension_matches and $depth_matches
    }
  }

  if ($matches | is-empty) {
    let source_description = if $mapping.source_exact != null {
      $mapping.source_exact
    } else {
      $"($mapping.source_prefix)*($mapping.extension | default '')"
    }
    error make {msg: $"no Git-tracked assets match configured source: ($source_description)"}
  }

  $matches | sort
}

def destination-relative [mapping: record, source: string] {
  if $mapping.relative_mode == "preserve" {
    $source | str replace $mapping.source_prefix ""
  } else {
    $source | path basename
  }
}

def preflight-file [
  repo_root: path
  mapping: record
  source_relative: string
  install_roots: list<string>
] {
  let source = ([$repo_root $source_relative] | path join)
  let source_type = ($source | path type | default null)
  if $source_type != "file" {
    error make {msg: $"tracked source is missing or not a regular file: ($source_relative); type=($source_type | default 'missing')"}
  }

  let content = (open --raw $source)
  if $mapping.guidance {
    return {
      status: "guidance"
      source: $source
      source_relative: $source_relative
      content: $content
      destination: null
      resolved: null
      through_symlink: false
    }
  }

  let relative = (destination-relative $mapping $source_relative)
  let destination = ([$mapping.destination_root $relative] | path join | path expand --no-symlink)
  let resolved = (resolve-existing-prefix $destination)

  if (is-within $resolved.resolved $repo_root) {
    error make {msg: $"destination resolves into the source repo: ($destination) -> ($resolved.resolved)"}
  }

  if not ($install_roots | any {|root| is-within $resolved.resolved $root }) {
    error make {msg: $"destination resolves outside configured install roots: ($destination) -> ($resolved.resolved)"}
  }

  let status = if $resolved.exact_type == null {
    "create"
  } else {
    let target_type = ($resolved.resolved | path type)
    if $target_type != "file" {
      error make {msg: $"type mismatch: tracked file would target ($target_type), not a file: ($destination)"}
    }

    if (open --raw $resolved.resolved) == $content {
      "unchanged"
    } else {
      "replace"
    }
  }

  {
    status: $status
    source: $source
    source_relative: $source_relative
    content: $content
    destination: $destination
    resolved: $resolved.resolved
    through_symlink: $resolved.through_symlink
  }
}

def validate-collisions [actions: list<record>] {
  mut seen = []
  for action in ($actions | where {|item| $item.status not-in ["guidance" "excluded"] }) {
    let previous = ($seen | where {|item| $item.resolved == $action.resolved })
    if not ($previous | is-empty) {
      let other = ($previous | first)
      if $other.source_relative != $action.source_relative {
        error make {msg: $"multiple tracked sources resolve to one destination: ($other.source_relative), ($action.source_relative) -> ($action.resolved)"}
      }
    } else {
      $seen = ($seen | append $action)
    }
  }
}

export def build-actions [
  repo_root: path
  mappings: list<record>
  tracked: list<string>
  install_roots: list<string>
] {
  mut actions = []
  for mapping in $mappings {
    let excluded_prefixes = ($mapping.exclude_prefixes? | default [])
    for source in (sources-for-mapping $mapping $tracked) {
      let held_back = ($excluded_prefixes | where {|prefix| $source | str starts-with $prefix } | first | default null)
      if $held_back != null {
        $actions = ($actions | append {
          status: "excluded"
          excluded_prefix: $held_back
          source: ([$repo_root $source] | path join)
          source_relative: $source
          content: null
          destination: null
          resolved: null
          through_symlink: false
        })
      } else {
        $actions = ($actions | append (preflight-file $repo_root $mapping $source $install_roots))
      }
    }
  }

  validate-collisions $actions
  $actions
}

export def report-actions [actions: list<record>] {
  # One line per held-back prefix rather than per file per target, so a single
  # excluded skill does not bury the rest of the run.
  let excluded = ($actions | where {|item| $item.status == "excluded" })
  for prefix in ($excluded | get excluded_prefix | uniq | sort) {
    let files = ($excluded | where {|item| $item.excluded_prefix == $prefix } | get source_relative | uniq | length)
    print $"excluded ($prefix) -> held back by catalog, ($files) files not installed"
  }

  for action in ($actions | where {|item| $item.status != "excluded" }) {
    if $action.status == "guidance" {
      print $"guidance ($action.source_relative) -> manual project-root instructions only"
    } else {
      let resolution = if $action.through_symlink {
        $" resolved: ($action.resolved)"
      } else {
        ""
      }
      print $"($action.status) ($action.source_relative) -> ($action.destination)($resolution)"
    }
  }
}

export def confirm-replacements [actions: list<record>, force: bool] {
  if $force or not ($actions | any {|action| $action.status == "replace" }) {
    return
  }

  if not (is-terminal --stdin) {
    error make {msg: "non-interactive overwrite refused; rerun with --force after reviewing --dry-run output"}
  }

  let answer = (input "Replace existing changed files for this run? [y/N] " | str trim | str lowercase)
  if $answer not-in ["y" "yes"] {
    error make {msg: "installation cancelled; no files were changed"}
  }
}

export def write-actions [actions: list<record>] {
  mut written = []
  for action in ($actions | where {|item| $item.status in ["create" "replace"] }) {
    if not ($written | any {|destination| $destination == $action.resolved }) {
      mkdir ($action.resolved | path dirname)
      $action.content | save --raw --force $action.resolved
      $written = ($written | append $action.resolved)
    }
  }
}
