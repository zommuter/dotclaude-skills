#!/usr/bin/env bash
# (no `# roadmap:` header — this specs TODO id:9fa2, which has NO ROADMAP twin.
#  Its failures therefore ALWAYS count; there is no expected-red escape.)
#
# id:9fa2 — deliberate same-id MIRRORS across a parent repo and its plugin repo
# (`zkm` / `zkm-whatsapp`) are EXPECTED and must stop producing a class-A error,
# recorded as ONE convention rather than per-token ledger edges (owner-ratified
# 2026-09-01).
#
# THE TRAP this test pins (a first attempt hit it and was reverted): a purely
# STRUCTURAL `<parent>` / `<parent>-<suffix>` repo-name rule ALSO captures
#   * 5e19 / cfd1 — the two S4 doctrine-vs-instance tokens the owner separately
#     ruled must get a FRESH id on the zkm-whatsapp side (routed:4ede), and
#   * df4e (zkm / zkm-notmuch) — never in the needs-a-look set at all,
# silently removing them from the decision queue. Repo-name SHAPE is therefore
# not sound as the DRIVER; it may only act as a GUARD.
#
# Contract asserted here:
#   a. the four S1 mirror tokens (1c7d, 4b8e, d058, f5b7) stop erroring;
#   b. 5e19, cfd1 and df4e are NOT auto-downgraded (still fatal, still named);
#   c. two genuinely independent repos sharing a token still error — and a mirror
#      declaration for such a pair is REFUSED, loudly, rather than honoured;
#   d. every recognised mirror is REPORTED and COUNTED in the output (never a
#      silent downgrade — an invisible downgrade hides real collisions inside a
#      growing plugin family);
#   e. a mirror is scoped to its EXACT declared repo PAIR, not to the family —
#      a declared token that also turns up in a THIRD family repo is a genuine
#      birthday collision and stays FATAL, with a message naming both the declared
#      pair and the observed set (owner's 2026-09-01 narrowing ruling);
#   f. a BARE token line (the family-scoped spelling) is REJECTED outright — it is
#      the exact spelling that used to carry the superset hole.
#   g. the superset hole is closed in the PARENT'S OWN spelling too: `--mirror-token
#      1c7d` (bare) over {zkm, zkm-whatsapp, zkm-notmuch} must not exit 0.
#   h. a DECLARED mirror whose declaration is REFUSED outranks the homonym allow-list:
#      allow-listing the token must NOT cancel the refusal or make the run pass, and
#      the remediation text must not send the operator to the allow-list.
#   i. an ORDINARY (undeclared) class-A homonym is still adjudicated by --allow-homonym
#      exactly as before -- (h) must not over-fix into the plain allow-list path.
#
# REACHABILITY OF THE NEGATIVE CONTROL -- which assertions actually discriminate, and
# against WHICH ancestor. This matters because an unreached fixture in a file that goes
# red LOOKS like a passing negative control and is not one.
#
#   * Against 275fec46 (`tracker: record the parent/plugin mirror convention`, the
#     bare-token FAMILY-scoped implementation): assertions (a)-(f) are UNREACHABLE.
#     That commit's `collect_mirror_tokens` is the bare-token `_collect_tokens`, so the
#     PAIRED file this test writes (`1c7d zkm zkm-whatsapp`) fails its 4-hex check and
#     the run dies at exit 2 before any collision logic runs. The file goes red at (a)
#     -- but for the wrong reason, and (e)/(f) are never evaluated at all.
#     Assertion (g) is the DISCRIMINATING one: it is written in 275fec46's own
#     bare-token spelling and pins the actual defect. It is therefore ORDERED FIRST in
#     the file, ahead of the negative control and (a) -- otherwise the exit-2 abort at
#     (a) would keep it from ever running there, and (g) would itself be an unreached
#     fixture. Measured, against that commit:
#       $ python3 ledger-map.py validate superset.json --mirror-token 1c7d
#       WARN: cross-repo id MIRROR (class A downgraded): '1c7d' in repos
#             ['zkm', 'zkm-notmuch', 'zkm-whatsapp'] — parent/plugin mirror
#             convention (id:9fa2); parent 'zkm'
#       validate: OK (3 items, 3 repos, 2 warning(s))          exit 0   <-- absorbed
#     and against this tree, exit 2 (a bare token declares no repo PAIR).
#
#   * Against 66ed9f9a (`narrow the mirror ... to PAIR-scoped`, the first pair-scoped
#     implementation): (a)-(g) all PASS -- that commit closed the superset hole. The
#     DISCRIMINATING assertion there is (h): its `validate_doc` elif chain read
#     `tok in mirror_tokens and mirror_refusal(...) is None`, so a REFUSED mirror fell
#     through to the `allowed_homonyms` branch and the refusal was never emitted.
#     Measured, against that commit:
#       $ ledger-map.py validate superset.json --mirror-file mirror-tokens.txt \
#             --allow-homonym 1c7d
#       WARN: cross-repo id homonym (class A): '1c7d' in repos [...] — composite key
#             disambiguates; ADJUDICATED via --allow-homonym 1c7d
#       validate: OK (3 items, 3 repos, 4 warning(s))          exit 0   <-- absorbed
#     Latent rather than live (no token is on both lists today), and signposted the
#     wrong way: the refusal text said the allow-list is not the fix while the class-A
#     ERROR printed beside it said "adjudicate it explicitly with --allow-homonym".
#
# THE SECOND TRAP (e/f, found by review of the first implementation): the
# family guard accepts any SUPERSET, because `parent_plugin_family()` only asks
# whether EVERY repo hangs off one parent. Live proof against that code:
#   $ python3 ledger-map.py validate superset.json --mirror-file <(echo 1c7d)
#   WARN: cross-repo id MIRROR (class A downgraded): '1c7d' in repos
#         ['zkm', 'zkm-notmuch', 'zkm-whatsapp'] — parent/plugin mirror
#         convention (id:9fa2); parent 'zkm'
#   validate: OK (3 items, 3 repos, 2 warning(s))
# i.e. a fresh collision minted in ANY sibling plugin on a declared token was
# absorbed, exit 0. The hazard id:9fa2 exists to prevent, displaced one level:
# the growth is in the token's REPO SET rather than in the token list.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"
MIRROR_FILE="$ROOT/tracker/mirror-tokens.txt"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

