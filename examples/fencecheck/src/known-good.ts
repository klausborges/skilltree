import { Clock, Context, Effect, Layer, Schema } from "effect"

export class ParseInputError extends Schema.TaggedErrorClass<ParseInputError>()("ParseInputError", {
  input: Schema.String,
}) {}

export class Stamper extends Context.Service<Stamper, {
  readonly stamp: (label: string) => Effect.Effect<string, ParseInputError>
}>()("fencecheck/known-good/Stamper") {
  static readonly layer = Layer.sync(Stamper, () => {
    const stamp = Effect.fn("Stamper.stamp")(function* (label: string) {
      if (label.length === 0) {
        return yield* ParseInputError.make({ input: label })
      }
      const now = yield* Clock.currentTimeMillis
      return `${label}@${now}`
    })
    return Stamper.of({ stamp })
  })
}
