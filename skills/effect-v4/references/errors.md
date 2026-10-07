# Errors (effect@4.0.0)

Every failure a caller could reasonably handle belongs in the error channel as a
tagged error. Reserve defects for genuine bugs and impossible states.

## Defining

```ts
import { Schema } from "effect"

export class ParseInputError extends Schema.TaggedError<ParseInputError>()("ParseInputError", {
  input: Schema.String,
}) {}
```

- `Schema.TaggedError` is the default — use it for anything that crosses a
  boundary (HTTP, persistence, IPC, logs, another module's error channel).
  Before 4.0.0 it was `Schema.TaggedErrorClass`, which no longer exists.
- `Data.TaggedError` — same name, different module, no schema — remains
  legitimate for internal errors that never need decode/encode. If in doubt,
  use the Schema form.
- Pass `Self` as the first type argument. The tag string usually matches the class
  name and doubles as the schema identifier.
- Zero-field errors: `Schema.TaggedError<E>()("E", {})`.
- Untagged variant has a **different argument order**:
  `Schema.Error<Self>("Name")({ fields })` (formerly `Schema.ErrorClass`). The
  schema for native JS `Error` values is now `Schema.ErrorInstance()`.

```ts
export class WrappedError extends Schema.TaggedError<WrappedError>()("WrappedError", {
  cause: Schema.Defect(),
}) {}
```

`Schema.Defect()` — invoked, not referenced — transports unknown causes through
JSON non-losslessly. A `Schema.Unknown` cause field is an obsolete pre-release
workaround.

## Constructing and raising

Errors are yieldable — no `Effect.fail` wrapper needed. Build with the static
`.make(...)`, not `new`:

```ts
Effect.gen(function* () {
  if (bad) {
    return yield* ParseInputError.make({ input: raw })
  }
  return ok
})
```

Use `return yield*` for never-succeeding Effects. TypeScript compiles it either
way; the `missingReturnYieldStar` diagnostic enforces the explicit form because
it makes the control flow unambiguous.

`new ParseInputError({...})` still compiles — the Effect repo's own docs use it,
but that is library-internal style; use `.make(...)` in application code. The
`newSchemaClass` diagnostic enforces this with an autofix; it defaults to `off`,
so promote it to `error`.

## Recovering

Narrowest tool that fits, in order:

```ts
program.pipe(Effect.catchTag(["ParseInputError", "ReservedPortError"], () => fallback))

program.pipe(Effect.catchTags({
  ParseInputError: (e) => Effect.succeed(e.input.length),
  ReservedPortError: (e) => Effect.succeed(e.port),
}))

program.pipe(Effect.catch(() => fallback))
```

| Combinator | Use |
|---|---|
| `Effect.catchTag` / `catchTags` | typed recovery — prefer these |
| `Effect.catch` | the whole error channel |
| `Effect.catchIf` | predicate-selected |
| `Effect.catchFilter` | `Filter`-selected (v3 `catchSome`) |
| `Effect.catchCause` / `catchCauseIf` / `catchCauseFilter` | cause-level |
| `Effect.catchDefect` | defects; hands you `unknown` |
| `Effect.result` | reify into `Result` (v3 `Effect.either`) |

Do not reach for cause-level recovery when typed recovery suffices, and never
catch causes just to make failures disappear.

When you must catch broadly at an ingress, worker, or stream boundary, **preserve
interruption**:

```ts
program.pipe(
  Effect.catchCauseIf(
    (cause) => !Cause.hasInterrupts(cause),
    () => Effect.succeed(fallback),
  ),
)
```

`Effect.catchDefect` hands back `unknown` — narrow it and re-die anything
unrecognized. Which narrowing depends on what the class is:

```ts
const isParseInputError = Schema.is(ParseInputError)

program.pipe(Effect.catchDefect((u) =>
  isParseInputError(u) ? Effect.succeed(u.input) : Effect.die(u)))
```

- **Schema classes** (`Schema.Class`, `Schema.TaggedError`, …) —
  `Schema.is(Class)` returns a type guard `(input) => input is Class`. Hoist it;
  it builds a parser per call site otherwise. `instanceof` on a Schema class is
  an `instanceOfSchema` error in the preset.
- **Ordinary classes** (vendor SDK errors, Node built-ins) — `instanceof` or
  `Match.instanceOf` as usual.

## Reason-shaped errors

When one error has several distinct causes, model them as a `reason` union rather
than proliferating top-level error types:

```ts
export class AiError extends Schema.TaggedError<AiError>()("AiError", {
  reason: Schema.Union([RateLimit, SafetyBlocked]),
}) {}

callModel.pipe(
  Effect.catchReason("AiError", "RateLimit", (reason) =>
    Effect.succeed(`retry after ${reason.retryAfter}`)),
)
```

`Effect.catchReason(errorTag, reasonTag, handler, orElse?)`,
`Effect.catchReasons`, and `Effect.unwrapReason` (lifts the reason into the error
channel) are the tools. This is the idiom for platform errors — do not hand-roll
`error.reason._tag === "NotFound"` over `Effect.result`.

## At boundaries

Map infrastructure failures into domain errors at the service boundary, including
an operation label:

```ts
readFile(path).pipe(Effect.mapError((cause) => StorageError.make({ operation: "read", cause })))
```

A shared curried helper beats hand-written per-module wrappers. Name the union of
a service's failures and use it on every method signature:

```ts
export type GitHubError = CommandError | JsonParseError | Schema.SchemaError
```

Keep the error channel honest: a known failure mode belongs in the type even when
the immediate caller cannot recover. Translate at the outermost boundary that has
a truthful response.

## Do nots

- Do not `Effect.orDie` on config loading, reconciliation, state, or recovery
  paths — those failures are expected and must stay typed.
- Do not use `try`/`catch` inside `Effect.gen`. It cannot observe an Effect
  failure and breaks the semantics. Use `Effect.result` and branch.
- Do not hand-roll `_tag` error classes when `Schema.TaggedError` fits.
- Do not `extends Error` for domain errors.
- Do not catch or retry where the boundary has no truthful response — let
  exhausted failures stay visible.