cd "$ROOT/tracker"

# --- fixture: one real imported item, cloned into the collision topology -----------
python3 "$MAP" import repo-alpha fixtures/repo-alpha > "$tmp/alpha.json" 2>/dev/null \
  || fail "import repo-alpha exited non-zero"

python3 - "$tmp/alpha.json" "$tmp/fleet.json" <<'PY' || fail "fixture derivation failed"
import copy, json, sys

doc = json.load(open(sys.argv[1]))
tpl = next((i for i in doc["items"] if i.get("id") == "cccc"), None)
if tpl is None:
    print("ERROR: fixture template item cccc not found"); sys.exit(1)

# The topology under test:
#   zkm / zkm-whatsapp  -> the four S1 mirrors AND the two S4 remint tokens
#   zkm / zkm-notmuch   -> df4e, a plain birthday collision in the same family shape
#   repo-alpha / repo-beta -> cccc, two genuinely independent repos
PAIRS = [
    ("zkm", "zkm-whatsapp", ["1c7d", "4b8e", "d058", "f5b7", "5e19", "cfd1"]),
    ("zkm", "zkm-notmuch", ["df4e"]),
    ("repo-alpha", "repo-beta", ["cccc"]),
]

items, repos = [], {}
for a, b, tokens in PAIRS:
    for repo in (a, b):
        repos.setdefault(repo, {"repo": repo, "path": "fixtures/%s" % repo,
                                "ledger_files": ["TODO.md"], "labels": [], "verdict": None})
    for tok in tokens:
        for repo in (a, b):
            it = copy.deepcopy(tpl)
            it["repo"] = repo
            it["id"] = tok
            it["uid"] = "%s/%s" % (repo, tok)
            it["links"] = []
            it["blocked_by"] = []
            it["parent"] = None
            it["parents"] = []
            it["children"] = []
            items.append(it)

