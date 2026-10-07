# Testing (effect@4.0.0)

Test through public service seams with real layers and fakes. Do not reach into
module internals.

```ts
import { assert, it, layer } from "@effect/vitest"
import { Effect, Fiber, Layer, Ref } from "effect"
import { TestClock } from "effect/testing"
```

Keep `effect` and `@effect/vitest` on the **same version** — a mismatch produces
confusing type errors. `@effect/vitest` 4.0.x peers on Vitest 5.

## Test forms

| Form | Use |
|---|---|
| `it.effect` | Effect-returning tests — the default |
| `it.live` | only when real wall-clock time is under test |
| `it` | pure synchronous functions |
| `it.prop` / `it.effect.prop` | property tests over Schemas or `Arbitrary` values |
| `layer(L)("name", (it) => ...)` | one shared layer instance across a block |

Rules:

- Project convention: `assert` from `@effect/vitest`. (It re-exports all of
  vitest, so `expect` is available — it is simply not the house style.)
- Never `Effect.runSync` / `runPromise` inside a test — return the Effect.
- `it.effect` installs `TestClock` at epoch; `it.live` does not.
- `it.prop` (synchronous) and `it.effect.prop` both take an array or record of
  Schemas and `Arbitrary` values — see [Property tests](#property-tests).

## Providing layers

Default to a **fresh layer per test**:

```ts
it.effect("round-trips a value", () =>
  Effect.gen(function* () {
    const s = yield* Store
    yield* s.put("a", "1")
    assert.strictEqual(yield* s.get("a"), "1")
  }).pipe(Effect.provide(Store.layerFake)))
```

`layer(...)` blocks share **one instance across every test in the block**,
including mutable state. Reserve them for genuinely expensive resources and
assume state leaks between cases.

## Fakes, not mocks

A fake is a real implementation of the contract with in-memory state. Hold state
in a `Ref` inside the layer, never in module-level mutable variables.

```ts
static readonly layerFake = Layer.effect(
  Store,
  Effect.gen(function* () {
    const ref = yield* Ref.make(new Map<string, string>())
    return Store.of({
      get: Effect.fn("Store.get")(function* (k: string) {
        const v = (yield* Ref.get(ref)).get(k)
        if (v === undefined) {
          return yield* NotFound.make({ key: k })
        }
        return v
      }),
      put: Effect.fn("Store.put")(function* (k: string, v: string) {
        yield* Ref.update(ref, (m) => new Map(m).set(k, v))
      }),
    })
  }),
)
```

- `Layer.succeed(Tag, Tag.of({...}))` for a complete static fake.
- `Layer.mock(Tag, {...})` only for tiny partial stubs that should fail loudly on
  anything unimplemented.
- Fake **one level below** the unit under test — stub the process/transport
  boundary and let the real service run.
- Never use `vi.mock` / `jest.mock` for module mocking.
- A partial object whose unused methods die is a focused test fixture, not a
  reusable in-memory adapter. Keep it local to the test.

## Asserting failures

```ts
const err = yield* Effect.flip(store.get("nope"))
assert.strictEqual(err.key, "nope")
```

`Effect.flip` moves the typed error into the success channel — and fails if the
effect succeeds. `Effect.result` reifies typed failures only — defects and
interrupts still fail — and reads better when you also need the success case;
assert the `Result.isFailure` branch explicitly. For defects, inspect
`Exit` / `Cause`.

Richer assertion helpers live in a **separate module** — `@effect/vitest/utils`,
not the package root:

```ts
import { assertFailure, assertInstanceOf, assertNone, assertSome } from "@effect/vitest/utils"
```

Also available there: `assertSuccess`, `assertExitSuccess`, `assertExitFailure`,
`assertDefined`, `assertUndefined`, `deepStrictEqual`, `strictEqual`. Importing
any of these from `@effect/vitest` fails to compile.

## Time

`it.effect` runs on `TestClock`. **Fork the sleeping work first, then advance:**

```ts
it.effect("advances the test clock", () =>
  Effect.gen(function* () {
    const fiber = yield* Effect.forkChild(Effect.sleep("5 seconds"))
    yield* TestClock.adjust("5 seconds")
    yield* Fiber.await(fiber)
  }))
```

Adjusting before forking deadlocks — nothing is waiting yet.

`Fiber.await(fiber)` / `Fiber.join(fiber)`; a fiber is not yieldable in v4, and
`.await` is not a method.

Never use `Effect.sleep(n)` as a fiber-readiness wait. Synchronise explicitly:

| Primitive | Use |
|---|---|
| `Deferred` | one-shot signal |
| `Latch` | reusable gate |
| `Queue` | cross-fiber work or events |
| `Ref` | observable state |

## Config in tests

```ts
Effect.provideService(program, ConfigProvider.ConfigProvider, ConfigProvider.fromUnknown({ PORT: "8080" }))
```

Use `ConfigProvider.fromUnknown` when the decoding path is what you are testing;
otherwise provide a config service layer with literal values directly.

## Property tests

Property testing is core `Arbitrary` — Effect's own engine, `@stability
unstable`. fast-check is not used and its generators are not accepted;
`effect/testing/FastCheck` and `Schema.toArbitrary` no longer exist.

```ts
import { Arbitrary, Effect, Schema } from "effect"

it.prop("addition commutes", [Schema.Int, Schema.Int], ([a, b]) => a + b === b + a)

it.effect.prop("names round-trip", { name: Arbitrary.schema(Name) }, ({ name }) =>
  Effect.gen(function* () {
    assert.strictEqual(yield* roundTrip(name), name)
  }), { arbitrary: { runs: 200 } })
```

- Returning `false`, throwing (a failed `assert` included), or failing the
  Effect falsifies the property; the input is then shrunk. Interruption stays
  interruption.
- The failure message carries the shrunk input and a `Replay:` token. Pass it
  back as `{ arbitrary: { replay } }` to reproduce the failure and its shrink
  path. Tokens are not guaranteed across releases — keep a shrunk
  counterexample as an ordinary named regression test.
- `Arbitrary.schema(S)` derives generation from a Schema and throws at
  derivation when it cannot; there is no report option. `Arbitrary.checkEffect`
  and `Arbitrary.sampleEffect` run outside vitest; `Arbitrary.configureGlobal`
  sets default `runs`/`seed`.
- `TestSchema.Asserts` from `effect/testing` (also unstable) checks codec
  round-trip laws: `verifyRoundTrip()` / `verifyRoundTripEffect()`.

## Type-level proofs

`@ts-expect-error` assertions only count in files the typechecker actually
includes — a proof in an excluded file is vacuous. Type-level tests belong in
`typetest/` and run separately.
