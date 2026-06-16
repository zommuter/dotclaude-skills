# SEED — Distributed relay orchestrator (multi-machine, dynamic membership)

> **Status: SEED, not a decision.** This is a pre-meeting design brief to give a
> future `/meeting` a strong starting point. Tracked as ROADMAP id:de4e
> (`[HARD — strong model]`, decision-gate → `/meeting`). Captured 2026-06-16 from a
> working session; do NOT implement before the meeting ratifies a substrate.

## Problem

Today's relay is single-host. Two gaps motivate this:

1. **Cross-machine races.** Leases (`claim.sh`) and `relay.toml` live in a *plain
   local* `~/.config/fables-turn/` and are arbitrated by **`flock` on a local lock
   file** — a single-host primitive. If `/relay` runs on zomni AND fievel against
   overlapping repos (same origin), there is **no cross-machine mutual exclusion**:
   both fully claim+work the same repo (a whole redundant Opus/Sonnet session each),
   then both `git-lock-push.sh --ff-only` to the same origin. First wins; the slower
   one's ff-only pull fails loud → its checkpoint is **stranded** (committed locally,
   unpushed) and its work wasted. No corruption (ff-only never force-clobbers), but
   redundant burn + stranded checkpoints + ledger divergence on the next round.
   (Full analysis in the session that produced this seed.)
2. **Local parallelism ceiling.** The Workflow harness caps concurrent agents at
   `min(16, cpu_cores-2)` **per workflow on one box**. Distributing units across
   machines multiplies that ceiling.

## Constraint (the hard one)

**Any combination of the PCs may be (un)available** — including "all but one off",
or all off. Machines: **zomni** (Manjaro, strong), **fievel** (Raspberry Pi, also the
git host candidate — but intermittent), **cartmanjaro** (Manjaro, SSH gateway),
**pixel** (Termux/Android).

- **pixel is NOT just a light consumer** (correction, user 2026-06-16): Termux can run
  **cloud-AI HARD/review** units fine — anything whose work is API-bound with little
  local compute. It should be EXCLUDED only from `[INTENSIVE — <resource>]`
  local-compute units (local-LLM benchmarks, big index rebuilds), and is constrained by
  battery / flaky net / limited local toolchain. So: a viable worker for the
  cloud-bound majority, gated off local-heavy work.

## Key reframe: k3s is *almost* right, but its quorum assumption breaks here

k3s/Kubernetes coordinates via a **control plane + etcd**, and etcd needs a **quorum
of stable nodes** to make progress. Our constraint is exactly the case a quorum model
**stalls** (3 nodes, 2 off → no quorum → no scheduling, even with one good machine
idle). A literal etcd/Raft port imports the one property we can't satisfy.

Instead ask: *what is reliably reachable whenever ANY node is online?* Not a node —
the **git remote** (GitHub; NOT fievel-as-server, since fievel is itself an
intermittent node). So the proposed model:

> **Use the git remote as the control plane.** Stateless workers + durable shared
> queue + atomic claims via **ref compare-and-swap**. No leader, no quorum, no
> always-on node. Closer to a serverless job queue than to k8s.

### Mapping

| k8s concept | Git-remote-as-control-plane |
|---|---|
| etcd (shared state) | Coordination refs/branch on origin (durable, atomic) |
| Scheduler assigns pods→nodes | Workers pull the queue and **self-assign** the next free unit |
| Lease / mutual exclusion | `git push` of a lock ref with an **old-value precondition** (`update-ref` CAS / `push --force-with-lease`) — the **server** arbitrates atomically → true cross-machine exclusion, **no flock** |
| Node heartbeat / liveness | Claim ref carries a timestamp; any worker reaps a stale claim after TTL → self-healing on node death/offline |
| Reconciliation loop | Worker: pull desired state → claim free unit → work → push result + release |

**Dynamic membership falls out for free:** one online node makes full progress alone;
N nodes → N× parallelism; a node vanishing mid-work → its claim goes stale → reaped.
Nothing waits on a quorum.

## Evolution, not rewrite — primitives that already exist

- `claim.sh` (acquire/release/heartbeat/reap + TTL + worktree-liveness predicate) →
  **swap its flock-on-local-dir backend for git-ref CAS**; same interface. (id:ebfb,
  id:0902 built the current registry; design ratified in
  `2026-06-15-1216-relay-dispatch-safety-cluster.md`.)
- `git-lock-push.sh --ff-only` is already a weak CAS (reject-on-divergence) — generalize.
- `RELAY_LOG.md` is already `merge=union` (append-only) — ideal distributed event log.
- orphan-park / `/relay reconcile` already handle stranded work — reap path reuses them.

## Open decisions for the meeting (do not pre-empt)

1. **Substrate**: git-remote-CAS (favored) vs shared-FS+flock (NFS flock unreliable;
   syncthing has propagation lag → racy) vs a lightweight external datastore. Substrate
   gates everything else.
2. **Coordination layout**: a dedicated coordination repo? orphan refs (`refs/relay/lock/<repo>`,
   `refs/relay/queue/...`) on each managed repo's origin? one central queue repo?
3. **relay.toml**: stays per-machine, or becomes a shared (remote-backed) fleet registry?
   Who is the single writer when there is no single host?
4. **Quota as a fleet concern**: per-machine quota gates → need a shared view (also a
   remote ref?), else N machines each spend to their own threshold = N× burn.
5. **Worker capability matrix**: tag units (cloud-bound vs `[INTENSIVE]` local) and
   tag workers (zomni=all, fievel=cloud+light-local, pixel=cloud-only, cartmanjaro=?);
   scheduler honors the match. pixel pulls only cloud-AI HARD/review.
6. **Ledger conflicts**: remote lock prevents *concurrent* per-repo writers (the real
   fix), but `TODO/ROADMAP/REVIEW_ME` checkbox toggles still can't union-merge —
   keep line-scoped `md-merge.py` discipline.
7. **Claim-then-crash-before-first-push** window: heartbeat/TTL/reap must be airtight.
8. **Bootstrap/UX**: how does a node join? `/relay` auto-detects fleet membership? how
   does a human see fleet-wide status (a merged RELAY_STATUS)?

## Recommendation to carry into the meeting
Push the **git-remote-as-control-plane / CAS-ref-lock** model and pressure-test it
against: (a) all-but-one-offline, (b) pixel-is-cloud-only, (c) claim-then-crash,
(d) fleet-wide quota. Favor evolving `claim.sh`'s backend over a green-field orchestrator.
