# Destructive-operation guardrail (auto-mode soft-block + ask net)

A client-side guardrail that stops **auto mode** from running destructive shell
operations without an explicit go-ahead. Added 2026-07-15 after a near-miss where a
*reprioritize this running work* request was mis-handled as *stop it and clean up*,
putting a destructive `git restore` + `rm -f` in motion; only a human interrupt stopped
it. The lesson: a reorder is not a restart, and destructive git/`rm` must never run to
"clean up" un-inspected work.

## What it covers

- **`rm` force flags:** `-f`, `-rf`, `-fr`, `-r -f`, `--force` (incl. under `sudo`) —
  force-deletes with no recovery.
- **git force operations:** `push --force` / `-f` / `--force-with-lease`, and any git
  command run with a `--force` flag.
- **Destructive-but-not-`--force` git ops:** `git reset --hard`, `git restore <path>`,
  `git checkout -- <path>`, `git clean -f`/`-fd` — discard uncommitted work irrecoverably.

## How it behaves (by permission mode)

| Mode | Mechanism | Effect |
|---|---|---|
| `auto` (default) | `autoMode.soft_deny` classifier rules | Treated as destructive → **not run unless the user's message conveys that intent**. Clearable by explicitly asking for the specific deletion/force. |
| `default` / `acceptEdits` | `permissions.ask` patterns | **Prompts** on the canonical forms — the prompt is where the user says "yes". |
| `bypassPermissions` | (not covered, by choice) | A mode the user deliberately enters; no hard hook, to preserve "clearable unless I say so". |

Chosen as a **clearable soft-block + ask net** (not a hard PreToolUse deny) so the user
can still perform these deliberately by saying so, rather than having to disable a hook.

## Where it lives

The rules are added to the per-machine `~/.claude/settings.json`:

- `autoMode.soft_deny` — three natural-language classifier rules (plus `$defaults`), the
  **semantic** protection (robust to flag-order / compound-command variations that pattern
  matching alone would miss).
- `permissions.ask` — canonical Bash patterns (`rm -f *`, `git push --force*`,
  `git reset --hard*`, `git restore *`, `git clean -f*`, …), a best-effort net for the
  interactive modes.

### Interplay with existing force-push handling

This is a **client-side** layer. It composes with the two existing layers and does not
replace them:

1. The git server rejects all non-fast-forward / delete pushes by default
   (`receive.denyNonFastForwards` / `receive.denyDeletes`), so force-pushes fail at the
   server regardless of the client.
2. `relay/scripts/force-push.sh` is the **human-only, confirm-gated** override for the rare
   deliberate force-push — it refuses unless `FORCE_PUSH_CONFIRM=1` is set (which the
   automation never sets), uses `--force-with-lease`, lifts the server guard per-repo only,
   and re-arms it on exit. The guardrail's `git … --force` rules do **not** interfere with
   it: the classifier/`ask` matching sees the *command string*, and the force happens inside
   the script, not as a typed `git … --force`.

## Reproducible install — OPEN

`settings.json` is **per-machine** (each machine's `~/.claude` is its own branch), and this
repo is the source of truth applied by `make install` (see `install-allowlist` /
`install-relay-env`, which idempotently merge into `settings.json` via
`tools/allowlist.py` / `tools/settings-env.py`). These guardrail rules were added by hand on
one machine and are **not yet part of the install flow** — a fresh `make install` (or a
`settings.json` reset) on another machine would not carry them. Closing that is tracked as a
TODO: add an idempotent `install-guardrails` (or equivalent) merge target, wired into
`install`, mirroring the existing settings-merge targets. See TODO `id:98fc`.
