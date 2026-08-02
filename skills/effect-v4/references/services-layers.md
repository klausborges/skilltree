# Services and layers (effect@4.0.0-beta.100)

Whether something earns a service at all is [architecture.md](architecture.md)'s
call — the dependency-category table there sets the default. This file owns the
how: syntax, layers, composition, naming.

## Defining a service

```ts
import { Context, Effect, Layer, Schema } from "effect"

export class Database extends Context.Service<Database, {
  readonly query: (sql: string) => Effect.Effect<ReadonlyArray<unknown>, DatabaseError>
}>()("myapp/db/Database") {
  static readonly layer = Layer.effect(
    Database,
    Effect.gen(function* () {
      const query = Effect.fn("Database.query")(function* (sql: string) {
        yield* Effect.log("Executing SQL query:", sql)
        return [{ id: 1, name: "Alice" }]
      })
      return Database.of({ query })
    }),
  )
}

export class DatabaseError extends Schema.TaggedErrorClass<DatabaseError>()("DatabaseError", {
  cause: Schema.Defect(),
}) {}
```

Rules:

- Class syntax (project convention; Effect also supports a function form).
  `Context.Service<Self, Shape>()("id")` — note the `()` between the type
  arguments and the id.
- The id is `<package>/<file basename>/<ClassName>` — the file's **directories
  are ignored**. `Database` in `src/db/database.ts` of package `myapp` is
  `"myapp/database/Database"`; in `src/db.ts` it is `"myapp/db/Database"`.
  Segments elide in a few cases, and the derivation differs between the editor
  and the CLI runner — do not derive an id by hand. Write anything, then take the
  exact key `deterministicKeys` reports.
- Ids must be unique across the process, and directories cannot disambiguate
  them: `Client` in `src/db/client.ts` and `Client` in `src/http/client.ts` both
  derive `"myapp/client"` — `deterministicKeys` demands that colliding key in
  both files. Give one a distinct basename or class name.
- Members are `readonly` and return `Effect`. **Method signatures carry no `R`** —
  requirements are resolved by the layer, not leaked to callers. The one
  exception is per-request cross-cutting authority (tenant, caller identity),
  which stays in `R` deliberately — see
  [architecture.md](architecture.md).
- Declare the shape as a named `interface` when it is large or shared; inline it
  when small.
- Build the value with `Service.of({...})` as the last expression of the layer.
- Read the instance type with `Database["Service"]` when you need it.

`Context.Reference` is for values with a meaningful default (feature flags,
tuning knobs). `defaultValue` is a **thunk**, not a value:

```ts
export const Verbose = Context.Reference<boolean>("myapp/Verbose", {
  defaultValue: () => false,
})
```

Never hide required authority — credentials, persistence, transports — behind a
`Reference` default.

## Layer constructors

| Constructor | Use when |
|---|---|
| `Layer.succeed(Tag, value)` | the value is already built |
| `Layer.sync(Tag, () => value)` | lazy, synchronous construction |
| `Layer.effect(Tag, effect)` | effectful acquisition — the default |
| `Layer.effectDiscard(effect)` | background work with no service interface |
| `Layer.unwrap(effect)` | the *choice* of layer depends on config |
| `LayerMap.Service` | dynamically keyed resources (per-tenant pools) |

`Layer.scoped` does not exist in v4 — use `Layer.effect`. Acquire resources with
`Effect.acquireRelease` inside the layer body; the layer's scope owns them.

```ts
static readonly layer = Layer.unwrap(
  Effect.gen(function* () {
    const inMemory = yield* Config.boolean("STORE_IN_MEMORY").pipe(Config.withDefault(false))
    return inMemory ? MessageStore.layerInMemoryStore : MessageStore.layer
  }),
)
```

## Naming

| Name | Meaning |
|---|---|
| `layer` | the production implementation, dependencies closed |
| `layerNoDeps` | same implementation with dependencies left in `RIn` |
| `layerFake` | deterministic fake for tests |
| `layerTest` | test wiring, usually a composed stack |
| `layerInMemoryStore` | in-memory persistence that honours the real contract |
| `layerInProcess` | runs in-process instead of out-of-process |
| `layerFromEnv` | configured from the environment |

**Banned:** `Live` suffixes (`DatabaseLive`) and the generic `layerMemory`.

