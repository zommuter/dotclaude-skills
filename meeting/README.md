# meeting — Claude Code skill

A structured design meeting skill for Claude Code. Summons named personas — 🏗️ Archie (architect — anchors claims in file paths and line numbers), 😈 Riku (devil's advocate — names specific risks), ✂️ Petra (productivity — enforces scope) — to scrutinise non-trivial decisions before you commit to code.

**Trigger:** `/meeting` (no-arg: classifies TODO items and dispatches) or `/meeting <topic>` (full persona meeting).

## What it does

- **With a subject**: runs an interactive multi-persona meeting in plan mode, writes a dated meeting note to `<root>/docs/meeting-notes/`, captures decisions and action items.
- **With no subject**: classifies unchecked TODO items into impl-ready / planning-worthy / meeting-worthy and dispatches the top candidate.

## How it works

### `/meeting` (no subject)

The skill audits your project's TODO + past meeting notes, classifies each
unchecked item, and asks which to take on.

1. Read `<root>/TODO.md` and `<root>/docs/meeting-notes/*.md`.
2. Classify each unchecked item into Class 1 / 2 / 3.
3. Print a grouped summary so you can see the buckets.
4. Recommend the top candidate (highest class first) and ask
   `[ do this / pick something else ]`.
5. Dispatch per the chosen class.

| Class | Trigger | What happens |
|---|---|---|
| 1 — impl-ready | A linked meeting note covers this item in its Decisions | Proceed to implementation in normal mode (no plan mode, no meeting). |
| 2 — planning-worthy | A meeting framed the question but didn't decide it, OR the TODO text signals "design / investigate / decide" with no link | Enter plan mode, native explore → design → present flow, write a Class 2 planning record at the end. |
| 3 — meeting-worthy | No link and ambiguous scope | Run the full multi-persona meeting (same flow as `/meeting <topic>`). |

The bucket summary prints in chat like this (illustrative — drawn from this repo's `TODO.md`):

```
Class 1 — impl-ready (2)
  - Verify diary commit at end of meeting fires without prompt
  - Verify Class 2 format (live test)

Class 2 — planning-worthy (3)
  - Investigate built-in "update project memory" mechanism
  - Add Write allowlist for project meeting notes
  - Verify cross-repo writes end-to-end

Class 3 — meeting-worthy (2)
  - Meeting: avoid ~/.claude/ as cwd
  - Meeting: global TODO skill / cross-project task tracking

Recommend: Class 1 → "Verify diary commit at end of meeting fires…"
[ do this / pick something else ]
```

### `/meeting <topic>` (with a subject)

The skill enters plan mode and runs an interactive multi-persona meeting:

1. **Warrantability self-check** — flags if the request looks like a bug fix
   or one-liner that doesn't need a meeting.
2. **Past-meetings audit** — flags prior action items not yet tracked in
   `TODO.md`.
3. Opens with the **Attendees** + **Topic** line, then walks the agenda.
4. At each decision point, the discussion is printed verbatim and an
   `AskUserQuestion` prompt fires with persona-derived options.
5. On the final decision, writes a dated meeting note to
   `<root>/docs/meeting-notes/YYYY-MM-DD-HHMM-<slug>.md` and exits plan mode.

A typical decision point looks like this (illustrative):

```
🏗️ Archie: Three candidate presentations for the no-arg flow…
✂️ Petra: N=2 check — that's two artefacts. Line budget?
😈 Riku: Pre-emption — your profile flags drift aversion. Three copies?

tl;dr: Personas converge on (c) — step list + table.

[1] Step list + class table (Recommended)
[2] Class table only
[3] Prose narrative
```

## Example output

Real meeting notes produced by this skill live in
[`../docs/meeting-notes/`](../docs/meeting-notes/) — most of them are recursive
(meetings about designing the meeting skill itself), so they double as
authentic example output.

Good starting points:

- [`2026-05-10-1658-publish-meeting-skill.md`](../docs/meeting-notes/2026-05-10-1658-publish-meeting-skill.md) — deciding how to publish this skill (meta).
- [`2026-05-10-1623-class2-format.md`](../docs/meeting-notes/2026-05-10-1623-class2-format.md) — Class 2 planning-record format.
- [`2026-05-10-1519-meeting-skill-planmode-entry.md`](../docs/meeting-notes/2026-05-10-1519-meeting-skill-planmode-entry.md) — design debate over `EnterPlanMode` timing.

`meeting-style.md` in the same directory is the project's standing-attendee
override, not a meeting note.

## Install

```bash
git clone https://github.com/zommuter/dotclaude-skills.git ~/src/dotclaude-skills
cd ~/src/dotclaude-skills
make install-meeting
```

This symlinks the published spec files into `~/.claude/skills/meeting/` (P2 per-file pattern) and creates empty `discoveries.md` and `user-profile.md` if they don't exist — your personal accumulator files stay local and are never overwritten on re-install.

## Settings.json allowlist

Add these entries to `~/.claude/settings.json` (under `permissions.allow`) for prompt-free operation:

```json
"Bash(~/.claude/skills/meeting/append.sh -t discoveries -e *)",
"Bash(~/.claude/skills/meeting/append.sh -t personas -e *)",
"Bash(~/.claude/skills/meeting/append.sh -t discoveries -f *)",
"Bash(~/.claude/skills/meeting/append.sh -t personas -f *)",
"Read(~/.claude/skills/meeting/*)",
"Write(~/.claude/docs/meeting-notes/*)",
"Read(~/.claude/docs/meeting-notes/*)"
```

## Broker daemon (`/meeting-live`)

The companion `/meeting-live` skill can stream persona discussion to a web renderer (meeting-rpg) via an HTTP+SSE broker. The broker is a global fixed-port daemon — one process shared by all concurrent sessions, each isolated by Claude session ID.

**Quick start:**

```bash
# Option A: let MEETING_LIVE=1 self-start on demand
MEETING_LIVE=1 claude

# Option B: always-on via systemd --user
cp meeting/meeting-broker.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now meeting-broker
```

**Env vars:**

| Variable | Default | Effect |
|---|---|---|
| `MEETING_BROKER_PORT` | `64109` | Fixed bind port (IANA-dynamic, above Linux ephemeral ceiling) |
| `MEETING_BROKER_IDLE` | `300` | Idle-shutdown after N seconds of no subscribers; `0` = never |

**Discovery file:** `/tmp/meeting-rpg/broker.json` → `{"port": N, "pid": M}`.

Clients read the actual port from this file; `64109` is the preferred-bind default and safe to hardcode in Caddy/proxy config.

## Files

| File | Published | Notes |
|---|---|---|
| `SKILL.md` | ✓ | Skill frontmatter + instructions |
| `format.md` | ✓ | Persona definitions, note format, effort table |
| `personas.md` | ✓ | Ad-hoc persona registry (public, no PII) |
| `append.sh` | ✓ | Registry append helper — `chmod +x` required |
| `cost-of.sh` | ✓ | Post-hoc session cost lookup |
| `broker.py` | ✓ | Global HTTP+SSE broker daemon |
| `broker-curl.sh` | ✓ | HTTP wrapper for broker calls (allowlist-friendly) |
| `meeting-broker.service` | ✓ | systemd --user unit for always-on broker |
| `discoveries.md` | local only | Your cross-project technical findings |
| `user-profile.md` | local only | Behavioural observations (personal) |
