import { Cache, Context, Effect, Exit, Layer, Schedule, Schema } from "effect"

export class UpstreamError extends Schema.TaggedErrorClass<UpstreamError>()("UpstreamError", {
  status: Schema.Int,
}) {}

// Backoff policy: exponential, jittered, capped at five retries.
export const backoff = Schedule.exponential("100 millis").pipe(
  Schedule.jittered,
  Schedule.upTo({ times: 5 }),
)

export class Upstream extends Context.Service<Upstream, {
  readonly fetchProfile: (userId: string) => Effect.Effect<string, UpstreamError>
}>()("fencecheck/retry-cache/Upstream") {
  static readonly layerFake: Layer.Layer<Upstream> = Layer.sync(Upstream, () =>
    Upstream.of({
      fetchProfile: Effect.fn("Upstream.fetchProfile")((userId: string) =>
        Effect.succeed(`profile:${userId}`)),
    }))
}

export class Profiles extends Context.Service<Profiles, {
  readonly get: (userId: string) => Effect.Effect<string, UpstreamError>
  readonly evict: (userId: string) => Effect.Effect<void>
}>()("fencecheck/retry-cache/Profiles") {
  static readonly layerNoDeps: Layer.Layer<Profiles, never, Upstream> = Layer.effect(
    Profiles,
    Effect.gen(function* () {
      const upstream = yield* Upstream
      // One retry policy: back off, and only while the failure is transient.
      // A bare { while } with no schedule/times retries forever with no delay.
      const lookup = Effect.fn("Profiles.lookup")(
        function* (userId: string) {
          return yield* upstream.fetchProfile(userId)
        },
        Effect.retry({ while: (e: UpstreamError) => e.status >= 500, schedule: backoff }),
      )
      // Failed lookups are cached as their Exit: give errors a short life
      // instead of replaying them for the full success TTL.
      const cache = yield* Cache.makeWith(lookup, {
        capacity: 256,
        timeToLive: (exit) => (Exit.isFailure(exit) ? "30 seconds" : "5 minutes"),
      })
      const get = Effect.fn("Profiles.get")(function* (userId: string) {
        return yield* Cache.get(cache, userId)
      })
      const evict = Effect.fn("Profiles.evict")(function* (userId: string) {
        yield* Cache.invalidate(cache, userId)
      })
      return Profiles.of({ get, evict })
    }),
  )
}
