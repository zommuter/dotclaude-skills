#!/usr/bin/env bash
# roadmap:1102 — relay-doctor must detect INSTALL DRIFT: a file that IS in the Makefile
# manifest but is NOT present in the live install tree.
#
# INCIDENT (2026-07-17, verified): `roadmap-lint.sh` sources `lib-anchored-id.sh`. The
# latter was added to the repo at 10:51 AND correctly listed in `relay_FILES` — but
# `make install` was never re-run, so the installed tree at ~/.claude/skills/relay/scripts/
# had 62 of 64 declared scripts. Running the lint from the installed path died with
# `No such file or directory`, costing a loderite session a broken lint and a false
# "relay-machinery bug" diagnosis. Also missing: `handback-summary.mjs`.
#
# WHY THE EXISTING GUARD MISSED IT — this test's whole reason to exist:
# `test_relay_refs_install_complete.sh` (roadmap:69ef) checks repo -> manifest ("is every
# reference doc DECLARED?"). It cannot catch this: lib-anchored-id.sh WAS declared. The
# unchecked direction is manifest -> tree ("is every DECLARED file actually INSTALLED?").
# id:69ef also only covers `references/*.md`, never `scripts/*`. Both gaps are this item.
#
# WHY THIS LIVES IN relay-doctor AND NOT IN tests/ AS A DIRECT CHECK:
# CLAUDE.md §Testing requires tests be hermetic and never touch ~/.claude. A suite test
# therefore CANNOT read the real install tree — so the drift check must inspect the LIVE
# environment, which is relay-doctor's remit (`/relay health`, id:9bec), not the suite's.
# This test asserts the CHECK EXISTS and BEHAVES, by driving relay-doctor against a
# synthetic install root — never against the real ~/.claude.
#
# RED until id:1102 lands. Hermetic: mktemp -d only; asserts it never reads real $HOME.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR="$ROOT/relay/scripts/relay-doctor.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$DOCTOR" ]] || fail "relay-doctor.sh not found at $DOCTOR"

# --- the check must exist and be discoverable by its id -------------------------------
grep -q 'id:1102' "$DOCTOR" \
  || fail "relay-doctor.sh has no install-drift check tagged id:1102 — the detector exists (make status) but nothing routine invokes it; that is the whole item"
pass "relay-doctor.sh carries an id:1102 install-drift check"

grep -qiE 'install.drift|drift.*install' "$DOCTOR" \
  || fail "relay-doctor.sh's id:1102 check must be identifiable as an install-drift check (a section heading naming it)"
pass "the check is identifiable as install-drift"

# --- it must be INJECTABLE, so it can be tested without touching the real ~/.claude ----
# The check must take its install root from an env var (not a hardcoded ~/.claude), or it
# is untestable by construction and this test cannot be hermetic.
grep -qE 'RELAY_INSTALL_ROOT|INSTALL_ROOT|DEST_DIR' "$DOCTOR" \
  || fail "the id:1102 check must read its install root from an injectable var (e.g. \$RELAY_INSTALL_ROOT) — a hardcoded ~/.claude is untestable and would force this test to touch the real install tree, which CLAUDE.md §Testing forbids"
pass "the check's install root is injectable"

# --- behaviour: a synthetic install root missing a manifested file MUST be flagged -----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
INSTALL="$TMP/install"
if ! make -s -C "$ROOT" DEST_DIR="$INSTALL" install-relay >/dev/null 2>&1; then
  fail "could not stage a synthetic install root via 'make DEST_DIR=... install-relay'"
fi
[[ -e "$INSTALL/relay/scripts/lib-anchored-id.sh" ]] \
  || fail "fixture broken: staged install root lacks lib-anchored-id.sh, so the drop below would be meaningless"

# Reproduce the exact incident: a manifested file absent from the tree.
rm -- "$INSTALL/relay/scripts/lib-anchored-id.sh"

out="$(RELAY_INSTALL_ROOT="$INSTALL" "$DOCTOR" 2>&1)"
grep -q 'lib-anchored-id.sh' <<<"$out" \
  || fail "relay-doctor did not report the dropped manifested file (lib-anchored-id.sh) as install drift — this is the exact 2026-07-17 incident and it must not pass silently; got: $(head -c 400 <<<"$out")"
pass "drift on a manifested-but-absent file is reported, naming the file"

# --- and a COMPLETE tree must be clean — the guard must not cry wolf -------------------
INSTALL2="$TMP/install2"
make -s -C "$ROOT" DEST_DIR="$INSTALL2" install-relay >/dev/null 2>&1 \
  || fail "could not stage the second synthetic install root"
out2="$(RELAY_INSTALL_ROOT="$INSTALL2" "$DOCTOR" 2>&1)"
if grep -qE '^MISSING:.*(scripts|references)/' <<<"$out2"; then
  fail "relay-doctor reported install drift against a FRESHLY installed tree — a check that fires when nothing is wrong trains everyone to ignore it; got: $(grep -E '^MISSING:' <<<"$out2" | head -3)"
fi
pass "a freshly-installed tree reports no install drift"

# --- the deprecated-skill carve-out (mandatory: it fires on day one otherwise) ---------
# `make status` legitimately reports `meeting-cross: SKILL.md (not installed)` because that
# alias skill is DELIBERATELY uninstalled pending deletion (id:4f5f). A drift check that
# counts it is wrong on day one. Assert the carve-out is a conscious, on-record decision.
grep -qiE 'meeting-cross|4f5f|deprecat' "$DOCTOR" \
  || fail "the id:1102 check must explicitly account for deliberately-uninstalled deprecated skills (meeting-cross / id:4f5f) — otherwise it reports a false MISSING on every run and gets ignored"
pass "the deprecated-skill carve-out is on record"

echo "ALL PASS"
