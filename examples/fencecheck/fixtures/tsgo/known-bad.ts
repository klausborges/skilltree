import { Effect, Schema } from "effect"

export class BadError extends Schema.TaggedErrorClass<BadError>()("BadError", {
  input: Schema.String,
}) {}

export const newOnSchemaClass = new BadError({ input: "x" })

export const globalDate = Effect.sync(() => Date.now())

export const globalRandom = Effect.sync(() => Math.random())

export const asyncFn = async (): Promise<number> => 1

export const tryCatchInGen = Effect.gen(function* () {
  try {
    return yield* Effect.succeed(1)
  } catch {
    return 0
  }
})
