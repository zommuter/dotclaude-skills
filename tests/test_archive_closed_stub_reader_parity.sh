#!/usr/bin/env bash
# DEFECT-FIX test — no `# roadmap:XXXX` header on purpose (id:046a part (2) is an
# open item, but this covers a CORRECTNESS defect found while diagnosing it, not the
# item's acceptance). Failures here always count.
#
# `archive-closed.sh`'s STUB_LINE_RE was a divergent copy of `roadmap-archive.sh:111`
# that had DROPPED the load-bearing `.*` between the `<!-- id:XXXX -->` marker and the
# ratified " (archived — see ROADMAP.archive.md)" suffix. The `.*` is documented
# in-file on the sibling as load-bearing (cartulary 2026-08-14, routed:4a12): a ledger
# line routinely carries prose AFTER its own id marker — `/relay human` and `/meeting`
# write-backs append rationale there, and some lines end in a DIFFERENT HTML comment.
#
# Without the `.*` every such stub read as un-stubbed and was RE-ARCHIVED on every
# run: another full body appended to ROADMAP.archive.md and another suffix appended to
# the live line, WITHOUT BOUND. Measured 2026-08-26 across the 6 own repos: 24 stubs
# re-archived in a single run (loderite 14, dotclaude-skills 5, yinyang-puzzle 4,
# linguistic-universals 1), duplicating 16 ids into loderite's ROADMAP.archive.md.
#
# The pre-existing tests missed it because their fixture stubs all put the id marker
# at END of line, which the broken regex still matched.
#
# Part A  — LEGACY stub-reader parity: each stub shape survives untouched, only the
#           genuine closed item is archived, and repeated runs are stable.
#
# id:2eba (2026-09-03) stopped both archivers WRITING the stub, and re-based the
# idempotency test on ARCHIVE MEMBERSHIP (lib-archive-idempotency.py). The five stub
# shapes below are LEGACY — no writer emits them any more, but they exist in this repo
# and across the fleet, so the read half must still recognise them. That is exactly what
# Part A pins, unchanged, and it is why the legacy regex was kept rather than deleted.
# The one assertion that flipped is A1's second clause: the genuine item id:6666 now
# leaves NO stub behind.
# Part B  — safety regressions that must hold ACROSS an archive run:
#           B1 twin-open protection still refuses to archive
#           B2 resolve-gates.sh output byte-identical before vs after
#           B3 orphan-scan --cross-ledger clean before AND after
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/archive-closed.sh"
RG="$ROOT/relay/scripts/resolve-gates.sh"
OS="$ROOT/meeting/orphan-scan.sh"

