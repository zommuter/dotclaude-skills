# 2026-07-08 — Sandboxing: run Claude/`/relay` as write-scoped OS users

**Started:** 2026-07-08 12:14
**Session:** 33f11056-7feb-45dd-b898-f18dbf62e89b
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🛠️ Sven (systemd `--user`/linger/keyring), 🛡️ Ivo (OS privilege-separation — dedicated users, userns/subuid, ACL vs group write-isolation) *(new)*, 🔩 Gil (git plumbing — amendment)
**Topic:** Run the unattended relay components as separate, write-scoped OS users — user/group layout on `~/src`, per-component write scopes, polkit/systemd `--user` interaction, and whether `--dangerously-skip-permissions` inside the sandbox is the acceptable `af30` substrate.

## Surfaced discoveries / prior art
- ToS precedent (D1, `2026-06-17-0905-model-probe-tos-and-band.md`): dedicated-OS-user-with-empty-`~/.claude` already ToS-reviewed + chosen for the model probe; keeps subscription quota + the "explicitly permitted" ToS limb. This meeting generalizes it.
- `af30`: autonomous campaign governor was denied by the auto-mode classifier (correctly — persistent permission-bypassing loop). Reusable half (`quota-stop.sh` thresholds) shipped.
- `permissionMode: auto` is the `/config` default but is NOT pinned in `~/.claude/settings.json` — relying on harness default, not an explicit setting.

## Agenda
1. One sandbox user, or a tier matched to write-scope?
2. User/group layout on `~/src` + write-isolation mechanism (POSIX perms vs ACL vs userns).
3. polkit / systemd `--user` interaction — linger, keyring for push creds, unit ownership.
4. `--dangerously-skip-permissions` inside the sandbox as the `af30` substrate + the `permissionMode=auto` constraint-archaeology question (run an empirical probe first?).

## Discussion

### Item 1 — one user, or a write-scope tier?
Three use-cases have different write sets:
| Use-case | Reads | Writes | Push creds? |
|---|---|---|---|
| (A) Discovery producer (`id:9d97`, `discover-repos-mechanical.sh`) | all `~/src` | `~/.config/relay/discovery-queue/`, heartbeat, logs — nothing else | no |
| (B) Mechanical daemon (`id:b3d0`, `mechanical-daemon.sh`) | `recipes/pending` + repos | `recipes/{running,done,rejected}`, artifacts, `bash -c` recipe cmds | no |
| (C) Full relay pool (`af30`) | everything | repo trees, commits, `git push` | yes |

- 🛡️ Ivo: a separate uid is a sandbox ONLY for components whose boundary is "don't write X." (A) is textbook — `~/src` files are `tobias:tobias 0644`, so *other* users are write-denied by plain DAC (kills the e0f8 near-miss at the kernel). (C) buys little — you must GRANT it repo-write, after which a regressed git op still wrecks what it was granted; (C)'s real boundary is the permission/classifier layer, not a uid.
- 😈 Riku: (B) is the interesting middle — it `bash -c`'s relay-authored recipe cmds, and `id:1cb8`'s trust boundary ("only reviewer writes `pending/`") is documented-not-enforced. A forged recipe execs as whatever uid (B) runs as; if (A) and (B) share a uid it can poison the producer's queue.
- ✂️ Petra: near-term consumers are (A)+(B) (both ship today); (C)/`af30` is suggestion + already-denied-once. Don't design a three-tier matrix for an unauthorized pool.
- 🛡️ Ivo: strongest cheap control for (B) — the CODE it runs (`mechanical-daemon.sh`, `recipe-validate.sh`, unit files) must be owned by `tobias`, not the service user, so a forged *recipe* is bounded by an out-of-blast-radius validator.

**Decision 1 (user, ratified):** Build TWO users now — split the read-only producer (A) from the recipe-exec daemon (B) into separate uids (forged-recipe isolation taken as build-time, not observe-first). ALSO scope the (C) full-pool tier's write-isolation + push-credential design in this note so `af30` has a ready substrate when authorized (its BUILD stays gated on `af30` authorization). Three users designed, two shipped now.

