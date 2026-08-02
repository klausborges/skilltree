def test-cli-and-skills [fixture: record] {
  reset-home $fixture

  let missing_kind = (run-install $fixture ["--dry-run"])
  require-failure $missing_kind "missing --kind"
  check ($missing_kind.stderr | str contains "--kind is required") "missing kind should have a clear usage error"

  let invalid_filter = (run-install $fixture ["--kind" "skills" "--target" "claude-personal" "--dry-run"])
  require-failure $invalid_filter "non-all --target"
  check ($invalid_filter.stderr | str contains "--target is accepted only with --kind all") "invalid target filter should have a clear usage error"

  let invalid_target = (run-install $fixture ["--kind" "all" "--target" "unknown" "--dry-run"])
  require-failure $invalid_target "unknown --target"
  check ($invalid_target.stderr | str contains "invalid --target") "unknown target should have a clear usage error"

  write-file $fixture.repo "skills/alpha/SKILL.md" "modified tracked skill"
  write-file $fixture.repo "skills/alpha/private.txt" "untracked experiment"

  let dry_run = (run-install $fixture ["--kind" "skills" "--dry-run"])
  require-success $dry_run "skills dry-run"
  for root in [".agents/skills" ".claude-personal/skills" ".claude-work/skills"] {
    check ($dry_run.stdout | str contains ([$fixture.home $root "alpha" "SKILL.md"] | path join)) $"skills dry-run omitted ($root)"
  }
  check (not ($fixture.home | path join ".agents" | path exists)) "dry-run created a target directory"
  check (not ($dry_run.stdout | str contains "private.txt")) "dry-run included an untracked asset"

  let unknown = ([$fixture.home ".agents" "skills" "alpha" "mcp.json"] | path join)
  write-file $fixture.home ".agents/skills/alpha/mcp.json" "target only"
  write-file $fixture.home ".agents/skills/alpha/SKILL.md" "stale target"

  let changed_dry_run = (run-install $fixture ["--kind" "skills" "--dry-run"])
  require-success $changed_dry_run "changed-file dry-run"
  check ($changed_dry_run.stdout | str contains "replace") "changed-file dry-run did not report replacement"
  check-equal (open --raw ([$fixture.home ".agents" "skills" "alpha" "SKILL.md"] | path join)) "stale target" "changed-file dry-run overwrote its target"
  check (not ([$fixture.home ".claude-personal"] | path join | path exists)) "changed-file dry-run created another target root"

  let overlay = (run-install $fixture ["--kind" "skills" "--force"])
  require-success $overlay "forced skills overlay"
  for root in [".agents/skills" ".claude-personal/skills" ".claude-work/skills"] {
    let installed = ([$fixture.home $root "alpha" "SKILL.md"] | path join)
    check-equal (open --raw $installed) "modified tracked skill" $"tracked working-tree bytes were not installed to ($root)"
    check (not ([$fixture.home $root "alpha" "private.txt"] | path join | path exists)) $"untracked file installed to ($root)"
  }
  check-equal (open --raw $unknown) "target only" "overlay removed or changed a target-only file"
  check ($overlay.stdout | str contains "replace") "forced overlay did not report a replacement"

  let second = (run-install $fixture ["--kind" "skills" "--force"])
  require-success $second "idempotent skills run"
  check (not ($second.stdout | str contains "create ")) "second identical run reported a create"
  check (not ($second.stdout | str contains "replace ")) "second identical run reported a replacement"
  check ($second.stdout | str contains "unchanged") "second identical run did not report unchanged files"
}

