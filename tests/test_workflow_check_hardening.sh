#!/usr/bin/env bash
# roadmap:1b0e
#
# RED SPEC for THREE defects in tests/lib-workflow-check.sh, all found by the id:62c9 review
# on 2026-09-08 and all reproduced before this file was written:
#
#   id:1b0e -- `workflow_node_check` returns 0 (a PASS) on a file it could not READ. `[[ ! -f ]]`
#              guards existence, not readability; the `awk` refusal scan dies and its empty
#              stdout reads as "no unmodellable construct"; the wrapper build is a brace group
#              whose status is the last `printf`'s, so `sed`'s failure is discarded too. ~40 of
#              the 48 call sites redirect stderr to /dev/null, so nothing surfaces. A FALSE
#              GREEN -- the single outcome the helper exists to prevent.
#              Detail: docs/ledger-notes/1b0e.md
#
#   id:e044 -- the refusal scan reads PROSE as module syntax. A line-initial `export `/`import `
#              inside a backticked template literal or a `/* */` block comment REFUSES the whole
#              file, and `import ("x")` (one space before the paren, a legal dynamic import) is
#              refused too. Latent, not live -- relay-loop.js has exactly one match, line 1 --
#              but that file is 4,930 lines of mostly backticked prompt templates. Fails CLOSED,
#              so a fragility, not a false green. Detail: docs/ledger-notes/e044.md
#
#   id:ad67 -- the Workflow runtime is STRICT (PROBED 2026-09-08:
#              {"thisIsUndefined":true,"implicitGlobalThrew":"ReferenceError","verdict":"STRICT"}),
#              while the wrapper carries no strict directive, so the wrapped body is SLOPPY and
#              a file whose only defect is strict-only syntax passes. A second false green,
#              arriving through the opposite door. Detail: docs/ledger-notes/ad67.md
#
# WHAT THE EXECUTOR MUST NOT DO
# -----------------------------
# * Do not make the check permissive: assertions (a) and (c4) below pin that a real syntax
#   error and a real non-line-1 module construct are STILL rejected. "Stop refusing anything"
#   fails this file.
# * Do not narrow the strict fix to one construct: (d1)-(d3) use three DISTINCT strict-only
#   syntax errors, so special-casing duplicate parameters alone is caught.
# * Do not restructure relay/scripts/relay-loop.js -- the owner closed that option under
#   id:62c9. Assertion (a) is the regression guard for the live file.
#
# NOT PINNED HERE, deliberately: `export default` on line 1 currently produces a confusing
# node parse error rather than a clean refusal (the `sed -E '1s/^export //'` strip leaves a
# bare `default ...`). The right behaviour there -- strip, or refuse loudly -- is a judgement
# the ledger notes settle, so this spec does not dictate one -- pinning an unratified choice in
# a RED spec would decide it by default. Recorded in docs/ledger-notes/e044.md
# §"Adjacent residue, NOT pinned by the spec"; it needs an owner call first.
#
# `# roadmap:1b0e` above means this file is EXPECTED-RED while THAT item is unticked
# (tests/run-tests.sh reads the FIRST roadmap token), and ROADMAP-SHADOWED in
# tests/verify-negative-cases.py (id:7c82) -- so the declaration below does NOT execute until
# the item is ticked. The file also specs roadmap:e044 and roadmap:ad67; all three are one
# executor unit and should be ticked together, because ticking only 1b0e turns the still-open
# e044/ad67 assertions into hard suite failures.
#
# fails-against: the tree as it stands at 062ea7d731efcf463c957560767de225845bf80e, where
#   tests/lib-workflow-check.sh is the landed, defective version -- which is also the CURRENT
#   version, so this file is red today for exactly the reason it declares. `fail()` exits, so
#   precisely one FAIL line fires and it is the FIRST failing assertion: (a) passes against
#   that helper (it parses the pristine relay-loop.js), so (b1) -- the id:1b0e unreadable-file
#   case -- is the assertion that must fire. (c*) and (d*) are unreached there; that is
#   expected, and each was independently reproduced against the same helper by hand before
#   this file was authored.
#   Reachability caveat, on the record: if this spec is ever run as a user who can read a
#   `chmod 000` file (root), (b1) is UNREACHABLE and the file exits 3 (ERROR, never
#   EXPECTED-RED) instead of emitting a FAIL line -- the declaration cannot be satisfied there
#   and the run is loud about why. That is the id:735f contract, not a silent pass.
# fails-against-rev: 062ea7d731efcf463c957560767de225845bf80e -- tests/lib-workflow-check.sh
# fails-against-assertion: (b1) an UNREADABLE but syntactically BROKEN file was ACCEPTED

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/tests/lib-workflow-check.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

