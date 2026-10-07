# Module paths (effect@4.0.0)

Verified against the published `effect@4.0.0` package (`package.json` exports,
`src/`, `dist/*.d.ts`) and `@effect/platform-node`, `@effect/platform-bun`,
`@effect/vitest` at `4.0.0`.

In v4 most of the v3 `@effect/*` ecosystem was absorbed into core `effect`.
Importing a v3 package name is the single most common agent failure.

## Import style

```ts
import { Context, Effect, Layer, Schema } from "effect"
import { Command, Flag } from "effect/cli"
import { TestClock } from "effect/testing"
import { NodeRuntime, NodeServices } from "@effect/platform-node"
```

Core modules come from the `"effect"` barrel. Subsystems come from
`effect/<area>` (`effect/cli`, `effect/http`, …); a single module is also
reachable as `effect/<area>/<Module>`. For relative imports, follow the host
repo's module-resolution and extension convention.

Your own `index.ts` files use named re-exports, never `export *`: the preset's
`oxc/no-barrel-file` counts transitively loaded modules against a threshold of
100, and `export *` over a Schema-importing module blows it on its own.

## Core — `"effect"` barrel

Effect, Context, Layer, Schema, Config, ConfigProvider, Option, Result, Data,
Cause, Exit, Fiber, FiberHandle, FiberMap, FiberSet, Ref, SynchronizedRef,
SubscriptionRef, Deferred, Queue, PubSub, Stream, Sink, Channel, Schedule, Scope,
Duration, DateTime, Clock, Random, Predicate, Filter, Match, Brand, Newtype,
Semaphore, PartitionedSemaphore, Latch, Redacted, Redactable, Logger,
LogLevel, References, Runtime, ManagedRuntime, ExecutionPlan, Metric, Tracer,
Cache, ScopedCache, Pool, Resource, Equal, Equivalence, Order, Hash, Struct,
Tuple, Array, Record, Chunk, HashMap, HashSet, Trie, Graph, Optic, JsonSchema,
JsonPatch, JsonPointer, LayerMap, LayerRef, Request, RequestResolver, Types,
ByteSize, StandardSchema, Arbitrary (`@stability unstable`; see `effect/testing`
below).

Transactional (v3 `T*` → v4 `Tx*`): TxRef, TxHashMap, TxHashSet, TxQueue,
TxPubSub, TxSemaphore, TxDeferred, TxPriorityQueue, TxReentrantLock,
TxSubscriptionRef, TxChunk.

Schema companions: SchemaAST, SchemaGetter, SchemaIssue, SchemaParser,
SchemaRepresentation, SchemaTransformation. `SchemaError` lives in `Schema`
itself (`Schema.SchemaError`); there is no `SchemaError` or `SchemaUtils`
module. The pre-4.0.0 `Encoding` module is split into
`effect/encoding/{Base64,Base64Url,Hex,EncodingError}`.

**Platform modules are core in v4** — these were `@effect/platform` in v3:
`FileSystem`, `Path`, `Terminal`, `Crypto`, `Stdio`, `PlatformError`,
`ChannelSchema`.

## `effect/<area>` subsystems

`ai` · `cli` · `cluster` · `devtools` · `encoding` · `eventlog` · `http` ·
`http-api` · `net` · `observability` · `persistence` · `process` ·
`reactivity` · `rpc` · `schema` · `socket` · `sql` · `workers` · `workflow`

These were `effect/unstable/<area>` before 4.0.0; the `unstable` path segment
and `effect/httpapi` are gone. Every module here except
`effect/encoding/{Base64,Base64Url,Hex,EncodingError}` is still tagged
`@stability unstable` and may break in a minor release; untagged APIs follow
semver. Pin exactly and re-verify unstable surfaces after any bump.

HTTP splits across two namespaces — client/router/server in `effect/http`,
`HttpApi*` and `OpenApi` in `effect/http-api`.

## `effect/testing`

`TestClock` · `TestConsole` · `TestSchema` (only `TestSchema` is `@stability unstable`)

Property testing is core `Arbitrary` (`effect/Arbitrary`, `@stability
unstable`): Effect's own engine, not fast-check, which it does not accept.
There is no `FastCheck` module and no `Schema.toArbitrary`.

## Separate packages

