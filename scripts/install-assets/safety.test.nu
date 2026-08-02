def test-overwrite-gate-and-type-mismatch [fixture: record] {
  reset-home $fixture
  write-file $fixture.home ".agents/skills/alpha/SKILL.md" "do not replace"

  let refused = (run-install $fixture ["--kind" "skills"])
  require-failure $refused "non-interactive overwrite"
  check ($refused.stderr | str contains "non-interactive overwrite refused") "non-interactive overwrite did not fail closed clearly"
  check-equal (open --raw ([$fixture.home ".agents" "skills" "alpha" "SKILL.md"] | path join)) "do not replace" "overwrite gate changed an existing file"
  check (not ([$fixture.home ".claude-personal"] | path join | path exists)) "overwrite gate applied a later create"

  reset-home $fixture
  mkdir ([$fixture.home ".claude-personal" "CLAUDE.md"] | path join)

  let mismatch = (run-install $fixture ["--kind" "all" "--target" "claude-personal" "--force"])
  require-failure $mismatch "late type mismatch"
  check ($mismatch.stderr | str contains "type mismatch") "type mismatch error was not clear"
  check (not ([$fixture.home ".claude-personal" "skills"] | path join | path exists)) "a late type mismatch allowed an earlier skills write"
  check (not ([$fixture.home ".claude-personal" "agents"] | path join | path exists)) "a late type mismatch allowed an earlier agents write"
  check-equal (([$fixture.home ".claude-personal" "CLAUDE.md"] | path join) | path type) "dir" "type mismatch target was replaced"
}

def test-symlink-safety [fixture: record] {
  reset-home $fixture
  let shared_skills = ([$fixture.home ".agents" "skills"] | path join)
  let personal_skills = ([$fixture.home ".claude-personal" "skills"] | path join)
  let shared_skill = ([$shared_skills "alpha"] | path join)
  let personal_skill = ([$personal_skills "alpha"] | path join)
  mkdir $shared_skill ($personal_skills | path dirname)
  write-file $fixture.home ".agents/skills/alpha/keep.txt" "unknown through-link file"
  ^ln -s $shared_skills $personal_skills

  let safe = (run-install $fixture ["--kind" "all" "--target" "claude-personal" "--force"])
  require-success $safe "safe symlink write-through"
  check-equal ($personal_skills | path type) "symlink" "safe configured-root symlink was replaced"
  check-equal (open --raw ([$shared_skill "SKILL.md"] | path join)) "modified tracked skill" "safe symlink target did not receive tracked bytes"
  check-equal (open --raw ([$shared_skill "keep.txt"] | path join)) "unknown through-link file" "safe symlink overlay removed an unknown file"
  check ($safe.stdout | str contains "resolved:") "symlink action did not report its resolved destination"

  reset-home $fixture
  let outside_file = ([$fixture.outside "CLAUDE.md"] | path join)
  "outside must remain" | save --raw --force $outside_file
  let unsafe = ([$fixture.home ".claude-personal" "CLAUDE.md"] | path join)
  mkdir ($unsafe | path dirname)
  ^ln -s $outside_file $unsafe

  let refused = (run-install $fixture ["--kind" "all" "--target" "claude-personal" "--force"])
  require-failure $refused "late unsafe symlink"
  check ($refused.stderr | str contains "outside configured install roots") "unsafe symlink refusal was not clear"
  check-equal ($unsafe | path type) "symlink" "unsafe symlink was replaced"
  check-equal (open --raw $outside_file) "outside must remain" "unsafe symlink target was changed"
  check (not ([$fixture.home ".claude-personal" "skills"] | path join | path exists)) "a late unsafe symlink allowed an earlier skills write"
  check (not ([$fixture.home ".claude-personal" "agents"] | path join | path exists)) "a late unsafe symlink allowed an earlier agents write"

  reset-home $fixture
  let outside_root = ([$fixture.outside "profile-skills"] | path join)
  let linked_root = ([$fixture.home ".claude-personal" "skills"] | path join)
  mkdir $outside_root ($linked_root | path dirname)
  ^ln -s $outside_root $linked_root
  let root_result = (run-install $fixture ["--kind" "all" "--target" "claude-personal" "--force"])
  require-failure $root_result "outside configured-root symlink"
  check ($root_result.stderr | str contains "outside configured install roots") "outside configured-root symlink refusal was not clear"
  check-equal ($linked_root | path type) "symlink" "outside configured-root symlink was replaced"
  check (not ([$outside_root "alpha" "SKILL.md"] | path join | path exists)) "outside configured-root symlink received repo bytes"

  reset-home $fixture
  let broken = ([$fixture.home ".claude-personal" "skills" "alpha"] | path join)
  mkdir ($broken | path dirname)
  ^ln -s ([$fixture.home "missing-skill"] | path join) $broken
  let broken_result = (run-install $fixture ["--kind" "all" "--target" "claude-personal" "--force"])
  require-failure $broken_result "broken symlink"
  check ($broken_result.stderr | str contains "broken symlink") "broken symlink refusal was not clear"
  check-equal ($broken | path type) "symlink" "broken symlink was replaced"

  reset-home $fixture
  let repo_source = ([$fixture.repo "instructions" "claude-personal" "CLAUDE.md"] | path join)
  let source_pointing = ([$fixture.home ".claude-personal" "CLAUDE.md"] | path join)
  mkdir ($source_pointing | path dirname)
  ^ln -s $repo_source $source_pointing
  let source_result = (run-install $fixture ["--kind" "all" "--target" "claude-personal" "--force"])
  require-failure $source_result "source-pointing symlink"
  check ($source_result.stderr | str contains "source repo") "source-pointing symlink refusal was not clear"
  check-equal ($source_pointing | path type) "symlink" "source-pointing symlink was replaced"
  check-equal (open --raw $repo_source) "personal instructions" "source-pointing symlink changed repo bytes"
  check (not ([$fixture.home ".claude-personal" "skills"] | path join | path exists)) "a late source-pointing symlink allowed an earlier skills write"
  check (not ([$fixture.home ".claude-personal" "agents"] | path join | path exists)) "a late source-pointing symlink allowed an earlier agents write"
}

def run-safety-tests [fixture: record] {
  test-overwrite-gate-and-type-mismatch $fixture
  test-symlink-safety $fixture
}
