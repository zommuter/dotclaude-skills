#!/usr/bin/env bash
# orphan-scan.sh — sibling to append.sh, cost-of.sh
# Usage: orphan-scan.sh [--reverse|-r | --cross-ledger|-x | --promotion|-p] [<root-dir>]
# Forward (default): scans <root>/docs/meeting-notes/*.md for ID-bearing unchecked action items
#   whose <!-- id:XXXX --> token is absent from the union of TODO.md + TODO.archive.md + ROADMAP.md.
# Reverse (--reverse): finds ID-bearing checked ([x]) or inline lines absent from the TODO union
#   — the forward scan's blind spot (Step 5b skipped, items completed in-session).
# Cross-ledger (--cross-ledger): single-id-two-views guard (D2, meeting note
#   2026-06-15-0715-meeting-fables-interaction.md). Flags any <!-- id:XXXX --> token
#   present in BOTH the TODO union (TODO.md + TODO.archive.md) AND ROADMAP.md whose
#   checkbox state ([ ] vs [x]) DISAGREES across the two ledgers — i.e. work closed in
#   ROADMAP but left open in TODO (or vice versa). A duplicate id with matching state is
#   the intended single-id-two-views shape and is NOT flagged; a duplicate is only
#   detectable once promotion reuses the id, so this guard also enforces that contract.
#   Scope-split false-positives can be suppressed with <!-- xledger-ok: <reason> --> on
#   the open-side line (id:d9b0) — a divergence annotated with xledger-ok is intentional
#   and not flagged; an unannotated divergence still is.
# Promotion (--promotion): id:d9b0 — scans TODO.md (and archive) for OPEN items carrying
#   an executable lane tag ([ROUTINE] or [HARD — pool]) whose <!-- id:XXXX --> token has
#   NO twin in ROADMAP.md. An un-promoted item is "pool-invisible": the relay can't see it.
#   Prints one line per un-promoted item; exits 0 regardless (caller decides severity).
# Shipped (--shipped): id:b3ee — report-only reconciliation of stale-ledger drift (see
#   docs/meeting-notes/2026-07-07-1138-stale-ledger-root-cause.md). Scans OPEN `- [ ]`
#   items in TODO.md for two classes; NEVER auto-ticks anything, advisory text only.
#   Gate words split into two disjoint classes (tuned 2026-07-07):
#     COMPLETION-pending = REMAIN|pending|activation (work that finishes + clears silently)
#     EXTERNAL-WAIT      = observe|verify|awaiting|gated|re-evaluate|let it run (legit-open)
#   - TICK-READY: item has NEITHER gate class AND a test file carries `# roadmap:<token>`
#     for this item (the intentional test-owns-item link — a bare inline path mention is
#     NOT trusted, it over-fires on umbrella items) that passes GREEN when run.
#   - GATE-STALE: item has a COMPLETION-pending word (and no EXTERNAL-WAIT word) AND its
#     TODO.md line is >= 14 days old by `git blame` author-time (override via
#     ORPHAN_SCAN_SHIPPED_AGE_DAYS) — the completion clause may have lapsed; re-check.
#   - EXTERNAL-WAIT items are suppressed from BOTH classes (genuinely gated, don't nag).
# Un-IDed lines are skipped (clean cutover; legacy notes stay frozen).
# Prints candidate lines to stdout; writes one log line to ~/.claude/logs/meeting-orphan-scan.log.
set -euo pipefail

mode="forward"
if [[ "${1:-}" == "--reverse" || "${1:-}" == "-r" ]]; then
  mode="reverse"
  shift
elif [[ "${1:-}" == "--cross-ledger" || "${1:-}" == "-x" ]]; then
  mode="cross-ledger"
  shift
elif [[ "${1:-}" == "--promotion" || "${1:-}" == "-p" ]]; then
  mode="promotion"
  shift
elif [[ "${1:-}" == "--shipped" || "${1:-}" == "-s" ]]; then
  mode="shipped"
  shift
fi

ROOT="${1:-$(git rev-parse --show-toplevel)}"
NOTES_DIR="$ROOT/docs/meeting-notes"
LOG="$HOME/.claude/logs/meeting-orphan-scan.log"
mkdir -p "$(dirname "$LOG")"

