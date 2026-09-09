#!/usr/bin/env bash
# roadmap:aa5e
#
# Retargeted 2026-09-09 (id:11a4) from the container `id:4839` to its seam `id:aa5e`
# ("Install the head-length and shape-prose baselines via the Makefile … "), which
# is exactly this file's own Done-check. id:4839 is `@container DECOMPOSED into
# seams id:eccb, id:c655, id:aa5e, id:cb9a` and stays open forever by design, so
# keying this spec to it would have granted this test EXPECTED-RED permanently
# even after id:aa5e lands and ticks. id:aa5e is itself still open (unticked), so
# this file remains legitimately red for now -- the retarget changes WHO it is
# swallowed under, not whether it is currently red.
#
# RED SPEC for dimension (a) of id:4839, plus the ORDERING constraint that makes (a) unsafe to
# land on its own.
#
# (a) todo-conformance.sh resolves both baselines relative to itself
# (LENGTH_BASELINE=$SCRIPTS_DIR/../head-length-baseline.txt, SHAPE_BASELINE likewise), the
# files live at relay/head-length-baseline.txt and relay/shape-prose-baseline.txt, and
# relay_FILES in the Makefile declares SKILL.md + references/* + scripts/* and nothing else --
# so `make install` symlinks the script and never the baselines. Measured on this repo's own
# TODO.md, 2026-09-05: the repo path emits 1 ratchet finding, the install path emits 216 plus
# `head-length ratchet INERT -- no baseline` and its shape twin. It fails OPEN, not silent.
# What is lost is the RATCHET SEMANTIC: with no baseline there is no regrowth-versus-
# grandfathered distinction, so 1 genuine regrowth is indistinguishable from 215 forgiven ones
# and id:0d7c's monotonic-shrink guarantee is unavailable to exactly the callers built to
# enforce it -- review.md section 4b and relay-doctor.sh, both of which prescribe the install
# path.
#
# ORDERING IS PART OF THE ACCEPTANCE, NOT A PREFERENCE. Shipping this manifest line while the
# baseline key still has no repo dimension (test_conformance_baseline_repo_key_4839.sh)
# converts an ANNOUNCED INERT into an UNANNOUNCED WRONG on all 46 non-owning repos: every one
# of them would then read OUR baseline rows as if they were their own. Loudly inert everywhere
# beats quietly authoritative. Case (c) below enforces that ordering mechanically so it cannot
# be lost as a note nobody reads.
#
# HERMETICITY: installs into `make DEST_DIR=<mktemp -d>` per CLAUDE.md; never touches
# ~/.claude.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
report() { echo "FAIL: $1"; fail=1; }

DEST="$tmp/skills"
mkdir -p "$DEST"
make -C "$ROOT" DEST_DIR="$DEST" install-relay >"$tmp/install.log" 2>&1 \
  || report "fixture sanity: 'make DEST_DIR=... install-relay' failed; see $tmp/install.log -- every assertion below would be vacuous"

INST="$DEST/relay/scripts/todo-conformance.sh"
[[ -e "$INST" ]] || report "fixture sanity: the script itself is not in the install tree at $INST -- the install did not happen and the assertions below are vacuous"

# (a) Both baseline files must be reachable from the INSTALLED script by its own resolution
# rule ($SCRIPTS_DIR/../<name>). Asserted on the resolved path, not on the manifest text, so
# any correct manifest spelling satisfies it.
for bl in head-length-baseline.txt shape-prose-baseline.txt; do
  if [[ ! -e "$DEST/relay/$bl" ]]; then
    report "(a) relay/$bl is not installed -- the installed todo-conformance.sh resolves it as \$SCRIPTS_DIR/../$bl and finds nothing, so the ratchet is INERT on the path review.md 4b and relay-doctor both prescribe (id:4839 dimension a)"
  fi
done

# (b) The installed script must not announce either ratchet INERT when run on this repo's own
# ledgers. This is the end-to-end statement of (a): a manifest entry that ships a file the
# script cannot actually resolve would satisfy (a) and fail here.
if [[ -e "$INST" ]]; then
  err="$(bash "$INST" "$ROOT/TODO.md" 2>&1 >/dev/null || true)"
  if grep -q 'ratchet INERT' <<<"$err"; then
    report "(b) the INSTALLED todo-conformance.sh still reports a ratchet INERT on $ROOT/TODO.md: $(grep -m2 'ratchet INERT' <<<"$err" | tr '\n' ' ') (id:4839 dimension a)"
  fi

  # (c) ORDERING. The two invocation paths must agree finding-for-finding. Before dimension
  # (b) of id:4839 lands, the install path is INERT (findings differ loudly). AFTER a
  # manifest-only fix -- the exact regression this item exists to prevent -- they would agree
  # here while the same installed script silently applies OUR rows to 46 other repos'
  # ledgers. So this assertion is necessary but NOT sufficient on its own, and it is
  # deliberately paired with test_conformance_baseline_repo_key_4839.sh: neither file may be
  # green while the other is red, which is what makes "the manifest line must not land first"
  # a mechanical constraint rather than a comment.
  repo_n="$(bash "$ROOT/relay/scripts/todo-conformance.sh" "$ROOT/TODO.md" 2>/dev/null | grep -cE 'length-(regrowth|grandfathered|over-budget)|shape-(regrowth|grandfathered|new|prose)' || true)"
  inst_n="$(bash "$INST" "$ROOT/TODO.md" 2>/dev/null | grep -cE 'length-(regrowth|grandfathered|over-budget)|shape-(regrowth|grandfathered|new|prose)' || true)"
  if [[ "$repo_n" != "$inst_n" ]]; then
    report "(c) repo path and install path disagree on $ROOT/TODO.md: repo path reports $repo_n ratchet finding(s), install path reports $inst_n -- the two callers are enforcing different rules (id:4839 dimension a)"
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: both ratchet baselines install, and the installed script agrees with the repo path (id:4839 dimension a)"
fi
exit "$fail"
