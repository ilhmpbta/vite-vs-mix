# vite-vs-mix

A head-to-head comparison of two otherwise-identical Laravel + Inertia + React starter kits, one built with **Vite** and one with **Laravel Mix / webpack**.

The goal is to answer, with reproducible numbers, a question that comes up in every new Laravel + React project:

> In 2026, how much does the bundler actually matter - and at what point
> does it stop mattering?

## What this repo offers

- **Two sibling starter kits** baased on the [laravel/react-starter-kit](https://github.com/laravel/react-starter-kit), byte-for-byte identical on the PHP side and
  differing only in frontend build tooling:
  - `laravel-vite/` - Vite 8 (via `vite-plus`), `@vitejs/plugin-react`,
    `@tailwindcss/vite`, SSR enabled.
  - `laravel-mix/` - Laravel Mix 6 / webpack 5.93, `ts-loader` in
    `transpileOnly` mode, `@tailwindcss/postcss`, SSR disabled.
- **A deterministic stress generator** (`scripts/gen-stress.mjs`) that writes
  N React components (100, 9999, …) sharing a single utility module,
  so both bundlers see the same module graph shape.
- **A clean-up script** (`scripts/clean-stress.mjs`) that removes every
  generated artefact.
- **A benchmark harness** (`bench.sh`) that generates components, runs cold
  and warm production builds N times per configuration, records wall time,
  peak RSS, output size and chunk count, and writes both a raw and a
  summarised CSV.
- **Committed lockfiles** (`pnpm-lock.yaml` in both projects) so
  `pnpm install --frozen-lockfile` is byte-reproducible.

## TL;DR

Initial numbers on a single workstation, 5 iterations per cell, median:

| Components | Vite (median) | Mix / webpack (median) | Speedup |
|-----------:|--------------:|-----------------------:|--------:|
| 100        | ~8.8 s        | ~19.2 s                | **2.2×** |
| 9999       | ~10.2 s       | ~22.0 s                | **2.2×** |

Both bundlers remain usable at 9999 components. Vite's per-component cost
is roughly flat; Mix's grows slowly and varies more run-to-run.

## Repository layout

```
vite-vs-mix/
├── README.md          ← this file
├── bench.sh           ← benchmark harness (raw + summary CSV)
├── laravel-vite/      ← Vite 8 starter kit (SSR enabled)
│   ├── scripts/gen-stress.mjs
│   ├── scripts/clean-stress.mjs
│   ├── vite.config.ts
│   └── ...
└── laravel-mix/       ← Laravel Mix 6 / webpack 5 starter kit (SSR disabled)
    ├── scripts/gen-stress.mjs
    ├── scripts/clean-stress.mjs
    ├── webpack.mix.js
    └── ...
```

## Quickstart

### 1. Install dependencies

For each project:

```bash
cd laravel-vite   # or laravel-mix
composer install
pnpm install --frozen-lockfile
```

### 2. Generate a stress tree

```bash
node scripts/gen-stress.mjs 100    # or 1000, 9999
```

This writes:

- `resources/js/components/stress/Stress0001.tsx` … `StressNNNN.tsx`
- `resources/js/components/stress/index.tsx` - barrel that mounts them all
- `resources/js/lib/stress-utils.ts` - shared module every component imports

A page at `/stress` mounts the whole grid. Run `php artisan serve` and visit
`http://localhost:8000/stress` to inspect it.

### 3. Build

```bash
pnpm run build
```

### 4. Clean up

```bash
node scripts/clean-stress.mjs
```

## Benchmarking

`bench.sh` orchestrates the whole loop for you.

```bash
./bench.sh --help
```

Typical invocations:

```bash
# Full sweep: 5 iterations × {100,1000,9999} × both projects
./bench.sh

# Quick smoke test: 1 iteration × {100} × both projects
./bench.sh --smoke

# Focused: 3 iterations, one project, custom counts
./bench.sh --iterations 3 --counts 100,9999 --projects laravel-vite
```

Outputs:

- `results.csv` - one row per build, with columns
  `timestamp_utc, project, component_count, iteration, phase, duration_s,
  peak_rss_kb, total_js_kb, total_css_kb, chunk_count`
- `summary.csv` - same data grouped by `project × component_count × phase`,
  with median, min, max for duration and peak RSS.

### What gets measured

| Metric | How |
|---|---|
| **Duration** | wall clock around `pnpm run build` |
| **Peak RSS** | `/usr/bin/time -v` (Linux) or `-l` (macOS) when available |
| **Cold vs warm** | cold = cache directories removed first; warm = immediate rebuild |
| **Total JS / CSS** | byte sum of `.js` / `.css` in the build output dir |
| **Chunk count** | count of `.js` files emitted |

Cache directories cleared per project:

- `laravel-vite`: `node_modules/.vite`, `public/build`, `bootstrap/ssr`
- `laravel-mix`: `node_modules/.cache`, `public/js`, `public/css`,
  `public/mix-manifest.json`

## Interpreting the numbers

A few things to keep in mind when reading the CSVs:

- **Wall-clock variance is real.** Even warm, both bundlers swing ±10–25 %
  between runs. Use median, not mean, and never trust a single `time`
  invocation.
- **Absolute numbers don't transfer.** CPU, disk, and Node version all move
  the needle. The *ratio* is the portable quantity.
- **Cold vs warm matters differently per tool.** Vite relies heavily on
  `node_modules/.vite`; Mix relies on `node_modules/.cache` (babel-loader,
  terser). Clearing one but not the other biases the comparison.
- **This is not a feature-parity comparison.** `laravel-mix` has SSR
  disabled; `laravel-vite` ships an SSR bundle. That's a capability
  difference, not a speed one.
- **Mix builds with `transpileOnly: true`.** Type errors are not caught by
  the build in either project - `pnpm run types:check` handles that
  separately and is bundler-independent.