### Item 2 — user/group layout + write-isolation
Grounded facts: `/home/tobias` = `0711` (other can traverse), `~/src` = `0755`, repo files `0644` → **read access to all repos is already free via plain DAC; no group/ACL needed on the read side.** `~/.config/relay` = `tobias:tobias 0755` (readable, not writable by others). `setfacl`/`getfacl` present.
- 🛡️ Ivo: writable state is bidirectional (producer↔consumer, reviewer↔daemon). A flat shared group would hand relay-ro write on `recipes/` — reopening the producer-forges-recipe hole Decision 1 just paid a uid to close. Use **per-directory named POSIX ACLs**: `u:relay-ro:rwx` on `discovery-queue/` only, `u:relay-svc:rwx` on `recipes/` only, `u:tobias:rwx` everywhere; **default ACLs** for inheritance; setgid dirs.
- 🛠️ Sven gotcha: `relay-ro` running `git` (in `discover-sig.sh`) against a `tobias`-owned repo trips git's `safe.directory` guard (dubious ownership, git ≥2.35.2) → each service user needs `safe.directory = *` in its own gitconfig or the producer silently produces nothing.
- 😈 Riku: relay-svc needs `rwx` on `pending/` to `mv` recipes out → it can create files there too. 🛡️ Ivo: vacuous — relay-svc is the executor (already runs recipe cmds); the forgery threat is *external* injection, which per-dir ACL blocks for everyone except {reviewer, executor}. This makes `id:1cb8`'s "only reviewer writes pending" DAC-enforced instead of documented.
- ✂️ Petra: scope ACL work to what ships (`discovery-queue/` + `recipes/`); (C) repo-write = per-repo ACL or `relay-repos` group, note-and-defer; push creds = Item 3.

**Decision 2 (user, ratified):** Keep the state under `~/.config/relay` **for now**; enforce write-isolation with **per-directory named POSIX ACLs** matching the write matrix + default ACLs for inheritance. Reads of `~/src` need no provisioning (free via existing DAC). Provision each service user's gitconfig with `safe.directory = *`. Code unchanged (env overrides already exist). (C)'s repo-write grant = per-repo ACL / `relay-repos` group, deferred. **Reopen** toward a neutral `/var/lib/relay` tree if a real multi-user / external application materializes.

### Item 3 — polkit / systemd interaction
Grounded: current units all `--user`+linger (`discover-repos-mechanical`, `mechanical-daemon`, `quota-sample`, `relay-gap-sample`, `relay-watchdog`); linger=yes. **Claude creds are file-based** (`~/.claude/.credentials.json` 0600) — NOT keyring.
- 🛠️ Sven: headless keyring blocker is absent — `claude -p` as a service user needs only the 0600 creds file provisioned; git push creds for (C) likewise file-based (passphraseless deploy key / `~/.git-credentials` / helper). No graphical unlock anywhere.
- 🛡️ Ivo: polkit denies interactive-auth for a seatless service user **by default** — the sandbox user physically can't `pamac`/escalate/touch system units. That's the CLAUDE.md "never sudo pamac" rule enforced at the OS, not by discipline. Nothing to configure.
- 🏗️ Archie: **systemd hardening directives are a second kernel-enforced write boundary over the ACLs** — `ReadOnlyPaths=%h/src` + `ReadWritePaths=<queue>` + `ProtectHome=`/`NoNewPrivileges=`/`PrivateTmp=` would have stopped `e0f8` on their own. Two independent layers for a few unit lines.
- 😈 Riku: `--system` only marginally beats `/etc/systemd/user`+root-owned-units+directives, at a recurring sudo tax on the dev loop. 🛡️ Ivo concedes ~80%; real deltas (`ProtectSystem=strict`, address-family restriction, no service-user-owned manager) matter most for the (C) pool running a whole skip-perms `claude -p`.

**Decision 3 (user, ratified):** Hybrid. Ship (A)/(B) as `--user`+linger units split onto the two service users, **unit files root-owned in `/etc/systemd/user/`** (tamper-proof) + systemd hardening directives (`ReadWritePaths`/`ReadOnlyPaths`/`ProtectHome`/`NoNewPrivileges`/`PrivateTmp`) as a second enforcement layer over the ACLs. Reserve **`--system`** for the (C) pool (gated on `af30`). File-based creds only (no keyring). polkit default-deny is a feature, unconfigured.

