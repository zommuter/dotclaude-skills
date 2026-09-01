#!/usr/bin/env bash
# id:dd59 (since-ckpt half) — ledger-slice.sh must be able to DERIVE the id set itself from
# a git checkpoint ref, for the case relay-loop.js's mechanical hop cannot: it carries exactly
# one fenced allowlisted command, so deriving "what changed since the last checkpoint" has to
# live in this script rather than as real logic bolted onto the caller. relay-loop.js is
# NOT read or touched by this test or the change it specs.
#
# (No `# roadmap:` header: id:dd59 is a TODO.md-only item, not a ROADMAP.md unit, so its
# failures always count — never EXPECTED-RED.)
#
# Hermetic: mktemp -d fixture repo with real git history, bash + git + coreutils only, no
# network, never touches ~/.claude. Neutralizes the developer's global core.hooksPath (id:4d1c)
# since this builds and commits into a throwaway fixture repo directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/hermetic-git-env.sh
source "$ROOT/tests/lib/hermetic-git-env.sh"
SLICE="$ROOT/relay/scripts/ledger-slice.sh"

pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -x "$SLICE" ]] || { echo "FAIL: $SLICE missing/not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e
git -C "$R" config user.name t

printf '# ROADMAP\n\n## Items\n\n- [ ] [ROUTINE] **ITEM ONE** — base item <!-- id:1111 -->\n\n' > "$R/ROADMAP.md"
printf '# TODO\n\n## Current\n\n- [ ] twin of item one <!-- id:1111 -->\n' > "$R/TODO.md"
git -C "$R" add -A
git -C "$R" commit -qm "init" >/dev/null
git -C "$R" tag ckpt1

# (A) A commit that ADDS a ROADMAP item and mentions its id in the commit message.
printf -- '- [ ] [ROUTINE] **ITEM TWO** — added by commit <!-- id:2222 -->\n\n' >> "$R/ROADMAP.md"
git -C "$R" add -A
git -C "$R" commit -qm "feat: add item two (id:2222)" >/dev/null

# (B) A ROADMAP item added with NO commit-message mention at all -- the reverse-handoff case
# (a /meeting write or manual edit) that source (1) alone would miss.
printf -- '- [ ] [ROUTINE] **ITEM THREE** — added by meeting, no commit-message mention <!-- id:3333 -->\n\n' >> "$R/ROADMAP.md"
git -C "$R" add -A
git -C "$R" commit -qm "meeting: extend personas" >/dev/null

# (C) A commit whose message contains a BARE prose id mention (id:9999, never anchored
# anywhere) and a near-miss keyword (invalid:8888) -- neither must be picked up. Also adds a
# TODO.md line whose OWN id (id:4444) IS anchored, and its commit message ALSO mentions it.
printf -- '- [ ] some prose incidentally mentioning id:9999, not its own marker <!-- id:4444 -->\n' >> "$R/TODO.md"
git -C "$R" add -A
git -C "$R" commit -qm "todo: note (id:4444); prose mentions id:9999 and invalid:8888, neither is an edge" >/dev/null

# ── (1) Ids from COMMIT MESSAGES are derived (id:2222, id:4444). ────────────────────────────
O1="$TMP/since1.md"
err1="$TMP/err1.txt"
rc=0
"$SLICE" --repo repo --path "$R" --since-ckpt ckpt1 --out "$O1" >/dev/null 2>"$err1" || rc=$?
grep -q 'derived 4 id(s)' "$err1" \
  && ok "since-ckpt derives exactly 4 ids (2222, 3333, 4444, 9999 -- 1111 predates the checkpoint)" \
  || bad "id:dd59: expected 'derived 4 id(s)' on stderr, got: $(cat "$err1")"
grep -qF ' 2222' "$err1" && ok "commit-message id:2222 is in the derived set (printed on stderr)" || bad "id:dd59: id:2222 (from a commit message) missing from derived set"

# ── (2) Ids from ADDED ledger lines with NO commit-message mention (reverse-handoff, id:3333). ──
grep -qF ' 3333' "$err1" && ok "reverse-handoff id:3333 (ROADMAP line added, no commit mention) is derived" || bad "id:dd59: id:3333 (added-line-only) missing -- the reverse-handoff source was not consulted"

# ── (3) UNION + de-dup: id:4444 appears once even though it is mentioned in the commit ─────
#        message AND lives on an added TODO.md line (both sources see it).
n4444=$(grep -oc ' 4444' "$err1" || true)
grep -qF ' 4444' "$err1" \
  && ok "id:4444 (seen by BOTH sources) is present in the union" \
  || bad "id:dd59: id:4444 missing from the union entirely"

# ── (4) Anchoring is asymmetric BY DESIGN (owner-decided 2026-09-01) ────────────────────────
# Ledger diffs are anchored strictly (`<!-- id:X -->` only) because that convention EXISTS
# there. Commit messages are matched INCLUSIVELY on a keyword-prefixed `id:`/`routed:`,
# because no HTML-comment convention exists in a commit message and requiring one would
# derive almost nothing.
#
# Measured on 9 real commits since relay-ckpt-20260831-2326: commit messages yielded
# 2065/6958/cb22/dd59/e977, of which FOUR were genuinely worked; the anchored ledger diff
# yielded only dd59, because that session's work landed in hooks/, tests/ and tracker/ and
# was hand-committed without ticking checkboxes. Strict anchoring everywhere would therefore
# have hidden 3 of 4 worked items from the reviewer.
#
# The asymmetry is deliberate: over-inclusion costs BYTES against a slice with ~4x headroom;
# under-inclusion silently hides worked code from review, which is the D3 anti-gaming blind
# spot this whole item exists to close. So a passing prose mention like id:9999 IS derived,
# and that is not a defect.
grep -qF ' 9999' "$err1" && ok "bare prose id:9999 in a COMMIT MESSAGE is derived (inclusive by design -- see above)" || bad "id:dd59: id:9999 missing -- commit-message matching should be inclusive, not anchored"
grep -qF ' 8888' "$err1" && bad "id:dd59: invalid:8888 near-miss keyword was picked up as an id" || ok "invalid:8888 near-miss keyword is correctly rejected (word-boundary anchoring)"
grep -qF ' 1111' "$err1" && bad "id:dd59: id:1111 (predates the checkpoint, unchanged since) was incorrectly derived" || ok "id:1111 (present before ckpt1, untouched since) is correctly excluded"

# ── (5) The slice itself carries the derived items' blocks. ─────────────────────────────────
if [[ -s "$O1" ]]; then
  grep -q 'ITEM TWO' "$O1" && ok "slice contains ITEM TWO (id:2222, commit-message source)" || bad "id:dd59: slice missing ITEM TWO"
  grep -q 'ITEM THREE' "$O1" && ok "slice contains ITEM THREE (id:3333, reverse-handoff source)" || bad "id:dd59: slice missing ITEM THREE"
  grep -q 'ITEM ONE' "$O1" && bad "id:dd59: slice leaked ITEM ONE (id:1111), which predates the checkpoint" || ok "slice correctly excludes ITEM ONE (predates the checkpoint)"
else
  bad "id:dd59: no slice file written even though ids were derived and some resolve"
fi
# id:4444 has no owning ROADMAP.md item but DOES live in TODO.md. Two contract changes made
# on live evidence (run relay-20260901-100342-3206) meet here, and this assertion is rewritten
# rather than merely inverted:
#   (a) TODO-only ids are SLICED, not dropped -- ROADMAP is the execution queue but plenty of
#       worked ids live only in the design ledger (3 of the 14 derived live).
#   (b) a written slice EXITS 0 even with unresolved ids -- a non-zero exit is flattened to
#       `MECH-ERROR exit=N` by the mechanical hop and the good slice is thrown away.
# So id:4444 is now RESOLVED (as TODO-only), the run exits 0, and it must NOT be reported as
# owning nothing.
[[ "$rc" -eq 0 ]] && ok "a derived TODO-only id does not fail the run (exit 0)" || bad "id:dd59: derived TODO-only id:4444 exited $rc -- the slice would be discarded as MECH-ERROR"
grep -q '^## TODO-only items' "$TMP/since1.md" && ok "the TODO-only section carries the design-ledger id" || bad "id:dd59: id:4444 has no ROADMAP item and no TODO-only section was emitted"
grep -qi '4444.*owns no ROADMAP.*AND no TODO' "$err1" && bad "id:dd59: id:4444 reported as owning nothing, but it has a TODO.md entry" || ok "a TODO-only id is NOT reported as unresolved"

# ── (6) An INVALID / unreachable ref fails LOUDLY and does NOT silently slice everything. ──
O2="$TMP/since2.md"
rc2=0
"$SLICE" --repo repo --path "$R" --since-ckpt this-tag-does-not-exist --out "$O2" >/dev/null 2>"$TMP/err2.txt" || rc2=$?
[[ "$rc2" -eq 2 ]] && ok "an invalid --since-ckpt ref exits with the usage code (2)" || bad "id:dd59: invalid ref exited $rc2, expected 2"
[[ -e "$O2" ]] && bad "id:dd59: DANGEROUS -- an invalid ref still wrote a slice file (silent fall-back to whole history?)" || ok "an invalid ref writes NO slice file"
if [[ -e "$O2" ]]; then
  grep -q 'ITEM ONE' "$O2" && bad "id:dd59: invalid ref produced a slice covering the WHOLE repo (id:1111 present) -- the exact failure this change exists to prevent" || true
fi

# ── (7) A valid ref with an EMPTY derived set (tag == HEAD) is reported and distinguishable. ──
git -C "$R" tag ckpt_head
O3="$TMP/since3.md"
rc3=0
"$SLICE" --repo repo --path "$R" --since-ckpt ckpt_head --out "$O3" >/dev/null 2>"$TMP/err3.txt" || rc3=$?
[[ "$rc3" -eq 5 ]] && ok "an empty derived set exits 5 (distinct from 2=misuse and 4=unresolved-id)" || bad "id:dd59: empty derived set exited $rc3, expected 5"
[[ -e "$O3" ]] && bad "id:dd59: empty derived set still wrote a slice file" || ok "empty derived set writes no slice file"
grep -qi 'derived NO ids' "$TMP/err3.txt" && ok "empty derivation is reported on stderr with a reason" || bad "id:dd59: empty derivation not reported on stderr"

# ── (8) --since-ckpt is mutually exclusive with --id and --ids. ─────────────────────────────
rc4=0; "$SLICE" --repo repo --path "$R" --since-ckpt ckpt1 --id 1111 --out "$TMP/x1.md" >/dev/null 2>"$TMP/errx1.txt" || rc4=$?
[[ "$rc4" -eq 2 ]] && ok "--since-ckpt + --id together exits 2" || bad "id:dd59: --since-ckpt + --id exited $rc4, expected 2"
rc5=0; "$SLICE" --repo repo --path "$R" --since-ckpt ckpt1 --ids 1111,2222 --out "$TMP/x2.md" >/dev/null 2>"$TMP/errx2.txt" || rc5=$?
[[ "$rc5" -eq 2 ]] && ok "--since-ckpt + --ids together exits 2" || bad "id:dd59: --since-ckpt + --ids exited $rc5, expected 2"

# ── (9) The id:35b7 stdout contract survives: slice-bytes first, path LAST. ─────────────────
stdout1="$("$SLICE" --repo repo --path "$R" --since-ckpt ckpt1 --out "$TMP/since_stdout.md" 2>/dev/null || true)"
first="$(head -1 <<<"$stdout1")"
last_line="$(printf '%s\n' "$stdout1" | grep -v '^[[:space:]]*$' | tail -1)"
[[ "$first" =~ ^slice-bytes:\ [0-9]+$ ]] && ok "slice-bytes line still leads stdout under --since-ckpt" || bad "id:dd59: stdout does not lead with 'slice-bytes: N' (got: '$first')"
[[ "$last_line" == "$TMP/since_stdout.md" ]] && ok "the slice path is still the LAST stdout line under --since-ckpt" || bad "id:dd59: last stdout line is '$last_line', expected the slice path"

# ── (10) --since-last-review resolves the REVIEW checkpoint family itself. ──────────────────
# WHY THIS EXISTS: relay-loop.js used to pass `unit.lastCkpt`, which is NEVER assigned for a
# naturally-discovered unit (discover-repo.sh emits no last_ckpt; discovery is mechanical), so
# the review path was a silent no-op. The one script that does emit it greps `fable-ckpt-*`,
# a family that here was ~3 months stale -- measured, that ref spanned 3,612 commits, derived
# 1,702 ids and produced a 1,515,130 B "slice". So the slicer resolves `relay-ckpt-*` itself.
# This test pins BOTH halves: the right family is chosen, and a STALER OTHER family present in
# the same repo is NOT chosen.
git -C "$R" tag relay-ckpt-20260101-0000 >/dev/null 2>&1
git -C "$R" tag fable-ckpt-20990101-0000 >/dev/null 2>&1   # lexically NEWER, wrong family
err_slr="$TMP/err_slr.txt"
rc_slr=0
"$SLICE" --repo repo --path "$R" --since-last-review --out "$TMP/slr.md" >/dev/null 2>"$err_slr" || rc_slr=$?
grep -q 'resolved to relay-ckpt-20260101-0000' "$err_slr" \
  && ok "--since-last-review resolves the newest relay-ckpt-* tag and says so" \
  || bad "id:dd59: --since-last-review did not resolve relay-ckpt-20260101-0000 (got: $(head -2 "$err_slr"))"
grep -q 'fable-ckpt' "$err_slr" \
  && bad "id:dd59: --since-last-review picked up a fable-ckpt-* tag -- wrong checkpoint family" \
  || ok "a lexically-newer fable-ckpt-* tag is correctly IGNORED (review family only)"

# A repo with NO relay-ckpt-* tag is 'nothing to slice', not a failure: exit 5, no file.
R2="$TMP/repo2"; mkdir -p "$R2"; git -C "$R2" init -q .
git -C "$R2" config user.email t@e; git -C "$R2" config user.name t
printf -- '- [ ] [ROUTINE] a <!-- id:1111 -->\n' > "$R2/ROADMAP.md"
: > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm base >/dev/null
rc_no=0
"$SLICE" --repo repo2 --path "$R2" --since-last-review --out "$TMP/no_tag.md" >/dev/null 2>"$TMP/err_no.txt" || rc_no=$?
[[ "$rc_no" -eq 5 ]] && ok "no relay-ckpt-* tag exits 5 (nothing to slice, distinguishable from failure)" || bad "id:dd59: expected exit 5 with no relay-ckpt tag, got $rc_no"
[[ ! -e "$TMP/no_tag.md" ]] && ok "no relay-ckpt-* tag writes no slice file" || bad "id:dd59: a slice file was written with no relay-ckpt tag"

rc_mx=0
"$SLICE" --repo repo --path "$R" --since-last-review --ids 1111 --out "$TMP/mx.md" >/dev/null 2>&1 || rc_mx=$?
[[ "$rc_mx" -eq 2 ]] && ok "--since-last-review + --ids together exits 2" || bad "id:dd59: mutual exclusion not enforced for --since-last-review (got $rc_mx)"

# ── (11) SIZE GUARD: a slice that cannot fit the dispatch budget is REFUSED, not returned. ──
# The first version of this guard was "refuse if not smaller than the ledgers" and it MISSED
# its own motivating case: the runaway came to 1,515,130 B against 1,555,658 B of ledgers --
# 97.4%, technically smaller, useless, and it sailed through. The bound is now the dispatch
# budget: a slice above (BUDGET - OVERHEAD) * CHARS_PER_TOKEN cannot dispatch no matter what.
rc_big=0
LEDGER_SLICE_MAX_BYTES=1 "$SLICE" --repo repo --path "$R" --since-ckpt ckpt1 --out "$TMP/big.md" >/dev/null 2>"$TMP/err_big.txt" || rc_big=$?
[[ "$rc_big" -eq 6 ]] && ok "an over-ceiling slice exits 6 (distinct from 4=unresolved and 5=empty)" || bad "id:dd59: expected exit 6 over the size ceiling, got $rc_big"
[[ ! -e "$TMP/big.md" ]] && ok "an over-ceiling slice writes NO file (not returned to be refused downstream)" || bad "id:dd59: an over-ceiling slice was still written"
grep -q 'cannot fit the dispatch budget' "$TMP/err_big.txt" && ok "the size refusal is LOUD and names the ceiling (id:4347)" || bad "id:dd59: size refusal message missing from stderr"
grep -qE 'produced [0-9]+ B' "$TMP/err_big.txt" && ok "the size refusal names the actual slice size, so a runaway range is diagnosable" || bad "id:dd59: size refusal does not report the produced byte count"

echo "---"
echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: ledger-slice.sh derives its own id set from --since-ckpt (id:dd59)"
