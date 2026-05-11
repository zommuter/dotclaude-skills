# meeting — Claude Code skill

A structured design meeting skill for Claude Code. Summons named personas (Archie the architect, Riku the devil's advocate, Petra the productivity enforcer) to scrutinise non-trivial decisions before you commit to code.

**Trigger:** `/meeting` (no-arg: classifies TODO items and dispatches) or `/meeting <topic>` (full persona meeting).

## What it does

- **With a subject**: runs an interactive multi-persona meeting in plan mode, writes a dated meeting note to `<root>/docs/meeting-notes/`, captures decisions and action items.
- **With no subject**: classifies unchecked TODO items into impl-ready / planning-worthy / meeting-worthy and dispatches the top candidate.

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
# 1. Clone or copy this repo
git clone https://github.com/zommuter/dotclaude-skills.git ~/src/dotclaude-skills

# 2. Create the skills directory if it doesn't exist
mkdir -p ~/.claude/skills/meeting

# 3. Symlink the spec files (P2 per-file pattern — keeps personal data local)
for f in SKILL.md format.md personas.md append.sh cost-of.sh; do
  ln -sf ~/src/dotclaude-skills/meeting/$f ~/.claude/skills/meeting/$f
done

# 4. Make scripts executable
chmod +x ~/src/dotclaude-skills/meeting/append.sh
chmod +x ~/src/dotclaude-skills/meeting/cost-of.sh

# 5. Create local-only personal data files (not in this repo)
touch ~/.claude/skills/meeting/discoveries.md
touch ~/.claude/skills/meeting/user-profile.md
```

The P2 symlink pattern means the live skill **is** the published version for spec files. Personal accumulator files (`discoveries.md`, `user-profile.md`) stay local.

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

## Files

| File | Published | Notes |
|---|---|---|
| `SKILL.md` | ✓ | Skill frontmatter + instructions |
| `format.md` | ✓ | Persona definitions, note format, effort table |
| `personas.md` | ✓ | Ad-hoc persona registry (public, no PII) |
| `append.sh` | ✓ | Registry append helper — `chmod +x` required |
| `cost-of.sh` | ✓ | Post-hoc session cost lookup |
| `discoveries.md` | local only | Your cross-project technical findings |
| `user-profile.md` | local only | Behavioural observations (personal) |
