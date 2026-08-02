# v3 → v4 API delta (effect@4.0.0-beta.100)

Extracted from `migration/*.md` at tag `effect@4.0.0-beta.100`, spot-verified
against `packages/effect/src/`. Module/package moves live in
[module-paths.md](module-paths.md).

## Traps — look right, are wrong

These typecheck or read plausibly. Highest risk first.

1. **`Schema.decode` reversed meaning.** v3 `decode` ran the decoder. v4
   `Schema.decode(transformation)` *builds* a schema. The runner is
   `Schema.decodeEffect` / `decodeUnknownEffect`.
2. **`Effect.zipLeft` → `Effect.tap`.** v4 `tap` also exists with its own v3
   meaning, so two different v3 habits land on one v4 name.
3. **`Cause.isFailType` → `Cause.isFailReason`, and it takes a *Reason*, not a
   `Cause`.** Passing a `Cause` looks correct and is not.
4. **`Cause.findError` / `findDefect` return `Result`, not `Option`.** Use
   `findErrorOption` when you want `Option`.
5. **`catchIf` and `catchFilter` both exist.** `catchIf` takes a predicate;
   `catchFilter` takes a `Filter` and has a two-arg shape. v3 `catchSome` maps to
   `catchFilter`. Same split for `catchCauseIf` / `catchCauseFilter`.
6. **`Schema.optional` vs `optionalKey`.** `optional` admits `undefined`;
   `optionalKey` does not — decoding `{a: undefined}` against an `optionalKey`
   schema fails. v3's `{exact: true}` is `optionalKey`.
7. **`Layer.scoped` → `Layer.effect`.** `Layer.effect` already existed in v3 with
   non-scoped semantics.
8. **`forkScoped` / `forkIn` are unchanged while `fork` / `forkDaemon` were
   renamed** to `forkChild` / `forkDetach`. Partial familiarity makes
   `Effect.fork` look safe. It does not exist.
9. **`Context.Service` inverts `Context.Tag`'s shape**:
   `Context.Service<Self, Shape>()("Id")` — the `()` sits between type args and id.
10. **`Context.Reference` exists in both with different call shapes** — v3
    `Context.Reference<Self>()(id, opts)` class-extend, v4
    `Context.Reference<T>(id, opts)` plain function.
11. **`Effect.provideService` replaced `Effect.locally`** and scopes the value to
    the provided effect, not "from here onward" like `FiberRef.set`.
12. **`Unsafe` is a suffix, not a prefix**: `DateTime.makeUnsafe`,
    `Semaphore.makeUnsafe`, `Queue.offerUnsafe`, `Layer.makeMemoMapUnsafe`.
13. **Schema combinators take arrays**: `Schema.Literals(["a","b"])`,
    `Schema.Union([A, B])`, `Schema.Tuple([A, B])`. v3 was variadic.
14. **`Schema.TaggedErrorClass<Self>()("Tag", fields)` vs
    `Schema.ErrorClass<Self>("Name")({fields})`** — the argument order differs
    between the tagged and untagged forms. Easy to write backwards.
15. **`Schema.brand` adds no runtime check.** It only narrows the type.
16. **`Stream.async` / `asyncEffect` / `asyncPush` / `asyncScoped` all collapse to
    `Stream.callback`** — four v3 signatures, one v4 name.
17. **`Cause.combine` replaces both `sequential` and `parallel`.** Code that
    inspected the distinction silently loses information.

## Services

| v3 | v4 |
|---|---|
| `Context.Tag(id)<Self, Shape>()` | `Context.Service<Self, Shape>()(id)` |
| `Context.GenericTag<T>(id)` | `Context.Service<T>(id)` |
| `Effect.Tag(id)<Self, Shape>()` | `Context.Service<Self, Shape>()(id)` |
| `Effect.Service<Self>()(id, {effect, dependencies})` | `Context.Service<Self>()(id, { make })` |
| auto `.Default` layer | write `static readonly layer = Layer.effect(this, this.make)` |
| `dependencies: [...]` | `Layer.provide(...)` — the option no longer exists |
| `.Default` / `.Live` naming | `.layer`, `.layerTest`, `.layerConfig` |
| static accessor proxy `Svc.method(x)` | `Svc.use((s) => s.method(x))` — prefer `yield*` |
| `Context.Reference<Self>()(id, opts)` | `Context.Reference<T>(id, opts)` |

`ServiceMap.Service` was a real intermediate-beta name (≈beta.40) renamed to
`Context.Service` by beta.47. There is no `ServiceMap` module in beta.100.

## Errors

| v3 | v4 |
|---|---|
| `Effect.catchAll` | `Effect.catch` |
| `Effect.catchAllCause` | `Effect.catchCause` |
| `Effect.catchAllDefect` | `Effect.catchDefect` |
| `Effect.catchSome` | `Effect.catchFilter` |
| `Effect.catchSomeCause` | `Effect.catchCauseFilter` |
| `Effect.catchSomeDefect` | **removed** |
| `Effect.tapErrorCause` | `Effect.tapCause` |
| `Effect.either` | `Effect.result` |
| `Effect.optionFromOptional` | `Effect.catchNoSuchElement` |
| `Effect.ignoreLogged` | `Effect.ignore` |
| `Data.TaggedError` (for schema-crossing errors) | `Schema.TaggedErrorClass` |

`catchTag`, `catchTags`, `catchIf` are unchanged. New in v4:
`catchReason`, `catchReasons`, `catchEager`, `unwrapReason`.