tmp="$(mktemp -d)"
cleanup() { chmod -R u+rwX "$tmp" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }
# id:735f contract: a check that COULD NOT RUN exits 3, which tests/run-tests.sh reports as
# ERROR and never as EXPECTED-RED. Used only where the fixture itself is unbuildable here.
cannot_run() { echo "ERROR: $*"; exit 3; }

command -v node >/dev/null 2>&1 || cannot_run "node is not on PATH -- this spec cannot be verified here"
[[ -f "$LOOP" ]] || cannot_run "relay/scripts/relay-loop.js is missing; the spec's subject does not exist"
[[ -f "$HELPER" ]] || fail "(0) tests/lib-workflow-check.sh does not exist -- id:62c9's helper is this spec's subject"
# shellcheck source=/dev/null
source "$HELPER"
declare -F workflow_node_check >/dev/null 2>&1 \
  || fail "(0b) tests/lib-workflow-check.sh does not define a workflow_node_check function"

# write <name> <body>  -> prints the path of the fixture
write() { local out="$tmp/$1.js"; printf '%s\n' "$2" > "$out"; printf '%s' "$out"; }

# ---------------------------------------------------------------------------------------
# (a) REGRESSION GUARD -- the pristine relay/scripts/relay-loop.js must still parse green.
#     Every fix below is only acceptable if it leaves the live file alone. This passes today
#     and must keep passing; it is what makes "add 'use strict'" (id:ad67) safe, and it was
#     verified against a strict wrapper before that fix was proposed.
# ---------------------------------------------------------------------------------------
workflow_node_check "$LOOP" \
  || fail "(a) workflow_node_check REJECTS the pristine relay/scripts/relay-loop.js -- a hardening change has reddened the one file the helper exists to guard"
pass "(a) the pristine relay-loop.js still parses green"

# ---------------------------------------------------------------------------------------
# (b) id:1b0e -- an UNREADABLE file must never be reported as a clean parse.
#     The fixture is genuinely broken JavaScript, so a helper that could read it would reject
#     it; the ONLY thing under test is what happens when the read fails.
# ---------------------------------------------------------------------------------------
b_src="$tmp/unreadable_broken.js"
printf 'const a = ;\nthis is not javascript at all {{{\n' > "$b_src"

# Sanity: readable, it IS caught. Without this, (b1) could pass for the wrong reason -- a
# helper that rejects every file would satisfy (b1) while being useless.
workflow_node_check "$b_src" >/dev/null 2>&1 \
  && fail "(b0) the fixture is not actually broken -- workflow_node_check ACCEPTED it while readable, so (b1) would prove nothing"
pass "(b0) the fixture is genuinely broken while readable"

chmod 000 "$b_src"
if cat "$b_src" >/dev/null 2>&1; then
  # Running as root (or on a filesystem that ignores the mode). The case cannot be exercised
  # at all, and a test that silently cannot exercise its case is the id:735f class -- so this
  # is LOUD (exit 3 => ERROR in run-tests.sh), never a vacuous pass.
  cannot_run "(b) the id:1b0e unreadable-file case CANNOT be exercised as this user -- a chmod 000 file is still readable here (root?), so the case is skipped rather than passed vacuously"
fi
b_msg="$(workflow_node_check "$b_src" 2>&1)" \
  && fail "(b1) an UNREADABLE but syntactically BROKEN file was ACCEPTED (rc=0) -- id:1b0e: readability is unguarded, and the failures of awk and sed are both discarded, so every stage failed and the function still returned success"
grep -qF "$(basename "$b_src")" <<<"$b_msg" \
  || fail "(b2) the unreadable-file refusal does not NAME the file, so the ~40 call sites that redirect stderr see nothing actionable: $b_msg"
chmod 644 "$b_src"
pass "(b) an unreadable file is refused, loudly, naming the file"

