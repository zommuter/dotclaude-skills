# Strong-model audit — Run 70 (2026-08-11-2039)

**Item:** ROADMAP id:401c (recurring `[HARD]` strong-model audit), dispatched as an
Opus-apex HARD-execute child (run `relay-20260811-144639-28608`, model `claude-opus-4-8`).

**Headline finding (the reason this note exists):** the recurring audit has been
**STARVED for ~6 weeks** and did not know it. The mechanical audit watermark
(`relay.toml [repos.dotclaude-skills] last_strong_ckpt`) reads `relay-ckpt-20260811-2032`,
which is **HEAD** — so `git rev-list last_strong_ckpt..HEAD` is **0 commits** and
`gather-repo-state.sh`'s `substantive_unaudited` (id:365b) would report "nothing new to
audit". But the last **actual** id:401c audit note is **Run 69 (2026-06-30-1855**,
`docs/meeting-notes/2026-06-30-1855-strong-model-audit.md`, window ending at `7527cb1`).
The true id:401c window is `7527cb1..HEAD` = **1709 commits (1198 non-ledger)**. The
watermark is falsely pinned at HEAD because a **strong-EXECUTE** checkpoint advances it —
see finding **F1 (id:da95)** below, which is the primary deliverable of this run.

Because the true window (1709 commits) is far too large to audit soundly in one turn, this
run does **not** claim to have re-reviewed it. It does two things honestly:
1. **F1** — root-causes and files the watermark-starvation mechanism defect (the finding
   that explains the empty window); recommended fix quoted, **not applied inline** (rationale
   below).
2. A **bounded representative code+security pass** over the newest still-unwired engine
   surface — the id:1f4f in-repo-parallelism wave scripts (`provision-worktree.sh`,
   `disjoint-greenlight.sh`, `drain-integrate.sh`) — yielding **F2 (id:ac8a)**.

Windows before Run 70 are NOT retroactively certified by this note. A future reviewer/owner
who wants the 6-week gap genuinely audited must do so against a corrected watermark (post-F1)
and will likely need to hard-split it.

---

## F1 — a strong-EXECUTE checkpoint advances `last_strong_ckpt`, self-suppressing id:401c  [CONFIRMED · design-coherence · HIGH]  <!-- id:da95 -->

**Mechanism.** `relay/scripts/ckpt-tag.sh` (the checkpoint choke-point, id:0a3b) advances
the strong-audit watermark when the checkpoint label carries a full `claude-*` model id and
the model is not sonnet/haiku. id:ecce added ONE role-prefix carve-out *before* model
detection so an **integrate** checkpoint never advances it:

```sh
if [[ "$label" == integrate* ]]; then
  echo "... label '$label' is a non-strong role (integrate) — strong-watermark sync skipped ..." >&2
else
  model="$(grep -oE 'claude-[a-z0-9.-]+' <<<"$label" | head -n1 || true)"
  if [[ -z "$model" ]]; then
    if [[ "$label" == executor* || "$label" == reconcile* ]]; then
      # non-strong role — skip (note)
    else
      # WARNING: no claude-* id — skip
    fi
  elif [[ "$model" == *sonnet* || "$model" == *haiku* ]]; then
    # weak model — skip (note)
  else
    "$sw" toml-set "$name" last_strong_ckpt "\"$tag\""   # <-- ADVANCES
    "$sw" toml-set "$name" strong_model "\"$model\""
  fi
fi
```

The current HEAD checkpoint (`relay-ckpt-20260811-2032`) has label
`strong-execute (claude-opus-4-8, fable-standin, relay-loop)`. It is **not** `integrate*`,
it **does** carry a full `claude-*` id, and the model is not sonnet/haiku — so it falls
straight into the `else` branch and **advances `last_strong_ckpt` to HEAD**. Confirmed
end-to-end: `relay.toml` now reads `last_strong_ckpt = "relay-ckpt-20260811-2032"`,
`strong_model = "claude-opus-4-8"`.

