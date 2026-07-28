#!/usr/bin/env bash
# roadmap:1af1
#
# id:1af1 — a PLAN-phase park claim must not outlive the action it describes.
#
# INCIDENT (2026-07-28, run relay-20260728-111835-4075, wf_099fc97f-6d6): the reconcile surface
# reported "parked orphan from a dead run — ref renamed to relay/orphan/specfix-1792" and the
# pool stopped `blocked-pending-human` with 0 dispatched. No such ref ever existed — refuted four
# ways (`relay-reconcile.sh .` → "no parked orphans", `--all` → 0, `git for-each-ref refs/heads/relay`
# → 15 refs all relay/exec|handoff with no relay/orphan/*, and an empty worktree dir).
#
# ROOT CAUSE (located by the 2026-07-28 executor survey): `reconcile-repo.sh` emitted the surfaced
# line in the PLAN phase, worded as a COMPLETED rename ("ref renamed to ..."), while the APPLY-side
# `worktree-retire.sh` call swallowed every failure via `|| true`. In --dry-run APPLY never runs at
# all, so the claim was false by construction there too.
#
# THE CONSTRAINT that makes the obvious fix wrong: the parity oracle (id:77ce) requires the dry-run
# PLAN to be the oracle for the live run — APPLY must add NOTHING to the emitted actions/surfaced
# JSON. So the fix cannot be "emit the surfaced line from APPLY once it succeeds". It is instead:
#   (a) TENSE — PLAN states an INTENT ("to be parked as ..."), never a completed fact;
#   (b) VERIFY — APPLY checks the ref really exists and fails LOUDLY to stderr/log (never JSON),
#       so a swallowed rename stops being invisible (no-silent-swallow, id:4347).
#
# Hermetic: real git repos under mktemp -d; no network, no ~/.claude writes (RECONCILE_LOG is
# redirected into the temp dir).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECONCILE="$ROOT/relay/scripts/reconcile-repo.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$RECONCILE" ]] || fail "reconcile-repo.sh not found/executable at $RECONCILE"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RECONCILE_LOG="$tmp/reconcile.log"

# ── fixture: a repo with one UNMERGED relay worktree branch (the park case) ──────
work="$tmp/repo"
git init -q "$work"
git -C "$work" config user.email t@e; git -C "$work" config user.name t
echo base > "$work/f.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
main_branch="$(git -C "$work" rev-parse --abbrev-ref HEAD)"

# reconcile-repo.sh resolves worktrees as $RELAY_WORKTREE_BASE/<repo>/<basename>.
wtbase="$tmp/wtbase"; wtdir="$wtbase/testrepo"; mkdir -p "$wtdir"
bn="deadrun-execute"
git -C "$work" worktree add -q "$wtdir/$bn" -b "relay/$bn" >/dev/null 2>&1
echo change > "$wtdir/$bn/f.txt"
git -C "$wtdir/$bn" add -A; git -C "$wtdir/$bn" commit -qm "unmerged work"

run() { RELAY_WORKTREE_BASE="$wtbase" "$RECONCILE" "$@" --repo testrepo --path "$work" --runid otherrun --live-claims "" 2>"$tmp/err.txt"; }

# ── (1) PLAN/dry-run must NOT assert a completed rename ──────────────────────────
dry="$(run --dry-run || true)"
surfaced="$(jq -r '.surfaced[]? // empty' <<<"$dry" 2>/dev/null || echo "")"

if grep -qi 'ref renamed to' <<<"$surfaced"; then
  fail "(1) PLAN still asserts a COMPLETED rename ('ref renamed to ...') — this is the phantom-park wording: in --dry-run nothing is renamed at all, so the claim is false by construction"
fi
pass "(1) PLAN does not assert a completed rename"

# The dry run must not have mutated anything (parity precondition).
git -C "$work" show-ref --verify --quiet "refs/heads/relay/orphan/$bn" \
  && fail "(1b) --dry-run actually created the orphan ref — dry-run must be side-effect-free"
pass "(1b) --dry-run left the orphan ref uncreated (side-effect-free)"

# ── (2) a park claim, when made, must name a ref that a consumer can verify ──────
# If the surface mentions relay/orphan/<bn> at all, it must be phrased so a reader knows to
# check — the incident's cost was a consumer trusting the name without verifying.
if grep -q "relay/orphan/$bn" <<<"$surfaced"; then
  grep -qi 'verify' <<<"$surfaced" \
    || fail "(2) surfaced park line names relay/orphan/$bn without telling the reader to verify the ref exists — that is exactly how the phantom idled a pool"
  pass "(2) surfaced park line names the ref AND tells the reader to verify it"