doc["items"] = items
doc["repos"] = [repos[k] for k in sorted(repos)]
json.dump(doc, open(sys.argv[2], "w"))
PY

# --- fixture 2: the SUPERSET topology (a THIRD family repo mints a declared token) --
# Built here, before any assertion, because assertion (g) below is the one that must
# stay REACHABLE against 275fec46 (see REACHABILITY in the header).
python3 - "$tmp/alpha.json" "$tmp/superset.json" <<'PY' || fail "superset fixture derivation failed"
import copy, json, sys
doc = json.load(open(sys.argv[1]))
tpl = next((i for i in doc["items"] if i.get("id") == "cccc"), None)
if tpl is None:
    print("ERROR: fixture template item cccc not found"); sys.exit(1)
# 1c7d is a DECLARED zkm/zkm-whatsapp mirror; zkm-notmuch mints it independently.
items, repos = [], {}
for repo in ("zkm", "zkm-whatsapp", "zkm-notmuch"):
    repos[repo] = {"repo": repo, "path": "fixtures/%s" % repo,
                   "ledger_files": ["TODO.md"], "labels": [], "verdict": None}
    it = copy.deepcopy(tpl)
    it.update(repo=repo, id="1c7d", uid="%s/1c7d" % repo, links=[],
              blocked_by=[], parent=None, parents=[], children=[])
    items.append(it)
doc["items"] = items
doc["repos"] = [repos[k] for k in sorted(repos)]
json.dump(doc, open(sys.argv[2], "w"))
PY

errors_naming() { grep '^ERROR' "$1" | grep -c "$2" || true; }

# --- (g) FIRST, because it is the assertion that discriminates against 275fec46 -----
# The superset hole must be closed in the PARENT'S OWN bare-token spelling. Ordered
# ahead of (a)-(f) deliberately: those use the PAIRED file, which 275fec46 rejects at
# exit 2 before any collision logic runs, so if (a) ran first this case would never be
# evaluated there -- an unreached fixture masquerading as a negative control. Measured
# against 275fec46 this exits 0, having absorbed the third repo's independent mint.
set +e
python3 "$MAP" validate "$tmp/superset.json" --mirror-token 1c7d \
  > /dev/null 2> "$tmp/sup_bare.err"
rc_sb=$?
set -e
[[ "$rc_sb" -ne 0 ]] \
  || fail "(g) the family-scoped bare spelling '--mirror-token 1c7d' absorbed a superset repo set and exited 0 -- the original defect: $(cat "$tmp/sup_bare.err")"
[[ "$(errors_naming "$tmp/sup_bare.err" 1c7d)" -ge 1 ]] \
  || fail "(g) the bare-token spelling produced no ERROR naming 1c7d: $(cat "$tmp/sup_bare.err")"

# --- negative control: with NO adjudication EVERY token is fatal -------------------
set +e
python3 "$MAP" validate "$tmp/fleet.json" > /dev/null 2> "$tmp/none.err"
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail "unadjudicated homonyms must exit 3, got $rc: $(cat "$tmp/none.err")"
for tok in 1c7d 4b8e d058 f5b7 5e19 cfd1 df4e cccc; do
  [[ "$(errors_naming "$tmp/none.err" "$tok")" -ge 1 ]] \
    || fail "baseline: $tok is not a class-A ERROR without adjudication"
done

# --- (a) the four S1 mirrors stop erroring under the recorded convention -----------
cat > "$tmp/mirrors.txt" <<'EOF'
# parent/plugin mirror convention — TOKEN then its EXACT repo pair
1c7d zkm zkm-whatsapp
4b8e zkm zkm-whatsapp
d058 zkm zkm-whatsapp
f5b7 zkm zkm-whatsapp
EOF

set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-file "$tmp/mirrors.txt" \
  > /dev/null 2> "$tmp/mir.err"
