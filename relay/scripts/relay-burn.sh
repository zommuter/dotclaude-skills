#!/usr/bin/env bash
# relay-burn.sh — quota burnup time-series sampler + reporter (id:219b).
#
# The relay pool only ever READ point-in-time `utilization` snapshots from the usage
# cache to drive its stop-gate; it never persisted a series, so "how much did this run
# burn?" / "what's my $/hour overage?" was unanswerable. This script closes that gap by
# appending one sample per call to a JSONL and summarizing it — the data you need to
# evaluate Max x20 / x5 / Pro subscription-tier viability.
#
# Subcommands:
#   sample
#       Read $USAGE_CACHE, append ONE compact JSON line to $RELAY_QUOTA_SAMPLES.
#       Captures: ts, epoch, runId (from $RELAY_RUN_ID, best-effort), the three
#       utilization buckets (0-100%), extra_usage.used_credits (cumulative USD) +
#       monthly_limit, and each bucket's resets_at. Non-fatal: if the cache is
#       missing/unparseable it prints a note to stderr and exits 0 (callers on the
#       quota hot-path must never be broken by sampling).
#   report [--since <date-d-arg>] [--run <runId>] [--json]
#       Read the JSONL, segment at window/credit RESETS (a drop in used_credits or a
#       changed resets_at), and over the latest contiguous segment compute: elapsed,
#       Δused_credits ($ + $/h + $/day), and per-bucket Δutilization (%/h) projected to
#       each bucket's reset. --since filters by sample time; --run by runId; --json emits
#       the computed object instead of the human table.
#
# Paths: $RELAY_QUOTA_SAMPLES (default ~/.config/fables-turn/quota-samples.jsonl),
#        $USAGE_CACHE (default /tmp/claude-usage-cache.json — same file the statusline
#        and quota-stop.sh use). Append is serialized under a flock so concurrent
#        relay runs never interleave a line.
set -euo pipefail

SAMPLES="${RELAY_QUOTA_SAMPLES:-$HOME/.config/fables-turn/quota-samples.jsonl}"
USAGE_CACHE="${USAGE_CACHE:-/tmp/claude-usage-cache.json}"
RUN_ID="${RELAY_RUN_ID:-}"

cmd="${1:-}"; shift || true

