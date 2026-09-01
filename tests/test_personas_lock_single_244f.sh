#!/usr/bin/env bash
# DEFECT-FIX test for id:244f — deliberately NO `# roadmap:XXXX` header.
# This specs a confirmed defect (both divergent lock files were observed on disk
# 2026-08-13), not an open roadmap item, so it must NEVER be reported EXPECTED-RED:
# its failures always count (CLAUDE.md §Testing).
#
# DEFECT: meeting/append.sh derives SKILL_DIR from `dirname "$0"` — the INVOCATION
# directory — so `dest="$SKILL_DIR/personas.md"` and every write path's
# `9>"${dest}.lock"` name a DIFFERENT lock file depending on how the script was
# reached. Invoked through the install (~/.claude/skills/meeting/append.sh, itself a
# symlink into the checkout) the lock is ~/.claude/skills/meeting/personas.md.lock;
# invoked canonically it is ~/src/dotclaude-skills/meeting/personas.md.lock. But
# personas.md is a per-file SYMLINK, so both $dest paths resolve to ONE underlying
# file while the two flocks are independent — an install-path writer and a repo-path
# writer are NOT mutually excluded. personas.md is `merge=union`, so an interleaved
# write is exactly the unrecoverable case.
#
# CONTRACT asserted here: one underlying file has exactly ONE lock, regardless of the
# invocation path — and holding that lock actually blocks a writer arriving by the
# other path (real serialization, not just a matching filename).
# fails-against: rev bcde33a4d333 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix meeting/append.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: bcde33a4d333 -- meeting/append.sh
# fails-against-assertion: $dest, so an install-path writer and a repo-path writer take DIFFERENT locks and are not mutually excluded (id:244f). Locks found:

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPEND="$ROOT/meeting/append.sh"
[[ -x "$APPEND" ]] || { echo "FAIL: meeting/append.sh not found/executable at $APPEND"; exit 1; }

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"   # hermetic: never touch the real ~/.claude
mkdir -p "$HOME"

# Reproduce the real topology: a canonical checkout dir + an install dir of per-file
# symlinks pointing into it (exactly what `make install-meeting` creates).
CANON="$TMP/canon/meeting"
INST="$TMP/home/.claude/skills/meeting"
mkdir -p "$CANON" "$INST"
cp "$APPEND" "$CANON/append.sh"
cat > "$CANON/personas.md" <<'FIXTURE'
# Ad-hoc persona registry

- 🚚 **Gil** — release engineering. RELEASE-TAG-PUSH-SEMANTICS. Introduced 2026-06-02 (zkm/tags).
FIXTURE
chmod 0644 "$CANON/personas.md"
ln -s "$CANON/append.sh"   "$INST/append.sh"
ln -s "$CANON/personas.md" "$INST/personas.md"

locks() { find "$CANON" "$INST" -maxdepth 1 -name '*.lock' | sort; }

# ── 1. Both invocation paths must lock the SAME file ──────────────────────────────────
# One write through the INSTALL symlink (plain append of a new name) …
bash "$INST/append.sh" -t personas \
  -e "- 🦉 **Nyx** — a genuinely new lens. Introduced 2026-08-13 (dotclaude-skills/locks)." \
  >/dev/null 2>&1 || fail "(1) append.sh failed writing through the install path"
# … and one write through the CANONICAL path (the extend branch).
bash "$CANON/append.sh" -t personas \
  -e "- 🚚 **Gil** — release engineering; now also changelog derivation. Extended 2026-08-13 (dotclaude-skills/locks)." \
  >/dev/null 2>&1 || fail "(1) append.sh failed writing through the canonical path"

n_locks="$(locks | wc -l)"
(( n_locks == 1 )) \
  || fail "(1) $n_locks lock files exist for ONE underlying personas.md — the lock path is derived from the unresolved \$dest, so an install-path writer and a repo-path writer take DIFFERENT locks and are not mutually excluded (id:244f). Locks found:
$(locks)"
pass "(1) exactly one lock file for one underlying registry file across both invocation paths"

# 2. …and it is the one beside the RESOLVED target, not beside the symlink.
want="$(readlink -f -- "$CANON/personas.md").lock"
got="$(locks)"
[[ "$got" == "$want" ]] \
  || fail "(2) the lock is at '$got', expected '$want' — derive it from the resolved target (readlink -f) so one underlying file has one lock (id:244f)"
pass "(2) the lock sits beside the resolved target"

# ── 3. BEHAVIOURAL: holding that lock blocks a writer arriving by the other path ───────
# A matching filename is not the claim; mutual exclusion is. Hold the canonical-side lock
# and prove an install-path append blocks on it rather than sailing straight through.
(
  flock -x 9
  sleep 3
) 9>"$want" &
holder=$!
sleep 0.4

set +e
timeout 1 bash "$INST/append.sh" -t personas \
  -e "- 🐝 **Bea** — a second new lens. Introduced 2026-08-13 (dotclaude-skills/locks)." \
  >/dev/null 2>&1
rc=$?
set -e
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true

(( rc == 124 )) \
  || fail "(3) an install-path append completed (rc=$rc) while the resolved file's lock was HELD — the two invocation paths are not mutually excluded, so two writers can interleave on a merge=union registry (id:244f)"
pass "(3) an install-path writer blocks on the lock held by a canonical-path writer"

# 4. Once the lock is released the write goes through (the fix must not deadlock).
bash "$INST/append.sh" -t personas \
  -e "- 🐝 **Bea** — a second new lens. Introduced 2026-08-13 (dotclaude-skills/locks)." \
  >/dev/null 2>&1 || fail "(4) append.sh failed after the lock was released — the single-lock fix must not deadlock"
grep -q -- '\*\*Bea\*\*' "$CANON/personas.md" \
  || fail "(4) the post-release write never reached the canonical registry (id:244f)"
pass "(4) writes proceed normally once the lock is released"

echo "PASS test_personas_lock_single_244f"
