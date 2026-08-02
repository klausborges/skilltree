# Module paths (effect@4.0.0-beta.100)

Verified against `packages/effect/src/` and `packages/*/package.json` at tag
`effect@4.0.0-beta.100`.

In v4 most of the v3 `@effect/*` ecosystem was absorbed into core `effect`.
Importing a v3 package name is the single most common agent failure.

## Import style

```ts
import { Context, Effect, Layer, Schema } from "effect"
import { Command, Flag } from "effect/unstable/cli"
import { TestClock } from "effect/testing"
import { NodeRuntime, NodeServices } from "@effect/platform-node"
```

Core modules come from the `"effect"` barrel. Subsystems come from
`effect/unstable/<domain>`. For relative imports, follow the host repo's
module-resolution and extension convention.

Your own `index.ts` files use named re-exports, never `export *`: the preset's
`oxc/no-barrel-file` counts transitively loaded modules against a threshold of
100, and `export *` over a Schema-importing module blows it on its own.

## Core — `"effect"` barrel

Effect, Context, Layer, Schema, Config, ConfigProvider, Option, Result, Data,
Cause, Exit, Fiber, FiberHandle, FiberMap, FiberSet, Ref, SynchronizedRef,
SubscriptionRef, Deferred, Queue, PubSub, Stream, Sink, Channel, Schedule, Scope,
Duration, DateTime, Clock, Random, Predicate, Filter, Match, Brand, Newtype,
Semaphore, PartitionedSemaphore, Latch, Encoding, Redacted, Redactable, Logger,
LogLevel, References, Runtime, ManagedRuntime, ExecutionPlan, Metric, Tracer,
Cache, ScopedCache, Pool, Resource, Equal, Equivalence, Order, Hash, Struct,
Tuple, Array, Record, Chunk, HashMap, HashSet, Trie, Graph, Optic, JsonSchema,
JsonPatch, JsonPointer, LayerMap, LayerRef, Request, RequestResolver, Types.

Transactional (v3 `T*` → v4 `Tx*`): TxRef, TxHashMap, TxHashSet, TxQueue,
TxPubSub, TxSemaphore, TxDeferred, TxPriorityQueue, TxReentrantLock,
TxSubscriptionRef, TxChunk.

Schema companions: SchemaAST, SchemaError, SchemaGetter, SchemaIssue,
SchemaParser, SchemaRepresentation, SchemaTransformation, SchemaUtils.

**Platform modules are core in v4** — these were `@effect/platform` in v3:
`FileSystem`, `Path`, `Terminal`, `Crypto`, `Stdio`, `PlatformError`,
`ChannelSchema`.

## `effect/unstable/*`

`ai` · `cli` · `cluster` · `devtools` · `encoding` · `eventlog` · `http` ·
`httpapi` · `observability` · `persistence` · `process` · `reactivity` · `rpc` ·
`schema` · `socket` · `sql` · `workers` · `workflow`

`unstable` may break in minor releases; the rest follows strict semver once v4 is
stable. During the beta, treat every surface as movable: pin exactly and
re-verify after any bump.

HTTP splits across two namespaces — client/router/server in `unstable/http`,
`HttpApi*` and `OpenApi` in `unstable/httpapi`.

## `effect/testing`

`TestClock` · `FastCheck` · `TestConsole` · `TestSchema`

FastCheck ships inside core — do not install `fast-check` separately.

## Separate packages

| Package | Provides |
|---|---|
| `@effect/platform-node` (re-exports `-node-shared`) | `NodeRuntime`, `NodeServices`, `NodeFileSystem`, `NodeHttpServer`, `NodeStdio`, `NodeTerminal`, `NodeChildProcessSpawner` |
| `@effect/platform-bun` | `BunRuntime`, `BunServices` |
| `@effect/platform-browser` | browser bindings |
| `@effect/vitest` | `it.effect`, `it.live`, `layer`, `assert` |
| `@effect/opentelemetry` | OTel SDK bridge (prefer `effect/unstable/observability` for new code) |
| `@effect/ai-openai`, `-anthropic`, `-openrouter`, `-openai-compat` | AI providers |
| `@effect/sql-pg`, `-sqlite-node`, `-sqlite-bun`, `-libsql`, `-d1`, `-mysql2`, `-mssql`, `-clickhouse`, `-pglite`, … | SQL drivers |
| `@effect/atom-react`, `-vue`, `-solid` | UI bindings |
| `@effect/tsgo`, `@effect/language-service` | compiler + diagnostics |

Runtime and provider packages share one release-train version; keep `effect` and
`@effect/vitest` in lockstep, since a mismatch produces confusing type errors.
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
| `@effect/platform/Http*`, `Headers`, `Cookies`, `UrlParams`, `Multipart` | `effect/unstable/http/*` |
| `@effect/platform/HttpApi*`, `OpenApi` | `effect/unstable/httpapi/*` |
| `@effect/platform/HttpApp` | `effect/unstable/http/HttpEffect` |
| `@effect/platform/Command`, `CommandExecutor` | `effect/unstable/process/{ChildProcess,ChildProcessSpawner}` |
| `@effect/platform/{Socket,Worker,KeyValueStore}` | `effect/unstable/{socket,workers,persistence}/*` |
| `@effect/platform/{MsgPack,Ndjson}` | `effect/unstable/encoding/{Msgpack,Ndjson}` |
| `@effect/cli` (`Options`→`Flag`, `Args`→`Argument`) | `effect/unstable/cli` |
| `@effect/schema` | `effect` (core `Schema`) |
| `@effect/rpc`, `@effect/cluster`, `@effect/workflow` | `effect/unstable/{rpc,cluster,workflow}/*` |
| `@effect/sql/*` | `effect/unstable/sql/*` |
| `@effect/ai/*` | `effect/unstable/ai/*` |
| `@effect/experimental/{Persistence,RateLimiter,…}` | `effect/unstable/persistence/*` |
| `@effect/experimental/Event*`, `EventLog*` | `effect/unstable/eventlog/*` |
| `@effect/experimental/Reactivity` | `effect/unstable/reactivity/Reactivity` |
| `@effect/experimental/DevTools*` | `effect/unstable/devtools/*` |
| `@effect/opentelemetry/Otlp*` | `effect/unstable/observability/*` |
| `@effect/typeclass/{Semigroup,Monoid}` | `effect/{Combiner,Reducer}` |
| `effect/Either` | `effect/Result` |
| `effect/FiberRef` | `effect/References` |
| `effect/JSONSchema` | `effect/JsonSchema` |
| `effect/ParseResult` | `effect/SchemaIssue` + `effect/SchemaParser` |
| `effect/Inspectable` | split: `effect/{Formatter,Inspectable,Redactable}` |
| `effect/T*` (STM) | `effect/Tx*` |
| `effect/FastCheck`, `effect/TestClock` | `effect/testing/*` |
| `BunContext.layer` | `BunServices.layer` |
