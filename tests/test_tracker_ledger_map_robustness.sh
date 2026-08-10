#!/usr/bin/env bash
# (no `# roadmap:` header — this is a DEFECT-FIX regression test found in review of
#  TODO id:2bb1; it has no roadmap item, so its failures ALWAYS count.)
#
# Two defects found by the reviewer's static pass over `tracker/ledger-map.py`:
#
#   (1) CRASH — `main()` built its argparse description from `__doc__.split(...)`.
#       Under `python3 -OO` the interpreter strips docstrings, so `__doc__` is None
#       and EVERY subcommand died with
#           AttributeError: 'NoneType' object has no attribute 'split'
#       before parsing a single argument. The mapper is a library-grade artifact the
#       fleet driver (id:94ce) and the adapters (id:90f2) will shell out to; it must
#       not depend on docstrings surviving interpreter optimisation.
#
#   (2) UNENFORCED CONTRACT — `derived_status` is documented in BOTH
#       `tracker/SCHEMA.md` and the JSON schema as "DERIVED for adapters only, never
#       authoritative", but `validate` only checked enum membership plus the single
#       drift=>not-done case. A document whose `derived_status` flatly contradicted its
#       per-view statuses validated OK. Per this repo's enforce-don't-document rule,
#       `validate` must RE-DERIVE the field and fail loudly on any mismatch — otherwise
#       an adapter round-trip can launder exactly the drift D2 (meeting 2026-08-10,
#       finding 5) forced the schema to represent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP="$ROOT/tracker/ledger-map.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$MAP" ]] || fail "missing mapper $MAP"

cd "$ROOT/tracker"

# === (1) docstring-free interpreter (`-OO`) ===========================================
# Every subcommand must work with docstrings stripped. `--help` alone is enough to
# reach the argparse construction that crashed.
if ! python3 -OO "$MAP" --help > "$tmp/help.out" 2> "$tmp/help.err"; then
  fail "python3 -OO ledger-map.py --help exited non-zero: $(cat "$tmp/help.err")"
fi
grep -qi 'no attribute' "$tmp/help.err" && fail "-OO --help still raised: $(cat "$tmp/help.err")"
grep -q 'import' "$tmp/help.out" || fail "-OO --help did not list the subcommands"

# A real end-to-end pass under -OO, not just --help.
python3 -OO "$MAP" import repo-alpha fixtures/repo-alpha > "$tmp/doc.json" 2> "$tmp/imp.err" \
  || fail "python3 -OO import exited non-zero: $(cat "$tmp/imp.err")"
python3 -OO "$MAP" validate "$tmp/doc.json" > /dev/null 2> "$tmp/val.err" \
  || fail "python3 -OO validate exited non-zero: $(cat "$tmp/val.err")"
python3 -OO "$MAP" render-status "$tmp/doc.json" > /dev/null \
  || fail "python3 -OO render-status exited non-zero"

# The -OO document must be byte-identical to the ordinary one: docstring stripping is
# an interpreter flag, never a behaviour switch.
python3 "$MAP" import repo-alpha fixtures/repo-alpha > "$tmp/doc-plain.json" 2>/dev/null
cmp -s "$tmp/doc.json" "$tmp/doc-plain.json" \
  || fail "-OO produced a different document than the default interpreter"

echo "PASS: ledger-map.py runs under python3 -OO (docstrings stripped)"

# === (2) derived_status is RE-DERIVED by validate, not merely enum-checked ============
# Corrupt one item's derived_status to another VALID enum value that contradicts its
# per-view statuses. Enum membership alone would let this through.
victim="$(python3 - "$tmp/doc-plain.json" "$tmp/bad-derived.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for it in doc["items"]:
    # an item whose correct derived_status is unambiguously "queued"
    if it["roadmap_status"] == "open" and it["derived_status"] == "queued":
        it["derived_status"] = "backlog"   # valid enum member, WRONG value
        json.dump(doc, open(sys.argv[2], "w"))
        print(it["uid"]); break
PY
)"
[[ -n "$victim" ]] || fail "could not build the contradicting-derived_status fixture"

set +e
python3 "$MAP" validate "$tmp/bad-derived.json" > /dev/null 2> "$tmp/bad.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "validate ACCEPTED a derived_status that contradicts its per-view statuses (\"derived, never authoritative\" is unenforced)"
[[ "$rc" -eq 3 ]] || fail "expected exit 3 from validate, got $rc"
grep -q 'derived_status' "$tmp/bad.err" || fail "validate rejected without naming derived_status: $(cat "$tmp/bad.err")"
grep -q "$victim" "$tmp/bad.err" || fail "validate did not name the offending uid $victim"

# ...and the honest document still validates clean (no false positive).
python3 "$MAP" validate "$tmp/doc-plain.json" > /dev/null 2> "$tmp/ok.err" \
  || fail "the re-derive check broke the clean fixture: $(cat "$tmp/ok.err")"

echo "PASS: validate re-derives derived_status and fails loudly on a mismatch"
