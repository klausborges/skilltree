# Schedule and Cache (effect@4.0.0-beta.100)

Never hand-roll retry/poll loops (`while` + sleep + counter) or TTL caches
(`Map` + timestamps). `Schedule` is a reusable policy value; `Cache` is a keyed,
bounded store. Both run on `Clock`, so tests drive them with `TestClock` — see
[testing.md](testing.md) — but `Schedule.jittered` draws from `Random`; seed it
(`Random.withSeed`) when a test needs a jittered policy to be deterministic.

## Retrying failures

`Effect.retry` takes an options object. Give every predicate its bound:

```ts
Effect.retry(task, { times: 3 })

const backoff = Schedule.exponential("100 millis").pipe(
  Schedule.jittered,
  Schedule.upTo({ times: 5 }),
)
Effect.retry(task, { while: (e) => e.status >= 500, schedule: backoff })
```

- **A bare `{ while }` or `{ until }` is unbounded and has no delay** — the
  default schedule is `forever`, which is `spaced(0)`, so a persistent
  transient failure becomes a hot loop. Always pair a predicate with
  `schedule` or `times`.
- The effect always runs once before the policy applies: `{ times: 3 }` means
  up to four executions.
- Only typed failures are retried — never defects or interruptions. Retry is
  not a substitute for typed errors ([errors.md](errors.md)); the `while`
  predicate on the error's tag or fields targets the transient subset.
- Bounds and composition: `Schedule.upTo({ times })` caps attempts (it also
  takes `duration`, an elapsed-time bound checked before each sleep — it
  bounds when the next retry may start, not total wall time). Compose
  policies with `Schedule.max([...])` (delay pattern + hard cap, e.g. backoff
  with `Schedule.recurs(5)`) and `Schedule.min([...])` (e.g. cap the delay:
  min of an exponential and `Schedule.spaced("2 seconds")`). The beta-line
  `Schedule.both`/`either` became `max`/`min` at .96. Predicates can live
  schedule-side too: `Schedule.while` with `Schedule.setInputType<E>()` when
  building a standalone policy.
- Exhausted retries propagate the last failure. To fall back instead:
  `Effect.retryOrElse(task, policy, (error, out) => fallback)`.

## Repeating successes

Same options shape, driven by success values: `Effect.repeat(eff, { times })`,
`{ while }` (same unbounded-predicate trap), or a schedule. A polling loop
belongs in a layer's scope with `Effect.forkScoped` + `Effect.repeat` — the
fence, the `spaced`-vs-`fixed` distinction, and the forever-loop-in-acquisition
trap are in [services-layers.md](services-layers.md). For wall-clock work use
`Schedule.cron("0 4 * * *")` rather than sleep-until arithmetic; note its error
channel carries `CronParseError`, which the caller handles.

## Cache

Two constructors, different shapes — `Cache.make` takes one options object;
`Cache.makeWith` takes the lookup separately and prices the TTL per result:

```ts
const cache = yield* Cache.make({
  capacity: 256,
  timeToLive: "5 minutes",
  lookup: (userId: UserId) => fetchUser(userId),
})

const priced = yield* Cache.makeWith(lookup, {
  capacity: 256,
  timeToLive: (exit, key) => (Exit.isFailure(exit) ? "30 seconds" : "5 minutes"),
})
```

- Concurrent `get`s of a missing key share a single lookup.
- **Failures are cached too.** The stored `Exit` replays the failure until the
  entry expires, `Cache.invalidate(cache, key)` removes it, or
  `Cache.refresh(cache, key)` replaces it.
- **The default `timeToLive` is `Duration.infinity`.** A cache built without a
  TTL caches one transient failure permanently. Set a TTL, and give failures
  a shorter one than successes (above) unless replaying them is intended.
- A cache is service state: build it during layer acquisition behind a seam,
  as in the worked example (`examples/fencecheck/src/retry-cache.ts`). Not a
  module-level global.
- `capacity` is mandatory — an unbounded cache is a leak with a name. Eviction
  at capacity is oldest-first.

## Do nots

- Do not recurse with `Effect.sleep` and a mutable attempt counter; the policy
  is a `Schedule` value.
- Do not catch-and-retry inside the effect body; apply `Effect.retry` at the
  call site that owns the policy — as an `Effect.fn` trailing combinator when
  the callee owns it ([services-layers.md](services-layers.md)).
- Do not build `Map`-plus-timestamp caches; `Date.now()` is banned in Effect
  code (`globalDateInEffect`) and the TTL/dedup/capacity logic already exists.
- Do not share one `Cache` across unrelated key domains; one cache per lookup
  contract.