A layer that takes options is a function returning a layer. Layers memoize by
**reference identity** — calling a parameterized constructor twice builds two
instances. Hoist it to a module-level const when it should be shared.

## Composition

```ts
static readonly layerNoDeps: Layer.Layer<UserRepository, never, SqlClient> =
  Layer.effect(UserRepository, Effect.gen(function* () {
    const sql = yield* SqlClient
    return UserRepository.of({ findById })
  }))

static readonly layer = this.layerNoDeps.pipe(Layer.provide(SqlClientLayer))

static readonly layerWithSql = this.layerNoDeps.pipe(Layer.provideMerge(SqlClientLayer))
```

- `Layer.provide` — satisfies a dependency and hides it.
- `Layer.provideMerge` — satisfies it and keeps it in the output. Only when
  downstream genuinely needs it.
- `Layer.mergeAll` — combines independent layers.

Neither `mergeAll` nor `provideMerge` is a make-it-compile tool. Annotate public
layers explicitly as `Layer.Layer<A, E, R>`.

## Where `provide` belongs

Let requirements propagate until the module that *truthfully chooses* an
implementation provides them. That module is the composition root.

In production wiring `provide` appears in exactly two places:

1. Inside a layer definition, closing that layer's own dependencies.
2. Once at the process root.

Tests and managed-host integration are separate composition boundaries and
legitimately provide their own layers.

A local `Effect.provide` that erases requirements below the composition root is a
design smell — it hard-codes a choice the caller should have made. Keep handlers,
commands, hooks, and UI free of layers entirely; the root file itself is
[runtime-config.md](runtime-config.md)'s subject.

The `layerNoDeps` / `layer` pair is what makes this work: the root composes the
`NoDeps` variants and provides shared dependencies once for all of them.

## Long-lived work

Layer acquisition must **complete**. Never run a forever-loop inline during
acquisition.

```ts
static readonly layer = Layer.effectDiscard(
  Effect.gen(function* () {
    yield* Effect.forkScoped(
      poll.pipe(Effect.repeat(Schedule.spaced("1 second"))),
    )
  }),
)
```

`Schedule.spaced` waits the interval *after* each run completes;
`Schedule.fixed` holds a constant rate, running again immediately after an
overrun rather than replaying missed windows. Not interchangeable — pick
deliberately. Either way `Effect.repeat` runs sequentially: the effect runs
once before the schedule steps.

To fork from a method into the layer's lifetime, capture `Scope.Scope` at
acquisition and use `Effect.forkIn(scope)` internally. Do not expose the scope,
and do not add a public `start` method unless the domain truly needs manual
lifecycle control.

## Generator style

- `Effect.gen(function* () {...})` — anonymous programs, layer bodies, inline
  composition.
- `Effect.fn("Domain.operation")(function* (...) {...})` — project default for
  every named function returning an Effect, including zero-argument ones. Gives a
  span and a stack-trace name.
- `Effect.fnUntraced` — internal helpers and hot paths where that instrumentation
  is unwanted.

Avoid writing a plain function whose only job is to return an `Effect.gen`.

**Do not `.pipe` an `Effect.fn`.** Combinators go in as trailing arguments; they
receive `(effect, ...originalArgs)`:

```ts
export const loadUser = Effect.fn("loadUser")(
  function* (id: UserId) {
    return yield* fetchUser(id)
  },
  Effect.retry({ times: 3 }),
  Effect.annotateLogs({ method: "loadUser" }),
)
```

Annotate the generator's return with `Effect.fn.Return<A, E, R>` — **not**
`Effect.Effect<...>` — when you need to pin the error channel:

```ts
export const parsePort = Effect.fn("parsePort")(
  function* (raw: string): Effect.fn.Return<number, ParseInputError> {
    if (!/^\d+$/.test(raw)) {
      return yield* ParseInputError.make({ input: raw })
    }
    return Number(raw)
  },
)
```

The `effectFnImplicitAny` diagnostic fires at error severity on unannotated
`Effect.fn` / `Effect.fnUntraced` parameters with no contextual type.

## Consuming services

`yield* ServiceTag` inside a generator is the default. `Service.use((s) =>
s.method(x))` is fine for a single call at a leaf, but prefer `yield*` — `use`
makes it easy to leak service dependencies into return values.
