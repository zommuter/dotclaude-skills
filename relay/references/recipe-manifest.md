# Recipe manifest — drop-dir contract + schema (id:64d3)

**Single source of truth** for the recipe JSON schema and the `{pending,running,done}/`
drop-dir lifecycle the (gated, not-yet-built) mechanical-run daemon (A3) will consume.
This item (A2, meeting 2026-07-02-1924 decision 3) pins the contract and ships a LOUD
validator so a malformed recipe can never reach the daemon; it does **not** build the
daemon itself and does **not** wire `relay/scripts/inject.sh`.

## The core safety invariant: WHITELISTED, never auto-scanned

Recipes are **whitelisted / relay-authored only**. A recipe reaches `pending/` because
a relay reviewer session (Opus) deliberately wrote it there — the drop-dir itself, not
a tag on a ROADMAP item, is the gate. The daemon (A3) MUST NEVER auto-scan ROADMAP.md,
TODO.md, or any other ledger to invent or infer recipes on its own. This mirrors
devil's-advocate Riku's constraint from the meeting: an automatic scanner that turns
ROADMAP items into executable recipes would let a mis-tagged or adversarial ROADMAP
line silently trigger execution with no human-authored intermediate artifact. The
registry (the set of files relay-authored into `pending/`) is the only trust boundary;
nothing upstream of it is trusted to author a recipe.

## Drop-dir lifecycle

Default location: `~/.config/relay/recipes/{pending,running,done}/` — i.e.
`recipes/pending`, `recipes/running`, `recipes/done` under the recipe root
(env-overridable via `RELAY_RECIPE_DIR`, default `~/.config/relay/recipes`, for
hermetic testing — `recipe-validate.sh` itself doesn't touch the drop-dir, but any
daemon/wrapper built on top of it must honor this override the same way).

- **`drafts/`** (id:8a6b) — auto-DRAFTED recipe SKELETONS land here, NOT in `pending/`. The
  daemon NEVER reads `drafts/`, so a draft is non-executable by construction: an Opus reviewer /
  human must fill its `TODO:` placeholders and deliberately MOVE `drafts/<id>.json → pending/` to
  make it runnable. This is the resolution half of the mechanical-orphan loop (`relay-doctor`
  check-12 / id:1bd1 detects the orphan; `mechanical-orphan-draft.sh` drafts the skeleton). The
  skeleton's `est_wall` is a STRING placeholder, so `recipe-validate.sh` hard-rejects it even if
  copied verbatim into `pending/` — the whitelist trust boundary is doubly preserved.
- **`pending/`** — a relay reviewer session authors a recipe JSON file here (or promotes a
  filled-in `drafts/` skeleton here). This is the ONLY directory anything outside the daemon
  ever writes to, and the ONLY directory the daemon consumes.
- **`running/`** — the (future) daemon moves a recipe here the instant it starts
  executing it, so a crash mid-run leaves an unambiguous "was running" marker instead
  of silently vanishing from `pending/`.
- **`done/`** — the daemon moves the recipe here on completion (success or failure),
  alongside (or pointing at) the `acceptance_artifact` the recipe named.

Only the daemon (A3, not built by this item) performs the `pending → running → done`
moves. `recipe-validate.sh` is a pure validator: given a single recipe file path, it
checks the file against the schema below and exits 0/nonzero — it never lists a
directory or moves anything.

## Recipe JSON schema

Every recipe is a flat JSON object with exactly these 7 fields:

| Field | Type | Notes |
|---|---|---|
| `id` | string | non-empty; the relay item/run id this recipe executes |
| `repo` | string | non-empty; which repo the command runs in |
| `cmd` | string | non-empty; the shell command to execute |
| `host` | string | non-empty; which host the recipe is bound to (mirrors the `[host:<name>]` ROADMAP tag) |
| `est_wall` | integer | **positive** integer seconds; the ADMISSION estimate — see "est_wall estimates, it does not kill" below |
| `resource` | string | non-empty; the `resource:<name>` claim token this recipe should acquire (see `resource-claims.md`) |
| `acceptance_artifact` | string | non-empty; path/pointer to the artifact that proves completion |

### ⚠ THE CAP DOES NOT COVER `resource: local-llm` RECIPES (measured 2026-09-08)

**Read this before trusting the cap for anything that talks to a model server.** The section
below is accurate for a recipe that does its own work in-process. It is **worthless** for one
that delegates to `llama-swap`, and the `local-llm` recipes all delegate.

`ai-codebench judge` is an HTTP **client**. It does not load the model — it asks
`llama-swap` (a *root system service*, `system.slice`) to, and llama-swap's `llama-server`
children live in **its** cgroup, not ours:

    /proc/<llama-server>/cgroup  ->  0::/system.slice/llama-swap.service
    systemctl show llama-swap.service -p MemoryMax -p MemorySwapMax
      MemoryMax=infinity      MemorySwapMax=infinity

So `relay-mech.slice` capped a 378 MB HTTP client while ~17 GiB of model weights loaded
somewhere entirely outside it. Observed live: the owner's machine filled RAM **and** swap and
crawled, while the capped scope reported `MemoryCurrent=396439552`. That 378 MB figure was the
tell and it was misread as "climbing" — a 30B model load is not 378 MB.

