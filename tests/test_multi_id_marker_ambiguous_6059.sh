#!/usr/bin/env bash
# DEFECT FIX — no `# roadmap:` header on purpose: this pins a read-side and a write-side
# corruption guard, not an open roadmap item. Its failures always count.
# fails-against: e68794e (the pre-fix tree: 18 of 27 assertions RED — own_id_of_line
#   returned id:aaaa / id:cccc / id:eeee instead of refusing, typed_edges_own_id_of_line
#   guessed 'cccc', md-merge exited 0 on four ambiguous updates and on the loderite
#   quote-in-annotation append, ledger-map assigned an id, roadmap-lint did not flag)
#
# THE DEFECT (id:6059 / routed:b71e / loderite routed:3ad9). `<!-- id:XXXX -->` carries
# TWO OPPOSITE meanings with IDENTICAL syntax — "this line IS X" (define) and "this line
# REFERS to X" (refer). Both shapes are live, and they put the owning id at OPPOSITE ends:
#
#   (i)  BODY QUOTES A MARKER    → own id LAST.  Live here: TODO.md's `id:f346` item
#        documents its own re-mint by quoting a literal marker.
#   (ii) TRAILING REFERENCE      → own id FIRST. Live in loderite's ROADMAP.md
#        L211/L229/L628 (routed:3ad9): three OPEN items each ending
#        `<!-- id:XXXX --> <!-- id:50f3 -->` where 50f3 is a CLOSED item. A last-match
#        parser reads all three OPEN items as belonging to a closed id.
#   (iii) DUPLICATED OWN MARKER  → the SAME id twice (loderite `<!-- id:466d -->
#        <!-- id:466d -->`). A set/dedup check calls this fine; only a COUNT catches it.
#
# So NEITHER positional rule is safe, and standardising on first is exactly as wrong as
# standardising on last. The contract this file pins is: **REFUSE LOUDLY, never guess** —
# read side refuses to INTERPRET such a line, write side refuses to CREATE one. The two
# compose; they are not redundant. The durable fix is a define-vs-refer grammar
# (routed:20ce / cartulary id:344d) and is NOT decided here.
#
# Hermetic: pure function calls + mktemp -d fixtures. No ~/.claude, no network.
# fails-against-rev: 6142f2329b34 -- meeting/append.sh meeting/md-merge.py meeting/orphan-scan.sh relay/references/hard-lanes.md relay/scripts/classify-repo.sh relay/scripts/discover-sig.sh relay/scripts/gather-repo-state.sh relay/scripts/handback-guard.mjs relay/scripts/lib-anchored-id.sh relay/scripts/lib-roadmap-sections.sh relay/scripts/lib-typed-edges.sh relay/scripts/reconcile-repo.sh relay/scripts/relay-loop.js relay/scripts/resolve-gates.sh relay/scripts/roadmap-lint.sh relay/scripts/unpromoted-scan.sh tracker/SCHEMA.md tracker/ledger-map.py
# fails-against-assertion: (3-state) no <ambiguous:…> display handle

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

# Marker syntax is assembled from pieces so THIS FILE never becomes a second anchor for a
# real token — the exact trap the item describes (and the one loderite re-created while
# trying to repair it).
O='<!--'; C='-->'
QUOTE_SHAPE="- [ ] [ROUTINE] re-minted from ${O} id:aaaa ${C} after a collision ${O} id:bbbb ${C}"
REF_SHAPE="- [ ] [ROUTINE] an open item that refers onward ${O} id:cccc ${C} ${O} id:dddd ${C}"
DUP_SHAPE="- [ ] [ROUTINE] duplicated own marker ${O} id:eeee ${C} ${O} id:eeee ${C}"
CLEAN_SHAPE="- [ ] [ROUTINE] an ordinary single-marker item ${O} id:bbbb ${C}"

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
export RELAY_TOML="$tmpdir/relay.toml"; : > "$RELAY_TOML"

