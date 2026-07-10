#!/usr/bin/env bash
# (No roadmap token — this test tracks TODO id:2e6d and always counts.)
# Hermetic tests for tools/memory-index.py — the derived MEMORY.md index.
# Everything runs in a mktemp -d fixture dir; the real ~/.claude memory dir is
# NEVER read or written.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/memory-index.py"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$TOOL" ]] || fail "memory-index.py not found at $TOOL"
pass "tool exists"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Write a memory file with optional hook / description / archived.
# usage: mkmem <dir> <filename> <name> <description> [<hook>] [<archived>]
mkmem() {
    local dir="$1" fn="$2" name="$3" desc="$4" hook="${5:-}" arch="${6:-}"
    {
        echo "---"
        echo "name: $name"
        [[ -n "$desc" ]] && echo "description: \"$desc\""
        [[ -n "$hook" ]] && echo "hook: \"$hook\""
        echo "metadata:"
        echo "  type: project"
        [[ -n "$arch" ]] && echo "  archived: $arch"
        echo "  originSessionId: abcd1234"
        echo "---"
        echo ""
        echo "body of $name"
    } > "$dir/$fn"
}

# ── test 1: pointerless file gets APPENDED (the core dissolution) ─────────────
D="$TMP/t1"; mkdir -p "$D"
mkmem "$D" "alpha.md" "alpha" "alpha desc"
mkmem "$D" "beta.md"  "beta"  "beta desc"
# Existing index that only knows about alpha — beta has no pointer.
cat > "$D/MEMORY.md" <<EOF
# Project memory — t1

> old header

- [alpha](alpha.md) — alpha desc
EOF
python3 "$TOOL" --dir "$D" --write --project t1
grep -q "beta.md" "$D/MEMORY.md" || fail "test1: pointerless beta.md was not appended"
pass "test1: pointerless memory file is appended (dropped pointer cannot survive)"

# ── test 2: pointer whose file was deleted disappears ────────────────────────
D="$TMP/t2"; mkdir -p "$D"
mkmem "$D" "alpha.md" "alpha" "alpha desc"
cat > "$D/MEMORY.md" <<EOF
# Project memory — t2

> old

- [alpha](alpha.md) — alpha desc
- [ghost](ghost.md) — ghost desc
EOF
python3 "$TOOL" --dir "$D" --write --project t2
grep -q "ghost.md" "$D/MEMORY.md" && fail "test2: deleted ghost.md pointer survived"
grep -q "alpha.md" "$D/MEMORY.md" || fail "test2: alpha.md wrongly dropped"
pass "test2: pointer to a deleted file disappears"

# ── test 3: existing order preserved for already-pointered files ─────────────
D="$TMP/t3"; mkdir -p "$D"
mkmem "$D" "aaa.md" "aaa" "a desc"
mkmem "$D" "bbb.md" "bbb" "b desc"
mkmem "$D" "ccc.md" "ccc" "c desc"
# Cache order deliberately NOT alphabetical: ccc, aaa, bbb
cat > "$D/MEMORY.md" <<EOF
# Project memory — t3

> old

- [ccc](ccc.md) — c desc
- [aaa](aaa.md) — a desc
- [bbb](bbb.md) — b desc
EOF
python3 "$TOOL" --dir "$D" --write --project t3
ORDER="$(grep -oE '\]\([a-z]+\.md\)' "$D/MEMORY.md" | tr -d '])(' | tr '\n' ' ')"
[[ "$ORDER" == "ccc.md aaa.md bbb.md " ]] || fail "test3: order not preserved, got: $ORDER"
pass "test3: existing pointer order is preserved"

# ── test 4: hook wins over description; description used when hook absent ─────
D="$TMP/t4"; mkdir -p "$D"
mkmem "$D" "withhook.md" "withhook" "the description" "the HOOK"
mkmem "$D" "nohook.md"   "nohook"   "desc only"
python3 "$TOOL" --dir "$D" --write --project t4
grep -q "^- \[withhook\](withhook.md) — the HOOK$" "$D/MEMORY.md" \
    || fail "test4: hook did not win over description"
grep -q "^- \[nohook\](nohook.md) — desc only$" "$D/MEMORY.md" \
    || fail "test4: description not used as fallback"
pass "test4: hook wins over description; description is the fallback"

# ── test 5: archived routes to MEMORY.archive.md, out of MEMORY.md ───────────
D="$TMP/t5"; mkdir -p "$D"
mkmem "$D" "live.md" "live" "live desc"
mkmem "$D" "old.md"  "old"  "old desc" "" "true"
python3 "$TOOL" --dir "$D" --write --project t5
grep -q "old.md" "$D/MEMORY.md" && fail "test5: archived old.md leaked into MEMORY.md"
grep -q "old.md" "$D/MEMORY.archive.md" || fail "test5: archived old.md not in archive"
grep -q "live.md" "$D/MEMORY.md" || fail "test5: live.md missing from MEMORY.md"
pass "test5: archived entry routes to MEMORY.archive.md and out of MEMORY.md"

# ── test 6: feedback-* + archived → exit 2, loud message ─────────────────────
D="$TMP/t6"; mkdir -p "$D"
mkmem "$D" "feedback-x.md" "feedback-x" "a preference" "" "true"
set +e
ERR="$(python3 "$TOOL" --dir "$D" --write --project t6 2>&1 >/dev/null)"
RC=$?
set -e
[[ $RC -eq 2 ]] || fail "test6: expected exit 2, got $RC"
echo "$ERR" | grep -qi "never be archived" || fail "test6: missing loud message, got: $ERR"
echo "$ERR" | grep -q "feedback-x.md" || fail "test6: message did not name the file"
pass "test6: feedback-* + archived is a loud exit-2 failure"

