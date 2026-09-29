#!/usr/bin/env bash
#
# bench.sh — Vite vs Laravel Mix benchmark harness.
#
# Generates stress components at several sizes, runs cold and warm production
# builds N times each, records duration / peak RSS / output size / chunk count,
# and writes a raw CSV plus a summarised CSV with medians.
#
# Usage:
#   ./bench.sh                                  # 5 iters x {100,1000,9999} x both projects
#   ./bench.sh --smoke                          # 1 iter x {100} x both
#   ./bench.sh --iterations 3 --counts 100,9999
#   ./bench.sh --projects laravel-vite
#   ./bench.sh --output custom.csv
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITERATIONS=5
COUNTS="100,1000,9999"
PROJECTS="laravel-vite,laravel-mix"
OUTPUT="${ROOT}/results.csv"
SUMMARY="${ROOT}/summary.csv"

usage() {
  sed -n '2,17p' "$0" | sed -E 's/^# ?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --counts)     COUNTS="$2";     shift 2 ;;
    --projects)   PROJECTS="$2";   shift 2 ;;
    --output)     OUTPUT="$2";     shift 2 ;;
    --summary)    SUMMARY="$2";    shift 2 ;;
    --smoke)      ITERATIONS=1; COUNTS="100"; shift ;;
    -h|--help)    usage ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

for bin in node pnpm awk; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing dependency: $bin" >&2; exit 1; }
done

IFS=',' read -ra PROJ_ARR <<< "$PROJECTS"
IFS=',' read -ra CNT_ARR  <<< "$COUNTS"

for proj in "${PROJ_ARR[@]}"; do
  dir="${ROOT}/${proj}"
  if [[ ! -d "$dir" ]]; then
    echo "Project not found: $proj" >&2
    exit 1
  fi
  if [[ ! -d "${dir}/node_modules" ]]; then
    echo "Run 'pnpm install' in ${proj}/ first." >&2
    exit 1
  fi
  if [[ ! -f "${dir}/scripts/gen-stress.mjs" ]]; then
    echo "Missing scripts/gen-stress.mjs in ${proj}/" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Portable timing + peak RSS
# ---------------------------------------------------------------------------

now() {
  if date +%s.%N >/dev/null 2>&1; then
    date +%s.%N
  else
    date +%s
  fi
}

TIME_BIN=""
TIME_STYLE="none"
if command -v /usr/bin/time >/dev/null 2>&1 && /usr/bin/time -v true >/dev/null 2>&1; then
  TIME_BIN="/usr/bin/time"; TIME_STYLE="gnu"
elif command -v /usr/bin/time >/dev/null 2>&1 && /usr/bin/time -l true >/dev/null 2>&1; then
  TIME_BIN="/usr/bin/time"; TIME_STYLE="bsd"
elif command -v gtime >/dev/null 2>&1 && gtime -v true >/dev/null 2>&1; then
  TIME_BIN="gtime"; TIME_STYLE="gnu"
fi

# timed CMD... -> prints "duration_s peak_rss_kb"
timed() {
  case "$TIME_STYLE" in
    gnu)
      local tmp; tmp=$(mktemp)
      "$TIME_BIN" -v "$@" >/dev/null 2>"$tmp" || true
      local dur rss
      dur=$(grep -E "Elapsed \(wall clock\)" "$tmp" \
            | sed -E 's/.*\): //' \
            | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else if (NF==2) print $1*60+$2; else print $1 }')
      rss=$(grep -E "Maximum resident set size" "$tmp" | awk '{print $NF}')
      rm -f "$tmp"
      echo "${dur:-0} ${rss:-0}"
      ;;
    bsd)
      local tmp; tmp=$(mktemp)
      "$TIME_BIN" -l "$@" >/dev/null 2>"$tmp" || true
      local dur rss
      dur=$(grep -E "^[[:space:]]*[0-9.]+ real" "$tmp" | awk '{print $1}')
      rss=$(grep -E "maximum resident set size" "$tmp" | awk '{print $1}')
      rm -f "$tmp"
      echo "${dur:-0} ${rss:-0}"
      ;;
    *)
      local start end
      start=$(now); "$@" >/dev/null 2>&1 || true; end=$(now)
      awk -v a="$start" -v b="$end" 'BEGIN { printf "%.3f 0\n", b - a }'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Per-project helpers
# ---------------------------------------------------------------------------

clear_cache() {
  local dir="$1" name="$2"
  case "$name" in
    laravel-vite)
      rm -rf "${dir}/node_modules/.vite" \
             "${dir}/public/build" \
             "${dir}/bootstrap/ssr" 2>/dev/null || true
      ;;
    laravel-mix)
      rm -rf "${dir}/node_modules/.cache" \
             "${dir}/public/js" \
             "${dir}/public/css" \
             "${dir}/public/mix-manifest.json" 2>/dev/null || true
      ;;
  esac
}