[[ -f "$SCRIPT" ]] || { echo "FAIL: archive-closed.sh missing at $SCRIPT"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

SUF=" (archived — see ROADMAP.archive.md)"

# ===========================================================================
# Part A — stub-reader parity
# ===========================================================================
repo="$tmp/A"; mkdir -p "$repo"

# Five stub shapes, all of which a prior run legitimately produced, plus one
# genuine (never-archived) closed item that MUST still be swept.
cat > "$repo/ROADMAP.md" <<EOF
# ROADMAP

## Queue
- [ ] open item stays put <!-- id:0001 -->
- [x] prose after the id marker <!-- id:1111 --> rationale appended by a later write-back${SUF}
- [x] trailing non-id comment <!-- id:2222 --> tail <!-- 2222-decision-gate: review 2026-08-18 -->${SUF}
- [x] annotation PAST the suffix <!-- id:3333 -->${SUF} **⚠ still needs an owner look**
- [x] already doubly damaged <!-- id:4444 --> tail${SUF}${SUF}
- [x] plain stub, id at end <!-- id:5555 -->${SUF}
- [x] genuine closed item never yet archived <!-- id:6666 -->
EOF
printf '# TODO\n\n## Current\n- [ ] unrelated open item <!-- id:0002 -->\n' > "$repo/TODO.md"

# Snapshot every stub line verbatim; each must come back byte-identical.
declare -A BEFORE_LINE
for id in 1111 2222 3333 4444 5555; do
  BEFORE_LINE[$id]="$(grep -F "<!-- id:$id -->" "$repo/ROADMAP.md")"
done

out="$(HOME="$tmp" bash "$SCRIPT" "$repo" 2>&1)" || { echo "FAIL: run exited non-zero"; echo "$out"; exit 1; }

RS="$repo/ROADMAP.md"; RA="$repo/ROADMAP.archive.md"
[[ -f "$RA" ]] || { echo "FAIL: ROADMAP.archive.md not created — fixture unreached"; echo "$out"; exit 1; }

# A1 — the genuine item WAS archived. Guards against an inert fixture: if this
#      fails, every assertion below is vacuous.
grep -qF 'genuine closed item never yet archived' "$RA" \
  || { echo "FAIL(A1): genuine item id:6666 was not archived — fixture is inert"; cat "$RA"; exit 1; }
grep -qF "<!-- id:6666 -->" "$RS" \
  && { echo "FAIL(A1): id:6666 was left in the live ledger — id:2eba leaves no stub"; cat "$RS"; exit 1; }

# A2 — every pre-existing stub line is byte-identical: not re-archived, and in
#      particular NO second suffix appended.
for id in 1111 2222 3333 4444 5555; do
  now="$(grep -F "<!-- id:$id -->" "$RS" || true)"
  [[ -n "$now" ]] || { echo "FAIL(A2): stub id:$id vanished from the live ledger"; exit 1; }
  [[ "$now" == "${BEFORE_LINE[$id]}" ]] || {
    echo "FAIL(A2): stub id:$id was rewritten (re-archived)"
    echo "  before: ${BEFORE_LINE[$id]}"
    echo "  after : $now"; exit 1; }
done

# A3 — no stub body was copied into the archive. Only id:6666 belongs there.
for id in 1111 2222 3333 4444 5555; do
  grep -qF "<!-- id:$id -->" "$RA" \
    && { echo "FAIL(A3): stub id:$id was re-archived into ROADMAP.archive.md"; exit 1; }
done

# A4 — no line ever carries the suffix twice as a RESULT of this run. (id:4444
#      arrives already damaged and must simply be left alone, not damaged further.)
trip="$(grep -cF "${SUF}${SUF}${SUF}" "$RS" || true)"
[[ "$trip" == "0" ]] || { echo "FAIL(A4): a third suffix was appended to a damaged line"; exit 1; }

# A5 — stability under repetition: two further runs change nothing at all.
snap_s="$(cat "$RS")"; snap_a="$(cat "$RA")"
for n in 2 3; do
  HOME="$tmp" bash "$SCRIPT" "$repo" >/dev/null 2>&1 || { echo "FAIL(A5): run $n exited non-zero"; exit 1; }
  [[ "$(cat "$RS")" == "$snap_s" ]] || { echo "FAIL(A5): run $n mutated ROADMAP.md"; head -10 < <(diff <(echo "$snap_s") "$RS"); exit 1; }
  [[ "$(cat "$RA")" == "$snap_a" ]] || { echo "FAIL(A5): run $n grew ROADMAP.archive.md"; head -10 < <(diff <(echo "$snap_a") "$RA"); exit 1; }
done

# ===========================================================================
# Part B — safety regressions across an archive run
# ===========================================================================
repo2="$tmp/B"; mkdir -p "$repo2"

# id:7001 is closed in ROADMAP but its TODO twin is still OPEN → must NOT archive.
# id:7002 is closed in both → archivable, AND it is a gate target of open id:7003,
# so archiving it exercises the ROADMAP.archive.md leg of resolve-gates.sh's
# four-file resolution map (resolve-gates.sh:42-43 — verified at the CALL SITE, not
# from lib-typed-edges.sh's header prose, which describes a different consumer).
# id:7004 is an open item gated on a still-open target → a stable block=1 row.
cat > "$repo2/ROADMAP.md" <<'EOF'
# ROADMAP

## Queue
- [ ] open gated on the archived target <!-- gated-on:7002 --> <!-- id:7003 -->
- [ ] open gated on a still-open target <!-- gated-on:7005 --> <!-- id:7004 -->
- [ ] the still-open gate target <!-- id:7005 -->
- [x] closed here but TODO twin is open <!-- id:7001 -->
- [x] closed in both ledgers, and a gate target <!-- id:7002 -->
EOF
cat > "$repo2/TODO.md" <<'EOF'
# TODO

## Current
- [ ] still open over here <!-- id:7001 -->
- [x] closed over here too <!-- id:7002 -->
EOF

rg_before="$("$RG" "$repo2" 2>/dev/null)"; rg_before_rc=$?
os_before="$(bash "$OS" --cross-ledger "$repo2" 2>&1)" || true

# B0 — the before-side must be LIVE: resolve-gates must actually emit rows here,
#      otherwise "identical" is two empty strings and proves nothing.
[[ -n "$rg_before" ]] || { echo "FAIL(B0): resolve-gates emitted nothing before archiving — unreached fixture"; exit 1; }
grep -q '7004' <<<"$rg_before" || { echo "FAIL(B0): expected a block row for id:7004"; echo "$rg_before"; exit 1; }

out2="$(HOME="$tmp" bash "$SCRIPT" "$repo2" 2>&1)" || { echo "FAIL: run on repo2 exited non-zero"; echo "$out2"; exit 1; }

# B0b — and the archiver must have actually moved id:7002 out of ROADMAP.md.
grep -qF '<!-- id:7002 -->' "$repo2/ROADMAP.archive.md" 2>/dev/null \
  || { echo "FAIL(B0b): id:7002 was not archived — safety comparison would be vacuous"; echo "$out2"; exit 1; }

# B1 — twin-open protection: id:7001 stays in BOTH ledgers, archived from neither.
grep -qF 'closed here but TODO twin is open' "$repo2/ROADMAP.md" \
  || { echo "FAIL(B1): twin-open item id:7001 was archived out of ROADMAP.md"; exit 1; }
if [[ -f "$repo2/ROADMAP.archive.md" ]]; then
  grep -qF 'closed here but TODO twin is open' "$repo2/ROADMAP.archive.md" \
    && { echo "FAIL(B1): twin-open item id:7001 leaked into the archive"; exit 1; }
fi
grep -qF 'still open over here' "$repo2/TODO.md" \
  || { echo "FAIL(B1): id:7001's open TODO twin was removed"; exit 1; }

# B2 — resolve-gates.sh output BYTE-IDENTICAL before vs after. Archiving a gate
#      target out of the live ROADMAP must not change gate resolution.
rg_after="$("$RG" "$repo2" 2>/dev/null)"; rg_after_rc=$?
[[ "$rg_before" == "$rg_after" ]] || {
  echo "FAIL(B2): resolve-gates output changed across archiving"
  head -20 < <(diff <(echo "$rg_before") <(echo "$rg_after")); exit 1; }
[[ "$rg_before_rc" == "$rg_after_rc" ]] \
  || { echo "FAIL(B2): resolve-gates exit code changed ($rg_before_rc -> $rg_after_rc)"; exit 1; }

# B3 — orphan-scan --cross-ledger output identical before vs after.
#      id:7001 is DELIBERATELY in drift here (ROADMAP [x] / TODO [ ]) — that is the
#      exact state the twin-open rule exists to keep VISIBLE. So the property is not
#      "clean", it is "unchanged, and the drift is still reported": archiving must
#      never SILENCE a drift by sweeping one side of it into an archive orphan-scan
#      does not read. A `grep -q clean` here would have passed vacuously.
os_after="$(bash "$OS" --cross-ledger "$repo2" 2>&1)" || true
[[ "$os_before" == "$os_after" ]] || {
  echo "FAIL(B3): orphan-scan --cross-ledger output changed across archiving"
  head -20 < <(diff <(echo "$os_before") <(echo "$os_after")); exit 1; }
grep -q '7001' <<<"$os_before" \
  || { echo "FAIL(B3): fixture unreached — expected id:7001 drift to be reported BEFORE archiving"; echo "$os_before"; exit 1; }
grep -q '7001' <<<"$os_after" \
  || { echo "FAIL(B3): archiving HID the id:7001 cross-ledger drift"; echo "$os_after"; exit 1; }
# and archiving a properly-closed twin (id:7002) must not INVENT new drift.
grep -q '7002' <<<"$os_after" \
  && { echo "FAIL(B3): archiving id:7002 introduced spurious cross-ledger drift"; echo "$os_after"; exit 1; }

echo ok
