import { Data } from "effect"
import type { UpstreamError } from "./retry-cache.js"

// Internal-only state union: trusted values that never cross a boundary —
// Data.TaggedEnum territory. Anything untrusted still decodes through Schema.
export type FetchState = Data.TaggedEnum<{
  Idle: {}
  Fetching: { readonly attempt: number }
  Failed: { readonly error: UpstreamError }
}>
export const FetchState = Data.taggedEnum<FetchState>()

export const describeState = (state: FetchState): string =>
  FetchState.$match(state, {
    Idle: () => "idle",
    Fetching: ({ attempt }) => `fetching (attempt ${attempt})`,
    Failed: ({ error }) => `failed (${error.status})`,
  })
