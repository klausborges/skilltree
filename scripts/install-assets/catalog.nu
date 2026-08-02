export def valid-kinds [] {
  ["skills" "agents" "instructions" "all"]
}

export def valid-targets [] {
  ["claude-personal" "claude-work" "cursor" "codex" "droid" "opencode"]
}

# Tracked skills deliberately held back from every install target. The source
# stays version-controlled here; only the install is suppressed.
#
# - skills/fable-style/: premise predates Opus 5 and its self-verification and
#   delegation directives now push behavior the wrong way. Reworking under
#   plans/fable-style-opus-5-rework.md; re-enable by removing the entry.
def held-back-skills [] {
  ["skills/fable-style/"]
}

def skill-mappings [home: string] {
  [
    {
      kind: "skills"
      harness: "shared"
      source_prefix: "skills/"
      source_exact: null
      extension: null
      destination_root: ([$home ".agents" "skills"] | path join)
      relative_mode: "preserve"
      guidance: false
      exclude_prefixes: (held-back-skills)
    }
    {
      kind: "skills"
      harness: "claude-personal"
      source_prefix: "skills/"
      source_exact: null
      extension: null
      destination_root: ([$home ".claude-personal" "skills"] | path join)
      relative_mode: "preserve"
      guidance: false
      exclude_prefixes: (held-back-skills)
    }
    {
      kind: "skills"
      harness: "claude-work"
      source_prefix: "skills/"
      source_exact: null
      extension: null
      destination_root: ([$home ".claude-work" "skills"] | path join)
      relative_mode: "preserve"
      guidance: false
      exclude_prefixes: (held-back-skills)
    }
  ]
}

def agent-mappings [home: string] {
  [
    {
      kind: "agents"
      harness: "claude-personal"
      source_prefix: "agents/claude-personal/"
      source_exact: null
      extension: ".md"
      destination_root: ([$home ".claude-personal" "agents"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "agents"
      harness: "claude-work"
      source_prefix: "agents/claude-work/"
      source_exact: null
      extension: ".md"
      destination_root: ([$home ".claude-work" "agents"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "agents"
      harness: "cursor"
      source_prefix: "agents/cursor/"
      source_exact: null
      extension: ".md"
      destination_root: ([$home ".cursor" "agents"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "agents"
      harness: "codex"
      source_prefix: "agents/codex/"
      source_exact: null
      extension: ".toml"
      destination_root: ([$home ".codex" "agents"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "agents"
      harness: "droid"
      source_prefix: "agents/droid/"
      source_exact: null
      extension: ".md"
      destination_root: ([$home ".factory" "droids"] | path join)
      relative_mode: "basename"
      guidance: false
    }
  ]
}

def instruction-mappings [home: string] {
  [
    {
      kind: "instructions"
      harness: "claude-personal"
      source_prefix: null
      source_exact: "instructions/claude-personal/CLAUDE.md"
      extension: null
      destination_root: ([$home ".claude-personal"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "instructions"
      harness: "claude-work"
      source_prefix: null
      source_exact: "instructions/claude-work/CLAUDE.md"
      extension: null
      destination_root: ([$home ".claude-work"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "instructions"
      harness: "codex"
      source_prefix: null
      source_exact: "instructions/codex/AGENTS.md"
      extension: null
      destination_root: ([$home ".codex"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "instructions"
      harness: "droid"
      source_prefix: null
      source_exact: "instructions/droid/AGENTS.md"
      extension: null
      destination_root: ([$home ".factory"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "instructions"
      harness: "opencode"
      source_prefix: null
      source_exact: "instructions/opencode/AGENTS.md"
      extension: null
      destination_root: ([$home ".config" "opencode"] | path join)
      relative_mode: "basename"
      guidance: false
    }
    {
      kind: "instructions"
      harness: "cursor"
      source_prefix: null
      source_exact: "instructions/cursor/AGENTS.md"
      extension: null
      destination_root: null
      relative_mode: "basename"
      guidance: true
    }
  ]
}

export def install-map [home: string] {
  [
    ...(skill-mappings $home)
    ...(agent-mappings $home)
    ...(instruction-mappings $home)
  ]
}