# measure_output DIR NAME -> "js_kb css_kb chunk_count"
measure_output() {
  local dir="$1" name="$2"
  local js_bytes=0 css_bytes=0 chunks=0
  case "$name" in
    laravel-vite)
      if [[ -d "${dir}/public/build" ]]; then
        js_bytes=$(find "${dir}/public/build" -name '*.js' -type f -exec cat {} + 2>/dev/null | wc -c)
        css_bytes=$(find "${dir}/public/build" -name '*.css' -type f -exec cat {} + 2>/dev/null | wc -c)
        chunks=$(find "${dir}/public/build" -name '*.js' -type f 2>/dev/null | wc -l)
      fi
      ;;
    laravel-mix)
      if [[ -d "${dir}/public/js" ]]; then
        js_bytes=$(find "${dir}/public/js" -name '*.js' -type f -exec cat {} + 2>/dev/null | wc -c)
        chunks=$(find "${dir}/public/js" -name '*.js' -type f 2>/dev/null | wc -l)
      fi
      if [[ -d "${dir}/public/css" ]]; then
        css_bytes=$(find "${dir}/public/css" -name '*.css' -type f -exec cat {} + 2>/dev/null | wc -c)
      fi
      ;;
  esac
  awk -v j="$js_bytes" -v c="$css_bytes" -v n="$chunks" \
    'BEGIN { printf "%d %d %d\n", j/1024, c/1024, n }'
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

echo "timestamp_utc,project,component_count,iteration,phase,duration_s,peak_rss_kb,total_js_kb,total_css_kb,chunk_count" > "$OUTPUT"

for proj in "${PROJ_ARR[@]}"; do
  dir="${ROOT}/${proj}"
  for count in "${CNT_ARR[@]}"; do
    echo ">>> ${proj} @ ${count} components" >&2

    ( cd "$dir" && node scripts/gen-stress.mjs "$count" ) >&2

    for ((i=1; i<=ITERATIONS; i++)); do
      # ----- cold -----
      clear_cache "$dir" "$proj"
      read -r dur rss <<< "$( cd "$dir" && timed pnpm run build )"
      read -r js_kb css_kb chunks <<< "$( measure_output "$dir" "$proj" )"
      ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      echo "${ts},${proj},${count},${i},cold,${dur},${rss},${js_kb},${css_kb},${chunks}" >> "$OUTPUT"

      # ----- warm -----
      read -r dur rss <<< "$( cd "$dir" && timed pnpm run build )"
      read -r js_kb css_kb chunks <<< "$( measure_output "$dir" "$proj" )"
      ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      echo "${ts},${proj},${count},${i},warm,${dur},${rss},${js_kb},${css_kb},${chunks}" >> "$OUTPUT"
    done

    ( cd "$dir" && node scripts/clean-stress.mjs ) >&2
  done
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "project,component_count,phase,n,median_s,min_s,max_s,median_rss_kb,total_js_kb,total_css_kb,chunk_count" > "$SUMMARY"

awk -F, '
  NR == 1 { next }
  {
    key = $2 "|" $3 "|" $5
    n[key]++
    durs[key, n[key]] = $6 + 0
    rsss[key, n[key]] = $7 + 0
    js[key]  = $8 + 0
    css[key] = $9 + 0
    ch[key]  = $10 + 0
  }
  END {
    for (k in n) {
      split(k, p, "|")
      m = n[k]

      for (i = 1; i <= m; i++) d[i] = durs[k, i]
      for (i = 1; i <= m; i++)
        for (j = i + 1; j <= m; j++)
          if (d[i] > d[j]) { t = d[i]; d[i] = d[j]; d[j] = t }
      med  = (m % 2) ? d[int(m/2) + 1] : (d[m/2] + d[m/2 + 1]) / 2

      for (i = 1; i <= m; i++) r[i] = rsss[k, i]
      for (i = 1; i <= m; i++)
        for (j = i + 1; j <= m; j++)
          if (r[i] > r[j]) { t = r[i]; r[i] = r[j]; r[j] = t }
      rmed = (m % 2) ? r[int(m/2) + 1] : (r[m/2] + r[m/2 + 1]) / 2

      printf "%s,%s,%s,%d,%.3f,%.3f,%.3f,%d,%d,%d,%d\n", \
        p[1], p[2], p[3], m, med, d[1], d[m], rmed, js[k], css[k], ch[k]
    }
  }
' "$OUTPUT" | sort -t, -k1,1 -k2,2n -k3,3 >> "$SUMMARY"

echo
echo "Raw:     $OUTPUT"
echo "Summary: $SUMMARY"
