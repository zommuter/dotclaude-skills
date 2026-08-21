#!/usr/bin/env bash
# roadmap:353e — the id:bc2b demote path must not bypass the id:365b breaker, and excluding
# `review` must not be able to grow an unaudited window.
#
# TWO DEFECTS under test:
#  (1) In the id:365b circuit-breaker loop (relay-loop.js) a demoted unit was pushed straight
#      into `keptCB` WITHOUT re-entering the breaker — so a demoted class that is ITSELF >3x
#      suppressed dispatched anyway. The breaker the demotion was meant to soften was bypassed.
#  (2) Excluding `review` disabled BOTH review branches (the ordinary one AND the id:8123
#      chain-end re-ask). A repo with substantive_unaudited then got an EXECUTE child stacked
#      on an unaudited window; next round `repo:review` is still over count, so the window
#      GROWS for the whole run — the exact starvation id:8123 was ratified to prevent, coming
#      back in through the exclusion door.
#
# The classifier half (2) is testable directly (pure stdin→stdout). The loop half (1) is
# structural-only: relay-loop.js cannot be imported in this harness (id:2ec4), the same stated
# limit as tests/test_suppression_demotes_bc2b.sh (G).
#
# EXPECTED-RED while roadmap:353e is unticked.
# Hermetic: no repo, no git, no network, never touches ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CV="$ROOT/relay/scripts/classify-verdict.sh"
JS="$ROOT/relay/scripts/relay-loop.js"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -x "$CV" ]] || { echo "FAIL: classify-verdict.sh not found at $CV"; exit 1; }

verdict_of() {
  local json="$1"; shift
  "$CV" "$@" <<<"$json" 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("verdict","<<ERR>>"))' 2>/dev/null \
    || echo "<<ERR>>"
}
excluded_of() {
  local json="$1"; shift
  "$CV" "$@" <<<"$json" 2>/dev/null \
    | python3 -c 'import sys,json;print(",".join(json.load(sys.stdin).get("excluded",[])))' 2>/dev/null \
    || echo "<<ERR>>"
}

base='"repo":"loderite","is_finished":false,"hasRoutine":true,"open_hard_pool":0,"top_intensive":"","roadmap_open":10'

# An unaudited window WITH plenty of other work to fall through to (hard pool + promotables):
# if `review` were excludable, the cascade would happily hand back `hard`/`handoff` and stack
# a child on top of the unaudited commits.
UNAUDITED='{'"$base"',"substantive_unaudited":true,"roadmap_actionable_open":1,"actionable_routine_open":1,"open_hard_pool":3,"unpromoted":{"promote":9,"surface":0}}'

# ── (b) `review` is REFUSED as an exclusion while substantive_unaudited is true ─────────────
# NOTE the fixture: `review` is rank 2, so it is only OBSERVABLY excluded on a repo where review
# is the class the cascade actually reaches. UNAUDITED also holds an actionable [ROUTINE] item,
# which pins it at `execute` (rank 1) whether or not review is excluded — so this first probe
# uses an unaudited repo with NO actionable routine work, where review IS the natural verdict and
# the exclusion would otherwise demote it to hard/handoff.
UNAUDITED_ONLY='{'"$base"',"substantive_unaudited":true,"roadmap_actionable_open":0,"actionable_routine_open":0,"open_hard_pool":3,"unpromoted":{"promote":9,"surface":0}}'
v="$(verdict_of "$UNAUDITED_ONLY" --exclude review)"
case "$v" in
  review) ok "review is NOT excludable under substantive_unaudited — the unaudited window cannot grow through the exclusion door" ;;
  hard|handoff|human|execute)
    bad "id:353e: --exclude review under substantive_unaudited demoted to '$v' — a child would stack on an unaudited window" ;;
  *) bad "id:353e: --exclude review under substantive_unaudited gave '$v', expected review" ;;
esac

# …and it stays refused when execute is suppressed too (the real demote call shape).
v="$(verdict_of "$UNAUDITED" --exclude execute,review)"
[[ "$v" == "review" ]] \
  && ok "--exclude execute,review under substantive_unaudited still yields review" \
  || bad "id:353e: --exclude execute,review under substantive_unaudited gave '$v', expected review"

# The refusal must be RECORDED as a refusal, exactly like blocked/idle: `review` is dropped
# from the emitted `excluded` set, so the trail never claims an exclusion that was ignored.
e="$(excluded_of "$UNAUDITED" --exclude execute,review)"
[[ "$e" == "execute" ]] \
  && ok "the emitted \`excluded\` set records only the HONOURED exclusions (review dropped, like blocked/idle)" \
  || bad "id:353e: emitted excluded='$e', expected 'execute' (review must be dropped as non-excludable)"