limit="${ORPHAN_SCAN_LIMIT:-10}"
start_ms=$(date +%s%3N)
# Union ledger: TODO + archive + relay ROADMAP (a note item mirrored to
# ROADMAP.md instead of TODO.md is not an orphan).
# Plugin-aware union (zkm B-topology, meeting 2026-06-30 D2): in a polyrepo whose
# plugins own their own TODO.md (each `plugins/*/`), a root meeting note can cite an
# id that now lives in a plugin's ledger, not central. Include those ledgers so the
# "tracked anywhere?" scans (forward + reverse) don't false-flag relocated ids. Only
# the union blob is plugin-aware; cross-ledger/promotion build their own intra-ledger
# maps and stay per-(plugin-or-root) by design. No-op for plugins-less repos.
ledger_files=("$ROOT/TODO.md" "$ROOT/TODO.archive.md" "$ROOT/ROADMAP.md")
if [[ -d "$ROOT/plugins" ]]; then
  for p in "$ROOT"/plugins/*/; do
    ledger_files+=("$p/TODO.md" "$p/TODO.archive.md" "$p/ROADMAP.md")
  done
fi
todo="$(cat "${ledger_files[@]}" 2>/dev/null || true)"
notes=0
id_lines=0
candidates=0
output_lines=()

if [[ "$mode" == "cross-ledger" ]]; then
  # Build token→state maps for the TODO union and for ROADMAP separately, then
  # flag tokens present in both whose checkbox state disagrees. A line may carry
  # multiple <!-- id:XXXX --> tokens (all share that line's state).
  # id:d9b0: a line annotated with <!-- xledger-ok: <reason> --> is an intentional
  # scope-split (e.g. closed ROADMAP decision + open TODO action with different scope).
  # Such lines are NOT flagged; an empty reason "<!-- xledger-ok: -->" still suppresses.
  declare -A todo_state roadmap_state todo_xledger_ok
  while IFS= read -r l; do
    st=' '; [[ "$l" == "- [x] "* || "$l" == "- [X] "* ]] && st='x'
    xok=''; [[ "$l" == *"<!-- xledger-ok:"* ]] && xok='1'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      # First-wins: the FIRST occurrence of a token is the authoritative (active)
      # state. TODO.md is processed before TODO.archive.md (grep -h file order), so
      # the active TODO.md entry wins over a reused/recycled id in TODO.archive.md.
      # This prevents a recycled archive id from overwriting the current open-item
      # state and producing a false-positive drift report (id:9221 fix).
      [[ -n "${todo_state[$tk]+x}" ]] || todo_state["$tk"]="$st"
      [[ -n "$xok" ]] && todo_xledger_ok["$tk"]='1' || true
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^- \[[ xX]\] ' "$ROOT/TODO.md" "$ROOT/TODO.archive.md" 2>/dev/null || true)
  while IFS= read -r l; do
    st=' '; [[ "$l" == "- [x] "* || "$l" == "- [X] "* ]] && st='x'
    xok=''; [[ "$l" == *"<!-- xledger-ok:"* ]] && xok='1'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      # First-wins: same rationale as the TODO loop above (id:9221).
      [[ -n "${roadmap_state[$tk]+x}" ]] || roadmap_state["$tk"]="$st"
      [[ -n "$xok" ]] && todo_xledger_ok["$tk"]='1' || true
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^- \[[ xX]\] ' "$ROOT/ROADMAP.md" 2>/dev/null || true)
  for tk in "${!todo_state[@]}"; do
    [[ -n "${roadmap_state[$tk]:-}" ]] || continue
    id_lines=$((id_lines+1))
    if [[ "${todo_state[$tk]}" != "${roadmap_state[$tk]}" ]]; then
      # Suppress intentional scope-splits annotated with xledger-ok (id:d9b0).
      [[ -n "${todo_xledger_ok[$tk]:-}" ]] && continue
      candidates=$((candidates+1))
      output_lines+=("id:$tk — TODO:[${todo_state[$tk]}] ROADMAP:[${roadmap_state[$tk]}] (checkbox state disagrees across ledgers)")
    fi
  done
elif [[ "$mode" == "promotion" ]]; then
  # id:d9b0 — flag open TODO items with an executable lane tag ([ROUTINE] or [HARD — pool])
  # that have no twin id:XXXX in ROADMAP.md. Such items are "un-promoted, pool-invisible".
  roadmap_content="$(cat "$ROOT/ROADMAP.md" 2>/dev/null || true)"
  while IFS= read -r l; do
    # Executable lane tag: [ROUTINE] or [HARD — pool]
    echo "$l" | grep -qE '\[ROUTINE\]|\[HARD — pool\]' || continue
    token="$(echo "$l" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)"
    [[ -z "$token" ]] && continue
    id_lines=$((id_lines+1))
    if ! grep -qF "id:$token" <<<"$roadmap_content"; then
      candidates=$((candidates+1))
      output_lines+=("un-promoted id:$token — $l")
    fi
  done < <(grep -hE '^- \[ \] ' "$ROOT/TODO.md" "$ROOT/TODO.archive.md" 2>/dev/null || true)
elif [[ "$mode" == "shipped" ]]; then
  # id:b3ee — stale-ledger reconciliation. Only TODO.md's OPEN items are in scope
  # (already-[x] items are never candidates; ROADMAP/archive are out of scope by design).
  # Two disjoint gate-word classes (tuned 2026-07-07 after dogfooding flagged ~50
  # GATE-STALE hits — see the root-cause note's follow-up). A COMPLETION-pending
  # clause describes remaining work that will finish and clear SILENTLY (the
  # id:6f61/b67e silent-drift class) → worth an age-based re-check. An EXTERNAL-WAIT
  # clause is legitimately open (external dep / observation window still running) →
  # neither GATE-STALE (would nag forever) nor TICK-READY (it is genuinely gated).
  completion_re='REMAIN|pending|activation'
  wait_re='observe|verify|awaiting|gated|re-evaluate|let it run'
  age_days_threshold="${ORPHAN_SCAN_SHIPPED_AGE_DAYS:-14}"
  now_epoch=$(date +%s)
  while IFS=: read -r lineno text; do
    token=$(echo "$text" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)
    [[ -z "$token" ]] && continue
    id_lines=$((id_lines+1))
    if echo "$text" | grep -qiE "$wait_re"; then
      # EXTERNAL-WAIT clause: legitimately open — suppress from both classes.
      continue
    elif echo "$text" | grep -qiE "$completion_re"; then
      # GATE-STALE candidate: the completion clause may have lapsed — check line age.
      commit_epoch=$(git -C "$ROOT" blame -L "${lineno},${lineno}" --porcelain -- TODO.md 2>/dev/null \
        | grep -m1 '^author-time ' | awk '{print $2}' || true)
      [[ -z "$commit_epoch" ]] && continue
      age_days=$(( (now_epoch - commit_epoch) / 86400 ))
      if (( age_days >= age_days_threshold )); then
        candidates=$((candidates+1))
        output_lines+=("id:$token — GATE-STALE (line age ${age_days}d >= ${age_days_threshold}d) — gating clause may have lapsed; re-check. $text")
      fi
    else
      # TICK-READY candidate: needs a test that EXPLICITLY owns this item via a
      # `# roadmap:<token>` header (the intentional test-owns-item signal). A bare
      # inline `tests/test_*.sh` path mention is NOT trusted — a multi-part/umbrella
      # item routinely cites a sub-part's test in prose, which produced false
      # "ready to tick" hits on live items (id:401c/af30) when dogfooded 2026-07-07.
      match=$(grep -rlE "# roadmap:$token([^0-9a-f]|\$)" "$ROOT/tests" 2>/dev/null | head -1 || true)
      [[ -z "$match" ]] && continue
      test_rel="${match#"$ROOT"/}"
      [[ ! -f "$ROOT/$test_rel" ]] && continue
      if (cd "$ROOT" && bash "$test_rel") >/dev/null 2>&1; then
        candidates=$((candidates+1))
        output_lines+=("id:$token — TICK-READY (green: $test_rel, no gate) — ready to tick. $text")
      fi
    fi
  done < <(grep -n '^- \[ \] ' "$ROOT/TODO.md" 2>/dev/null || true)
else
for f in $(ls -r1 "$NOTES_DIR"/*.md 2>/dev/null); do
  [[ -f "$f" ]] || continue
  [[ "$(basename "$f")" == "meeting-style.md" ]] && continue
  notes=$((notes+1))
  if [[ "$mode" == "forward" ]]; then
    while IFS=: read -r lineno text; do
      # Only consider lines that carry an <!-- id:XXXX --> token
      token=$(echo "$text" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)
      [[ -z "$token" ]] && continue
      id_lines=$((id_lines+1))
      if ! grep -qF "id:$token" <<<"$todo"; then
        candidates=$((candidates+1))
        output_lines+=("$(basename "$f"):$lineno  $text")
      fi
    done < <(grep -n '^- \[ \] ' "$f" || true)
  else
    # Reverse mode: all ID-bearing lines EXCEPT unchecked action items (forward scan's domain)
    while IFS=: read -r lineno text; do
      # Skip unchecked action items — covered by the forward scan
      [[ "${text:0:6}" == "- [ ] " ]] && continue
      token=$(echo "$text" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)
      [[ -z "$token" ]] && continue
      id_lines=$((id_lines+1))
      if ! grep -qF "id:$token" <<<"$todo"; then
        candidates=$((candidates+1))
        if [[ "${text:0:6}" == "- [x] " ]]; then
          state="[x]"
        else
          state="inline"
        fi
        output_lines+=("$(basename "$f"):$lineno  $state $text")
      fi
    done < <(grep -n '<!-- id:[0-9a-f]\{4\} -->' "$f" || true)
  fi
done
fi

runtime_ms=$(( $(date +%s%3N) - start_ms ))
printf '%s\t%s\tmode=%s\tnotes=%d\tid_lines=%d\tcandidates=%d\truntime_ms=%d\n' \
  "$(date -Iseconds)" "$(basename "$ROOT")" "$mode" "$notes" "$id_lines" "$candidates" "$runtime_ms" \
  >> "$LOG"

total=${#output_lines[@]}
if [[ "$limit" -gt 0 && "$total" -gt "$limit" ]]; then
  printf '%s\n' "${output_lines[@]:0:$limit}"
  suppressed=$(( total - limit ))
  printf '# orphan-scan: %d more candidates suppressed (cap=%d); set ORPHAN_SCAN_LIMIT=0 for full output\n' \
    "$suppressed" "$limit"
else
  printf '%s\n' "${output_lines[@]:-}"
fi
