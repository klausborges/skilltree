# Architecture judgment (Effect)

Effect makes it cheap to add a service, a layer, and an interface — so structure
appears before it has earned its place, and the compiler is happy either way.

`review-work` and `improve-architecture` own the general architecture vocabulary
(module, interface, seam, adapter, depth, leverage, locality), the general
deletion test, and the rule that a single adapter can still justify a seam.

## Functional core, imperative shell

- Domain decisions are plain functions that compute a plan; Effect executes it.
- Being inside an Effect codebase is not a reason to wrap a pure decision.
- Push the effectful skin outward until the middle is data in, data out.
- A module that is hard to test without layers usually has a decision trapped
  inside an Effect, not a missing fake.

```ts
import { Effect } from "effect"

type Slot = { readonly id: string; readonly taken: boolean }
type Booking = { readonly slot: string } | { readonly rejected: "full" }

export const bookTrapped = (slots: ReadonlyArray<Slot>): Effect.Effect<Booking> =>
  Effect.sync(() => {
    const open = slots.find((s) => !s.taken)
    return open ? { slot: open.id } : { rejected: "full" }
  })

export const book = (slots: ReadonlyArray<Slot>): Booking => {
  const open = slots.find((s) => !s.taken)
  return open ? { slot: open.id } : { rejected: "full" }
}
```

A generator that never yields is not an Effect program — write it as
`Effect.sync` (or the matching constructor), which is what `eslint/require-yield`
in the oxlint preset enforces. That the constructor collapses to `Effect.sync` is
itself the signal the decision was pure and belongs outside Effect entirely.

**Complete when:** the decision runs in a test with no layers and no runtime.

## One lifecycle

- Everything asynchronous a module starts belongs to the Effect or layer scope
  that owns it — otherwise interruption and finalizers cannot see it.
- The hazard is work started *outside* that ownership — a raw timer, an
  unawaited Promise, a callback registered by hand, a mutable module global.
  `Effect.callback` and `Effect.tryPromise` are the owned boundaries, but
  ownership is opt-in: wire interruption there
  (mechanics in [runtime-config.md](runtime-config.md)).
- Treat Effect language-service diagnostics as architecture evidence, not a
  quick-fix queue. Suppress one only where the boundary really is the
  application or invocation lifetime the rule cannot see — and say which.

Unowned — invisible to interruption, finalizers, and `TestClock`:

```ts
setInterval(() => void Effect.runPromise(poll), 1000)
```

Owned by the layer's scope:

```ts
import { Effect, Layer, Schedule } from "effect"

declare const poll: Effect.Effect<void>

export const layer = Layer.effectDiscard(
  Effect.gen(function* () {
    yield* Effect.forkScoped(Effect.repeat(poll, Schedule.spaced("1 second")))
  }),
)
```

**Complete when:** every timer, fiber, and subscription dies with the scope
that started it.

## When a seam earns its place

Let the dependency category set the default, rather than the fact that something
performs IO:

| Category | Example | Default |
|---|---|---|
| in-process | pure library, standard data structures | no seam — call it |
| local-substitutable | SQLite, temp filesystem | no seam just for tests — use the real thing |
| remote but owned | your own service over the network | service + fake |
| true external | third-party API, provider SDK | service + fake, policy inside the adapter |

- Owning policy overrides the default either way. A local filesystem module *is*
  a seam when it owns file ownership, reconciliation, lifecycle, ordering, error
  mapping, validation, telemetry, or serialization policy.
- Never a service for parsed inputs, deterministic calculations, or per-call
  policy options. A test-only wish to inject a value is not sufficient reason.
- A remote call does *not* earn a wrapper when it renames one SDK method.
- A secret never enters an error, log, span, snapshot, or fixture.
- A fake validates a contract earned *independently of the fake*; it cannot earn
  the seam itself. Otherwise a service gets invented, its fake written, and the
  fake cited as proof the service was needed.

The deletion test has a signature in Effect: methods map one-to-one onto a lower
service, and the error channel is forwarded unchanged.

```ts
import { Effect, Schema } from "effect"

class SmtpError extends Schema.TaggedErrorClass<SmtpError>()("SmtpError", {}) {}
type Mail = { readonly to: string }

interface SmtpClient {
  readonly send: (m: Mail) => Effect.Effect<void, SmtpError>
}

interface Mailer {
  readonly send: (m: Mail) => Effect.Effect<void, SmtpError>
}
```

**Complete when:** every dependency has a category, and every seam owns policy
the layer below lacks.

## Coordinators, stores, executors

- Create a **coordinator** when one operation must order several modules,
  serialize mutations, compensate on failure, or map lower failures into domain
  failures. One that only forwards calls is a rename.
- Split a **store** from a lower **executor** when a domain persistence
  interface leaks SQL, transactions, codecs, retry policy, or backend errors.
  Once a caller catches a driver error by tag, the backend is in the contract.