**Why that is wrong.** A `strong-execute` child (an Opus-apex HARD-execute unit, id:da26 —
*this* unit) does red-green-refactor on **one** ROADMAP item and verifies **its own** work.
It performs **no** test-integrity audit, **no** spec-drift check, **no** roadmap
re-derivation, and **no** cross-cutting design-coherence review of the rest of the window —
i.e. none of the things advancing the strong-audit watermark is meant to certify. Advancing
`last_strong_ckpt` for it "would mark unreviewed work AUDITED" — verbatim the hazard the
id:ecce comment names for `integrate`. The code's own comment even lists the correct
verdict: *"Anything else (reviewer / strong-execute / unknown) IS a defect: warn and name
it."* — but that sentence lives only in the **model-LESS** branch. A `strong-execute` label
**with** a full `claude-*` id (which is exactly what the pool emits) never reaches that
branch. **The id:ecce fix closed the integrate hole and left the strong-execute hole open.**

**Impact (observed, not hypothetical).** The last real id:401c audit was **Run 69,
2026-06-30**. Every strong-execute (and every strong reviewer close) since has re-pinned
`last_strong_ckpt` to HEAD, so id:401c's window has read ~0 continuously and the recurring
audit has not fired for **~6 weeks / 1709 commits**. The ROADMAP id:401c "Run log" is
itself stale (stops at Run 4) — a secondary symptom of the same starvation, since no audit
ran to append to it. This defeats the entire purpose of the recurring pass: the one
mechanism meant to catch cross-cutting coherence drift is silently disabled by ordinary pool
execution.

**Recommended fix (for reviewer/owner ratification — NOT applied here).** Extend the
role-prefix carve-out so it also skips `strong-execute*` (and, defensively, any strong role
that is not an actual audit — the safe framing is an **allowlist**: only `reviewer*`
advances the strong-audit watermark; every other prefix skips). This mirrors the id:c500
ratification that made `reconcile` non-strong. Concretely, change the `integrate*` guard to
something like:

```sh
# Only a reviewer AUDIT advances the strong-audit watermark. Execute/integrate/reconcile
# are strong-MODEL work but not strong-AUDIT — advancing for them marks unreviewed work
# AUDITED (id:ecce for integrate; id:da95 extends it to strong-execute).
if [[ "$label" != reviewer* ]]; then
  echo "... label '$label' is a non-audit role — strong-watermark sync skipped ..." >&2
else
  ... existing model detection / advance ...
fi
```

**Why NOT fixed inline in this run (deliberate).** (a) This is a fleet-wide watermark-
semantics change (it changes when id:401c fires for *every* managed repo) — a consequential
mechanism decision that is the owner's to ratify, exactly as id:c500 ratified the reconcile
case; a delegated agent's verdict is a recommendation, not a settled decision. (b) There is
a self-certification trap: I am a `strong-execute` child, so under the *current* buggy logic
my own checkpoint would advance `last_strong_ckpt` and mark my unreviewed edit to
`ckpt-tag.sh` AUDITED — precisely the anti-pattern F1 describes. Filing it (finding quoted,
fix drafted) for a reviewer to land under review discipline is the correct in-contract
action. A red-green test belongs with the fix (plant a `strong-execute (claude-opus-4-8)`
label → assert `last_strong_ckpt` unchanged; keep the existing `reviewer (claude-*)` →
advances assertion green).

Filed as TODO id:da95 (see TODO.md).

---

## F2 — disjoint-greenlight treats paths as opaque strings → fail-OPEN on subpath overlaps  [PLAUSIBLE · correctness · MEDIUM]  <!-- id:ac8a -->

**Where.** `relay/scripts/disjoint-greenlight.sh` (`plan` and `merge-check`, id:5367) and
its consumer `relay/scripts/drain-integrate.sh` (merge-time re-enforcement, id:2062). Both
are built-but-**unwired** today (id:ae08 is the wiring child), so this is a latent gap to
resolve *before* they go live, not an active incident.