def test-target-and-kind-expansion [fixture: record] {
  reset-home $fixture

  let targeted = (run-install $fixture ["--kind" "all" "--target" "claude-personal"])
  require-success $targeted "targeted all install"
  for relative in [
    ".claude-personal/skills/alpha/SKILL.md"
    ".claude-personal/agents/personal.md"
    ".claude-personal/CLAUDE.md"
  ] {
    check ([$fixture.home $relative] | path join | path exists) $"targeted install omitted ($relative)"
  }
  for relative in [
    ".agents"
    ".claude-work"
    ".cursor"
    ".codex"
    ".factory"
    ".config/opencode"
  ] {
    check (not ([$fixture.home $relative] | path join | path exists)) $"targeted install wrote outside claude-personal: ($relative)"
  }
  check (not ([$fixture.home ".claude-personal" "agents" "ignored.md"] | path join | path exists)) "targeted install included a nested agent outside the *.md map"

  let target_cases = [
    {
      target: "claude-work"
      expected: [
        ".claude-work/skills/alpha/SKILL.md"
        ".claude-work/agents/work.md"
        ".claude-work/CLAUDE.md"
      ]
      unexpected: [".agents" ".claude-personal" ".cursor" ".codex" ".factory" ".config/opencode"]
    }
    {
      target: "cursor"
      expected: [".cursor/agents/cursor.md"]
      unexpected: [".agents" ".claude-personal" ".claude-work" ".codex" ".factory" ".config/opencode" ".cursor/AGENTS.md"]
    }
    {
      target: "codex"
      expected: [".codex/agents/codex.toml" ".codex/AGENTS.md"]
      unexpected: [".agents" ".claude-personal" ".claude-work" ".cursor" ".factory" ".config/opencode"]
    }
    {
      target: "droid"
      expected: [".factory/droids/droid.md" ".factory/AGENTS.md"]
      unexpected: [".agents" ".claude-personal" ".claude-work" ".cursor" ".codex" ".config/opencode"]
    }
    {
      target: "opencode"
      expected: [".config/opencode/AGENTS.md"]
      unexpected: [".agents" ".claude-personal" ".claude-work" ".cursor" ".codex" ".factory"]
    }
  ]

  for target_case in $target_cases {
    reset-home $fixture
    let result = (run-install $fixture ["--kind" "all" "--target" $target_case.target])
    require-success $result $"targeted ($target_case.target) install"
    for relative in $target_case.expected {
      check ([$fixture.home $relative] | path join | path exists) $"target ($target_case.target) omitted ($relative)"
    }
    for relative in $target_case.unexpected {
      check (not ([$fixture.home $relative] | path join | path exists)) $"target ($target_case.target) wrote unexpected path ($relative)"
    }
    if $target_case.target == "cursor" {
      check ($result.stdout | str contains "guidance instructions/cursor/AGENTS.md") "targeted cursor run omitted instruction guidance"
    }
  }

  reset-home $fixture
  let agents = (run-install $fixture ["--kind" "agents" "--force"])
  require-success $agents "unfiltered agents install"
  for relative in [
    ".claude-personal/agents/personal.md"
    ".claude-work/agents/work.md"
    ".cursor/agents/cursor.md"
    ".codex/agents/codex.toml"
    ".factory/droids/droid.md"
  ] {
    check ([$fixture.home $relative] | path join | path exists) $"agents install omitted ($relative)"
  }
  check (not ([$fixture.home ".claude-personal" "CLAUDE.md"] | path join | path exists)) "agents install wrote parent instructions"

  reset-home $fixture
  let instructions = (run-install $fixture ["--kind" "instructions" "--force"])
  require-success $instructions "unfiltered instructions install"
  for relative in [
    ".claude-personal/CLAUDE.md"
    ".claude-work/CLAUDE.md"
    ".codex/AGENTS.md"
    ".factory/AGENTS.md"
    ".config/opencode/AGENTS.md"
  ] {
    check ([$fixture.home $relative] | path join | path exists) $"instructions install omitted ($relative)"
  }
  check ($instructions.stdout | str contains "guidance instructions/cursor/AGENTS.md") "cursor instructions were not reported as guidance"
  check (not ([$fixture.home ".cursor" "AGENTS.md"] | path join | path exists)) "cursor guidance was automatically installed"
}

def test-held-back-skills [fixture: record] {
  reset-home $fixture

  let dry_run = (run-install $fixture ["--kind" "skills" "--dry-run"])
  require-success $dry_run "held-back skills dry-run"
  check ($dry_run.stdout | str contains "excluded skills/fable-style/") "held-back skill was not reported as excluded"
  check ($dry_run.stdout | str contains "2 files not installed") "held-back report did not carry a file count"
  check-equal ($dry_run.stdout | lines | where {|line| $line | str starts-with "excluded " } | length) 1 "held-back skill reported more than one excluded line"

  let installed = (run-install $fixture ["--kind" "skills" "--force"])
  require-success $installed "held-back skills install"
  for root in [".agents/skills" ".claude-personal/skills" ".claude-work/skills"] {
    check (not ([$fixture.home $root "fable-style"] | path join | path exists)) $"held-back skill installed to ($root)"
    check ([$fixture.home $root "alpha" "SKILL.md"] | path join | path exists) $"exclusion suppressed an unrelated skill in ($root)"
  }

  # An exclusion must not leak into other kinds sharing the same run.
  reset-home $fixture
  let all_targets = (run-install $fixture ["--kind" "all" "--target" "claude-personal"])
  require-success $all_targets "held-back skills under --kind all"
  check (not ([$fixture.home ".claude-personal" "skills" "fable-style"] | path join | path exists)) "held-back skill installed under --kind all"
  check ([$fixture.home ".claude-personal" "agents" "personal.md"] | path join | path exists) "exclusion suppressed agents under --kind all"
}

def run-behavior-tests [fixture: record] {
  test-cli-and-skills $fixture
  test-target-and-kind-expansion $fixture
  test-held-back-skills $fixture
}
