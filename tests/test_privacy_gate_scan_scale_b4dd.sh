#!/usr/bin/env bash
# fails-against: c9c7fc0 (hooks/pre-push-privacy-gate.sh before the id:b4dd rewrite —
#   it diffed every all-zero-remote-sha ref against the EMPTY TREE, so each of a
#   `--follow-tags` push's new tag refs re-scanned the WHOLE published history, and it
#   forked one `grep` per pattern per added line. Measured on ~/src/dotclaude-skills:
#   27.5 s for the branch ref alone, and >120 s (still running when killed) for ONE of
#   28 tag refs. Verified red: cases (1) and (3) below both fail against that revision.)
#
# NO `# roadmap:` header ON PURPOSE — this is a DEFECT-FIX test (id:b4dd is a TODO bug
# item, not an open ROADMAP spec item), so its failures always count and it must never be
# reported EXPECTED-RED. See CLAUDE.md §Testing + tests/lint-vacuous-fixtures.py.
#
# What this pins (id:b4dd — the gate was so slow the public remote got disabled):
#   (1) SCOPE. A pushed ref whose remote sha is all-zero (every new annotated tag under
#       `git push --follow-tags`) must be scanned against what the remote DEMONSTRABLY
#       ALREADY HAS — not against the empty tree. Content already published is not
#       re-scanned once per tag.
#   (2) DETECTION IS NOT WEAKENED. A leak in the genuinely-new commits is still found,
#       still printed, still logged — reached via a tag ref as well as a branch ref.
#   (3) COST IS O(patterns), NOT O(patterns x lines). Proven by SHIMMING `grep` and
#       counting invocations: the count must be scale-INVARIANT in the number of added
#       lines. This is deterministic — no wall-clock assertion, no flake.
#   (4) SEMANTICS PRESERVED. Still warn+LOG only, still exit 0, never blocks.
#   (5) FRESH REPO. With no remote-tracking refs and no known remote sha, the whole
#       history is still scanned (the pre-existing first-push behaviour).
#
# Hermetic: throwaway repos under mktemp, synthetic fixture tokens only (NEVER a real
# leak specific), fixture pattern file, fake remote URLs. Touches no ~/.claude, no
# ~/.config/dotclaude-skills/privacy-patterns.txt, no network.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$SRC_DIR/hooks/pre-push-privacy-gate.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "BAD: $*"; fail=$((fail+1)); }