## Cause

v3's recursive tree became a flat `{ reasons: ReadonlyArray<Reason<E>> }` where
`Reason = Fail | Die | Interrupt`.

| v3 | v4 |
|---|---|
| `Cause.isEmptyType(c)` | `c.reasons.length === 0` |
| `Cause.isFailType/isDieType/isInterruptType` | `Cause.isFailReason/isDieReason/isInterruptReason` |
| `Cause.isSequentialType` / `isParallelType` | **removed** |
| `Cause.isFailure` / `isDie` / `isInterrupted` | `Cause.hasFails` / `hasDies` / `hasInterrupts` |
| `Cause.isInterruptedOnly` | `Cause.hasInterruptsOnly` |
| `Cause.sequential` / `parallel` | `Cause.combine` |
| `Cause.failureOption` | `Cause.findErrorOption` |
| `Cause.failureOrCause` | `Cause.findError` (returns `Result`) |
| `Cause.dieOption` | `Cause.findDefect` (returns `Result`) |
| `Cause.failures` | `cause.reasons.filter(Cause.isFailReason)` |
| `Cause.defects` | `cause.reasons.filter(Cause.isDieReason)` |
| `Cause.*Exception` classes | `Cause.*Error` (`NoSuchElementError`, `TimeoutError`, …) |

## Runtime, forking, scope

| v3 | v4 |
|---|---|
| `Runtime<R>` type | **removed** — use `Context<R>` |
| `Effect.runtime<R>()` | `Effect.context<R>()` |
| `Runtime.runFork(rt)(eff)` | `Effect.runForkWith(services)(eff)` |
| `Effect.fork` | `Effect.forkChild` |
| `Effect.forkDaemon` | `Effect.forkDetach` |
| `Effect.forkAll` | **removed** — fork individually or use concurrency combinators |
| `Effect.forkWithErrorHandler` | **removed** — observe via `Fiber.join`/`Fiber.await` |
| `Scope.extend(eff, scope)` | `Scope.provide(eff, scope)` |
| `Effect.async` | `Effect.callback` |
| `Effect.zipRight` / `zipLeft` | `Effect.andThen` / `Effect.tap` |
| `Effect.makeSemaphore` / `makeLatch` | `Semaphore.make` / `Latch.make` |
| `Mailbox` | `Queue.Queue` |

## Generators & Yieldable

| v3 | v4 |
|---|---|
| `Effect.gen(this, function*(){})` | `Effect.gen({ self: this }, function*(){})` |
| `yield* ref` | `yield* Ref.get(ref)` |
| `yield* deferred` | `yield* Deferred.await(deferred)` |
| `yield* fiber` | `yield* Fiber.join(fiber)` |
| `yield* option` / `yield* result` | `yield* Effect.fromOption(o)` / `Effect.fromResult(r)` |

Yieldable in `Effect.gen`: `Effect`, `Config`, `Context.Service`.
**Not** yieldable: `Ref`, `Deferred`, `Fiber`, `Option`, `Result`.

`Option` and `Result` each carry their own iterator type, so `yield*`-ing them
fails to compile (and fails at runtime if you force past it with a cast). Lift
them with `Effect.fromOption` / `Effect.fromResult`.

> `migration/yieldable.md` describes a `Yieldable` trait with an `.asEffect()`
> method. Neither exists in the beta.100 source. The first-party migration docs
> lag the shipped code — when they disagree, the source wins.

## FiberRef → References

`FiberRef`, `FiberRefs`, and `FiberRefsPatch` are **removed**. Use
`Context.Reference`; read with `yield* Reference`, set with
`Effect.provideService(eff, Reference, v)`. (`Differ` still exists.)

Built-ins moved to `References.*`: `CurrentConcurrency`, `CurrentLogLevel`,
`MinimumLogLevel`, `CurrentLogAnnotations`, `CurrentLogSpans`, `Scheduler`,
`MaxOpsBeforeYield`, `TracerEnabled`, `UnhandledLogLevel`.

## Behavioral changes — no API signal

| Area | v3 | v4 |
|---|---|---|
| Layer memoization | per-`Effect.provide` memo scope; overlapping layers built twice | shared `MemoMap` across `provide` calls; built once |
| Memo opt-out | `Layer.fresh` | `Layer.fresh` **or** `Effect.provide(l, { local: true })` |
| Structural equality | reference equality unless in `structuralRegion` | structural by default; `Equal.equals(NaN, NaN)` is now `true` |
| Cause composition | tree preserved sequential vs parallel | flat array; distinction gone |
| Process keep-alive | needed `runMain`'s interval | reference-counted keep-alive in the core runtime |
| Fiber startup | — | `startImmediately` defaults to deferred; `uninterruptible` accepts `"inherit"` |
| Versioning | packages versioned independently | one shared version across the ecosystem |

Auto-memoization is a safety net, **not** a substitute for composing layers
before providing.

## Churn between betas

Concrete cases, as evidence that a pattern from another beta proves nothing:

- `Schema.Defect` in `TaggedErrorClass` fields — worked at .59, **crashed at .83**,
  works .93+. `Schema.Unknown` for `cause` is a dead workaround.
- .95 — ConfigProviders treat empty strings as missing (`preserveEmptyStrings` opts out).
- .96 — `Schedule` combinators removed, including `Schedule.both`.
- .98 — Schema union candidate ordering fixed.
- .99/.100 — CLI and tagged-union inference fixes.
