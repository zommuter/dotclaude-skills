#!/usr/bin/env bash
# roadmap:b099
#
# Spec for relay/scripts/declared-path-extractor.sh — the mechanical
# declared-path extractor feeding disjoint-greenlight.sh (children-of:1f4f,
# meeting 2026-07-26-1922 D3). Synthetic fixtures under mktemp -d only —
# never reads another repo's corpus at test time (hermeticity).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SC="$ROOT/relay/scripts/declared-path-extractor.sh"
HELPER="$ROOT/tests/lib/assert-repo-unchanged.sh"

[[ -f "$SC" ]] || { echo "FAIL: relay/scripts/declared-path-extractor.sh does not exist yet (RED spec)"; exit 1; }
[[ -x "$SC" ]] || { echo "FAIL: declared-path-extractor.sh not executable"; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: missing dependency: $HELPER"; exit 1; }
# shellcheck disable=SC1090
source "$HELPER"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# === extract: a fixture item with path tokens in Context/Tests/Wiring ===================
item1="$TMP/item1.txt"
cat > "$item1" <<'EOF'
- [ ] [ROUTINE] some item <!-- id:aaaa -->
  - **Why**: prose, no paths here.
  - **Context**: extractor lives at `relay/scripts/declared-path-extractor.sh`; sibling `relay/scripts/disjoint-greenlight.sh`.
  - **Tests**: `tests/test_declared_path_extractor_b099.sh` (`# roadmap:b099`)
  - **Wiring**: feeds `relay/scripts/disjoint-greenlight.sh` (not wired here — id:ae08).
EOF
out="$("$SC" extract < "$item1")"
expect="relay/scripts/declared-path-extractor.sh,relay/scripts/disjoint-greenlight.sh,tests/test_declared_path_extractor_b099.sh"
[[ "$out" == "$expect" ]] \
  && ok "extract: item with Context/Tests/Wiring path tokens emits that set" \
  || bad "extract: expected '$expect', got '${out:-<empty>}'"

# === extract: an item with NO extractable path -> explicit RUN-ALONE, not empty =========
item2="$TMP/item2.txt"
cat > "$item2" <<'EOF'
- [ ] [ROUTINE] pure-prose item <!-- id:bbbb -->
  - **Why**: this is a design-only discussion with no file references at all.
  - **Context**: discuss the approach with the owner before building anything.
EOF
out="$("$SC" extract < "$item2")"
[[ "$out" == "RUN-ALONE" ]] \
  && ok "extract: no extractable path -> explicit RUN-ALONE verdict (F3)" \
  || bad "extract: expected literal RUN-ALONE (not empty string), got '${out:-<empty>}'"
[[ -n "$out" ]] \
  && ok "extract: RUN-ALONE verdict is non-empty (never confusable with an empty greenlight set)" \
  || bad "extract: verdict must not be empty stdout"

# === extract: a citation token that is NOT path-shaped (contains ':'/quotes) is excluded =
item3="$TMP/item3.txt"
cat > "$item3" <<'EOF'
- [ ] [ROUTINE] mixed item <!-- id:cccc -->
  - **Context**: cites `model:'bash'` in prose and a real path `relay/scripts/x.sh`.
EOF
out="$("$SC" extract < "$item3")"
[[ "$out" == "relay/scripts/x.sh" ]] \
  && ok "extract: non-path-shaped backtick token excluded, real path kept" \
  || bad "extract: expected only the real path, got '${out:-<empty>}'"

# === eval-corpus: build a 4-unit fixture corpus with KNOWN ground truth =================
# u1, u2: fully covered, no declared overlap between them (baseline, neutral).
u1="$TMP/u1.txt";        printf '  - **Context**: `relay/scripts/a.sh`\n  - **Tests**: `tests/test_a.sh`\n' > "$u1"
u1_actual="$TMP/u1a.txt"; printf 'relay/scripts/a.sh\ntests/test_a.sh\n' > "$u1_actual"
u2="$TMP/u2.txt";        printf '  - **Context**: `relay/scripts/b.sh`\n  - **Tests**: `tests/test_b.sh`\n' > "$u2"
u2_actual="$TMP/u2a.txt"; printf 'relay/scripts/b.sh\ntests/test_b.sh\n' > "$u2_actual"
# u3: UNDER-EXTRACTION — Context cites only one of two files actually touched.
u3="$TMP/u3.txt";        printf '  - **Context**: `relay/scripts/c.sh`\n' > "$u3"
u3_actual="$TMP/u3a.txt"; printf 'relay/scripts/c.sh\nrelay/scripts/c_helper.sh\n' > "$u3_actual"
# u4: FALSE-SERIALIZATION — Context CITES u1's path (not an actual touch of u4's own diff),
# so declared(u1) and declared(u4) intersect, but the two units' actual diffs are disjoint.
u4="$TMP/u4.txt";        printf '  - **Context**: background, see `relay/scripts/a.sh`.\n  - **Tests**: `tests/test_d.sh`\n' > "$u4"
u4_actual="$TMP/u4a.txt"; printf 'tests/test_d.sh\n' > "$u4_actual"

manifest="$TMP/manifest.tsv"
printf 'u1\t%s\t%s\nu2\t%s\t%s\nu3\t%s\t%s\nu4\t%s\t%s\n' \
  "$u1" "$u1_actual" "$u2" "$u2_actual" "$u3" "$u3_actual" "$u4" "$u4_actual" > "$manifest"

out="$("$SC" eval-corpus "$manifest")"
grep -qx 'units=4' < <(echo "$out") \
  && ok "eval-corpus: unit count correct" \
  || bad "eval-corpus: expected units=4, got: $out"
grep -qx 'under_extracted=1' < <(echo "$out") \
  && ok "eval-corpus: under-extraction counted exactly the 1 under-extracted unit (u3)" \
  || bad "eval-corpus: expected under_extracted=1, got: $out"
grep -qx 'under_extraction_rate=0.25' < <(echo "$out") \
  && ok "eval-corpus: under-extraction rate = 1/4 = 0.25" \
  || bad "eval-corpus: expected under_extraction_rate=0.25, got: $out"
grep -qx 'declared_overlap_pairs=1' < <(echo "$out") \
  && ok "eval-corpus: exactly the u1/u4 pair has declared-set overlap" \
  || bad "eval-corpus: expected declared_overlap_pairs=1, got: $out"
grep -qx 'false_serialized_pairs=1' < <(echo "$out") \
  && ok "eval-corpus: the citation-only overlap (u1/u4) is COUNTED as false-serialization, not silently dropped" \
  || bad "eval-corpus: expected false_serialized_pairs=1, got: $out"
grep -qx 'false_serialization_rate=1.00' < <(echo "$out") \
  && ok "eval-corpus: false-serialization rate = 1/1 = 1.00" \
  || bad "eval-corpus: expected false_serialization_rate=1.00, got: $out"

# === eval-corpus: an all-covered, no-overlap corpus reports zero on both metrics ========
manifest2="$TMP/manifest2.tsv"
printf 'u1\t%s\t%s\nu2\t%s\t%s\n' "$u1" "$u1_actual" "$u2" "$u2_actual" > "$manifest2"
out2="$("$SC" eval-corpus "$manifest2")"
grep -qx 'under_extraction_rate=0.00' < <(echo "$out2") \
  && ok "eval-corpus: fully-covered corpus -> under_extraction_rate=0.00" \
  || bad "eval-corpus: expected under_extraction_rate=0.00, got: $out2"
grep -qx 'declared_overlap_pairs=0' < <(echo "$out2") \
  && ok "eval-corpus: disjoint-declared corpus -> declared_overlap_pairs=0" \
  || bad "eval-corpus: expected declared_overlap_pairs=0, got: $out2"
grep -qx 'false_serialization_rate=n/a' < <(echo "$out2") \
  && ok "eval-corpus: no overlap pairs -> false_serialization_rate reported as n/a, not a division error" \
  || bad "eval-corpus: expected false_serialization_rate=n/a, got: $out2"

# === purity: extractor is pure-read — writes nothing outside its own output stream ======
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@e
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
}
P="$TMP/purity_repo"; mkrepo "$P"
printf '# marker\n' > "$P/f.txt"
git -C "$P" add -A; git -C "$P" commit -qm init
printf 'dirty\n' > "$P/dirty.txt"
git -C "$P" worktree add -q -b relay/purity-wt "$TMP/purity_wt" >/dev/null 2>&1 || true

snap="$TMP/purity.snapshot"
repo_state_snapshot "$P" > "$snap"

# run extract and eval-corpus with the repo as CWD, feeding fixtures OUTSIDE the repo
( cd "$P" && "$SC" extract < "$item1" >/dev/null )
( cd "$P" && "$SC" eval-corpus "$manifest" >/dev/null )

assert_repo_unchanged "$P" "$snap" \
  && ok "purity: repo with commit + dirty file + live worktree is byte-identical after extract + eval-corpus" \
  || bad "purity: declared-path-extractor.sh MUTATED the repo — it is documented pure-read"

# === malformed manifest: missing second tab -> nonzero exit, no crash ===================
bad_manifest="$TMP/bad_manifest.tsv"
printf 'u1\tonly-one-field\n' > "$bad_manifest"
if "$SC" eval-corpus "$bad_manifest" >/dev/null 2>"$TMP/err"; then
  bad "eval-corpus: malformed manifest line must exit nonzero"
else
  grep -qi 'ERROR' "$TMP/err" \
    && ok "eval-corpus: malformed manifest -> nonzero + ERROR on stderr" \
    || bad "eval-corpus: malformed manifest exited nonzero but printed no ERROR"
fi

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