**Claim.** The disjointness test is exact-string equality on declared/touched paths:
`plan` keys a `declare -A seen` on each path token and calls overlap only on an exact
repeat (`disjoint-greenlight.sh:74`); `merge-check` keys `declare -A merged_paths` and
intersects by exact line (`:113`,`:119`). So two units whose file-sets are
`{"relay/scripts/"}` and `{"relay/scripts/relay-loop.js"}` — or `{"a/b"}` and `{"a/b/c"}` —
are judged **disjoint** and greenlit "concurrent", even though the first (a directory)
contains the second. For a guard the header explicitly advertises as **"FAIL-CLOSED"**,
subpath/prefix containment is a **fail-OPEN** hole: two concurrent units editing under the
same directory can be greenlit, and the same string-equality limitation propagates into
`drain-integrate.sh`'s merge-time re-enforcement (it delegates to the same `merge-check`),
so the "second line of defense" shares the blind spot.

**Severity is bounded by an unverified premise** (hence PLAUSIBLE, not CONFIRMED): the hole
only bites if a declared/touched **file-set can contain a directory path** (or if
`git diff --name-only` output for one unit can be a prefix of another's — which for plain
file paths it cannot, since `--name-only` emits leaf files). `plan` consumes each seam's
declared `file:` field; whether those are constrained to leaf files or may be directories is
the open question. If the contract already guarantees leaf-file-only declared sets, F2 is a
no-op and should be closed as accepted-with-rationale — but that guarantee is **not asserted
anywhere in the two scripts**, so today it is unverified tribal knowledge.

**Recommended resolution (decide when id:ae08 wires these).** Either (a) document +
**enforce** a leaf-file-only contract on declared/touched sets (reject a declared path that
is a directory or lacks an extension-bearing leaf — fail-closed on the ambiguous case), or
(b) make the disjointness check containment-aware (normalize each set to path prefixes and
treat `a/b` vs `a/b/c` as overlapping). (a) is the smaller, more fail-closed change and fits
the existing "declared file-set per seam" model; (b) is more permissive but needs the
normalization to itself be fail-closed. This is a small design call for the id:ae08
executor/reviewer, not an autonomous rewrite.

Filed as TODO id:ac8a (see TODO.md), noted as gated-on/resolve-with id:ae08.

---

## Pass notes (bounded representative surface only)

- **Pass 1 — code review** of the id:1f4f wave scripts:
  - `provision-worktree.sh` (id:34b7) — CLEAN. `git worktree add` + best-effort
    `ln -s node_modules/.venv` with `|| true` guards; single-target, no globbing. One
    **accepted** nit: it symlinks `node_modules`/`.venv` INTO the child worktree pointing
    back at the main checkout, a mild tension with the header's "no means to reach into
    [main]" framing — but these are gitignored build artifacts (children removed the symlink
    before commit historically), low blast radius. No action.
  - `drain-integrate.sh` (id:2062) — CLEAN otherwise: `--no-ff`, no force/destructive flags,
    fail-closed on merge-base/diff failure, clean `merge --abort` on conflict (exit 5),
    overlap handback (exit 4) with no merge attempted, `mktemp`+`trap rm` for the touched
    file. Its only weakness is the inherited F2 string-equality limitation.
  - `disjoint-greenlight.sh` (id:5367) — logic is otherwise correct and fail-closed on
    `<2` units / empty sets / malformed input; F2 is its one gap.
- **Pass 2 — security** (injection / path / secrets) over the same surface: no command-,
  path-, or jq-injection found; inputs are positional args and stdin TSV from the trusted
  relay parent; no secrets touched; git invocations are `-C`-scoped with quoted vars. The F2
  subpath issue is a **safety-guarantee** gap, not an injection vector.
- **Pass 3 — design coherence**: F1 is the coherence finding (a half-closed carve-out that
  silently disables a recurring safety pass). No other contradiction surfaced within the
  bounded surface; the broader 6-week window was **not** coherence-audited (see headline).

## Disposition

- id:da95 (F1) — **tracked**, TODO.md; fix drafted, deferred to reviewer/owner (mechanism +
  self-certification trap). No finding dropped.
- id:ac8a (F2) — **tracked**, TODO.md; resolve alongside id:ae08 wiring.
- provision-worktree symlink-into-main nit — **accepted** with rationale (above).

Checkbox for id:401c is **left unticked** (recurring item, stays open by design); a Run 70
line is appended to its ROADMAP Run log. `RELAY_LOG.md` carries the session self-report.