# ── (1) READ SIDE: lib-anchored-id.sh refuses, loudly, on all three shapes ────
# shellcheck source=/dev/null
source "$ROOT/relay/scripts/lib-anchored-id.sh"

probe() {  # probe <label> <line>
  local label="$1" line="$2" out err rc
  err="$tmpdir/err.$$"
  out="$(own_id_of_line "$line" "fixture:1" 2>"$err")"; rc=$?
  if [[ $rc -ne ${OWN_ID_AMBIGUOUS:-3} ]]; then
    bad "own_id_of_line ($label) returned rc=$rc out='$out' — must REFUSE (rc=3), not guess a position"
    return
  fi
  [[ -z "$out" ]] || { bad "own_id_of_line ($label) printed '$out' on refusal — must print nothing"; return; }
  grep -qi 'ambiguous' "$err" \
    || { bad "own_id_of_line ($label) refused SILENTLY — the refusal must name the problem on stderr"; return; }
  ok "own_id_of_line REFUSES the $label shape, loudly, with nothing on stdout"
}
probe "body-quotes-a-marker (own id would be LAST)"   "$QUOTE_SHAPE"
probe "trailing-reference (own id would be FIRST)"    "$REF_SHAPE"
probe "duplicated-own-marker (same id twice)"         "$DUP_SHAPE"

# the refusal must name every candidate, so an operator can repair the line
err="$tmpdir/err.cands"
own_id_of_line "$REF_SHAPE" "fixture:1" >/dev/null 2>"$err"
grep -q 'cccc' "$err" && grep -q 'dddd' "$err" \
  && ok "the refusal enumerates every candidate id" \
  || bad "the refusal does not name both candidates (stderr: $(tr '\n' ' ' < "$err"))"
grep -q 'fixture:1' "$err" \
  && ok "the refusal reports the caller-supplied location" \
  || bad "the refusal omits the caller-supplied location"

# unambiguous lines must be UNAFFECTED (no over-refusal)
got="$(own_id_of_line "$CLEAN_SHAPE")"
[[ "$got" == "id:bbbb" ]] \
  && ok "(control) a single-marker line still resolves normally" \
  || bad "(control) own_id_of_line got '$got', want id:bbbb — the refusal over-broadened"
got="$(own_id_of_line '- [ ] cites dep: id:1643 <!-- id:4148 -->')"
[[ "$got" == "id:4148" ]] \
  && ok "(control) a BARE prose id is still never an anchor (one real marker → resolves)" \
  || bad "(control) own_id_of_line got '$got', want id:4148"
own_id_of_line '- [ ] no marker at all' 2>/dev/null
[[ $? -eq 1 ]] \
  && ok "(control) a line with NO marker still exits 1 (absent), distinct from 3 (ambiguous)" \
  || bad "(control) a marker-less line must exit 1, not the ambiguity status"

# ERREXIT SAFETY: the lib is sourced into `set -euo pipefail` scripts (roadmap-lint.sh,
# scan-routed.sh, append.sh). Nonzero returns must not abort the caller when it captures
# the status — a refusal that KILLS the lint is worse than the guess it replaced.
if bash -c '
  set -euo pipefail
  source "$1/relay/scripts/lib-anchored-id.sh"
  rc=0; tok="$(own_id_of_line "$2" ctx 2>/dev/null)" || rc=$?
  [[ $rc -eq 3 ]] || exit 9
  rc=0; tok="$(own_token_of_line "$2" ctx 2>/dev/null)" || rc=$?
  [[ $rc -eq 3 ]] || exit 10
  echo survived
' _ "$ROOT" "$REF_SHAPE" >/dev/null 2>&1; then
  ok "the ambiguity refusal is errexit-safe in a set -euo pipefail caller"
else
  bad "sourcing caller under set -euo pipefail DIED on the ambiguity refusal (rc=$?)"
fi