Compounding it, the GPU is an **Intel Arc 140V iGPU with SHARED system memory**, so `-ngl 99`
("offload all layers to GPU") does not move the weights off system RAM; it allocates them from
the same 30 GB. The 30B entry also runs `--ctx-size 32768` against 8192 elsewhere.

`llama-swap` v255 has **no memory limits of its own** — its `groups`/`exclusive`/`swap` keys
govern which models may be RESIDENT TOGETHER, not how much they may use. Containing this needs
a lever at the server, not the recipe (a `systemd-run --scope` wrapper inside the model's
`cmd:`, or a `MemoryMax` drop-in on `llama-swap.service`), and both need root. Until one exists,
treat every `resource: local-llm` recipe as **UNCAPPED** and run it only when you can watch it.

### Execution is CAPPED, and `est_wall` estimates — it does not kill (id:c057)

`mechanical-daemon.sh` runs a recipe through **`capped-run.sh`**, not a bare `bash -c`. The
command executes inside a systemd user scope with `MemoryMax` (default 24G, `RELAY_MECH_MEM`),
`MemorySwapMax=0`, `CPUQuota` (default 200%, `RELAY_MECH_CPU`) and a wall-clock ceiling. On a
breach the kernel kills only the processes inside that scope, so the machine stays responsive.
If `systemd-run` is unavailable, `capped-run.sh` **refuses** (exit 3) rather than running
uncapped — a silent fallback would reintroduce the very bug this exists to prevent.

**`est_wall` is an ADMISSION estimate, not a deadline.** It is consumed by
`relay-intensity.sh permits <est_wall> <resource>` to decide whether *now* is a good moment to
start. The kill deadline is a separate, deliberately generous multiple:

    ceiling = max(est_wall * MECH_TIMEOUT_FACTOR, MECH_TIMEOUT_FLOOR)   # default 2x, floor 600s

They are kept distinct on purpose. Reusing `est_wall` directly as the deadline would silently
redefine a field every existing recipe already sets, and a run that merely overran its own
estimate by 10% would be killed having done all the work and written no artifact. Hitting the
ceiling should mean *genuinely stuck*, not *slower than guessed*.

**Failure is classified, not lumped.** A cap kill (137), a ceiling timeout (124) and a
`capped-run` refusal (3) each write a distinct reason into `done/<recipe>.error` and the log,
and the tick's summary line carries a `failed=` count. Before this, a failed recipe incremented
nothing, so `ran=0 deferred=0 rejected=0` read identically to a tick where nothing happened —
a cap kill was invisible in exactly the line a human reads to decide whether to look.

Example:

```json
{
  "id": "7616",
  "repo": "ai-codebench",
  "cmd": "make bench-drain",
  "host": "zomni",
  "est_wall": 3600,
  "resource": "local-llm",
  "acceptance_artifact": "results/latest.json"
}
```

## Validator: `relay/scripts/recipe-validate.sh`

```bash
relay/scripts/recipe-validate.sh <recipe.json>
```

- Exit 0, **silent**, on a well-formed recipe.
- Exit **nonzero** with a LOUD `ERROR: <field> ...` line on stderr naming the FIRST
  offending field, on:
  - any of the 7 keys missing,
  - any string field that is missing, non-string, or empty,
  - `est_wall` missing, non-integer (floats and booleans included), zero, or negative.
- **No silent coercion** — a malformed field is always a loud rejection, never quietly
  fixed up or defaulted (repo-wide no-silent-swallow rule, id:4347).

Built with `python3` stdlib `json` for parsing/typing (never fragile string munging —
the CLAUDE.md JSON gotcha), wrapped in `set -euo pipefail` bash per the repo's script
convention.

## Explicit success/failure marker (acceptance_artifact) — id:fd37

A `[MECHANICAL]` recipe's `cmd` must never leave the `acceptance_artifact` EMPTY on
success. Several common tools (e.g. `tsc`/`pnpm typecheck`) are silent-on-clean — a
plain `cmd` like `pnpm -s typecheck > "$ART" 2>&1` writes nothing to `$ART` when the
run is clean, and an empty artifact is an ambiguous acceptance signal: a reviewer
cannot tell "ran clean" from "never ran / redirect failed". The daemon's own
success/fail branch is exit-code driven and already correct; this doctrine is purely
about the artifact a human or reviewer inspects afterward.

**Requirement:** every recipe `cmd` that redirects into its `acceptance_artifact` must
append an EXPLICIT terminal marker AND preserve the real exit code, so the daemon's
exit-code branch keeps working. The canonical safe pattern (recipe authors should copy
this verbatim, substituting `<repo>`/`<realcmd>`):

```bash
cd <repo> && { <realcmd> > "$ART" 2>&1; rc=$?; echo "MARKER exit=$rc finished=$(date -Is)" >> "$ART"; exit $rc; }
```

