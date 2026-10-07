# Schema and boundaries (effect@4.0.0)

**Parse at the boundary.** Untrusted input — HTTP, DB rows, env, filesystem, CLI
args, IPC, external APIs, model output — gets decoded into typed domain values at
the edge. The interior only ever sees valid data.

The refined value flows inward. Never validate and then pass the raw value along.

All validation and domain modelling is `Schema`. Do not hand-roll type guards,
and never use `as` to skip validation.

## Choosing a shape

| Use | For |
|---|---|
| `Schema.Class` | domain values with identity, methods, or getters |
| `Schema.Struct` + `interface` | plain structural shapes and wire contracts |
| `Schema.TaggedClass` + `Schema.Union` | variants (OR types) |
| `Schema.Literals([...])` | simple string/number unions |
| `Schema.TaggedError` | errors — see [errors.md](errors.md) |

```ts
export class User extends Schema.Class<User>("User")({
  id: Schema.String.check(Schema.isUUID(4)),
  name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(64)),
  age: Schema.Int.check(Schema.isGreaterThanOrEqualTo(0)),
}) {
  get label() { return `${this.name} (${this.age})` }
}

export const Point = Schema.Struct({ x: Schema.Finite, y: Schema.Finite })
export interface Point extends Schema.Schema.Type<typeof Point> {}
```

`Schema.Opaque` is **not** `Schema.Class` — it has no prototype, no `instanceof`,
no methods, no `new`. It is a plain struct at runtime with a distinct type.

**Scope note:** `Data.TaggedEnum` is allowed for closed unions of trusted,
internal-only state — state machines, reducer states — where nothing crosses a
boundary. Its constructors make plain objects; `$is(tag)` type-guards on `_tag`
alone, and `$match` dispatches on `_tag` assuming an already-typed value —
neither validates structure. So the moment a value can arrive from outside, it
is Schema's job again
(the `Data` docs say the same: untrusted input validates through Schema first).
This scopes the "all modelling is Schema" rule; it does not reverse it.

## Refinements

v4 uses `.check(...)` with `is*` predicates. The v3 free functions
(`Schema.minLength`, `Schema.pattern`, `Schema.int`) are gone.

```ts
Schema.String.check(Schema.isMinLength(1), Schema.isPattern(/^[a-z-]+$/))
Schema.Int.check(Schema.isGreaterThan(0))
```

Available: `isMinLength` `isMaxLength` `isBetweenLength` `isPattern`
`isStartingWith` `isEndingWith` `isIncluding` `isTrimmed` `isNonEmpty` `isUUID`
`isULID` `isBase64` `isBetween({ minimum, maximum })`
`isGreaterThan(OrEqualTo)` `isLessThan(OrEqualTo)` `isInt` `isMultipleOf`
`isUnique`. The pre-4.0.0 spellings `isLengthBetween`, `isStartsWith`,
`isEndsWith`, and `isIncludes` are gone.

`.check` does not change the schema type — `.fields` and `.make` still work.
Filters must be **synchronous**; effectful validation goes through
`SchemaGetter.checkEffect` inside `Schema.decode`.

Custom filters return `undefined`/`true` for ok, or a message/issue for failure:

```ts
Schema.String.check(
  Schema.makeFilter((v) =>
    v.includes("\0") ? { path: [], issue: "contains a null byte" } : undefined),
)
```

Prefer `Schema.Finite` / `Schema.Int` over bare `Schema.Number` — the latter
admits `NaN` and `Infinity`.

Brand scalar identifiers. `Schema.brand` adds **no runtime check** — put
constraints before it:

```ts
export const UserId = Schema.String.check(Schema.isUUID(4)).pipe(Schema.brand("UserId"))
export type UserId = typeof UserId.Type
```

## Optionality

| API | Meaning |
|---|---|
| `Schema.optionalKey(S)` | key may be **absent**; decoding rejects explicit `undefined` |
| `Schema.optional(S)` | key may be absent **or** `undefined` |
| `Schema.OptionFromOptionalKey(S)` | absent key ⇔ required `Option<A>` on the Type side |
| `Schema.OptionFromOptional(S)` | absent **or** `undefined` ⇔ required `Option<A>` |
| `Schema.NullOr` / `UndefinedOr` / `NullishOr` | only when nullish is in the encoded contract |

Do not make a domain value optional merely for construction convenience. Keep
defaulted values required and apply the default during decoding or in the
constructor.

Locally, a plain `=== undefined` narrowing is fine and reads the way the Effect
source does. Once absence appears in a *public* signature, model it as `Option`.

## Decoding

The ladder — pick by what the caller can do with a failure:

| Form | Use |
|---|---|
| `decodeUnknownEffect` | **default** — inside Effect code, failure in the error channel |
| `decodeUnknownResult` | pure code that must branch on failure |
| `decodeUnknownSync` | scripts, tests, startup — **throws** |
| `decodeUnknownOption` | only when the reason is genuinely discarded |
| `decodeUnknownExit` | when you need defects/interrupts alongside the issue |

`decodeUnknown*` accepts `unknown`. `decode*` requires input already typed as the
schema's `Encoded`. Encoding mirrors all six shapes.

Parse JSON through a schema, never `JSON.parse(x) as T`:

```ts
export const Payload = Schema.fromJsonString(Schema.Struct({ id: Schema.String }))
const decode = Schema.decodeUnknownEffect(Payload)
```

Map decode failure into a domain error at the boundary so `SchemaError` does not
leak inward:

```ts
Schema.decodeUnknownEffect(User)(raw).pipe(
  Effect.mapError((e) => ConfigInvalid.make({ detail: e.message })),
)
```

Naming: call refiners `parseX` / `makeX` / `isX` — never `validateX`, which
invites validate-then-pass-the-raw-value. Every remaining cast needs a comment
justifying it.

## Config

Env is a boundary like any other — decode it with `Config.schema(...)`. Full
`Config` surface, providers, and secret handling: [runtime-config.md](runtime-config.md).

## Versioned persistence

Persisted data outlives the code. Use a literal-version union plus a fold:

```ts
const StoredV1 = Schema.Struct({ schemaVersion: Schema.Literal(1), name: Schema.String })
const StoredV2 = Schema.Struct({ schemaVersion: Schema.Literal(2), name: Schema.String, role: Role })
export const Stored = Schema.Union([StoredV1, StoredV2])
```

A union of one member is dead weight — add the second version when it exists.

## Traps

- `Schema.decode(t)` **builds** a schema; `decodeEffect` runs one.
- `Schema.Record` key schemas *select* properties — non-matching own keys are
  silently ignored, not rejected.
- `.check` filters are dropped by `mapFields` unless you pass
  `unsafePreserveChecks`, which the docs mark unsafe for good reason.
- `errors: "all"` is opt-in; the default reports the first issue only.
- v3's `Schema.filter` is gone. Its `check(makeFilter(...))` replacement keeps the
  original type by design — when you want narrowing, use `Schema.refine`.
- Do not use `Top` / `Schema` / `Codec` as annotations or return types; they are
  constraints. The exception is recursive schemas, which *require* an explicit
  `Schema.Codec<T>` annotation to stabilise.
- `validate*` is gone entirely — the equivalent is `decodeSync(Schema.toType(s))`.