# an INBOUND stub carries one `routed:` AND one `id:` — different namespaces, NOT ambiguous
got="$(own_token_of_line "- [ ] [t] ingest ${O} routed:9999 ${C} body ${O} id:8888 ${C}")"
[[ "$got" == "id:8888" ]] \
  && ok "(control) an INBOUND stub (one routed: + one id:) is NOT ambiguous — id wins" \
  || bad "(control) own_token_of_line got '$got' on an INBOUND stub, want id:8888"

# ── (2) READ SIDE: lib-typed-edges.sh agrees (empty + loud, never a guess) ────
# shellcheck source=/dev/null
source "$ROOT/relay/scripts/lib-typed-edges.sh"
err="$tmpdir/err.te"
got="$(typed_edges_own_id_of_line "$REF_SHAPE" 2>"$err")"
[[ -z "$got" ]] \
  && ok "typed_edges_own_id_of_line resolves NOTHING for an ambiguous line" \
  || bad "typed_edges_own_id_of_line guessed '$got' on an ambiguous line"
grep -qi 'ambiguous' "$err" \
  && ok "typed_edges_own_id_of_line says why (loud, not a silent empty)" \
  || bad "typed_edges_own_id_of_line refused SILENTLY — indistinguishable from an id-less line"
got="$(typed_edges_own_id_of_line "$CLEAN_SHAPE" 2>/dev/null)"
[[ "$got" == "bbbb" ]] \
  && ok "(control) typed_edges_own_id_of_line still resolves a single-marker line" \
  || bad "(control) typed_edges_own_id_of_line got '$got', want bbbb"

# ── (3) WRITE SIDE: md-merge.py update-ids refuses, and writes NOTHING ────────
MDMERGE="$ROOT/meeting/md-merge.py"
seed() { printf '# TODO\n\n## Current\n\n%s\n' "$1" > "$tmpdir/TODO.md"; }

# refuse_update <label> <seed-line> <target-id> <payload-json> [stderr-regex]
# The stderr-regex defaults to the ambiguity vocabulary; pass a tighter one where a
# PRE-FIX tree would also have failed for an UNRELATED reason (else the case is vacuous).
refuse_update() {
  local label="$1" want="${5:-AMBIGUOUS own id|anchored id markers}" before after err rc
  seed "$2"
  before="$(cat "$tmpdir/TODO.md")"
  err="$(printf '%s' "$4" | python3 "$MDMERGE" update-ids --file "$tmpdir/TODO.md" 2>&1 >/dev/null)"
  rc=$?
  after="$(cat "$tmpdir/TODO.md")"
  if [[ $rc -eq 0 ]]; then
    bad "md-merge ($label) exited 0 — an ambiguous/ill-formed write must fail LOUD"; return
  fi
  [[ "$before" == "$after" ]] \
    || { bad "md-merge ($label) MODIFIED the file on a refusal — must write NOTHING"; return; }
  grep -qE "$want" <<<"$err" \
    || { bad "md-merge ($label) failed for the wrong reason — want /$want/, got: $err"; return; }
  ok "md-merge REFUSES $label, writes nothing, and says why"
}

# (3a) target an id on a line that carries two markers — either candidate, both refused
refuse_update "an update aimed at the FIRST candidate of a two-marker line" \
  "$QUOTE_SHAPE" aaaa \
  '{"updates":[{"id":"aaaa","line":"- [x] rewritten <!-- id:aaaa -->"}]}'
refuse_update "an update aimed at the SECOND candidate of a two-marker line" \
  "$QUOTE_SHAPE" bbbb \
  '{"updates":[{"id":"bbbb","line":"- [x] rewritten <!-- id:bbbb -->"}]}'
refuse_update "an update aimed at a TRAILING-REFERENCE line" \
  "$REF_SHAPE" cccc \
  '{"updates":[{"id":"cccc","line":"- [x] rewritten <!-- id:cccc -->"}]}'
refuse_update "an update aimed at a DUPLICATED-own-marker line (count, not dedup)" \
  "$DUP_SHAPE" eeee \
  '{"updates":[{"id":"eeee","line":"- [x] rewritten <!-- id:eeee -->"}]}'