rc=$?
set -e
for tok in 1c7d 4b8e d058 f5b7; do
  [[ "$(errors_naming "$tmp/mir.err" "$tok")" -eq 0 ]] \
    || fail "(a) mirror token $tok still produces a class-A ERROR: $(grep "'$tok'" "$tmp/mir.err")"
done

# --- (b) 5e19 / cfd1 / df4e are NOT auto-downgraded -------------------------------
[[ "$rc" -eq 3 ]] || fail "(b) unlisted homonyms must still exit 3, got $rc"
for tok in 5e19 cfd1 df4e; do
  [[ "$(errors_naming "$tmp/mir.err" "$tok")" -ge 1 ]] \
    || fail "(b) $tok was silently swallowed by the mirror rule — it must stay fatal"
done

# --- (c) two genuinely independent repos sharing a token still error ---------------
[[ "$(errors_naming "$tmp/mir.err" cccc)" -ge 1 ]] \
  || fail "(c) cccc (repo-alpha/repo-beta) stopped erroring"

# ... and a mirror DECLARATION for such a pair is refused, loudly, not honoured.
cat > "$tmp/badmirror.txt" <<'EOF'
cccc repo-alpha repo-beta
EOF
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-file "$tmp/badmirror.txt" \
  > /dev/null 2> "$tmp/bad.err"
rc_bad=$?
set -e
[[ "$rc_bad" -eq 3 ]] || fail "(c) a mirror claim over unrelated repos must not make validate pass"
[[ "$(errors_naming "$tmp/bad.err" cccc)" -ge 1 ]] \
  || fail "(c) a mirror claim over unrelated repos downgraded cccc anyway"
grep -qi 'mirror' "$tmp/bad.err" \
  || fail "(c) the refused mirror claim for cccc was not reported at all"

# --- (d) every recognised mirror is reported AND counted --------------------------
grep '^WARN' "$tmp/mir.err" > "$tmp/mir.warn" || true
for tok in 1c7d 4b8e d058 f5b7; do
  grep -qi "mirror" "$tmp/mir.warn" \
    || fail "(d) no WARN line reports the recognised mirrors"
  grep -q "$tok" "$tmp/mir.warn" \
    || fail "(d) recognised mirror $tok is not named in the output — silent downgrade"
done
grep -qE 'mirror[^0-9]*4|4[^0-9]*mirror' "$tmp/mir.err" \
  || fail "(d) the output carries no COUNT of the recognised mirrors: $(grep -i mirror "$tmp/mir.err")"

# --- a stale mirror declaration (token is not a homonym here) is surfaced ----------
cat > "$tmp/stale.txt" <<'EOF'
1c7d zkm zkm-whatsapp
abcd zkm zkm-notmuch
EOF
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-file "$tmp/stale.txt" \
  > /dev/null 2> "$tmp/stale.err"
set -e
grep '^WARN' "$tmp/stale.err" > "$tmp/stale.warn" || true
grep -qi 'stale' "$tmp/stale.warn" \
  || fail "a mirror declaration for a non-homonym token is not reported as stale"
grep -q 'abcd' "$tmp/stale.warn" \
  || fail "the stale mirror token abcd is not named"

# --- (e) SUPERSET: a declared token that also appears in a THIRD family repo -------
# The mirror is scoped to its declared PAIR. A fresh birthday collision minted in any
# sibling plugin on one of the declared tokens must NOT be absorbed by the convention.
# (The superset fixture is built up front; see "fixture 2" above.)
set +e
python3 "$MAP" validate "$tmp/superset.json" --mirror-file "$tmp/mirrors.txt" \
  > /dev/null 2> "$tmp/sup.err"
rc_sup=$?
set -e
[[ "$rc_sup" -eq 3 ]] \
  || fail "(e) a superset repo set was absorbed by the declared mirror (exit $rc_sup) — the whole defect: $(cat "$tmp/sup.err")"
[[ "$(errors_naming "$tmp/sup.err" 1c7d)" -ge 1 ]] \
  || fail "(e) 1c7d over a superset repo set produced no class-A ERROR: $(cat "$tmp/sup.err")"
