#!/usr/bin/env bash
# Defect-fix test for id:9628 -- no `# roadmap:` header on purpose: 9628 was filed
# straight from a cross-repo report and never went through a ROADMAP promotion, so
# there is no checkbox to key EXPECTED-RED off. Its failures always count.
#
# DEFECT: tools/ledger-shrink.py's MUST_KEEP_PATTERNS matched `@owner-accepted` without
# its date, so split_head() kept the TOKEN on the head line and relocated the DATE into
# the note -- a dateless receipt. Its sibling `@owner-answered:[0-9-]+` names the date and
# was unaffected, which is the control. Found by loderite's 03a3 wave-1 run (6 items).
#
# BOTH DIRECTIONS ARE PINNED BELOW AND THAT IS THE POINT. The obvious fix -- copy the
# sibling, make the date mandatory -- passes a dated-only test while dropping the BARE
# form out of the keep-set entirely, relocating every bare receipt in every repo (1,774
# bare vs 222 dated across this tree). Case B exists to fail against that fix.
#
# fails-against-mutation: python3 - <<'EOF'
# import re,pathlib
# p = pathlib.Path("tools/ledger-shrink.py")
# s = p.read_text()
# s = s.replace('re.compile(r"`?@owner-accepted(?::[0-9-]+)?`?"),',
#               're.compile(r"`?@owner-accepted`?"),')
# p.write_text(s)
# EOF
# fails-against-assertion: (A) dated receipt lost its date
#
# The mutation restores the pre-fix pattern verbatim. Case A is the assertion that
# fires there; case B is reachable but green at the parent (the bare form was always
# kept), so A is the only one the ancestor can be pinned on -- recorded here rather
# than left implicit.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

fails=0
FAIL() { echo "FAIL: $*"; fails=$((fails + 1)); }
pass() { echo "ok: $*"; }

read -r -d '' PY <<'PYEOF' || true
import importlib.util, sys

spec = importlib.util.spec_from_file_location("ls", "tools/ledger-shrink.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

pad = "x" * 700   # push the line over any plausible cut so a split really happens

def split(marker):
    head = ("- [ ] [ROUTINE] **Title of the item** " + marker +
            " " + pad + " <!-- id:abcd -->")
    keep, moved, reason = mod.split_head(head, "abcd")
    if keep is None:
        return None, None, reason
    return keep, moved, reason

for label, marker in (("dated", "@owner-accepted:2026-09-01"),
                      ("bare", "@owner-accepted")):
    keep, moved, reason = split(marker)
    if keep is None:
        print("{}\tREFUSED\t{}".format(label, reason))
    else:
        print("{}\tKEEP\t{}".format(label, keep.replace("\t", " ")))
PYEOF

out=$(python3 -c "$PY" 2>&1) || { echo "FAIL: harness could not run split_head"; echo "$out"; exit 1; }

dated_line=$(grep '^dated' <<<"$out" || true)
bare_line=$(grep '^bare'  <<<"$out" || true)

# Fixture sanity: both cases must actually SPLIT. A refusal would make the assertions
# below vacuous -- they would pass for the wrong reason on a line nothing happened to.
if ! grep -q '^dated	KEEP' <<<"$out" || ! grep -q '^bare	KEEP' <<<"$out"; then
  echo "FIXTURE-BROKEN: split_head refused a case; assertions would be vacuous"
  echo "$out"
  exit 1
fi

# (A) the DATED receipt keeps its date on the head line -- the defect itself.
if grep -q '@owner-accepted:2026-09-01' <<<"$dated_line"; then
  pass "(A) dated receipt keeps its full date"
else
  FAIL "(A) dated receipt lost its date -- kept: ${dated_line#dated	KEEP	}"
fi

# (B) the BARE receipt is still kept -- the regression a mandatory-date fix would cause.
if grep -q '@owner-accepted' <<<"$bare_line"; then
  pass "(B) bare receipt still kept"
else
  FAIL "(B) bare receipt was relocated -- the mandatory-date regression"
fi

if (( fails )); then
  echo "$fails assertion(s) failed"
  exit 1
fi
echo "PASS: owner-accepted receipts keep their date, bare form still kept (id:9628)"