[[ -f "$HOOK" ]] || { echo "FAIL: hook not found at $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── fixture PRIVATE pattern file (synthetic tokens only) ───────────────────────────────
PAT="$TMP/patterns.txt"
{
  echo '# synthetic fixture — no real leak specifics'
  echo 'ZZOLDLEAK-[0-9]+'      # seeded ONLY in already-published history
  echo 'ZZNEWLEAK-[0-9]+'      # seeded ONLY in the commits this push publishes
  echo 'ZZMERGELEAK-[0-9]+'    # seeded ONLY in a merge's resolved tree (id:5171)
  echo 'allow: ZZALLOWED-[0-9]+'
} > "$PAT"

# A wide-but-cheap pattern set for the scale case (case 3): enough patterns that the old
# fork-per-pattern-per-line shape is unmistakable in the invocation count.
PAT_WIDE="$TMP/patterns-wide.txt"
{
  echo '# synthetic fixture'
  echo 'ZZNEWLEAK-[0-9]+'
  for i in $(seq 1 24); do echo "ZZNOMATCH${i}-[0-9]+"; done
} > "$PAT_WIDE"

# ── helper: build a repo with a PUBLISHED base (carrying ZZOLDLEAK) plus NEW commits ───
mkrepo() { # <dir>  → echoes "<published_sha> <head_sha>"
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name tester
  git -C "$d" config core.hooksPath /dev/null
  printf 'base line\nZZOLDLEAK-1111 published long ago\n' > "$d/file.txt"
  git -C "$d" add file.txt
  git -C "$d" commit -q -m published
  local published; published="$(git -C "$d" rev-parse HEAD)"
  printf 'base line\nZZOLDLEAK-1111 published long ago\nZZNEWLEAK-2222 added by this push\n' > "$d/file.txt"
  git -C "$d" add file.txt
  git -C "$d" commit -q -m new-work
  local head; head="$(git -C "$d" rev-parse HEAD)"
  # an annotated tag on the NEW head — this is what --follow-tags pushes with a zero
  # remote sha, and what used to trigger the whole-history rescan
  git -C "$d" tag -a -m ckpt zz-ckpt-1 "$head"
  # the remote-tracking ref proving the remote already holds $published
  git -C "$d" update-ref "refs/remotes/github/main" "$published"
  echo "$published $head"
}

relaytoml() { # <repo> → path to a relay.toml that marks <repo> as an own repo
  local d="$1" f
  f="$(dirname "$d")/relay.toml"
  printf '[repos.testfix]\nclassification = "own"\npath = "%s"\n' "$d" > "$f"
  printf '%s\n' "$f"
}

REPO="$TMP/r1/repo"; mkdir -p "$TMP/r1"
read -r PUBLISHED HEADSHA <<< "$(mkrepo "$REPO")"
RELAYTOML="$(relaytoml "$REPO")"
TAGSHA="$(git -C "$REPO" rev-parse refs/tags/zz-ckpt-1)"
ZERO=0000000000000000000000000000000000000000
PUBLIC_URL='https://github.com/acme/repo.git'

run_hook() { # <patterns-file> <log> [extra env assignments…] ; stdin = ref lines
  local pf="$1" lg="$2"; shift 2
  ( cd "$REPO" && env PRIVACY_GATE_PATTERNS="$pf" PRIVACY_GATE_LOG="$lg" \
      PRIVACY_GATE_RELAY_TOML="$RELAYTOML" "$@" \
      bash "$HOOK" github "$PUBLIC_URL" ) 2>&1
}

# ── (1) a NEW TAG ref must not drag the whole published history into the scan ──────────
# Both refs of a realistic `--follow-tags` push: the branch (with its true remote sha)
# and the new tag (remote sha all-zero). ZZOLDLEAK lives only in the ALREADY-PUBLISHED
# commit; the old empty-tree base reported it, once per tag.
LOG1="$TMP/gate1.log"; : > "$LOG1"
out1="$(printf 'refs/heads/main %s refs/heads/main %s\nrefs/tags/zz-ckpt-1 %s refs/tags/zz-ckpt-1 %s\n' \
          "$HEADSHA" "$PUBLISHED" "$TAGSHA" "$ZERO" | run_hook "$PAT" "$LOG1")"
rc1=$?

[[ $rc1 -eq 0 ]] \
  && ok "b4dd: push with a new-tag ref exits 0 (warn+log, never blocks)" \
  || bad "b4dd: exited $rc1 — the gate must never block a push"

grep -q 'ZZOLDLEAK-1111' <<<"$out1" \
  && bad "b4dd: ALREADY-PUBLISHED content was re-scanned via the tag ref (empty-tree base). Output: $out1" \
  || ok "b4dd: new-tag ref does NOT re-scan already-published history"

grep -q 'ZZOLDLEAK-1111' "$LOG1" 2>/dev/null \
  && bad "b4dd: already-published leak was LOGGED — the tag ref used an empty-tree base" \
  || ok "b4dd: already-published leak is not logged for a tag ref"

# ── (2) ANTI-REGRESSION: the genuinely-new leak is still detected, printed and logged ──
grep -q 'ZZNEWLEAK-2222' <<<"$out1" \
  && ok "b4dd: leak in the newly-pushed commits is STILL PRINTED (detection intact)" \
  || bad "b4dd: NEW leak went undetected — the optimisation weakened the gate. Output: $out1"

grep -q 'ZZNEWLEAK-2222' "$LOG1" 2>/dev/null \
  && ok "b4dd: leak in the newly-pushed commits is STILL LOGGED" \
  || bad "b4dd: NEW leak not appended to the log"

# ...and reached via the TAG ref alone, with NO branch ref in the push at all.
LOG2="$TMP/gate2.log"; : > "$LOG2"
out2="$(printf 'refs/tags/zz-ckpt-1 %s refs/tags/zz-ckpt-1 %s\n' "$TAGSHA" "$ZERO" \
          | run_hook "$PAT" "$LOG2")"
grep -q 'ZZNEWLEAK-2222' <<<"$out2" \
  && ok "b4dd: a tag-only push still detects the new leak (scope narrowed, not detection)" \
  || bad "b4dd: tag-only push missed the new leak. Output: $out2"
grep -q 'ZZOLDLEAK-1111' <<<"$out2" \
  && bad "b4dd: tag-only push re-scanned published history" \
  || ok "b4dd: tag-only push skips already-published history"

# ── (3) COST IS SCALE-INVARIANT: shim `grep`, count invocations at two input sizes ─────
# The old shape forked one grep per pattern per added line, so the count grew LINEARLY
# with the number of added lines. The count must now be driven by the PATTERN count only.
SHIMBIN="$TMP/shimbin"; mkdir -p "$SHIMBIN"
REAL_GREP="$(command -v grep)"
cat > "$SHIMBIN/grep" <<EOF
#!/usr/bin/env bash
printf 'x\n' >> "\$GREP_COUNT_FILE"
exec "$REAL_GREP" "\$@"
EOF
chmod +x "$SHIMBIN/grep"

grep_count_for() { # <added-line-count> → echoes number of grep invocations
  local n="$1"
  local d="$TMP/scale$n/repo"; mkdir -p "$TMP/scale$n"
  git -C "$(dirname "$d")" init -q "$(basename "$d")" 2>/dev/null || { mkdir -p "$d"; git -C "$d" init -q; }
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name tester
  git -C "$d" config core.hooksPath /dev/null
  printf 'seed\n' > "$d/f.txt"
  git -C "$d" add f.txt; git -C "$d" commit -q -m base
  local b; b="$(git -C "$d" rev-parse HEAD)"
  # n added lines, exactly one of which carries the seeded leak
  { printf 'seed\n'; for ((i=0;i<n;i++)); do printf 'filler line %d nothing here\n' "$i"; done
    printf 'ZZNEWLEAK-3333 one seeded leak\n'; } > "$d/f.txt"
  git -C "$d" add f.txt; git -C "$d" commit -q -m grow
  local h; h="$(git -C "$d" rev-parse HEAD)"
  local rt="$TMP/scale$n/relay.toml"
  printf '[repos.testfix]\nclassification = "own"\npath = "%s"\n' "$d" > "$rt"
  local cf="$TMP/scale$n/grepcount"; : > "$cf"
  local lg="$TMP/scale$n/gate.log"; : > "$lg"
  local so
  so="$( cd "$d" && printf 'refs/heads/main %s refs/heads/main %s\n' "$h" "$b" \
        | env PATH="$SHIMBIN:$PATH" GREP_COUNT_FILE="$cf" \
              PRIVACY_GATE_PATTERNS="$PAT_WIDE" PRIVACY_GATE_LOG="$lg" \
              PRIVACY_GATE_RELAY_TOML="$rt" \
              bash "$HOOK" github "$PUBLIC_URL" 2>&1 )"
  # non-vacuity: the run must actually have found the seeded leak, else the count is
  # measuring a scan that never happened.
  if ! grep -q 'ZZNEWLEAK-3333' <<<"$so"; then
    echo "VACUOUS" ; return 0
  fi
  wc -l < "$cf" | tr -d ' '
}

# Sizes are overridable ONLY so the negative control (running this file against the
# pre-fix hook, which forks ~26 greps per added line) can complete in finite time.
# The assertion is a RATIO/invariance claim, so it holds at any 10x pair.
SMALL="${B4DD_SCALE_SMALL:-200}"
LARGE="${B4DD_SCALE_LARGE:-2000}"
c_small="$(grep_count_for "$SMALL")"
c_large="$(grep_count_for "$LARGE")"

if [[ "$c_small" == "VACUOUS" || "$c_large" == "VACUOUS" ]]; then
  bad "b4dd: scale probe is VACUOUS — the shimmed run did not detect the seeded leak, so the grep count proves nothing (small=$c_small large=$c_large)"
else
  ok "b4dd: scale probe is non-vacuous (seeded leak detected at both sizes)"
  echo "     grep invocations: $SMALL added lines -> $c_small ; $LARGE added lines -> $c_large"
  # 10x the input must not meaningfully move the count. Generous absolute slack (+30)
  # covers the handful of fixed greps (remote-URL classification, own-repo lookup).
  if [[ "$c_large" -le $(( c_small + 30 )) ]]; then
    ok "b4dd: grep invocations are scale-INVARIANT in added lines ($c_small -> $c_large for $SMALL -> $LARGE added lines)"
  else
    bad "b4dd: grep invocations grew with input size ($c_small -> $c_large for $SMALL -> $LARGE added lines) — still forking per pattern per line"
  fi
  # Absolute sanity: ~25 patterns should not need thousands of greps.
  if [[ "$c_large" -lt 200 ]]; then
    ok "b4dd: absolute grep count stays O(patterns) ($c_large for $LARGE added lines, 25 patterns)"
  else
    bad "b4dd: $c_large grep invocations for $LARGE added lines — not O(patterns)"
  fi
fi

# ── (5) FRESH REPO (no remote-tracking refs, no known remote sha): whole history is ────
#        still scanned — the pre-existing first-push behaviour is preserved.
FRESH="$TMP/fresh/repo"; mkdir -p "$TMP/fresh"
git -C "$TMP/fresh" init -q repo
git -C "$FRESH" config user.email t@example.com
git -C "$FRESH" config user.name tester
git -C "$FRESH" config core.hooksPath /dev/null
printf 'ZZOLDLEAK-9999 in the very first commit\n' > "$FRESH/a.txt"
git -C "$FRESH" add a.txt; git -C "$FRESH" commit -q -m first
printf 'ZZOLDLEAK-9999 in the very first commit\nplain second line\n' > "$FRESH/a.txt"
git -C "$FRESH" add a.txt; git -C "$FRESH" commit -q -m second
FHEAD="$(git -C "$FRESH" rev-parse HEAD)"
FRT="$TMP/fresh/relay.toml"
printf '[repos.testfix]\nclassification = "own"\npath = "%s"\n' "$FRESH" > "$FRT"
LOG3="$TMP/gate3.log"; : > "$LOG3"
out3="$( cd "$FRESH" && printf 'refs/heads/main %s refs/heads/main %s\n' "$FHEAD" "$ZERO" \
          | env PRIVACY_GATE_PATTERNS="$PAT" PRIVACY_GATE_LOG="$LOG3" \
                PRIVACY_GATE_RELAY_TOML="$FRT" bash "$HOOK" github "$PUBLIC_URL" 2>&1 )"
grep -q 'ZZOLDLEAK-9999' <<<"$out3" \
  && ok "b4dd: FIRST push of a fresh repo still scans the whole history (no haves)" \
  || bad "b4dd: fresh-repo first push missed a leak in the root commit — first-push scanning regressed. Output: $out3"

# ── (6) MERGE-COMMIT RESOLVED-TREE CONTENT (id:5171) ───────────────────────────────────
# `git log -p` prints NO diff for a merge commit by default, so a leak that exists ONLY
# in the merge's RESOLVED TREE — a genuine conflict, hand-resolved with new content
# present in NEITHER parent — was invisible to the id:b4dd rewrite even though the old
# tree-diff caught it. Build a real conflict (not a synthetic "merge commit" faked via
# `commit --allow-empty` or similar) and resolve it with the seeded leak, then push ONLY
# the merge commit (the remote already has both parent tips, via remote-tracking refs).
MREPO="$TMP/merge/repo"; mkdir -p "$TMP/merge"
git -C "$TMP/merge" init -q repo
git -C "$MREPO" config user.email t@example.com
git -C "$MREPO" config user.name tester
git -C "$MREPO" config core.hooksPath /dev/null

printf 'line1\nline2\nline3\n' > "$MREPO/f.txt"
git -C "$MREPO" add f.txt
git -C "$MREPO" commit -q -m base

git -C "$MREPO" checkout -q -b branch-a
printf 'line1\nCHANGED-ON-A\nline3\n' > "$MREPO/f.txt"
git -C "$MREPO" commit -q -am on-a
MA="$(git -C "$MREPO" rev-parse HEAD)"

git -C "$MREPO" checkout -q main 2>/dev/null || git -C "$MREPO" checkout -q master
printf 'line1\nCHANGED-ON-B\nline3\n' > "$MREPO/f.txt"
git -C "$MREPO" commit -q -am on-b
MB="$(git -C "$MREPO" rev-parse HEAD)"

# Merge branch-a in: f.txt conflicts on line2. Resolve by hand with the seeded leak —
# text present in NEITHER MA's nor MB's version of the line.
git -C "$MREPO" merge -q --no-ff branch-a -m "merge with conflict" >/dev/null 2>&1 || true
printf 'line1\nZZMERGELEAK-8888 resolved by hand\nline3\n' > "$MREPO/f.txt"
git -C "$MREPO" add f.txt
git -C "$MREPO" commit -q -m "merge with conflict"
MM="$(git -C "$MREPO" rev-parse HEAD)"

# Remote already holds BOTH parent tips (a normal state: they were pushed earlier,
# the merge commit is the only new thing in this push).
git -C "$MREPO" update-ref "refs/remotes/github/main" "$MB"
git -C "$MREPO" update-ref "refs/remotes/github/branch-a" "$MA"

MRT="$TMP/merge/relay.toml"
printf '[repos.testfix]\nclassification = "own"\npath = "%s"\n' "$MREPO" > "$MRT"

LOG5="$TMP/gate5.log"; : > "$LOG5"
out5="$( cd "$MREPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "$MM" "$MB" \
          | env PRIVACY_GATE_PATTERNS="$PAT" PRIVACY_GATE_LOG="$LOG5" \
                PRIVACY_GATE_RELAY_TOML="$MRT" bash "$HOOK" github "$PUBLIC_URL" 2>&1 )"