case "$cmd" in
  sample)
    if [[ ! -f "$USAGE_CACHE" ]]; then
      echo "relay-burn: cache missing ($USAGE_CACHE) — no sample" >&2
      exit 0
    fi
    now_epoch=$(date +%s)
    now_iso=$(date '+%Y-%m-%dT%H:%M:%S%z')
    # Build the sample line from the cache with jq. If jq fails (bad JSON), skip — never
    # break a quota-gate caller. utilization fields may be null (buckets the API omits).
    line=$(RUN_ID="$RUN_ID" NOW_EPOCH="$now_epoch" NOW_ISO="$now_iso" \
      jq -c '{
        ts: env.NOW_ISO,
        epoch: (env.NOW_EPOCH | tonumber),
        runId: env.RUN_ID,
        five_hour: (.five_hour.utilization // null),
        seven_day: (.seven_day.utilization // null),
        seven_day_sonnet: (.seven_day_sonnet.utilization // null),
        used_credits: (.extra_usage.used_credits // null),
        monthly_limit: (.extra_usage.monthly_limit // null),
        five_hour_reset: (.five_hour.resets_at // null),
        seven_day_reset: (.seven_day.resets_at // null)
      }' "$USAGE_CACHE" 2>/dev/null) || {
        echo "relay-burn: cache unparseable — no sample" >&2; exit 0; }
    [[ -n "$line" ]] || { echo "relay-burn: empty sample — skipped" >&2; exit 0; }

    mkdir -p "$(dirname "$SAMPLES")"
    lock="$SAMPLES.lock"
    : >>"$lock"
    exec 9>>"$lock"
    flock -w 10 9 || { echo "relay-burn: sample lock timeout" >&2; exit 0; }
    printf '%s\n' "$line" >>"$SAMPLES"
    flock -u 9 || true
    ;;

  report)
    SINCE=""
    RUN_FILTER=""
    AS_JSON=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        --run)   RUN_FILTER="$2"; shift 2 ;;
        --json)  AS_JSON=1; shift ;;
        *) echo "relay-burn report: unknown arg '$1'" >&2; exit 2 ;;
      esac
    done
    [[ -f "$SAMPLES" ]] || { echo "relay-burn: no samples yet ($SAMPLES)" >&2; exit 1; }

    since_epoch=0
    if [[ -n "$SINCE" ]]; then
      since_epoch=$(date -d "$SINCE" +%s 2>/dev/null) || { echo "relay-burn: bad --since '$SINCE'" >&2; exit 2; }
    fi

    # Filter (by run, by since), sort by epoch, segment at resets, compute the latest
    # segment's burn. A reset boundary = used_credits drops OR seven_day_reset changes.
    result=$(SINCE_EPOCH="$since_epoch" RUN_FILTER="$RUN_FILTER" jq -s -c '
      ( [ .[]
          | select((env.RUN_FILTER == "") or (.runId == env.RUN_FILTER))
          | select(.epoch >= (env.SINCE_EPOCH | tonumber)) ]
        | sort_by(.epoch) ) as $rows
      | if ($rows | length) < 2 then
          { ok: false, n: ($rows | length) }
        else
          # Walk forward; start a new segment when used_credits drops or the 7d reset moves.
          ( reduce $rows[] as $r ({segs: [], cur: null};
              if .cur == null then { segs: .segs, cur: [$r] }
              elif ( ($r.used_credits != null) and ((.cur[-1].used_credits // 0) != null)
                     and ($r.used_credits < (.cur[-1].used_credits // 0)) )
                   or ( $r.seven_day_reset != (.cur[-1].seven_day_reset) ) then
                { segs: (.segs + [.cur]), cur: [$r] }
              else
                { segs: .segs, cur: (.cur + [$r]) }
              end
            ) ) as $acc
          | ( $acc.segs + [ $acc.cur ] ) as $segments
          | ( $segments | last ) as $seg
          | $seg[0] as $a | $seg[-1] as $b
          | (($b.epoch - $a.epoch)) as $dt
          | { ok: true,
              n: ($rows | length),
              segments: ($segments | length),
              seg_n: ($seg | length),
              from_ts: $a.ts, to_ts: $b.ts,
              elapsed_s: $dt,
              elapsed_h: ($dt / 3600),
              runId: ($b.runId // ""),
              d_credits: ( (($b.used_credits // 0) - ($a.used_credits // 0)) ),
              used_credits_now: ($b.used_credits),
              monthly_limit: ($b.monthly_limit),
              buckets: ( ["five_hour","seven_day","seven_day_sonnet"] | map(
                . as $k
                | { name: $k,
                    from: ($a[$k]), to: ($b[$k]),
                    delta: ( ($b[$k] // 0) - ($a[$k] // 0) ),
                    reset: ( if $k=="five_hour" then $b.five_hour_reset else $b.seven_day_reset end) } ) )
            }
          end
    ' "$SAMPLES")

    if [[ "$AS_JSON" -eq 1 ]]; then
      printf '%s\n' "$result"
      exit 0
    fi

    ok=$(jq -r '.ok' <<<"$result")
    if [[ "$ok" != "true" ]]; then
      n=$(jq -r '.n // 0' <<<"$result")
      echo "relay-burn: need ≥2 samples in range to compute a rate (have $n)." >&2
      exit 1
    fi

    # Human-readable summary. Rates computed in awk to avoid bc dep.
    jq -r '
      "RELAY BURNUP — " + (.from_ts) + "  →  " + (.to_ts),
      "  run:       " + (if .runId=="" then "(all)" else .runId end),
      "  samples:   \(.seg_n) in latest segment (\(.n) in range, \(.segments) segment(s))",
      "  elapsed:   \(.elapsed_h * 100 | round / 100) h"
    ' <<<"$result"
    # $ burn
    awk -v dc="$(jq -r '.d_credits' <<<"$result")" \
        -v h="$(jq -r '.elapsed_h' <<<"$result")" \
        -v now="$(jq -r '.used_credits_now // "?"' <<<"$result")" \
        -v lim="$(jq -r '.monthly_limit // "?"' <<<"$result")" '
      BEGIN {
        ph = (h>0)? dc/h : 0
        printf "  credits:   +$%.2f  ($%.3f/h, $%.2f/day)\n", dc, ph, ph*24
        if (now!="?") printf "  total now: $%.2f", now
        if (lim!="?") printf " of $%s monthly cap", lim
        if (now!="?") printf "\n"
      }'
    # per-bucket %/h + projected hours to reset/full
    jq -r '.buckets[] | [.name, (.from // 0), (.to // 0), .delta, (.reset // "")] | @tsv' <<<"$result" \
    | while IFS=$'\t' read -r name from to delta reset; do
        awk -v name="$name" -v from="$from" -v to="$to" -v d="$delta" \
            -v h="$(jq -r '.elapsed_h' <<<"$result")" -v reset="$reset" '
          BEGIN {
            rate = (h>0)? d/h : 0
            printf "  %-17s %5.1f%% → %5.1f%%  (%+.2f%%/h", name, from, to, rate
            if (reset != "") {
              cmd = "date -d \"" reset "\" +%s 2>/dev/null"; cmd | getline rs; close(cmd)
              cmd2 = "date +%s"; cmd2 | getline ns; close(cmd2)
              if (rs > ns) {
                hrs = (rs-ns)/3600
                # projected utilization at reset if rate holds
                proj = to + rate*hrs
                printf "; reset in %.1fh → ~%.0f%% at reset", hrs, proj
              }
            }
            printf ")\n"
          }'
      done
    ;;

  ""|-h|--help|help)
    sed -n '2,40p' "$0"
    ;;

  *)
    echo "relay-burn.sh: unknown subcommand '$cmd' (use sample|report)" >&2
    exit 2
    ;;
esac