# But `review` IS excludable when there is nothing unaudited — the refusal is scoped to the
# hazard, not a blanket carve-out.
NOAUDIT='{'"$base"',"substantive_unaudited":false,"roadmap_actionable_open":0,"actionable_routine_open":0,"open_hard_pool":3,"unpromoted":{"promote":0,"surface":0}}'
v="$(verdict_of "$NOAUDIT" --exclude review)"
[[ "$v" == "hard" ]] \
  && ok "review stays excludable when substantive_unaudited is false (refusal is scoped to the hazard)" \
  || bad "id:353e: --exclude review without unaudited commits gave '$v', expected hard"

# ── (c) the id:8123 chain-end re-ask branch survives an ordinary `review` exclusion ─────────
CHAIN='{'"$base"',"substantive_unaudited":true,"chain_ended":true,"chain_end_reason":"handback","roadmap_actionable_open":1,"actionable_routine_open":1,"unpromoted":{"promote":0,"surface":0}}'
v="$(verdict_of "$CHAIN" --exclude review)"
[[ "$v" == "review" ]] \
  && ok "id:8123 chain-end re-ask still fires with review excluded — the two branches are independent" \
  || bad "id:353e: chain-end re-ask silently disabled by --exclude review (got '$v')"

r="$("$CV" --exclude review <<<"$CHAIN" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin).get("reason",""))')"
case "$r" in
  *8123*) ok "the surviving verdict comes from the id:8123 chain-end branch, not the ordinary one" ;;
  *) bad "id:353e: chain-end reason lost the id:8123 provenance: '$r'" ;;
esac

# ── (a) PURITY — with NO --exclude the output must be byte-identical to the pre-353e script.
#        (The differential against the actual pre-change script is run separately; here we pin
#        that the no-exclude path emits no `excluded` key and no stderr.) ────────────────────
out="$("$CV" <<<"$UNAUDITED" 2>/tmp/353e-purity-err.$$)"
err="$(cat /tmp/353e-purity-err.$$)"; rm -- /tmp/353e-purity-err.$$
if [[ -z "$err" ]] && ! grep -q '"excluded"' <<<"$out"; then
  ok "no-exclude invocation stays byte-clean (no \`excluded\` key, empty stderr)"
else
  bad "id:353e: no-exclude invocation regressed purity (stderr='$err')"
fi

# ── (a) LOOP WIRING — a demoted unit must RE-ENTER the id:365b breaker (structural, id:2ec4).
if [[ -f "$JS" ]]; then
  # The defect was `if (demotedCB) keptCB.push(demotedCB)` — an unconditional push straight
  # past the counter. Assert that shape is GONE and that a shared breaker step exists which the
  # demote path also calls.
  if grep -qE 'if \(demotedCB\) keptCB\.push\(demotedCB\)' "$JS"; then
    bad "id:353e: relay-loop.js still pushes a demoted unit into keptCB WITHOUT re-entering the breaker"
  else
    ok "the unconditional demoted->keptCB push is gone"
  fi
  if grep -q 'breakerAllows' "$JS"; then
    ok "relay-loop.js has a shared breaker step (breakerAllows) the demote path re-enters"
    # It must be applied to BOTH the ordinary unit and the demoted replacement — a call on the
    # original alone is exactly the bypass this item fixes.
    grep -q 'breakerAllows(u)' "$JS" \
      && ok "breakerAllows gates the ordinary unit" \
      || bad "id:353e: breakerAllows is never applied to the ordinary unit"
    grep -q 'breakerAllows(demotedCB)' "$JS" \
      && ok "breakerAllows gates the DEMOTED unit — the demote path re-enters the breaker" \
      || bad "id:353e: the demoted unit never re-enters the breaker"
  else
    bad "id:353e: no shared breaker step in relay-loop.js — the demote path cannot re-enter the breaker"
  fi
  grep -q '353e' "$JS" \
    && ok "relay-loop.js carries the id:353e marker" \
    || bad "id:353e: relay-loop.js has no id:353e marker"
  # Termination: the demote retry loop must be bounded by the finite class set, never open.
  grep -q 'DEMOTE_MAX_CLASSES' "$JS" \
    && ok "the demote retry is bounded by an explicit class-count cap (termination)" \
    || bad "id:353e: no explicit bound on the demote retry loop"
else
  bad "relay-loop.js missing at $JS"
fi

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: demotion re-enters the breaker; review is non-excludable under an unaudited window (id:353e)"
