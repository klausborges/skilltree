import { Context, Effect, Layer, Schema } from "effect"

export class DatabaseLive {}

export class Store {
  static readonly layerMemory = Layer.sync(Store as never, () => ({}) as never)
}

export const tag = Context.GenericTag<number>("B")

export const either = Effect.either

export const refined = Schema.minLength