# (3b) WRITE-SIDE guard, POST-COMPOSITION: a replacement that would CREATE a two-marker
#      item line is refused even though the target line is perfectly unambiguous.
refuse_update "a REPLACEMENT that would create a two-marker item line" \
  "$CLEAN_SHAPE" bbbb \
  '{"updates":[{"id":"bbbb","line":"- [x] note: the marker is written <!-- id:aaaa --> <!-- id:bbbb -->"}]}'

# (3c) THE LODERITE SHAPE: an APPEND whose annotation quotes marker syntax. The
#      pre-append line has ONE marker (passes any pre-composition check); the COMPOSED
#      line has two. Only a post-composition guard catches this.
refuse_update "an APPEND whose annotation quotes marker syntax (post-composition check)" \
  "$CLEAN_SHAPE" bbbb \
  '{"updates":[{"id":"bbbb","append":"de-ambiguated: the stray reference was <!-- id:aaaa -->"}]}'

# (3d) a NEW item (--allow-new) may not be born ambiguous
seed "$CLEAN_SHAPE"
before="$(cat "$tmpdir/TODO.md")"
err="$(echo '{"updates":[{"id":"9a9a","line":"- [ ] new but ambiguous <!-- id:9a9a --> <!-- id:9a9a -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmpdir/TODO.md" --allow-new 2>&1 >/dev/null)"
rc=$?
[[ $rc -ne 0 && "$before" == "$(cat "$tmpdir/TODO.md")" ]] \
  && ok "md-merge REFUSES to APPEND a new item line that is already ambiguous" \
  || bad "md-merge appended an ambiguous NEW item (rc=$rc, stderr: $err)"

# (3e) controls — ordinary writes must still work, both modes
seed "$CLEAN_SHAPE"
echo '{"updates":[{"id":"bbbb","line":"- [x] plainly rewritten <!-- id:bbbb -->"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmpdir/TODO.md" >/dev/null 2>&1
grep -q 'plainly rewritten' "$tmpdir/TODO.md" \
  && ok "(control) an ordinary single-marker replacement still applies" \
  || bad "(control) an ordinary replacement was refused — the guard over-broadened"
seed "$CLEAN_SHAPE"
echo '{"updates":[{"id":"bbbb","append":"and a plain annotation with no marker syntax"}]}' \
  | python3 "$MDMERGE" update-ids --file "$tmpdir/TODO.md" >/dev/null 2>&1
grep -q 'plain annotation' "$tmpdir/TODO.md" \
  && ok "(control) an ordinary append still applies" \
  || bad "(control) an ordinary append was refused — the guard over-broadened"

# ── (4) tracker/ledger-map.py: no id assigned, still reported ─────────────────
seed "$REF_SHAPE"
out="$(python3 "$ROOT/tracker/ledger-map.py" import fixture "$tmpdir" 2>"$tmpdir/lm.report")" || true
if printf '%s' "$out" | python3 -c '
import json,sys
d = json.loads(sys.stdin.read())
ids = [i.get("id") for i in d.get("items", []) if i.get("id")]
sys.exit(0 if not ids else 1)
'; then
  ok "ledger-map.py assigns NO id to an ambiguous line (imports untracked)"
else
  bad "ledger-map.py assigned an id to an ambiguous line — a positional guess propagated fleet-wide"
fi
grep -qi 'multi-id-line' "$tmpdir/lm.report" \
  && ok "ledger-map.py still REPORTS the ambiguous line (loud, not silent)" \
  || bad "ledger-map.py dropped the ambiguous line silently"
schema_row="$(grep -F 'markers on one line' "$ROOT/tracker/SCHEMA.md" || true)"
if grep -qi 'AMBIGUOUS' <<<"$schema_row" && ! grep -qiE 'the \*\*(first|last)\*\* is the owning id' <<<"$schema_row"; then
  ok "tracker/SCHEMA.md documents the multi-marker line as ambiguous (no positional rule)"
else
  bad "tracker/SCHEMA.md still documents a positional rule for a multi-marker line: $schema_row"