# ...and the reader must be able to tell this from an UNDECLARED homonym: the message
# names both the declared pair and the observed set.
grep -qi 'mirror' "$tmp/sup.err" \
  || fail "(e) the superset mismatch is not reported as a mirror problem at all"
grep -q 'zkm-notmuch' "$tmp/sup.err" \
  || fail "(e) the message does not name the OBSERVED repo set (zkm-notmuch)"
grep -q 'zkm-whatsapp' "$tmp/sup.err" \
  || fail "(e) the message does not name the DECLARED pair (zkm-whatsapp)"

# ...while the very same declaration still downgrades on its exact pair (no over-fix).
[[ "$(errors_naming "$tmp/mir.err" 1c7d)" -eq 0 ]] \
  || fail "(e) the pair-equality narrowing broke the exact-pair downgrade for 1c7d"

# --- (f) a BARE token line (the old family-scoped spelling) is REJECTED ------------
cat > "$tmp/bare.txt" <<'EOF'
1c7d
EOF
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-file "$tmp/bare.txt" \
  > /dev/null 2> "$tmp/bare.err"
rc_bare=$?
set -e
[[ "$rc_bare" -eq 2 ]] \
  || fail "(f) a bare (repo-less) mirror token must be rejected outright, got exit $rc_bare: $(cat "$tmp/bare.err")"
grep -qi 'repo' "$tmp/bare.err" \
  || fail "(f) the bare-token rejection does not say a repo pair is required"

# --- (h) a REFUSED mirror declaration OUTRANKS the homonym allow-list --------------
# The two surfaces make incompatible claims (SAME item vs two UNRELATED items), so an
# allow-list entry must not cancel a refusal. Against 66ed9f9a this exited 0.
set +e
python3 "$MAP" validate "$tmp/superset.json" --mirror-file "$tmp/mirrors.txt" \
  --allow-homonym 1c7d > /dev/null 2> "$tmp/both.err"
rc_both=$?
set -e
[[ "$rc_both" -eq 3 ]] \
  || fail "(h) a token that is BOTH a declared (refused) mirror AND allow-listed passed validate (exit $rc_both) -- the allow-list cancelled the refusal: $(cat "$tmp/both.err")"
[[ "$(errors_naming "$tmp/both.err" 1c7d)" -ge 1 ]] \
  || fail "(h) the refused mirror 1c7d produced no class-A ERROR while allow-listed"
grep -qi 'REFUSED' "$tmp/both.err" \
  || fail "(h) the mirror refusal was not emitted at all when the token was also allow-listed"
if grep -q 'ADJUDICATED via --allow-homonym' "$tmp/both.err"; then
  fail "(h) the allow-list still reports the refused mirror as adjudicated"
fi
# ...and the remediation TEXT must not contradict the refusal by telling the operator
# to allow-list a token the refusal has just ruled out.
grep '^ERROR' "$tmp/both.err" > "$tmp/both.errlines" || true
if grep -q 'adjudicate it explicitly with --allow-homonym' "$tmp/both.errlines"; then
  fail "(h) the class-A ERROR for a REFUSED mirror still tells the operator to allow-list it, contradicting the refusal in the WARN above"
fi

# --- (i) an ORDINARY, UNDECLARED class-A homonym is still adjudicated normally -----
# (h) must not over-fix: df4e is a plain birthday collision that is NOT in the mirror
# file, so --allow-homonym must still downgrade it to a warning, exactly as before.
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-file "$tmp/mirrors.txt" \
  --allow-homonym df4e > /dev/null 2> "$tmp/df4e.err"
set -e
[[ "$(errors_naming "$tmp/df4e.err" df4e)" -eq 0 ]] \
  || fail "(i) --allow-homonym df4e no longer adjudicates an ordinary class-A homonym: $(grep df4e "$tmp/df4e.err")"
grep '^WARN' "$tmp/df4e.err" > "$tmp/df4e.warn" || true
grep -q "ADJUDICATED via --allow-homonym df4e" "$tmp/df4e.warn" \
  || fail "(i) the ordinary allow-list adjudication of df4e is no longer reported"