| Package | Provides |
|---|---|
| `@effect/platform-node` (re-exports `-node-shared`) | `NodeRuntime`, `NodeServices`, `NodeFileSystem`, `NodeHttpServer`, `NodeStdio`, `NodeTerminal`, `NodeChildProcessSpawner` |
| `@effect/platform-bun` | `BunRuntime`, `BunServices` |
| `@effect/platform-browser` | browser bindings |
| `@effect/vitest` | `it.effect`, `it.live`, `it.prop`, `layer`, `assert` (peers on Vitest 5) |
| `@effect/opentelemetry` | OTel SDK bridge (prefer `effect/observability` for new code) |
| `@effect/ai-openai`, `-anthropic`, `-openrouter`, `-openai-compat` | AI providers |
| `@effect/sql-pg`, `-sqlite-node`, `-sqlite-bun`, `-libsql`, `-d1`, `-mysql2`, `-mssql`, `-clickhouse`, `-pglite`, … | SQL drivers |
| `@effect/atom-react`, `-vue`, `-solid` | UI bindings |
| `@effect/tsgo`, `@effect/language-service` | compiler + diagnostics |

Runtime and provider packages share one release-train version; keep `effect` and
`@effect/vitest` in lockstep, since a mismatch produces confusing type errors
(`@effect/vitest@4.0.1` already peers on `effect@^4.0.1`).
Tooling (`@effect/tsgo`, `@effect/language-service`) versions independently.

## Banned — v3 packages

`@effect/platform` · `@effect/schema` · `@effect/cli` · `@effect/rpc` ·
`@effect/cluster` · `@effect/experimental` · `@effect/workflow` ·
`@effect/typeclass` · `@effect/sql` (the meta package; drivers are fine)

`@effect/platform-node` is allowed — only the bare `@effect/platform` meta
package is v3.

## v3 → v4 path map

| v3 | v4 |
|---|---|
| `@effect/platform` → `FileSystem`, `Path`, `Terminal` | `effect` (core) |
| `@effect/platform/Error` | `effect/PlatformError` |
| `@effect/platform/Http*`, `Headers`, `Cookies`, `UrlParams`, `Multipart` | `effect/http/*` |
| `@effect/platform/HttpApi*`, `OpenApi` | `effect/http-api/*` |
| `@effect/platform/HttpApp` | `effect/http/HttpEffect` |
| `@effect/platform/Command`, `CommandExecutor` | `effect/process/{ChildProcess,ChildProcessSpawner}` |
| `@effect/platform/{Socket,Worker,KeyValueStore}` | `effect/{socket,workers,persistence}/*` |
| `@effect/platform/Ndjson` | `effect/encoding/Ndjson` (MsgPack was removed; `SchemaBinary` is the binary codec) |
| `@effect/cli` (`Options`→`Flag`, `Args`→`Argument`) | `effect/cli` |
| `@effect/schema` | `effect` (core `Schema`) |
| `@effect/rpc`, `@effect/cluster`, `@effect/workflow` | `effect/{rpc,cluster,workflow}/*` |
| `@effect/sql/*` | `effect/sql/*` |
| `@effect/ai/*` | `effect/ai/*` |
| `@effect/experimental/{Persistence,RateLimiter,…}` | `effect/persistence/*` |
| `@effect/experimental/Event*`, `EventLog*` | `effect/eventlog/*` |
| `@effect/experimental/Reactivity` | `effect/reactivity/Reactivity` |
| `@effect/experimental/DevTools*` | `effect/devtools/*` |
| `@effect/opentelemetry/Otlp*` | `effect/observability/*` |
| `@effect/typeclass/{Semigroup,Monoid}` | `effect/{Combiner,Reducer}` |
| `effect/Either` | `effect/Result` |
| `effect/FiberRef` | `effect/References` |
| `effect/JSONSchema` | `effect/JsonSchema` |
| `effect/ParseResult` | `effect/SchemaIssue` + `effect/SchemaParser` |
| `effect/Inspectable` | split: `effect/{Formatter,Inspectable,Redactable}` |
| `effect/T*` (STM) | `effect/Tx*` |
| `effect/TestClock` | `effect/testing` (`TestClock`) |
| `effect/FastCheck` | `effect/Arbitrary` — native engine, not fast-check |
| `BunContext.layer` | `BunServices.layer` |
