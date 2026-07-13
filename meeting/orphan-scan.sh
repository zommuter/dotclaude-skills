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
#   Typed-edge closure (typed-ledger-edges meeting 2026-07-10, id:46f6): an item that
#   carries a `<!-- children:a,b,c -->` and/or `<!-- gated-on:d,e -->` sibling marker
#   (form C: sibling comments BEFORE the terminal `<!-- id:XXXX -->`) BYPASSES the
#   wait_re/completion_re heuristic entirely and is decided by the typed predicate.
#   Unmarked items keep the exact code path above (zero blast radius, A2 "dissolve don't
#   guard"). Child/gate tokens resolve against TODO.md ∪ TODO.archive.md ONLY (ROADMAP.md
#   drift belongs to --cross-ledger). "closed" ⇒ the resolving line is `- [x]` (mere
#   membership in the archive is NOT closed — an archived parent can nest an open `- [ ]`
#   sub-item). Typed classes:
#     UMBRELLA-READY     — every child resolves AND all `[x]`. Reported (no `# roadmap:` test needed).
#     UMBRELLA-OPEN      — every child resolves, ≥1 `[ ]`. Silent.
#     UMBRELLA-CROSS-REPO— ≥1 child unresolved but prose names a CONFIRMED own repo (from
#                          relay.toml via relay/scripts/lib-own-repos.sh — NEVER a ~/src glob;
#                          zkm-ner lives at ~/src/zkm/plugins/zkm-ner). Advisory, exit 0.
#     UMBRELLA-UNRESOLVED— ≥1 child unresolved, no own-repo evidence. LOUD; sets non-zero exit.
#     GATE-READY         — every `gated-on:` token resolves AND all `[x]`. Advisory.
#     GATE-BLOCKED       — ≥1 gate token open/unresolved. Silent.
#     UNMARKED-GATE      — an UNMARKED line carries gate vocabulary (`gated on`/`blocked
#                          until`/`blocked on`/`Gate:`). Advisory backstop (no-silent-swallow,
#                          id:4347) — catches non-id gates, backfill misses, future items.
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
unresolved_found=0  # shipped mode: set to 1 by any UMBRELLA-UNRESOLVED → non-zero exit