# --- no wildcard / blanket spelling can stand in for the recorded convention -------
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-token 'all zkm zkm-whatsapp' \
  > /dev/null 2> "$tmp/wild.err"
rc_wild=$?
set -e
[[ "$rc_wild" -eq 2 ]] || fail "a non-4-hex mirror token must be rejected (exit 2), got $rc_wild"

# ...and no wildcard can stand in for a REPO either.
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-token '1c7d zkm *' \
  > /dev/null 2> "$tmp/wildrepo.err"
rc_wr=$?
set -e
[[ "$rc_wr" -eq 2 ]] || fail "a wildcard mirror REPO must be rejected (exit 2), got $rc_wr"

# ...and a wildcard as the ONLY repo gets the NO-GLOB message, not the misleading
# "declares no repo PAIR" (repo shape is checked BEFORE the pair count).
set +e
python3 "$MAP" validate "$tmp/fleet.json" --mirror-token '1c7d zkm*' \
  > /dev/null 2> "$tmp/wildonly.err"
rc_wo=$?
set -e
[[ "$rc_wo" -eq 2 ]] || fail "a glob as the only mirror repo must be rejected (exit 2), got $rc_wo"
grep -qi 'not a literal repo name' "$tmp/wildonly.err" \
  || fail "a glob as the only mirror repo is misreported as a missing PAIR: $(cat "$tmp/wildonly.err")"

# --- declarations are SPACE-separated; colon/comma forms are NOT silently accepted --
# Every doc says `<4-hex token> <repo> <repo>`; a lenient split would quietly accept a
# spelling no document describes.
for bad_form in '1c7d:zkm:zkm-whatsapp' '1c7d,zkm,zkm-whatsapp'; do
  set +e
  python3 "$MAP" validate "$tmp/fleet.json" --mirror-token "$bad_form" \
    > /dev/null 2> "$tmp/sep.err"
  rc_sep=$?
  set -e
  [[ "$rc_sep" -eq 2 ]] \
    || fail "a non-space-separated mirror declaration ($bad_form) must be rejected (exit 2), got $rc_sep"
  grep -qi 'literal 4-hex token' "$tmp/sep.err" \
    || fail "the rejection of $bad_form does not say the required form: $(cat "$tmp/sep.err")"
done

# --- the SHIPPED convention file records exactly the four S1 tokens, each PAIRED ---
[[ -f "$MIRROR_FILE" ]] || fail "tracker/mirror-tokens.txt (the recorded convention) is missing"
shipped="$(sed 's/#.*//' "$MIRROR_FILE" | grep -E '^[[:blank:]]*[0-9a-f]{4}[[:blank:]]' \
           | awk '{print $1}' | sort)"
[[ "$shipped" == "$(printf '1c7d\n4b8e\nd058\nf5b7\n' | sort)" ]] \
  || fail "tracker/mirror-tokens.txt must list exactly the four S1 mirrors, got: $(echo "$shipped" | tr '\n' ' ')"
# every shipped line must carry its exact repo pair — a bare token is the old,
# family-scoped spelling and must not survive in the shipped file either.
while read -r line; do
  line="${line%%#*}"
  [[ -z "${line// /}" ]] && continue
  [[ "$(awk '{print NF}' <<<"$line")" -ge 3 ]] \
    || fail "tracker/mirror-tokens.txt line is not '<token> <repo> <repo>': '$line'"
done < "$MIRROR_FILE"
grep -q '^1c7d[[:blank:]]\+zkm[[:blank:]]\+zkm-whatsapp[[:blank:]]*$' "$MIRROR_FILE" \
  || fail "tracker/mirror-tokens.txt does not record 1c7d against its exact zkm/zkm-whatsapp pair"
for tok in 5e19 cfd1 df4e; do
  if grep -qE "^$tok$" <<<"$shipped"; then
    fail "$tok must NOT be on the mirror convention list (owner ruled it a separate case)"
  fi
done

echo "PASS: parent/plugin mirror convention (id:9fa2)"
