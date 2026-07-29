#!/usr/bin/env bash
# roadmap:cbd2
#
# RED SPEC — authored 2026-07-29 (handoff C3, run relay-20260729-133054-23284), NOT
# implemented. EXPECTED-RED while ROADMAP id:cbd2 is unticked. This file is the executable
# specification; do not weaken it to make it pass.
#
# WHY — the install-drift detector cannot fire in its normal invocation.
# `relay-doctor.sh` derives REPO_ROOT from `$(dirname "${BASH_SOURCE[0]}")/../..` WITHOUT
# resolving symlinks. Called through its installed symlink (`~/.claude/skills/relay/scripts/
# relay-doctor.sh` — how `/relay health` and every doc example call it), REPO_ROOT becomes
# `~/.claude/skills`, which has no Makefile, so BOTH manifest-reading checks bail:
#     install-drift (id:1102)        -> "SKIP — Makefile not found under …"
#     reference-install (id:69ef)    -> "SKIP — Makefile or relay/references not found under …"
# Same tree, same second, opposite verdicts from the two invocation paths — verified live
# 2026-07-29 and re-verified while authoring this spec. Cost that day: FOUR undetected
# install-drift instances (fable-config.sh; the pre-commit-lane-vocab.sh ratchet, closed as
# id:9ef7 and never symlinked; diagram-edge-coverage.sh), all found by `make status` or by
# hand — never by the check that exists for exactly this.
#
# WHAT THIS SPEC PINS (the ROADMAP acceptance, one section each):
#   (1) invocation-path INVARIANCE — the installed-symlink path yields the SAME verdict as
#       the source path, for BOTH checks;
#   (2) a deliberately-unlinked manifest entry is reported MISSING through BOTH paths;
#   (3) neither path emits the silent "SKIP — Makefile …" bail;
#   (4) a genuinely unlocatable manifest emits a LOUD WARN, never a silent skip;
#   (5) no crying wolf — a complete tree is clean through BOTH paths.
# (1)+(2)+(5) triangulate: a fix that hard-codes "always clean" fails (2); one that hard-codes
# "always MISSING" fails (5); one that fixes only id:1102 fails the id:69ef half of (1)/(3).
#
# Hermetic: everything under mktemp -d. HOME, RELAY_TOML, SRC_DIR, RELAY_INSTALL_ROOT,
# RELAY_DOCTOR_LOG, RELAY_RECIPE_DIR are all redirected — the real ~/.claude is never read
# for the audited install root and never written. No network.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR_SRC="$ROOT/relay/scripts/relay-doctor.sh"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }
[[ -f "$DOCTOR_SRC" ]] || { echo "FAIL: relay-doctor.sh not found at $DOCTOR_SRC" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- fixture scope repo (so the per-repo checks have something hermetic to read) --------
mkdir -p "$T/repo"
git init -q "$T/repo"
printf '# TODO\n' > "$T/repo/TODO.md"
printf '# Roadmap\n' > "$T/repo/ROADMAP.md"
: > "$T/repo/TODO.archive.md"
printf '[repos.fixture]\nclassification = "own"\npath = "%s/repo"\n' "$T" > "$T/relay.toml"

# --- two synthetic install roots -------------------------------------------------------
# CALLER: the tree we INVOKE the doctor THROUGH (stands in for ~/.claude/skills).
# AUDITED: the tree the doctor INSPECTS via $RELAY_INSTALL_ROOT.
make -s -C "$ROOT" DEST_DIR="$T/caller" install-relay >/dev/null 2>&1 \
  || { echo "FAIL: could not stage the caller install root via 'make DEST_DIR=… install-relay'" >&2; exit 1; }
make -s -C "$ROOT" DEST_DIR="$T/audited" install-relay >/dev/null 2>&1 \
  || { echo "FAIL: could not stage the audited install root" >&2; exit 1; }

DOCTOR_INSTALLED="$T/caller/relay/scripts/relay-doctor.sh"
[[ -L "$DOCTOR_INSTALLED" ]] \
  || note "fixture broken: the staged caller path is not a SYMLINK, so this test would not exercise the symlink-resolution bug at all"

DROPPED="lib-anchored-id.sh"
[[ -e "$T/audited/relay/scripts/$DROPPED" ]] \
  || { echo "FAIL: fixture broken — audited tree lacks $DROPPED, so the drop below is meaningless" >&2; exit 1; }

# run_doctor <doctor-path> <install-root-to-audit> -> stdout+stderr of a full doctor run
run_doctor() {
  HOME="$T/home" \
  RELAY_TOML="$T/relay.toml" \
  SRC_DIR="$T/src" \
  RELAY_INSTALL_ROOT="$2" \
  RELAY_DOCTOR_LOG="$T/doctor.log" \
  RELAY_RECIPE_DIR="$T/recipes" \
  RELAY_DOCTOR_ORPHAN_SCAN="$ROOT/meeting/orphan-scan.sh" \
    timeout 240 "$1" "$T/repo" 2>&1
}

# section <header-substring> <text> — the lines of one "=== <header> ===" block, up to the
# next "=== " header. Substring (not regex) matching, so the ids in the headers are literal.
section() {
  awk -v h="$1" '
    index($0, "=== ") == 1 { inb = (index($0, h) > 0); next }
    inb { print }
  ' <<<"$2"
}

H_DRIFT='install-drift: manifest -> tree (id:1102)'
H_REFS='reference-install completeness (id:69ef)'

# ══ (2)+(3) a manifested-but-absent file must be MISSING through BOTH paths ════════════
rm -- "$T/audited/relay/scripts/$DROPPED"

out_src="$(run_doctor "$DOCTOR_SRC" "$T/audited")"
out_ins="$(run_doctor "$DOCTOR_INSTALLED" "$T/audited")"

for pair in "source:$out_src" "installed:$out_ins"; do
  which="${pair%%:*}"; out="${pair#*:}"
  grep -qF "$DROPPED" <<<"$out" \
    || note "(2/$which) the dropped manifested file '$DROPPED' was NOT reported as install drift through the $which invocation path — this is the whole defect: the detector runs, exits 0, and says nothing"
  grep -qE 'SKIP — Makefile' <<<"$out" \
    && note "(3/$which) the $which invocation still emits a silent 'SKIP — Makefile …' bail; a skip that reads like a clean run is what hid four install-drift instances on 2026-07-29"
done

# ══ (1) invocation-path INVARIANCE — same verdict body from both paths ═════════════════
# Compare the two checks' section bodies with the install-root path (which legitimately
# differs only in that it is echoed) held constant: both runs audit the SAME root, so the
# bodies must be identical text.
for h in "$H_DRIFT" "$H_REFS"; do
  a="$(section "$h" "$out_src")"
  b="$(section "$h" "$out_ins")"
  [[ -n "$a" ]] || note "(1) could not locate the '$h' section in the SOURCE-path run"
  if [[ "$a" != "$b" ]]; then
    note "(1) '$h' gives DIFFERENT verdicts depending on how relay-doctor was invoked — source: [${a//$'\n'/ }] vs installed-symlink: [${b//$'\n'/ }]. Same tree, same second; the only difference is the path"
  fi
done

# ══ (5) no crying wolf — a COMPLETE audited tree is clean through BOTH paths ═══════════
make -s -C "$ROOT" DEST_DIR="$T/audited2" install-relay >/dev/null 2>&1 \
  || { echo "FAIL: could not stage the second audited install root" >&2; exit 1; }
clean_src="$(run_doctor "$DOCTOR_SRC" "$T/audited2")"
clean_ins="$(run_doctor "$DOCTOR_INSTALLED" "$T/audited2")"
for pair in "source:$clean_src" "installed:$clean_ins"; do
  which="${pair%%:*}"; out="${pair#*:}"
  grep -qE '^MISSING:.*(scripts|references)/' <<<"$out" \
    && note "(5/$which) install drift was reported against a FRESHLY installed tree — a check that fires when nothing is wrong trains everyone to ignore it"
  grep -qF 'clean' <<<"$(section "$H_DRIFT" "$out")" \
    || note "(5/$which) the id:1102 section on a complete tree does not report clean through the $which path; got: [$(section "$H_DRIFT" "$out" | tr '\n' ' ')]"
done

# ══ (4) a genuinely unlocatable manifest must WARN LOUDLY, never skip silently ═════════
# A dereferenced copy of the install tree: real files, no Makefile anywhere above them, so
# even correct real-path resolution cannot find a manifest. That is the ONLY case where the
# checks may decline — and it must say so loudly.
mkdir -p "$T/loose"
cp -rL "$T/caller/relay" "$T/loose/relay" 2>/dev/null
DOCTOR_LOOSE="$T/loose/relay/scripts/relay-doctor.sh"
if [[ -x "$DOCTOR_LOOSE" && ! -e "$T/loose/Makefile" ]]; then
  out_loose="$(run_doctor "$DOCTOR_LOOSE" "$T/audited2")"
  for h in "$H_DRIFT" "$H_REFS"; do
    body="$(section "$h" "$out_loose")"
    grep -qE 'WARN' <<<"$body" \
      || note "(4) with the manifest genuinely unlocatable, '$h' must emit a LOUD WARN naming the failure — got: [${body//$'\n'/ }]. 'SKIP' reads identically to 'clean' in the summary, which is exactly how this defect stayed invisible"
  done
else
  note "(4) fixture could not be built (dereferenced copy at $T/loose) — the unlocatable-manifest case went unchecked; fix the fixture rather than dropping the case"
fi

[[ $fail -eq 0 ]] || { echo "EXPECTED-RED: id:cbd2 not built yet" >&2; exit 1; }
echo "ALL PASS: relay-doctor's manifest checks are invocation-path invariant (id:cbd2)"
