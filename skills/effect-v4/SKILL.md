---
name: effect-v4
description: Effect v4 (4.0.0-beta.x) patterns and architecture judgment for TypeScript. Use when writing or reviewing Effect services, layers, schemas, typed errors, boundaries, config, CLIs, runtimes, or tests; when shaping or reviewing the structure of an Effect project, proposing a service or boundary, or arguing a wrapper is unnecessary — or when a project depends on `effect@4`. Effect v4 differs sharply from v3 and from plain TypeScript; verify APIs against the project's pinned source instead of recalling them.
compatibility: The enforcement preset script requires nu (nushell); its gates use the target project's effect-tsgo and oxlint installs plus ast-grep from the target or PATH.
---

# Effect v4

Effect v4 is barely present in model training data, and `effect.website`
documents v3 — recalled APIs look right and are wrong. Betas are not monotonic:
a pattern from another beta is evidence to verify, not a fact, and even the
first-party docs lag the shipped code (`migration/yieldable.md` still documents
an `.asEffect()` that does not exist). When any of these disagree with the
source, the source wins.

Established project conventions take precedence unless the task is explicitly
changing them.

## Source rule

Check these before guessing, highest authority first:

1. The project's installed types in `node_modules/effect` — the final word.
2. A pinned checkout of the Effect source, if the repo vendors one, at the tag
   matching the project's version.
3. First-party docs in that checkout: `LLMS.md`, `ai-docs/src/**`,
   `migration/**`, `packages/effect/SCHEMA.md`.
4. These reference files.

State the project's pinned version before writing Effect code.

## Which reference to read

Read only what the task needs.

| Task | Read |
|---|---|
| What earns a service or seam, coordinator/store splits, contracts-first, design review | `references/architecture.md` |
| Services, layers, DI, where to `provide`, `Effect.fn` | `references/services-layers.md` |
| Typed errors, catching, recovery, defects | `references/errors.md` |
| Retry/repeat policies, polling, TTL caches | `references/schedule-cache.md` |
| Schema, parsing untrusted input, domain modelling | `references/schema-boundaries.md` |
| Tests, fakes, `TestClock`, property tests | `references/testing.md` |
| Entrypoints, runtimes, `Config`, CLI, observability | `references/runtime-config.md` |
| Porting v3 code, or an API that "should" exist | `references/v3-to-v4.md` |
| Which package or import path a module lives in | `references/module-paths.md` |

If a task spans several, read all the matching files before editing.

## Core defaults

| Situation | Use |
|---|---|
| Define a service | `class X extends Context.Service<X, Shape>()("pkg/dir/X") {}` |
| Attach an implementation | `static readonly layer = Layer.effect(X, ...)` returning `X.of({...})` |
| Name a function returning an Effect | `Effect.fn("X.method")(function* () {...})` |
| Add combinators to an `Effect.fn` | trailing arguments — **not** `.pipe` |
| Define an error | `class E extends Schema.TaggedErrorClass<E>()("E", {...}) {}` |
| Raise an error | `return yield* E.make({...})` — the `return` is required |
| Catch | `Effect.catchTag` / `catchTags`; `Effect.catch` for the whole channel |
| Wrap a foreign cause | `cause: Schema.Defect()` |
| Decode untrusted input | `Schema.decodeUnknownEffect(S)(input)` |
| Refine a schema | `.check(Schema.isMinLength(1))` |
| Model a domain value | `Schema.Class`; `Schema.Struct` for structural shapes |
| Read config | `Config.*`, never `process.env` |
| Current time / randomness | `Clock`, `DateTime`, `Random` — never `Date.now`, `Math.random` |
| Files, paths, terminal | `FileSystem`, `Path` from core `effect` — not `node:fs` |
| Run the program | `NodeRuntime.runMain` / `BunRuntime.runMain` |
| Write a test | `it.effect` with `assert` from `@effect/vitest` |
| `provide` layers | inside a layer closing its own dependencies, and once at the process root — nowhere else |

## Layer naming

`layer` (production) · `layerNoDeps` (dependencies left in `RIn`) · `layerFake` ·
`layerTest` · `layerInProcess` · `layerInMemoryStore` · `layerFromEnv`

Never `Live` suffixes. Never the generic `layerMemory`.

## Enforcement preset

The skill ships a read-only checker for these rules. Run it against a project
before review or after substantial edits:

```sh
nu <path-to-this-skill>/scripts/check-effect.nu <project-dir> [source-paths...]
```

It runs effect-tsgo diagnostics, oxlint, and ast-grep using the preset in
`assets/`, never writes to the target, and reports gates whose tools the
target lacks as skipped. Wiring the diagnostics permanently into a project's
tsconfig/editor is first-party territory: `npx @effect/tsgo setup`.

`assets/tsconfig-compiler-options.json` is the strictness baseline the
diagnostics assume; extend it alongside `tsconfig-language-service.json`.
Without `strict` there is no `noImplicitAny`, and `effectFnImplicitAny`
silently no-ops.

`effect-tsgo patch` is **not** idempotent — it patches the installed `tsc`
binary in place. Guard it: `tsc --version` reports a `+effect-tsgo.<version>`
suffix once patched, so patch only when that suffix is absent or does not equal
the installed `@effect/tsgo` version. A bare `"prepare": "effect-tsgo patch"`
re-patches an already-patched compiler.

### Adapter carve-outs

Adapter files are where vendor reality lands, and a few diagnostics have to
yield there. Silence the narrowest thing that works:

- `// @effect-diagnostics <rule>:off` at the top of the file — the preferred
  form. A project-local plugin `overrides` entry is discarded by any runner
  that injects config with `--lspconfig` (it *replaces* project plugin config);
  the pragma survives both paths. See `references/runtime-config.md`.
- For `leakingRequirements` specifically, the language service has two JSDoc
  escapes: `@effect-leakable-service` on the interface declaration of a
  dependency that is meant to be passed through, or
  `@effect-expect-leaking <Type>` on the service that leaks it.

Every carve-out is a claim that the vendor boundary is genuinely here. If a
file needs several, the boundary is drawn in the wrong place.

## Do nots

- Do not use `try`/`catch` inside `Effect.gen` — it cannot see an Effect failure.
  Use `Effect.result` and branch.
- Do not use `async`/`await` or bare Promises; cross the boundary with
  `Effect.tryPromise`.
- Do not call `Effect.runPromise` / `runSync` / `runFork` in library code.
- Do not write a plain function whose only body is a returned `Effect.gen` — use
  `Effect.fn`.
- Do not use `as any`, `as unknown as`, non-null `!`, or unchecked casts to
  silence Effect typing. Branch, parse, or refine instead.
- Do not `JSON.parse(x) as T` — decode through a schema.
- Do not hand-roll `isString`-style guards; use `Predicate`.
- Do not hand-roll retry/poll loops or TTL caches; use `Schedule` and `Cache`.
- Do not `Effect.orDie` on config, state, reconciliation, or recovery paths.
- Do not import v3 packages: `@effect/platform`, `@effect/schema`, `@effect/cli`,
  `@effect/rpc`, `@effect/cluster`, `@effect/experimental`.
- Do not use `Context.Tag`, `Context.GenericTag`, `Effect.Tag`, or anything named
  `ServiceMap` — all are pre-v4 or intermediate-beta names.
- Do not use `Layer.mergeAll` or `provideMerge` as make-it-compile tools.