grep -q 'ZZMERGELEAK-8888' <<<"$out5" \
  && ok "id:5171: leak in a merge's RESOLVED TREE (present in neither parent) is PRINTED" \
  || bad "id:5171: merge-resolution-only leak went UNDETECTED — git log -p prints no diff for merge commits. Output: $out5"

grep -q 'ZZMERGELEAK-8888' "$LOG5" 2>/dev/null \
  && ok "id:5171: merge-resolution-only leak is LOGGED" \
  || bad "id:5171: merge-resolution-only leak was not appended to the log"

# ── (4) a ref this repo cannot resolve is reported LOUDLY, never silently dropped ──────
LOG4="$TMP/gate4.log"; : > "$LOG4"
out4="$(printf 'refs/heads/main %s refs/heads/main %s\n' \
          'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' "$PUBLISHED" | run_hook "$PAT" "$LOG4")"
rc4=$?
[[ $rc4 -eq 0 ]] && ok "b4dd: unresolvable ref still exits 0" || bad "b4dd: unresolvable ref exited $rc4"
grep -qiE 'not resolvable|NOT scanned' <<<"$out4" \
  && ok "b4dd: an unscannable ref is announced LOUDLY (no silent skip on a security gate)" \
  || bad "b4dd: unresolvable ref was dropped silently. Output: $out4"

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: pre-push privacy gate scan scope + cost (id:b4dd)"
