# skilltree

technical agent skills grown from real project work. [workflow skills](https://github.com/klausborges/workflow-skills) brings the rails; skilltree brings the unusually specific branches. they compose well, but neither repo needs the other.

the tree is young and, somehow, already overgrown. these skills are currently a bit gigantic: they began as working field notes while tools and APIs were moving, and i'm still pruning them toward something sharper and more concise. useful today, lighter tomorrow; the present acreage is not the ideal final shape.

## skills

| skill | purpose |
| --- | --- |
| [`effect-v4`](./skills/effect-v4/SKILL.md) | patterns, architecture judgment, and a read-only enforcement preset for Effect v4 and TypeScript. |

## install from GitHub

install `effect-v4` with the [Vercel Labs skills CLI](https://github.com/vercel-labs/skills):

```sh
npx skills add klausborges/skilltree --skill effect-v4 -a claude-code codex -y
```

list the skills from a local checkout:

```sh
npx skills add . --list
```

## verify

the example workspace contains known-good code and deliberately troublesome fixtures for the checker:

```sh
pnpm --dir examples install --frozen-lockfile
nu --no-config-file skills/effect-v4/scripts/check-effect.test.nu
```

if macOS reports `EACCES` for the `effect-tsgo` binary, restore its executable bit before rerunning:

```sh
find examples/node_modules/.pnpm -path '*tsgo-*/lib/tsc' -exec chmod +x {} +
```

## license

MIT. see [LICENSE](./LICENSE).
