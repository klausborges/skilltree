#!/usr/bin/env nu

const test_dir = (path self | path dirname)
const installer_source = ($test_dir | path join "install-assets.nu")
const catalog_source = ($test_dir | path join "install-assets" "catalog.nu")
const engine_source = ($test_dir | path join "install-assets" "engine.nu")
const behavior_tests = ($test_dir | path join "install-assets" "behavior.test.nu")
const safety_tests = ($test_dir | path join "install-assets" "safety.test.nu")

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

def write-file [root: path, relative: string, content: string] {
  let destination = ([$root $relative] | path join)
  mkdir ($destination | path dirname)
  $content | save --raw --force $destination
}

def new-fixture [] {
  let root = (^mktemp -d | str trim | path expand)
  let repo = ([$root "repo"] | path join)
  let home = ([$root "home"] | path join)
  let outside = ([$root "outside"] | path join)
  let scripts = ([$repo "scripts"] | path join)
  let installer_modules = ([$scripts "install-assets"] | path join)
  let installer = ([$scripts "install-assets.nu"] | path join)

  mkdir $installer_modules $home $outside
  cp $installer_source $installer
  cp $catalog_source ([$installer_modules "catalog.nu"] | path join)
  cp $engine_source ([$installer_modules "engine.nu"] | path join)

  let files = [
    {path: "skills/alpha/SKILL.md", content: "original skill"}
    {path: "skills/alpha/references/note.txt", content: "tracked reference"}
    {path: "skills/fable-style/SKILL.md", content: "held-back skill"}
    {path: "skills/fable-style/references/review.md", content: "held-back reference"}
    {path: "agents/claude-personal/personal.md", content: "personal agent"}
    {path: "agents/claude-personal/nested/ignored.md", content: "nested agent is not mapped"}
    {path: "agents/claude-work/work.md", content: "work agent"}
    {path: "agents/cursor/cursor.md", content: "cursor agent"}
    {path: "agents/codex/codex.toml", content: "model = 'fixture'"}
    {path: "agents/droid/droid.md", content: "droid agent"}
    {path: "instructions/claude-personal/CLAUDE.md", content: "personal instructions"}
    {path: "instructions/claude-work/CLAUDE.md", content: "work instructions"}
    {path: "instructions/codex/AGENTS.md", content: "codex instructions"}
    {path: "instructions/droid/AGENTS.md", content: "droid instructions"}
    {path: "instructions/opencode/AGENTS.md", content: "opencode instructions"}
    {path: "instructions/cursor/AGENTS.md", content: "cursor guidance"}
  ]

  for file in $files {
    write-file $repo $file.path $file.content
  }

  ^git -C $repo init --quiet
  ^git -C $repo add skills agents instructions scripts/install-assets.nu scripts/install-assets/catalog.nu scripts/install-assets/engine.nu
  ^git -C $repo -c user.name=fixture -c user.email=fixture@example.invalid commit --quiet -m fixture

  {
    root: $root
    repo: $repo
    home: $home
    outside: $outside
    installer: $installer
  }
}

def reset-home [fixture: record] {
  if ($fixture.home | path exists) {
    rm --recursive --force $fixture.home
  }
  mkdir $fixture.home
}

def run-install [fixture: record, arguments: list<string>] {
  with-env {HOME: $fixture.home} {
    do { "" | ^nu --no-config-file $fixture.installer ...$arguments } | complete
  }
}

def require-success [result: record, context: string] {
  if $result.exit_code != 0 {
    error make {msg: $"($context) failed: ($result.stderr | str trim)"}
  }
}

def require-failure [result: record, context: string] {
  if $result.exit_code == 0 {
    error make {msg: $"($context) unexpectedly succeeded"}
  }
}

source $behavior_tests
source $safety_tests

def main [] {
  let fixture = (new-fixture)

  try {
    run-behavior-tests $fixture
    run-safety-tests $fixture
  } catch {|error|
    rm --recursive --force $fixture.root
    error make {msg: $error.msg}
  }

  rm --recursive --force $fixture.root
  print "install-assets tests passed"
}