# ---------------------------------------------------------------------------------------
# (b3) id:0165 -- TOCTOU: the file is READABLE when `[[ ! -r ]]` checks it, so the guard is
#     satisfied and cannot fire, but becomes unreadable before `sed` actually reads it. This is
#     the path that has NO assertion at all today: mutant-tested (docs/ledger-notes/0165.md),
#     removing the sed_rc capture+check while KEEPING `[[ ! -r ]]` still passes the whole suite,
#     because (b1)/(b2) exercise a file that is already unreadable at guard time and never reach
#     this branch. A fake `sed` shim is placed first on PATH: it chmods the source file to 000
#     as its FIRST action -- after the readability guard and the awk scan have both already run
#     against the still-readable file -- and only then execs the REAL sed, which now genuinely
#     fails to read it. This reproduces "readable at guard/awk time, unreadable at sed time"
#     deterministically instead of racing a real TOCTOU window, and the failure (and its message)
#     come from the real sed, not a faked one.
# ---------------------------------------------------------------------------------------
b3_src="$tmp/toctou_sed.js"
printf 'const a = 1;\nconst q = await Promise.resolve(a);\nif (q) { return q; }\n' > "$b3_src"
chmod 644 "$b3_src"

b3_bin="$tmp/b3-bin"
mkdir -p "$b3_bin"
real_sed="$(command -v sed)"
cat > "$b3_bin/sed" <<SHIM
#!/usr/bin/env bash
chmod 000 "$b3_src" 2>/dev/null || true
out="\$("$real_sed" "\$@")"
rc=\$?
printf '%s\n' "\$out"
exit "\$rc"
SHIM
chmod +x "$b3_bin/sed"

b3_msg="$(PATH="$b3_bin:$PATH" workflow_node_check "$b3_src" 2>&1)" \
  && { chmod 644 "$b3_src"; fail "(b3) a file that turned unreadable AFTER the guard check but BEFORE sed read it was ACCEPTED -- the sed_rc capture+check is the only thing that can catch a TOCTOU window, and this proves it is unpinned without this assertion"; }
chmod 644 "$b3_src"
grep -qF "sed exit" <<<"$b3_msg" \
  || fail "(b3b) the TOCTOU-before-sed refusal did not name it as a sed failure: $b3_msg"
pass "(b3) a file that turns unreadable between the guard check and the sed read is refused via the sed_rc capture"

# ---------------------------------------------------------------------------------------
# (b4) id:0165 -- pin the awk_rc capture+check's own failure message. A fake `awk` shim is placed
#     first on PATH that always fails (exit 7) instead of scanning -- this isolates the awk_rc
#     branch specifically (workflow_node_check must never reach `node --check` when the module-
#     syntax scan itself could not run) and pins the exact message text, so a mutant that drops
#     the `awk exit $awk_rc` wording (or the branch itself) is caught even though this shim never
#     touches file permissions at all.
# ---------------------------------------------------------------------------------------
b4_src="$tmp/awk_failure.js"
printf 'const a = 1;\nconst q = await Promise.resolve(a);\nif (q) { return q; }\n' > "$b4_src"

b4_bin="$tmp/b4-bin"
mkdir -p "$b4_bin"
cat > "$b4_bin/awk" <<'SHIM'
#!/usr/bin/env bash
exit 7
SHIM
chmod +x "$b4_bin/awk"

b4_msg="$(PATH="$b4_bin:$PATH" workflow_node_check "$b4_src" 2>&1)" \
  && fail "(b4) a file was ACCEPTED while the module-syntax scan (awk) itself failed to run -- the awk_rc capture+check is the only thing that can catch this"
grep -qF "awk exit 7" <<<"$b4_msg" \
  || fail "(b4b) the awk-scan-failure refusal did not pin the awk exit status in its message: $b4_msg"
pass "(b4) an awk scan that fails to run is refused, naming its exit status"

