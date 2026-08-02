import { Schema } from "@effect/schema"

export const anyCast = JSON.parse("{}") as any

export const nonNull = (x: string | undefined) => x!.length

export const floating = () => {
  void 0
  Promise.resolve(1).then(() => 2)
}

export const yieldFreeGen = function* () {
  return 1
}

export { Schema }