- A bloated service object is the same smell one scale down: when methods need
  repeated row decoders, inline `satisfies` signatures, or result-shape helpers
  to stay readable, move the mechanics into adapter-local modules.

```ts
import { Effect, Schema } from "effect"

class SqlError extends Schema.TaggedErrorClass<SqlError>()("SqlError", {}) {}
class StoreError extends Schema.TaggedErrorClass<StoreError>()("StoreError", {
  op: Schema.String,
}) {}
type Invoice = { readonly id: string }

interface InvoiceStoreLeaky {
  readonly query: (sql: string) => Effect.Effect<ReadonlyArray<unknown>, SqlError>
}

interface InvoiceStore {
  readonly findOverdue: (owner: string) => Effect.Effect<ReadonlyArray<Invoice>, StoreError>
}
```

**Complete when:** no caller of a domain interface can name the backend.

## Contracts first

Sketch the leaf `Context.Service` contracts before their production layers, write
the orchestration against them, and make the call graph typecheck before any
adapter exists. The compiler then enforces the design while implementations fill
in.

```ts
import { Context, Effect, Schema } from "effect"

export class ScanError extends Schema.TaggedErrorClass<ScanError>()("ScanError", {
  root: Schema.String,
  cause: Schema.Defect(),
}) {}

export class RepoScanner extends Context.Service<RepoScanner, {
  readonly scan: (root: string) => Effect.Effect<ReadonlyArray<string>, ScanError>
}>()("app/scan/RepoScanner") {}

export const countSources = Effect.fn("countSources")(function* (root: string) {
  const scanner = yield* RepoScanner
  const files = yield* scanner.scan(root)
  return files.filter((f) => f.endsWith(".ts")).length
})
```

- The contract names exact success and error types and, by default, no `R`.
- An unsatisfied requirement is a design signal, not a compile error to silence.
  Clearing `R` early to kill a red squiggle hard-codes a choice the caller owns.
- Of a request's own payload, none of it earns a service: request data and
  per-call options stay explicit arguments. Cross-cutting authority — the tenant,
  the target, the caller's identity — is the exception, and there `R` keeps it
  visible until the right caller supplies it, so code written in the wrong
  context cannot compile.

**Complete when:** the call graph typechecks against contracts alone, with no
production adapter imported.

## Call graphs are the design artifact

Sketch two graphs before implementing and check that they meet at the same
application-facing seam. The notation deliberately mixes call flow with layer
selection, because the layer choice is the decision being inspected.

```text
production                          tests
-----------------------------       -----------------------------
HTTP handlers                       HTTP handlers
  -> Catalog                          -> Catalog
    -> Catalog.layerHttpClient          -> Catalog.layerTest
      -- network boundary --              -> Catalog.layer
      -> Catalog.layer                      -> CatalogCoordinator
        -> CatalogCoordinator                 -> CatalogStore.layerInMemoryStore
          -> CatalogStore                     -> ReadIndex.layerInMemoryStore
            -> CatalogPostgresExecutor
          -> ReadIndex
```

- Handlers depend on `Catalog` in both. If the graphs diverge anywhere above the
  seam, the seam is in the wrong place.
- Name the real boundary — `layerHttpClient`, `layerDurableObject`,
  `layerWorker` — never a generic `layerRemote`.
- Name the backend too. `CatalogPostgresExecutor` tells a reader the store is
  remote-but-owned rather than a local SQLite the tests should just run for real.
- For a CLI, put subprocess execution, output capture, and exit-code policy
  behind a runner seam, and give dispatch tests a spawner that dies if invoked
  so a parsing test cannot silently shell out.

**Complete when:** production and test graphs meet at the same seam.

## What a design must name

For non-trivial architecture work — a new seam, a split, a replaced boundary —
name all of these as signatures and graphs rather than paragraphs about them.
Work whose shape is already obvious does not need the ceremony.

1. the application-facing seam;
2. the production adapter;
3. the authoritative implementation behind the seam;
4. the coordinator, if one operation owns ordering or compensation;
5. the store/executor split, if persistence mechanics are involved;
6. the fake or in-memory composition, where the seam warrants one;
7. the error union per seam;
8. the production and test call graphs.

Plus, per affected behaviour, one trace from its actual ingress to its actual
egress — decoding where the input is untrusted, serializing where the output
leaves the process — with the failure path. A design that cannot draw that line
is not ready.

Where a behaviour retries or is cancelled, name its owner:

- **adapter** — short technical retries, only where the operation is safe to
  repeat. A timeout after a mutation has an ambiguous outcome; surface that as
  a typed failure rather than retry through it.
- **application service** — user-visible policy and fallback.
- **durable workflow** — anything that must survive a crash.
- Cancellation follows the same ladder: name the owner that observes
  interruption, and what it leaves behind.

**Complete when:** all eight items are named, and every affected behaviour has
an ingress-to-egress trace with its failure path.