### Item 4 — skip-permissions, permissionMode=auto, measure-first
- 🏗️ Archie: the sandbox does two separable things — bounds **blast radius** (yes) and confers **authorization** for a persistent self-relaunching loop (no). Building `af30` on skip-perms "because writes are OS-bounded" conflates them.
- 😈 Riku: `af30` was denied *as a shape* (a persistent permission-bypassing loop the user hadn't authorized), not for one scary op. An OS sandbox doesn't answer the classifier's actual objection.
- 🛡️ Ivo: OS sandbox = **containment**, not authorization. It makes skip-perms' consequences acceptable; it doesn't make the loop permitted. `af30`'s a–f safeguards are the authorization layer and the sandbox retires none of them.
- ✂️ Petra: constraint archaeology — `permissionMode:auto` is now the `/config` default; re-measure whether the wall still binds before building machinery to dodge it. If auto mode approves the executor surface via classifier-as-guard, skip-perms is unnecessary and the sandbox need only cover the deny-tail.
- 🛠️ Sven: the probe composes with the design — run it **inside the write-scoped sandbox user against throwaway clones** (substrate = safe measurement env), logging per-op-class approve/deny.

**Decision 4 (user, ratified):** **Measure first.** Build the sandbox (Decisions 1–3) now, but do NOT design `af30` around `--dangerously-skip-permissions`. First run an instrumented headless `claude -p` under `permissionMode=auto` inside the sandbox user against throwaway repo clones, logging per-operation-class approve/deny. Branch on the result: (1) auto-mode approves the executor surface → no skip-perms, sandbox covers the deny-tail; (2) it denies load-bearing ops → skip-perms-*inside-the-sandbox* is the fallback, acceptable for **blast radius only**. In BOTH branches the OS sandbox is **containment, never authorization** — `af30`'s a–f persistence safeguards stand regardless.

## Amendment session — isolate (C) via `git push ssh://localhost` (attendee: 🔩 Gil, re-onboarded)
- 🔩 Gil: `git worktree` structurally needs write to the canonical `.git` (shared object store + worktree ref) → the current `~/.cache/relay/worktrees` model contradicts D2's "repos read-only to service users" for (C). ssh-push dissolves it: pool user takes its OWN clone (freely writable, zero ACL on tobias's tree) and pushes back over a transport boundary — (C) needs ZERO filesystem write on canonical repos.
- 🛡️ Ivo: strict containment upgrade — replaces a filesystem grant with a protocol boundary where a `pre-receive`/`update` hook (running as tobias) can say no before anything lands; SSH `authorized_keys` forced-command (`git-shell`) pins the key to git ops on specific repos. (C) becomes the tier with the STRONGEST checkpoint — the authorization gate the OS sandbox can't provide (D4).
- 🔩 Gil: wrinkle — canonical repos are non-bare working trees (`receive.denyCurrentBranch`). Resolve by pushing to a `relay/*` ref namespace + tobias-side hook fast-forwards when clean (mirrors orphan-park `relay/orphan/*`), preferred over `denyCurrentBranch=updateInstead` (gives the hook a natural review-gate home).
- ✂️ Petra: (C) only — not a retrofit of every relay merge today (no current consumer; the pool isn't authorized).

**Amendment decision (user, ratified):** Adopt the ssh-push boundary as the **preferred (C) repo-write mechanism** — **supersedes D2's per-repo ACL / `relay-repos` grant for (C)** (canonical repos stay read-only to the pool user; own-clone + `git push ssh://localhost` to `relay/*` refs + tobias-side `pre-receive` gate + SSH forced-command). Still gated on `af30`; (A)/(B) unaffected. Also **take note** of evaluating the boundary for the general integrator (id:d916, trigger-gated). *Out of scope:* building it now; retrofitting the interactive integrator.

## Decisions
- **D1 — Three users designed, two built now.** Split (A) read-only producer (`relay-ro`) from (B) recipe-exec daemon (`relay-svc`) into separate uids now (forged-recipe isolation as build-time). Scope the (C) full-pool tier (`relay-pool`) in this note; its BUILD is gated on `af30` authorization. *Out of scope:* building (C) now; broker/`b444` human-input channel.
- **D2 — Per-directory named POSIX ACLs on `~/.config/relay`** (kept there for now): `u:relay-ro:rwx` on `discovery-queue/`, `u:relay-svc:rwx` on `recipes/`, `u:tobias:rwx` everywhere; default ACLs + setgid for inheritance. Reads of `~/src` need no provisioning (free via `0711`+`0755`+`0644` DAC). Service-user gitconfig `safe.directory=*`. Code unchanged (`RELAY_DISCOVERY_QUEUE_DIR`/`RELAY_RECIPE_DIR` env). *Out of scope:* a flat shared group (reopens producer-forges-recipe); relocating to `/var/lib/relay` (reopen only if a real multi-user application appears). (C) repo-write superseded by the amendment (ssh-push).
- **D3 — Hybrid unit topology.** (A)/(B) as `--user`+linger, unit files **root-owned in `/etc/systemd/user/`** (tamper-proof), + systemd hardening directives (`ReadWritePaths`/`ReadOnlyPaths`/`ProtectHome`/`NoNewPrivileges`/`PrivateTmp`) as a second enforcement layer over the ACLs. `--system` reserved for (C). File-based creds only (Claude `.credentials.json` 0600; git push creds file-based) — no keyring. polkit default-deny for seatless users is a feature, unconfigured. *Out of scope:* per-edit `sudo` tax of uniform `--system`; keyring integration.
- **D4 — Measure-first on the permission strategy.** Instrumented headless `claude -p` under `permissionMode=auto` inside the sandbox, per-op-class verdict logging, GATES the skip-perms decision. Sandbox = **containment, not authorization**; `af30`'s a–f safeguards stand in every branch. *Out of scope:* committing to `--dangerously-skip-permissions` before the measurement; retiring any `af30` safeguard.
- **D5 (amendment) — ssh-push boundary is the preferred (C) repo-write mechanism** (own-clone + `git push ssh://localhost` → `relay/*` refs + tobias-side `pre-receive` gate + SSH forced-command); supersedes D2's ACL/group grant for (C). *Out of scope:* building it now; retrofitting the interactive integrator (id:d916, trigger-gated).

## Action items
- [ ] Provision two service users `relay-ro` (A, read-only producer) + `relay-svc` (B, recipe-exec daemon) + gitconfig `safe.directory=*` each; document the group/uid layout. `relay/` provisioning script + `make` target. (2026-07-08-1214 note) <!-- id:13ae -->
- [ ] Per-directory named POSIX ACLs on `~/.config/relay` (`discovery-queue/`→relay-ro, `recipes/`→relay-svc, tobias everywhere; default ACLs + setgid). Idempotent apply script; test asserts the write matrix (relay-ro cannot write recipes/, relay-svc cannot write discovery-queue/). (2026-07-08-1214 note) <!-- id:02c7 -->
- [ ] Migrate producer + daemon units onto the two service users: unit files root-owned in `/etc/systemd/user/`, add hardening directives (`ReadWritePaths`/`ReadOnlyPaths`/`ProtectHome`/`NoNewPrivileges`/`PrivateTmp`); new `make install-*` targets. Verify e0f8 class is blocked (producer cannot write a repo even as its own user). (2026-07-08-1214 note) <!-- id:8e7a -->
- [ ] **Auto-mode deny-tail probe** (GATES the af30 skip-perms decision, D4): instrumented headless `claude -p "/relay --afk"`-equivalent under `permissionMode=auto`, run inside the sandbox user against throwaway repo clones, logging per-operation-class approve/prompt/deny. Output = the verdict table that picks D4 branch 1 vs 2. (2026-07-08-1214 note) <!-- id:5937 -->
- [ ] Spec (do NOT build) the (C) `relay-pool` tier: `--system` unit + ssh-push repo-write model (D5) + file-based push creds; build gated on `af30` authorization. Record as an `af30` sub-note. (2026-07-08-1214 note) <!-- id:38bf -->
- [ ] Record the **containment ≠ authorization** invariant against `af30`: the OS sandbox bounds blast radius only; the a–f persistence safeguards (scoped settings.json rule, wall-clock/agent budget, kill switch, loud per-relaunch surfacing, completion-verify) are NOT retired by the sandbox and gate the loop in every branch. (2026-07-08-1214 note) <!-- id:e2b1 -->
- [ ] [TRIGGER-GATED] Evaluate the ssh-push boundary as a replacement for the general local worktree-merge integrator (not just (C)). No current consumer; trigger = (C) push-model piloted OR a second worktree↔sandbox write-tension incident. Note only for now. (2026-07-08-1214 note) <!-- id:d916 -->
