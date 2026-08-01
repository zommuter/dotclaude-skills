#!/usr/bin/env bash
# roadmap:2047
# RED SPEC for id:2047 — `validate-flags.sh` must parse the `--flag=value` form, so an
# explicitly-tightened cap is never silently loosened to the default.
#
# OBSERVED LIVE 2026-07-31: the owner ran `/relay --afk --quota-7d=90`; the guard printed
#   "unknown flag '--quota-7d=90' … warning and dropping it"
# and emitted only `--afk`. `--quota-7d` IS in known-flags-relay.tsv (arity 1) — the runtime
# guard simply never splits a token on `=`:
#   validate-flags.sh:203  if [[ -n "${KNOWN_ARITY[$tok]+x}" ]]   <- whole-token lookup only
#   validate-flags.sh:205  skip_next_as_value=1                   <- consumes the FOLLOWING token
#
# Neither backstop catches it: `--quota-7d=90` is edit-distance 3 from `--quota-7d`, and
# `--quota-7d` is in neither MODE_FLAGS nor SCOPE_FLAGS, so nearest_escalate_flag returns
# nothing; and the id:f475 value-swallow at :225-229 does not fire either (no following
# bare token). The failure is quiet in BOTH directions.
#
# THE HAZARD IS DIRECTIONAL. A dropped cap falls back to the LOOSER RELAY_QUOTA_THRESHOLD
# default (0.90), so `--quota-7d=45` — a deliberate tightening — silently becomes 0.90 and
# the run burns twice the intended weekly budget. The live case was harmless only by
# coincidence (90 == the default).
#
# FULLY BEHAVIOURAL and hermetic: runs the real script, no git, no network, no HOME writes.
#
# TRIANGULATION (id:108e): eleven assertions over five concerns — the named contract, other
# arity-1 flags (so the fix cannot be special-cased to --quota-7d), first-`=`-only splitting,
# the arity-0 error path, and four REGRESSION controls on the untouched paths. A fix that
# greps for "quota" or that strips everything after the first `=` unconditionally fails here.
#
# RED until `--flag=value` is split before the known-flag lookup. roadmap:2047 unticked
# => EXPECTED-RED.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VF="$ROOT/relay/scripts/validate-flags.sh"
[[ -x "$VF" ]] || { echo "FAIL: validate-flags.sh not found/executable at $VF"; exit 1; }

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

outfile="$(mktemp)"; errfile="$(mktemp)"
trap 'rm -f "$outfile" "$errfile"' EXIT

# run <args...> — sets $OUT (stdout), $ERR (stderr), $RC
run() {
  : > "$outfile"; : > "$errfile"
  "$VF" relay -- "$@" > "$outfile" 2> "$errfile"
  RC=$?
  OUT="$(cat "$outfile")"
  ERR="$(cat "$errfile")"
}

# ── Concern 1: the contract the item itself states ───────────────────────────────
run --afk --quota-7d=45
if [[ "$OUT" == "--afk --quota-7d 45" && -z "$ERR" && "$RC" -eq 0 ]]; then
  ok "the item's stated contract: '--afk --quota-7d=45' -> '--afk --quota-7d 45', no warning, exit 0"
else
  bad "'--afk --quota-7d=45' should emit '--afk --quota-7d 45' silently; got out='$OUT' rc=$RC err='$ERR'"
fi

# The live invocation that motivated the item (90 == the default, so it looked harmless).
run --afk --quota-7d=90
[[ "$OUT" == "--afk --quota-7d 90" ]] \
  && ok "the live 2026-07-31 invocation '--afk --quota-7d=90' survives intact" \
  || bad "'--afk --quota-7d=90' should emit '--afk --quota-7d 90', got '$OUT'"

# ── Concern 2: EVERY arity-1 manifest flag, not just the quota ones ──────────────
# The fix must be manifest-driven. Special-casing --quota-7d satisfies concern 1 alone.
for pair in "--exclude=loderite|--exclude loderite" \
            "--only=dotclaude-skills|--only dotclaude-skills" \
            "--strong-tier=opus|--strong-tier opus" \
            "--pool-width=3|--pool-width 3" \
            "--quota-5h=60|--quota-5h 60"; do
  arg="${pair%%|*}"; want="${pair##*|}"
  run "$arg"
  if [[ "$OUT" == "$want" && -z "$ERR" && "$RC" -eq 0 ]]; then
    ok "arity-1 generality: '$arg' -> '$want' silently"
  else
    bad "arity-1 generality: '$arg' should emit '$want' silently; got out='$OUT' rc=$RC err='$ERR'"
  fi
done

# ── Concern 3: split on the FIRST '=' only — a value may itself contain '=' ──────
run --exclude=a=b
[[ "$OUT" == "--exclude a=b" ]] \
  && ok "splits on the FIRST '=' only: '--exclude=a=b' -> '--exclude a=b'" \
  || bad "'--exclude=a=b' should emit '--exclude a=b' (first '=' only), got '$OUT'"

# ── Concern 4: '=' on an ARITY-0 flag is an ERROR, never a silent drop ───────────
# Stated explicitly in the item: "a `=` on an arity-0 flag stays an error." The point is
# that it must not become the very silent-drop this item exists to kill.
run --afk=1
if [[ "$RC" -ne 0 || "$ERR" == *"--afk=1"* ]]; then
  ok "arity-0 with '=': '--afk=1' is surfaced (rc=$RC, named on stderr) — not silently dropped"
else
  bad "'--afk=1' must be an error path naming the token; got rc=$RC out='$OUT' err='$ERR'"
fi
[[ "$OUT" != *"--afk=1"* ]] \
  && ok "arity-0 with '=': the malformed token is never emitted onto stdout" \
  || bad "'--afk=1' must not be emitted as a flag; got out='$OUT'"

# ── Concern 5: REGRESSION CONTROLS — the untouched paths must not move ───────────
run --afk --quota-7d 45
[[ "$OUT" == "--afk --quota-7d 45" && -z "$ERR" ]] \
  && ok "control: the space-separated form is unchanged" \
  || bad "control: '--afk --quota-7d 45' should be unchanged; got out='$OUT' err='$ERR'"

run --exclude -x
[[ "$OUT" == "--exclude -x" ]] \
  && ok "control: a dash-leading VALUE is still preserved verbatim ('--exclude -x')" \
  || bad "control: '--exclude -x' should be preserved; got '$OUT'"

run --afkk
[[ "$RC" -eq 2 && "$ERR" == *"near-miss"* ]] \
  && ok "control: the near-miss escalation path (--afkk -> --afk) still exits 2" \
  || bad "control: '--afkk' should escalate (rc=2, 'near-miss' on stderr); got rc=$RC err='$ERR'"

run --qqqqzzzz somerepo
if [[ "$RC" -eq 0 && "$OUT" == "" && "$ERR" == *"unknown flag"* ]]; then
  ok "control: unknown-flag warn+drop, including the id:f475 value swallow, is unchanged"
else
  bad "control: '--qqqqzzzz somerepo' should warn+drop both tokens (rc=0, empty stdout); got rc=$RC out='$OUT'"
fi

echo
echo "  ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