fi

# ── (5) roadmap-lint flags the shape so it gets repaired at the source ────────
printf '# Roadmap\n\n## Items\n\n%s\n' "$DUP_SHAPE" > "$tmpdir/lint.md"
lint_out="$("$ROOT/relay/scripts/roadmap-lint.sh" "$tmpdir/lint.md" 2>&1 || true)"
grep -qi 'MULTI-ID' <<<"$lint_out" \
  && ok "roadmap-lint.sh flags MULTI-ID (count-based: the same id twice still fires)" \
  || bad "roadmap-lint.sh does not flag a duplicated-own-marker line"
# REGRESSION (2026-08-14): the MULTI-ID rule's original `grep -o … | wc -l` was FATAL on a
# line with ZERO markers — grep exits 1, pipefail propagates, and a bare assignment under
# this script's `set -euo pipefail` aborts the whole scan. `$report` is printed only at the
# END, so the lint exited nonzero while reporting NOTHING, and every violation on every
# later line vanished. Exit code alone cannot see this: assert on the REPORT.
cat > "$tmpdir/lint_idless.md" <<EOF
# Roadmap

## Items

- [ ] [ROUTINE] an item with NO id marker at all
- [ ] a LATER item with no class tag ${O} id:dddd ${C}
EOF
lint_out="$("$ROOT/relay/scripts/roadmap-lint.sh" "$tmpdir/lint_idless.md" 2>&1 || true)"
grep -q 'MISSING its id token' <<<"$lint_out" \
  && ok "an id-less line is REPORTED (the scan does not abort on zero markers)" \
  || bad "an id-less line produced no report — the scan aborted mid-loop (errexit/pipefail): $lint_out"
grep -q 'id:dddd' <<<"$lint_out" \
  && ok "a violation AFTER an id-less line still reaches the report" \
  || bad "the violation after an id-less line was lost — the scan died before reaching it"

# THREE DISTINCT STATES must coexist: id-less, ambiguous, well-formed.
cat > "$tmpdir/lint_three.md" <<EOF
# Roadmap

## Items

- [ ] [ROUTINE] id-less item
- [ ] [ROUTINE] ambiguous item ${O} id:aaaa ${C} ${O} id:bbbb ${C}
- [ ] [ROUTINE] well-formed item ${O} id:cccc ${C}
EOF
lint_out="$("$ROOT/relay/scripts/roadmap-lint.sh" "$tmpdir/lint_three.md" 2>&1 || true)"
grep -q 'MISSING its id token' <<<"$lint_out" \
  && ok "(3-state) the id-less line fires the MISSING-ID clause" \
  || bad "(3-state) the id-less line did not fire MISSING-ID"
grep -q 'MULTI-ID' <<<"$lint_out" \
  && ok "(3-state) the ambiguous line fires MULTI-ID" \
  || bad "(3-state) the ambiguous line did not fire MULTI-ID"
grep -q '<ambiguous:aaaa,bbbb>' <<<"$lint_out" \
  && ok "(3-state) the ambiguous line gets an <ambiguous:…> handle, never a positional guess" \
  || bad "(3-state) no <ambiguous:…> display handle"
grep -qE 'MISSING its id token.*\n.*well-formed|MULTI-ID.*well-formed' <<<"$lint_out" \
  && bad "(3-state) the well-formed line was caught by an id-state rule" \
  || ok "(3-state) the well-formed line fires neither id-state rule"

printf '# Roadmap\n\n## Items\n\n%s\n' "$CLEAN_SHAPE" > "$tmpdir/lint_ok.md"
lint_out="$("$ROOT/relay/scripts/roadmap-lint.sh" "$tmpdir/lint_ok.md" 2>&1 || true)"
grep -qi 'MULTI-ID' <<<"$lint_out" \
  && bad "(control) roadmap-lint.sh flagged MULTI-ID on a single-marker line — false positive" \
  || ok "(control) a single-marker item is not flagged MULTI-ID"

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
