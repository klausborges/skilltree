# fencecheck

Verification project for the `effect-v4` skill and its enforcement preset.
Dependencies are exact-pinned through the pnpm catalog in
`../pnpm-workspace.yaml`.

- `src/` — passes typecheck and every preset check. Grows into worked
  examples, written under the skill's rules.
- `fixtures/tsgo/` — fails the language-service diagnostics on purpose.
- `fixtures/oxlint/` — fails the oxlint preset on purpose; excluded from
  `tsconfig.json` so unresolvable imports don't break typecheck.
- `fixtures/astgrep/` — fails the ast-grep rules on purpose; also excluded
  from `tsconfig.json`. `fixtures/astgrep/pure/` exists to match the shipped
  `**/pure/**` glob of `no-effect-in-pure-core`, whose `files:` key a host repo
  is expected to repoint at its own kernel directories.
- `tsconfig.src-only.json` — same preset, `src/` only; used by
  `check-effect.test.nu` as its known-good diagnostics target.

## Commands

```sh
pnpm install
pnpm exec tsc -p tsconfig.json    # plain typecheck; fixtures pass this
pnpm exec effect-tsgo diagnostics --project "$PWD/tsconfig.json" --format text
pnpm exec oxlint -c ../../skills/effect-v4/assets/oxlintrc.json src fixtures/oxlint
pnpm exec ast-grep scan -c ../../skills/effect-v4/assets/sgconfig.yml src fixtures/astgrep
pnpm exec ast-grep test -c ../../skills/effect-v4/assets/sgconfig.yml   # rule unit tests
```

Expected: diagnostics report 5 errors (all `fixtures/tsgo/`); oxlint reports
8 errors (all `fixtures/oxlint/`); ast-grep scan reports 6 errors (all
`fixtures/astgrep/`). All three exit non-zero on findings.

## Notes

- Plain `tsc` never runs the preset diagnostics; only `effect-tsgo diagnostics`
  does. The preset itself lives in
  `skills/effect-v4/assets/tsconfig-language-service.json`, which
  `tsconfig.json` extends.
- If diagnostics fail with `EACCES`, the platform binary lost its exec bit:
  `find ../node_modules/.pnpm -path '*tsgo-*/lib/tsc' -exec chmod +x {} +`
- `deterministicKeys` derives service ids **differently depending on how the
  plugin config reaches it**, which looks like an upstream tsgo bug. Config
  delivered through the project's `tsconfig.json` gives
  `<package>/<file basename>[/<ClassName>]` — directories dropped; config
  delivered through `--lspconfig` (what `check-effect.nu` does) gives
  `<package>/<path under src>[/<ClassName>]` — directories preserved. Verified
  2×2 with the flag as the sole variable: `src/nested/deep/probe-service.ts`
  is demanded as `fencecheck/probe-service/ProbeService` via tsconfig and
  `fencecheck/nested/deep/probe-service/ProbeService` via `--lspconfig`. A
  service in a nested directory therefore cannot satisfy both paths.
- Segment elision (both paths): the class segment is dropped when it equals the
  basename case-insensitively (`Probe` in `probe.ts` → `fencecheck/probe`);
  the basename segment is dropped for an index file, and that rule takes
  precedence — `class Index` in `index.ts` is `fencecheck/Index`, not
  `fencecheck/index`. `index.mts`, `index.cts`, and `index.tsx` drop the
  basename too. Measured 2026-08-02.
- The preset's plugin `overrides` block (test-scoped `strictEffectProvide`)
  resolves its `include` globs relative to the tsconfig that DECLARES the
  plugin. It works through `check-effect.nu`'s `--lspconfig` injection and
  through a plugin block in (or above) the project, but is silently inert
  when a project `extends` the asset from an unrelated tree — as this
  harness does. fencecheck has no test files, so nothing diverges here;
  measured 2026-07-29.