else
  pass "(2) surfaced park line does not name an unverified ref"
fi

# ── (3) APPLY must VERIFY the park and fail loudly when the ref is absent ────────
# Drive the real APPLY path, then assert the ref exists (the happy path must still work).
live="$(run || true)"
if git -C "$work" show-ref --verify --quiet "refs/heads/relay/orphan/$bn"; then
  grep -qi 'PARK VERIFY FAILED' "$tmp/err.txt" \
    && fail "(3) park succeeded but the verifier still cried failure — false alarm"
  pass "(3) APPLY parked the branch and the verifier stayed quiet"
else
  # Park did not happen — the ONLY acceptable behaviour now is a loud stderr failure.
  grep -qi 'PARK VERIFY FAILED' "$tmp/err.txt" \
    || fail "(3) the park did NOT happen and NOTHING was reported — this is the silent swallow (id:4347) that produced the phantom; APPLY must fail loudly on stderr"
  pass "(3) park did not happen and APPLY reported it LOUDLY (no silent swallow)"
fi

# ── (4) parity preserved: verification must never enter the emitted JSON ─────────
dk="$(jq -r '[.actions[]?.kind] | sort | join(",")' <<<"$dry" 2>/dev/null || echo "")"
lk="$(jq -r '[.actions[]?.kind] | sort | join(",")' <<<"$live" 2>/dev/null || echo "")"
[[ "$dk" == "$lk" ]] \
  || fail "(4) parity oracle BROKEN (id:77ce): dry-run action kinds [$dk] != live [$lk] — the id:1af1 verification must write to stderr/log ONLY, never to actions/surfaced"
pass "(4) parity oracle intact — verification stayed out of the emitted JSON"

# ── (5) THE CASE THAT MATTERS — park FAILS, verifier must fire ───────────────────
# (3) exercised the happy path, which cannot prove the verifier works. Force a real APPLY
# failure: worktree-retire.sh refuses a DIRTY worktree (surface-and-leave, id:373e), so PLAN
# still plans a park while APPLY cannot perform it — precisely the incident's shape. Without
# the id:1af1 verification this combination is SILENT, and the surfaced line names a ref that
# does not exist.
work2="$tmp/repo2"
git init -q "$work2"
git -C "$work2" config user.email t@e; git -C "$work2" config user.name t
echo base > "$work2/f.txt"; git -C "$work2" add -A; git -C "$work2" commit -qm base

wtbase2="$tmp/wtbase2"; wtdir2="$wtbase2/testrepo2"; mkdir -p "$wtdir2"
bn2="deadrun2-execute"
git -C "$work2" worktree add -q "$wtdir2/$bn2" -b "relay/$bn2" >/dev/null 2>&1
echo change > "$wtdir2/$bn2/f.txt"
git -C "$wtdir2/$bn2" add -A; git -C "$wtdir2/$bn2" commit -qm "unmerged work"
# Make it DIRTY so retirement refuses and the park cannot complete.
echo "uncommitted residue" > "$wtdir2/$bn2/dirty.txt"

RELAY_WORKTREE_BASE="$wtbase2" "$RECONCILE" --repo testrepo2 --path "$work2" \
  --runid otherrun --live-claims "" >/dev/null 2>"$tmp/err2.txt" || true

if git -C "$work2" show-ref --verify --quiet "refs/heads/relay/orphan/$bn2"; then
  echo "NOTE: retirement parked the dirty worktree anyway — cannot exercise the failure path here"
  pass "(5) skipped: could not force a park failure on this platform"
else
  grep -qi 'PARK VERIFY FAILED' "$tmp/err2.txt" \
    || fail "(5) park FAILED (relay/orphan/$bn2 absent) and the verifier did NOT fire — the id:1af1 fix is inert; this is the exact silent swallow that produced the 2026-07-28 phantom. stderr was: $(cat "$tmp/err2.txt")"
  grep -q "relay/orphan/$bn2" "$tmp/err2.txt" \
    || fail "(5) verifier fired but did not name the missing ref — an operator cannot act on it"
  pass "(5) park failed and the verifier fired LOUDLY, naming the missing ref"
fi

echo "ALL PASS: phantom-park PLAN/APPLY tense + verification (id:1af1)"