# ── test 7: multi-line/newline hook → exit 2 ─────────────────────────────────
D="$TMP/t7"; mkdir -p "$D"
cat > "$D/multi.md" <<'EOF'
---
name: multi
hook: "line one
line two"
metadata:
  type: project
---

body
EOF
set +e
ERR="$(python3 "$TOOL" --dir "$D" --write --project t7 2>&1 >/dev/null)"
RC=$?
set -e
[[ $RC -eq 2 ]] || fail "test7: expected exit 2 for newline hook, got $RC"
echo "$ERR" | grep -qi "newline" || fail "test7: missing newline error, got: $ERR"
echo "$ERR" | grep -q "multi.md" || fail "test7: did not name the file"
pass "test7: multi-line hook is a loud exit-2 failure"

# ── test 8: --check exits 0 in sync, 1 (with diff) out of sync ───────────────
D="$TMP/t8"; mkdir -p "$D"
mkmem "$D" "one.md" "one" "one desc"
python3 "$TOOL" --dir "$D" --write --project t8
set +e
python3 "$TOOL" --dir "$D" --check --project t8 >/dev/null
RC=$?
set -e
[[ $RC -eq 0 ]] || fail "test8: --check on in-sync dir should exit 0, got $RC"
# Introduce drift: add a new pointerless file.
mkmem "$D" "two.md" "two" "two desc"
set +e
DIFF="$(python3 "$TOOL" --dir "$D" --check --project t8)"
RC=$?
set -e
[[ $RC -eq 1 ]] || fail "test8: --check on drifted dir should exit 1, got $RC"
echo "$DIFF" | grep -q "two.md" || fail "test8: diff did not mention the new file"
pass "test8: --check exits 0 in sync, 1 with a diff out of sync"

# ── test 9: --write is idempotent (byte-identical second run) ─────────────────
D="$TMP/t9"; mkdir -p "$D"
mkmem "$D" "p.md" "p" "p desc"
mkmem "$D" "q.md" "q" "q desc" "" "true"
mkmem "$D" "r.md" "r" "r desc" "r HOOK"
python3 "$TOOL" --dir "$D" --write --project t9
H1="$(md5sum < "$D/MEMORY.md")"; A1="$(md5sum < "$D/MEMORY.archive.md")"
python3 "$TOOL" --dir "$D" --write --project t9
H2="$(md5sum < "$D/MEMORY.md")"; A2="$(md5sum < "$D/MEMORY.archive.md")"
[[ "$H1" == "$H2" ]] || fail "test9: MEMORY.md not byte-identical on second write"
[[ "$A1" == "$A2" ]] || fail "test9: MEMORY.archive.md not byte-identical on second write"
# write-then-check must be clean.
set +e
python3 "$TOOL" --dir "$D" --check --project t9 >/dev/null
RC=$?
set -e
[[ $RC -eq 0 ]] || fail "test9: --write then --check should exit 0, got $RC"
pass "test9: --write is idempotent and --check-clean afterwards"

# ── test 10: ceiling exceeded → stderr warning, exit still 0 ──────────────────
D="$TMP/t10"; mkdir -p "$D"
for i in $(seq 1 12); do
    mkmem "$D" "mem$i.md" "mem$i" "some reasonably long description number $i to add bytes"
done
set +e
ERR="$(python3 "$TOOL" --dir "$D" --write --project t10 --ceiling 200 2>&1 >/dev/null)"
RC=$?
set -e
[[ $RC -eq 0 ]] || fail "test10: over-ceiling should still exit 0, got $RC"
echo "$ERR" | grep -qi "WARNING" || fail "test10: no ceiling warning on stderr, got: $ERR"
echo "$ERR" | grep -q "over" || fail "test10: warning missing overage detail, got: $ERR"
pass "test10: ceiling exceeded warns on stderr but exits 0"

# ── test 11: title resolution order (title: → name: → stem) ──────────────────
D="$TMP/t11"; mkdir -p "$D"
# (a) title: present → used
cat > "$D/withtitle.md" <<'EOF'
---
name: the-long-name
title: short
description: "d"
metadata:
  type: project
---
body
EOF
# (b) title absent, name present → name used
cat > "$D/withname.md" <<'EOF'
---
name: just-the-name
description: "d"
metadata:
  type: project
---
body
EOF
# (c) both absent → filename stem used; also exercises trailing-space `metadata: `
#     and a name containing a space is never clobbered (covered by (b) not using stem).
# NOTE: `metadata: ` below intentionally has a TRAILING SPACE (real-data quirk).
printf '%s\n' \
  '---' \
  'description: "d"' \
  'metadata: ' \
  '  archived: false' \
  '---' \
  'body' > "$D/stemonly.md"
# (d) no metadata block at all → archived=false, must not crash
cat > "$D/nometa.md" <<'EOF'
---
name: no-meta
description: "d"
type: project
originSessionId: zzzz
---
body
EOF
python3 "$TOOL" --dir "$D" --write --project t11
grep -q "^- \[short\](withtitle.md) —" "$D/MEMORY.md" \
    || fail "test11a: title: was not used as display title"
grep -q "^- \[just-the-name\](withname.md) —" "$D/MEMORY.md" \
    || fail "test11b: name: was not used when title: absent"
grep -q "^- \[stemonly\](stemonly.md) —" "$D/MEMORY.md" \
    || fail "test11c: filename stem not used when both title: and name: absent"
grep -q "^- \[no-meta\](nometa.md) —" "$D/MEMORY.md" \
    || fail "test11d: file without a metadata block was not handled"
pass "test11: title→name→stem resolution order (and no-metadata / trailing-space robustness)"

echo "ALL PASS"