if [[ "$mode" == "cross-ledger" ]]; then
  # Build token→state maps for the TODO union and for ROADMAP separately, then
  # flag tokens present in both whose checkbox state disagrees. A line may carry
  # multiple <!-- id:XXXX --> tokens (all share that line's state).
  # id:d9b0: a line annotated with <!-- xledger-ok: <reason> --> is an intentional
  # scope-split (e.g. closed ROADMAP decision + open TODO action with different scope).
  # Such lines are NOT flagged; an empty reason "<!-- xledger-ok: -->" still suppresses.
  declare -A todo_state roadmap_state todo_xledger_ok
  while IFS= read -r l; do
    st=' '; [[ "$l" =~ ^[[:space:]]*-\ \[[xX]\]\  ]] && st='x'
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
  done < <(grep -hE '^\s*- \[[ xX]\] ' "$ROOT/TODO.md" "$ROOT/TODO.archive.md" 2>/dev/null || true)
  while IFS= read -r l; do
    st=' '; [[ "$l" =~ ^[[:space:]]*-\ \[[xX]\]\  ]] && st='x'
    xok=''; [[ "$l" == *"<!-- xledger-ok:"* ]] && xok='1'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      # First-wins: same rationale as the TODO loop above (id:9221).
      [[ -n "${roadmap_state[$tk]+x}" ]] || roadmap_state["$tk"]="$st"
      [[ -n "$xok" ]] && todo_xledger_ok["$tk"]='1' || true
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^\s*- \[[ xX]\] ' "$ROOT/ROADMAP.md" 2>/dev/null || true)
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
  # Word-boundary anchored (strong-model audit run 70 finding 3): plain substring
  # matching let e.g. "gated" fire inside investi-gated/aggre-gated/dele-gated,
  # "observe" inside observe-d, "verify" inside verif-y-related prose, etc. —
  # misclassifying ordinary words as a gate-word clause. \b(...)\b anchors each
  # alternative to whole-word boundaries only.
  completion_re='\b(REMAIN|pending|activation)\b'
  wait_re='\b(observe|verify|awaiting|gated|re-evaluate|let it run)\b'
  age_days_threshold="${ORPHAN_SCAN_SHIPPED_AGE_DAYS:-14}"
  now_epoch=$(date +%s)

  # --- Typed-edge closure setup (id:46f6) --------------------------------------
  # Local resolution map: token → checkbox state for every id-bearing line in
  # TODO.md ∪ TODO.archive.md. A child/gate token "resolves" iff it is a key here;
  # it is "closed" iff its state is 'x'. First-wins so an active TODO.md entry
  # beats a recycled archive id (same rationale as the cross-ledger map, id:9221).
  # ROADMAP.md is deliberately excluded (that drift belongs to --cross-ledger).
  # (2>/dev/null: a missing TODO.archive.md is a normal state, not an error.)
  declare -A local_state
  while IFS= read -r l; do
    st=' '; [[ "$l" =~ ^[[:space:]]*-\ \[[xX]\]\  ]] && st='x'
    while read -r tk; do
      [[ -z "$tk" ]] && continue
      [[ -n "${local_state[$tk]+x}" ]] || local_state["$tk"]="$st"
    done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$l" || true)
  done < <(grep -hE '^\s*- \[[ xX]\] ' "$ROOT/TODO.md" "$ROOT/TODO.archive.md" 2>/dev/null || true)

  # Confirmed own-repo NAMES for the UMBRELLA-CROSS-REPO decision. These come from
  # relay.toml via the shared, tested reader lib-own-repos.sh — NEVER a ~/src glob
  # (correction 2026-07-10: zkm-ner lives at ~/src/zkm/plugins/zkm-ner, which a glob
  # would miss → false UMBRELLA-UNRESOLVED + spurious non-zero exit). Resolve our own
  # real path first so this works whether invoked from the repo or via the ~/.claude
  # symlink. Fail LOUD if the reader is missing or relay.toml fails to parse — never
  # silently fall back to a glob or downgrade every unresolved child (id:4347).
  own_scan_self="$(readlink -f "${BASH_SOURCE[0]}")"
  own_repos_lib="$(dirname "$own_scan_self")/../relay/scripts/lib-own-repos.sh"
  if [[ ! -f "$own_repos_lib" ]]; then
    echo "orphan-scan: FATAL — own-repo reader not found at $own_repos_lib; cannot classify cross-repo umbrellas (refusing to guess)" >&2
    exit 3
  fi
  SRC_DIR="${SRC_DIR:-$HOME/src}"
  RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
  # shellcheck source=../relay/scripts/lib-own-repos.sh
  source "$own_repos_lib"
  # Capture to a variable and test $? — a bare `< <(own_repos)` process substitution
  # would DISCARD the subshell exit status (the lib header warns about exactly this),
  # so a corrupt relay.toml would look like an empty registry.
  if ! own_repos_out="$(own_repos)"; then
    echo "orphan-scan: FATAL — relay.toml failed to parse ($RELAY_TOML); cannot enumerate own repos (id:4347)" >&2
    exit 3
  fi
  own_repo_names=()
  while IFS=$'\t' read -r rname _rpath; do
    [[ -z "$rname" ]] && continue
    own_repo_names+=("$rname")
  done <<<"$own_repos_out"
  # ----------------------------------------------------------------------------

  while IFS=: read -r lineno text; do
    token=$(echo "$text" | grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' || true)
    [[ -z "$token" ]] && continue
    id_lines=$((id_lines+1))

    # Short stdout: emit the item's TITLE, never the whole line. Ledger items run to
    # thousands of characters; echoing them verbatim turned a 0-byte report into 36 KB
    # (the audit-pass ctx-bloat class this sibling-helper pattern exists to avoid).
    # The full line stays in the file; the id: token is the handle for looking it up.
    short_text() {
      local t="$1" title
      title=$(grep -oP '(?<=\*\*).*?(?=\*\*)' <<<"$t" | head -1 || true)
      if [[ -z "$title" ]]; then
        title=$(sed -E 's/^[[:space:]]*- \[[ x]\] //; s/<!--.*$//' <<<"$t")
      fi
      title=$(tr -s '[:space:]' ' ' <<<"$title")
      title="${title#"${title%%[![:space:]]*}"}"
      (( ${#title} > 110 )) && title="${title:0:107}..."
      printf '%s' "$title"
    }

    # Typed-edge markers (form C: sibling comments before the terminal id comment).
    children_csv=$(grep -oP '(?<=<!-- children:)[0-9a-f,]+(?= -->)' <<<"$text" || true)
    gated_csv=$(grep -oP '(?<=<!-- gated-on:)[0-9a-f,]+(?= -->)' <<<"$text" || true)
    has_typed=0
    [[ -n "$children_csv" || -n "$gated_csv" ]] && has_typed=1

    # <!-- gate-prose-only --> marker (id:8800): records "this prose gate is
    # confirmed; it intentionally has no typed edge" for gates whose blocking
    # condition is external prose (an upstream vendor, a human decision) rather
    # than a local TODO-id dependency. Bypasses ONLY the UNMARKED-GATE backstop
    # below — it does NOT set has_typed, so it does not suppress/replace the
    # typed-predicate branches (GATE-READY/GATE-BLOCKED/UMBRELLA-*) and does not
    # touch the EXTERNAL-WAIT / GATE-STALE paths. Marked, not because a regex got
    # smarter — a human confirmed this specific gate has no local id to point at.
    gate_prose_only=0
    grep -qF '<!-- gate-prose-only -->' <<<"$text" && gate_prose_only=1

    # <!-- xgate:TOKEN@repo --> marker (id:7f30): like gate-prose-only, records
    # "this prose gate is confirmed" — but for a CROSS-REPO gate whose blocking
    # token lives in ANOTHER repo, so there is no local id to point a `gated-on:`
    # edge at. Parses loosely (4-hex token, `@`, repo name); a malformed marker
    # simply doesn't match (no crash) and behaves as if absent. Bypasses ONLY
    # the UNMARKED-GATE backstop below, exactly like gate-prose-only — does NOT
    # set has_typed and does NOT suppress the typed-predicate branches or the
    # EXTERNAL-WAIT / GATE-STALE paths.
    xgate_marked=0
    grep -qP '<!-- xgate:[0-9a-f]{4}@[A-Za-z0-9._-]+ -->' <<<"$text" && xgate_marked=1

    if [[ -n "$children_csv" ]]; then
      # Umbrella predicate over the typed child edge set.
      IFS=',' read -ra _kids <<<"$children_csv"
      all_resolve=1; all_closed=1; dangling=()
      for k in "${_kids[@]}"; do
        if [[ -n "${local_state[$k]+x}" ]]; then
          [[ "${local_state[$k]}" == "x" ]] || all_closed=0
        else
          all_resolve=0; all_closed=0; dangling+=("$k")
        fi
      done
      if (( all_resolve )); then
        if (( all_closed )); then
          candidates=$((candidates+1))
          output_lines+=("id:$token — UMBRELLA-READY (all children [x]) — ready to close. $(short_text "$text")")
        fi
        # else: UMBRELLA-OPEN — every child resolves, ≥1 still open. Silent.
      else
        # ≥1 unresolved child. Cross-repo iff the prose names a CONFIRMED own repo.
        if (( ${#own_repo_names[@]} == 0 )); then
          echo "orphan-scan: FATAL — id:$token has unresolved child token(s) [${dangling[*]}] but the own-repo registry is EMPTY ($RELAY_TOML); cannot distinguish cross-repo from unresolved (refusing to guess, id:4347)" >&2
          exit 3
        fi
        # Collect the SET of confirmed own-repo names appearing on the line as
        # EVIDENCE — do NOT pick one and attribute the child to it (correction
        # 2026-07-10: nothing on the line connects a given child token to a given
        # repo name, so naming "the" home repo fabricates a mapping; a line can name
        # several own repos). Report all; let the human map child→repo.
        sibs=()
        for s in "${own_repo_names[@]}"; do
          if grep -qw -- "$s" <<<"$text"; then sibs+=("$s"); fi
        done
        if (( ${#sibs[@]} > 0 )); then
          candidates=$((candidates+1))
          output_lines+=("id:$token — UMBRELLA-CROSS-REPO — unresolved child(ren): ${dangling[*]}; own-repo names present on line: ${sibs[*]} (evidence, not an attribution) — child(ren) likely tracked in another repo. $(short_text "$text")")
        else
          candidates=$((candidates+1))
          unresolved_found=1
          output_lines+=("id:$token — UMBRELLA-UNRESOLVED (dangling child token(s): ${dangling[*]}) — unresolvable locally and no own-repo evidence; marker may be stale. $(short_text "$text")")
        fi
      fi
    fi

    if [[ -n "$gated_csv" ]]; then
      # Gate predicate over the typed gated-on edge set.
      IFS=',' read -ra _gates <<<"$gated_csv"
      g_all_resolve=1; g_all_closed=1
      for g in "${_gates[@]}"; do
        if [[ -n "${local_state[$g]+x}" ]]; then
          [[ "${local_state[$g]}" == "x" ]] || g_all_closed=0
        else
          g_all_resolve=0; g_all_closed=0
        fi
      done
      if (( g_all_resolve && g_all_closed )); then
        candidates=$((candidates+1))
        output_lines+=("id:$token — GATE-READY (all gates [x]) — unblocked now. $(short_text "$text")")
      fi
      # else: GATE-BLOCKED — ≥1 gate open or unresolved. Silent.
    fi

    if (( has_typed )); then
      # A typed-marker item is decided ENTIRELY by the predicates above; it bypasses
      # the gate-word heuristic and the UNMARKED-GATE backstop (A2 "dissolve don't
      # guard"). This is why 65f9 reaches the umbrella branch despite a `gated` word
      # quoted from a child clause — it is marked, not because a regex got smarter.
      continue
    fi

    # UNMARKED-GATE backstop (no-silent-swallow, id:4347): an UNMARKED line bearing
    # gate vocabulary cannot be concluded "ungated". Advisory only. This vocabulary is
    # deliberately DISJOINT from wait_re's bare words — it matches only structured gate
    # PHRASES (`gated on`, `blocked until/on`, `Gate:`) and the ledger's own gate
    # markers `🚧 GATED …` / `GATED (DEP: …)` — so an unmarked bare-"gated"/"observe"
    # item keeps its exact prior behaviour (falls through to the wait_re path below).
    # The 🚧/DEP forms were added after the live ledger showed cross-repo gates (e.g.
    # id:7df1, gate token in another repo, deliberately no local gated-on: edge) using
    # `🚧 GATED (DEP: …)` rather than the "gated on" phrasing.
    if (( ! gate_prose_only )) && (( ! xgate_marked )) && grep -qiE '\bgated on\b|\bblocked until\b|\bblocked on\b|\bgate:|🚧[[:space:]]*gated\b|\bgated \(dep:' <<<"$text"; then
      candidates=$((candidates+1))
      output_lines+=("id:$token — UNMARKED-GATE (gate vocabulary present, no gated-on: marker) — add a typed gated-on: edge or confirm the gate. $(short_text "$text")")
    fi

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
        output_lines+=("id:$token — GATE-STALE (line age ${age_days}d >= ${age_days_threshold}d) — gating clause may have lapsed; re-check. $(short_text "$text")")
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
      # Bounded execution (strong-model audit run 70 finding 4): this is an ADVISORY
      # scan, not the test harness — a non-hermetic or looping discovered test must
      # never hang the scan. timeout_s overridable via ORPHAN_SCAN_TEST_TIMEOUT_S; a
      # timed-out test is treated as non-green (no TICK-READY claim), matching a
      # genuinely-failing test's outcome rather than hanging or erroring the scan.
      timeout_s="${ORPHAN_SCAN_TEST_TIMEOUT_S:-60}"
      if (cd "$ROOT" && timeout "${timeout_s}s" bash "$test_rel") >/dev/null 2>&1; then
        candidates=$((candidates+1))
        output_lines+=("id:$token — TICK-READY (green: $test_rel, no gate) — ready to tick. $(short_text "$text")")
      fi
    fi
  done < <(grep -nE '^\s*- \[ \] ' "$ROOT/TODO.md" 2>/dev/null || true)
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

# Shipped mode (id:46f6): any UMBRELLA-UNRESOLVED is a LOUD failure — an unresolvable
# child token with no own-repo evidence means the umbrella can never read "ready" for a
# possibly-wrong reason (fail-open silent swallow, id:4347). Exit non-zero so a caller
# (or CI) surfaces it. All other classes are report-only and leave exit 0.
if [[ "$mode" == "shipped" && "$unresolved_found" == 1 ]]; then
  exit 1
fi