# ---------------------------------------------------------------------------------------
# (c) id:e044 -- the refusal must key on real module constructs, not on prose that happens to
#     start a line with `export `/`import `. Four cases: three that must be ACCEPTED and one
#     that must still be REFUSED, so "stop refusing anything" cannot pass.
# ---------------------------------------------------------------------------------------
c1="$(write export_in_template 'const t = `
export const fake = 1;
`;
const q = await Promise.resolve(t);
if (q) { return q; }')"
workflow_node_check "$c1" \
  || fail "(c1) a line-initial \`export \` INSIDE a backticked template literal was refused -- id:e044: the awk scan is line-oriented with no lexical context, and relay-loop.js is 4,930 lines of mostly backticked prompt templates"
pass "(c1) a line-initial export inside a template literal is accepted"

c2="$(write export_in_block_comment 'const a = 1;
/*
export const fake = 1;
*/
const q = await Promise.resolve(a);
if (q) { return q; }')"
workflow_node_check "$c2" \
  || fail "(c2) a line-initial \`export \` inside a /* */ BLOCK COMMENT was refused -- id:e044: the helper claims a mention in a comment never trips the refusal; that guarantee holds only for // comments"
pass "(c2) a line-initial export inside a block comment is accepted"

c3="$(write dynamic_import_spaced 'const a = 1;
import ("node:fs").then(() => {});
const q = await Promise.resolve(a);
if (q) { return q; }')"
workflow_node_check "$c3" \
  || fail "(c3) a line-initial \`import (\` with a space before the paren was refused -- id:e044: that is a legal dynamic import call, not a module construct, and the unspaced \`import(\` form is already accepted"
pass "(c3) a spaced dynamic import call is accepted"

c4="$(write real_export_line5 'const a = 1;
const b = 2;
const c = 3;
const d = 4;
export const e = 5;')"
c4_msg="$(workflow_node_check "$c4" 2>&1)" \
  && fail "(c4) a GENUINE top-level \`export \` on line 5 was ACCEPTED -- the id:e044 fix must narrow the refusal, not remove it; a real ESM module scope cannot be modelled by the async-function wrapper"
grep -qF "$(basename "$c4")" <<<"$c4_msg" \
  || fail "(c4b) the refusal of a genuine line-5 export does not name the file: $c4_msg"
pass "(c4) a genuine non-line-1 export is still refused, loudly"

# ---------------------------------------------------------------------------------------
# (d) id:ad67 -- the Workflow runtime is STRICT (probed), so the wrapper must be strict too.
#     THREE distinct strict-only SyntaxErrors, so a fix that special-cases one construct is
#     caught. Each fixture is otherwise valid and parses fine under a sloppy wrapper --
#     measured against the landed helper, which returns 0 for all three today.
# ---------------------------------------------------------------------------------------
d1="$(write strict_dup_params 'const a = 1;
function f(x, x) { return x; }
const q = await Promise.resolve(f(a, a));
if (q) { return q; }')"
workflow_node_check "$d1" >/dev/null 2>&1 \
  && fail "(d1) a DUPLICATE PARAMETER NAME was ACCEPTED -- id:ad67: the wrapper has no strict directive, so its body is sloppy while the Workflow runtime it models is STRICT (probed 2026-09-08)"
pass "(d1) duplicate parameter names are rejected"

d2="$(write strict_legacy_octal 'const a = 1;
const n = 0755;
const q = await Promise.resolve(n + a);
if (q) { return q; }')"
workflow_node_check "$d2" >/dev/null 2>&1 \
  && fail "(d2) a LEGACY OCTAL literal (0755) was ACCEPTED -- id:ad67: strict-only syntax errors must be caught, and one construct is not enough to prove the wrapper is strict"
pass "(d2) legacy octal literals are rejected"

d3="$(write strict_with_statement 'const a = 1;
with (Math) { const z = PI; }
const q = await Promise.resolve(a);
if (q) { return q; }')"
workflow_node_check "$d3" >/dev/null 2>&1 \
  && fail "(d3) a \`with\` STATEMENT was ACCEPTED -- id:ad67: the third distinct strict-only construct, present so that special-casing duplicate parameters or octal alone cannot pass this spec"
pass "(d3) a with statement is rejected"

# ---------------------------------------------------------------------------------------
# (e) NEGATIVE CONTROL for (d): making the wrapper strict must not redden the ordinary shapes.
#     relay-loop.js's own line-1-export + top-level await + top-level return shape stays green
#     ((a) covers the real file; this covers the minimal form), and so does a plain valid file.
# ---------------------------------------------------------------------------------------
e1="$(write line1_export_shape 'export const meta = { name: "x" };
const q = await Promise.resolve(1);
if (q) { return q; }')"
workflow_node_check "$e1" \
  || fail "(e1) the line-1-export + top-level await + top-level return shape was refused -- that is relay-loop.js's own shape and every hardening change must leave it green"
pass "(e1) relay-loop.js's own minimal shape is still accepted"

echo "OK: tests/test_workflow_check_hardening.sh"
