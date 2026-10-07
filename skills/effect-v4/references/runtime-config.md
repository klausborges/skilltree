# Runtime, entrypoints, config (effect@4.0.0)

## The composition root

Give each application one file that owns the dependency graph — `layers.ts`,
`runtime.ts`, or the entrypoint itself. It is the only place that names concrete
implementations.

```ts
const appLayer = Layer.mergeAll(NodeServices.layer, Greeter.layer, Storage.layer)
```

`NodeServices.layer` already bundles `FileSystem`, `Path`, `Stdio`, `Terminal`,
`Crypto`, and `ChildProcessSpawner` — do not merge them individually.

Compose layers *before* providing. Shared memoization in v4 will deduplicate an
overlapping layer built twice, but that is a safety net, not a substitute for
composing properly.

## Entrypoints

```ts
const program = Effect.gen(function* () { /* ... */ }).pipe(Effect.provide(appLayer))
NodeRuntime.runMain(program, { disableErrorReporting: true })
```

| Form | Use |
|---|---|
| `NodeRuntime.runMain` / `BunRuntime.runMain` | process entrypoint — the default |
| `Layer.launch(layer)` | apps that are entirely layers (servers, workers) |
| `ManagedRuntime.make(layer)` | bridging into a non-Effect host |

`runMain` handles teardown, interrupts, and error reporting. Pass
`disableErrorReporting: true` when the app renders its own errors. Do not call
`Effect.runPromise` / `runSync` / `runFork` in library code — they are entrypoint
and boundary tools only.

For a fiber's own result use `Fiber.join` / `Fiber.await`; `Effect.forkAll` and
`forkWithErrorHandler` no longer exist.

## Integrating with non-Effect code

Effect is usually a **core with a non-Effect shell**: an HTTP framework, a React
tree, or a Workers handler on the outside, with the boundary drawn at the service.

```ts
const runtime = ManagedRuntime.make(appLayer)

export const handler = (name: string) =>
  runtime.runPromise(Effect.gen(function* () {
    const g = yield* Greeter
    return yield* g.hello(name)
  }))
```

The handler is not `async`: `runPromise` already returns a `Promise`, and the
preset sets `asyncFunction: error` — everything of ours is an Effect, vendor
async is wrapped once at the adapter. Where an adapter file genuinely needs
multi-step vendor `async`/`await`, put
`// @effect-diagnostics asyncFunction:off` at the top of that file. Prefer the
pragma over a project-local plugin `overrides` entry: `--lspconfig` **replaces**
the project's plugin config, so an override added to your own tsconfig holds in
the editor but is discarded by a CLI runner that injects the preset that way.
The pragma survives both paths.

Crossing the other way — foreign async inside Effect — use `Effect.tryPromise`
for a one-shot Promise and `Effect.callback` for callback APIs. Interruption is
opt-in and gated on arity: a thunk that does not declare the `AbortSignal`
parameter never receives one. `callback`'s register may also return a cleanup
Effect; `tryPromise` has no cleanup path — its thunk must return a
`PromiseLike`.

Build the runtime **once** at module scope — a runtime per request rebuilds the
whole layer graph — and call `runtime.dispose()` (or `disposeEffect`) on host
shutdown, or the layer's scopes and resources leak. When server and tests should
share instances, share one `Layer.makeMemoMapUnsafe()`.

## CLI

```ts
import { Command, Flag } from "effect/cli"

const root = Command.make("greet", { name: Flag.String("name") }, ({ name }) =>
  Effect.gen(function* () {
    const g = yield* Greeter
    yield* Effect.log(yield* g.hello(name))
  }))

export const cli = Command.runWith(root, { version: "1.0.0" })
```

- `effect/cli` is `@stability unstable` — `Command`, `Flag`, and `Argument`
  included — and may break in a minor release.
- v3 `Options` → `Flag`, `Args` → `Argument`. Constructors are PascalCase:
  `Flag.String`, `Flag.Int`, `Flag.Boolean`, `Argument.String` — the
  pre-4.0.0 `Flag.string` / `Flag.integer` are gone.
- `Command.runWith(root, { version })` takes an explicit argv and is the
  **dispatch-test seam**; `Command.run` reads `Stdio` directly.
- `Command.withSharedFlags` parses both before *and* after the subcommand.
- Do not create one service per subcommand.

## Config

Read every environment value through `Config`. `process.env` in application logic
is an error.

```ts
export const port = Config.Int("PORT").pipe(Config.withDefault(3000))
```

Constructors (PascalCase, like `Schema`): `String` `NonEmptyString` `Number`
`Int` `Finite` `Boolean` `Redacted` `URL` `Port` `LogLevel` `Duration`
`ByteSize` `Date` `Literal` `Literals` `Array` `Record`; plus `succeed` `fail`
`all` `schema`.
Combinators: `option` `withDefault` `orElse` `map` `mapEffect` `flatMap`
`nested` `unwrap`.

The lowercase constructors (`Config.int`, `Config.port`, …) and
`Config.mapOrFail` are pre-4.0.0 names and no longer exist; neither does
`Config.integer`.

`Literal` / `Literals` take the value(s) first and the name second:
`Config.Literals(["a", "b"], "MODE")`.

For structured config, decode with a schema:

```ts
const ServerConfig = Config.schema(
  Schema.Struct({ host: Schema.String, port: Schema.Int }),
  "server",
)
```

`Config.withDefault` and `Config.option` recover from **missing** data only —
validation errors still propagate. On a `Config.all` group, one absent child
makes the default replace the whole group; default the children individually.
`ConfigError` wraps either a `SourceError` (I/O) or a `SchemaError` (shape);
branch on `error.cause._tag`.

Secrets use `Config.Redacted`; unwrap with `Redacted.value` only inside the
adapter that needs the plaintext.

### Providers

```ts
Effect.provideService(program, ConfigProvider.ConfigProvider, ConfigProvider.fromUnknown({ PORT: "8080" }))
```

- `ConfigProvider.layer` replaces the provider; `layerAdd` adds a fallback
  (`{ asPrimary: true }` to override).
- `fromUnknown` for tests, `fromDotEnv` for local files, `constantCase` for
  SCREAMING_SNAKE keys, `nested` for prefixes.
- `ConfigProvider.fromEnv({ env })` **replaces** the environment map rather than
  extending it — include every variable the code reads.
- Empty strings count as missing by default; `preserveEmptyStrings: true`
  opts out.

## Platform services

Use core `effect` modules, not Node built-ins: `FileSystem`, `Path`, `Terminal`,
`Crypto`, `Stdio`. `@effect/platform-node` supplies the *layers* that implement
them.

Never use `Date.now()` or `new Date()` — use `Clock` and the `DateTime` module,
with `TestClock` in tests. Never `Math.random()` or `crypto.randomUUID()` — use
`Random`. These have language-service diagnostics precisely because they silently
destroy testability.

## Observability

Prefer `effect/observability` (`OtlpTracer`, `OtlpLogger`,
`OtlpSerialization`; `@stability unstable`) for new projects;
`@effect/opentelemetry` when integrating with an existing OTel setup.

`Otlp.layerJson` appends `/v1/{logs,metrics,traces}` — the configured base URL
must not already carry a signal path. Provide the observability layer last, and
keep its scope alive for the process lifetime.

`Effect.fn("Name.method")` already opens a span; add `Effect.withSpan` and
`Effect.annotateCurrentSpan` where more detail helps.