This captures the command's real exit status in `rc`, appends an explicit
`exit=$rc` marker line to the `acceptance_artifact` unconditionally (so the artifact
is never empty, success or failure), and re-exits with the preserved `rc` so anything
branching on exit code (the daemon's `.error`-sibling logic) is unaffected.

`relay/scripts/recipe-validate.sh` enforces this as an ADVISORY (non-fatal) check: a
recipe whose `cmd` redirects into `acceptance_artifact` with no `exit=`/`exit $?`-style
marker draws a `WARNING:` on stderr but still exits 0 — the 7-field schema hard-fail
above is unchanged and takes priority. The validator can't parse arbitrary shell, so the
check is deliberately conservative (it only flags the specific footgun above, and never
flags a cmd already carrying the canonical `exit=$rc` marker).

## Context / non-goals

- Mirrors the `acquire-resource.sh` / `resource-claims.md` script+doc idiom already
  used for the `resource:<name>` claim vocabulary.
- Does **not** build the mechanical-run daemon that performs the `pending → running →
  done` moves (A3, gated on this item landing).
- Does **not** wire `relay/scripts/inject.sh`.
- The `resource` field's value should match the shared `resource:<name>` vocabulary in
  `relay/references/resource-claims.md` when the recipe's command needs to serialize
  against a contended physical resource (local-llm, gpu, …).

## Runbook — what makes a dropped recipe actually RUN (proven end-to-end 2026-07-13)

The A3 daemon (`mechanical-daemon.sh` + `.path`/`.service`) is now BUILT and shipped
(the non-goals above predate it). First real intensive run: isochrone id:ac14
(zurich r5-jvm field-gen → `web/fields/zurich-transit.json`). Authoring a valid recipe
into `pending/` is necessary but NOT sufficient — a dropped recipe passes THREE launch
gates before it runs, and failing any one makes the daemon **check-and-defer** (leave it
in `pending/`, log the reason to `~/.claude/logs/mechanical-daemon.log`, run nothing).
The three gates, in order, with the wall each caused on the ac14 first-run:

1. **HOST gate** — `host-gate.sh` must match the recipe's `host` to the current machine
   (exit 3 → `host-mismatch`, left for another host's daemon). No wall for a same-host recipe.
2. **RESOURCE gate** — `resource-probe.sh <resource>` must RECOGNIZE the token AND find no
   competing `resource:<token>` claim. **Wall:** the probe only knew `gpu|ram|cpu|local-llm`;
   a bespoke token (`r5-jvm`/`lean`/`xvfb-electron`) returned exit 2 → `resource-unavailable`
   forever. Fixed 2026-07-13 (commit e980b07): bespoke tokens are now claim-only. If you add a
   NEW `[INTENSIVE - <tok>]` token, add it to resource-probe.sh's allow-list too.
3. **INTENSITY gate** — `relay-intensity.sh permits <est_wall> <resource>` needs an ACTIVE
   permit window (`~/.config/relay/permitted-intensity.json`); a HEAVY resource needs a
   `--heavy`/`--intensive` window (a `--light`/`--afk` window is not enough). **Wall:** with no
   active `/relay --intensive` run, there is NO permit → `intensity-permit-denied` for ANY
   wall size. Grant one by hand: `relay-intensity.sh --intensive` (heavy, 2h) or
   `relay-intensity.sh --for <dur> --heavy`; check with `--status`; clear with `--clear`.

**Trigger + the retry timer (id:8a6b clause d — SHIPPED).** The daemon's `.path` unit
(`PathModified` on `pending/`) only fires when `pending/` changes, so a recipe that
check-and-defers once (a gate failed at that instant) would otherwise sit forever until
`pending/` is next modified. A low-cadence `mechanical-daemon.timer` (`tools/mechanical-daemon.timer`,
30 min, sharing the same `mechanical-daemon.service` oneshot) now fires a periodic tick so a
deferred recipe retries on its own after a gate clears — no manual nudge. Install both together
via `make install-mechanical-daemon` (path trigger + retry timer). To force an immediate re-fire
you can still `touch ~/.config/relay/recipes/pending/<recipe>.json`.

**Auto-draft + surfacing (id:8a6b clauses a+b — SHIPPED).** `mechanical-orphan-draft.sh` turns
every `relay-doctor` check-12 orphan into a `drafts/<id>.json` skeleton (id/repo prefilled; host
from `[host:<name>]`; resource from `[INTENSIVE - <res>]`; cmd/est_wall/acceptance_artifact as
`TODO:` placeholders), idempotently. `mechanical-orphan-scan.sh` (read-only) is the shared
collector. Both orphans and un-promoted drafts are LOUD-surfaced in `RELAY_STATUS.md` (the
"## Mechanical orphans / drafts" section, rendered by `relay-status-publish.sh`) and in
`gather-human-backlog.sh` (kinds `mechanical_orphan` / `mechanical_draft`), so `/relay human`
shows them and they never rot silently.

**On success:** the recipe moves `pending → running → done/`, its `acceptance_artifact` is
written, and the daemon auto-injects a `review` unit (`inject.sh add <repo> --item <id>
--verdict review …`) so the next pool run verifies the artifact and can tick the ROADMAP item.
A failing `cmd` still lands in `done/` (with a sibling `.error`) but injects NO review.
