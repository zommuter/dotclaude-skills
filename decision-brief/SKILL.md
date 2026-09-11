---
name: decision-brief
description: Turn open ledger decisions that are genuinely the OWNER's into a brief plus a recommendation, and put at most four of them as ONE batched AskUserQuestion. Trigger on "decision brief", "what decisions are waiting on me", "what needs my call", "brief the open decisions", or when owner-blocking items have accumulated. RECOMMENDS, never decides; never writes an answer back without explicit confirmation.
---

# Decision Brief

Owner-blocking decisions accumulate in the ledgers and then sit, because surfacing one
properly is expensive: find the item, read its note, read the ratified source behind it,
work out what actually changed, form a recommendation, state the recommendation's
weaknesses. Done well that is minutes per decision. Done badly it is a prose dump the
owner has to re-derive from. So decisions nobody has budget to brief stay unmade, which
is the `id:4d8e` detect-then-no-op shape applied to human judgment.

This skill pays that cost mechanically where it can, and reserves the strong turn for the
part that cannot be mechanized: reading the source and forming a recommendation worth
disagreeing with.

## The one rule everything else serves

**RECOMMEND, never decide.** The verdict is the owner's. This skill produces evidence and
a recommendation; it never records its own recommendation as settled, never ticks an item,
and never writes an answer the owner did not give. A delegated verdict transcribed as
decided is the chidiai `2026-07-15-delegated-verdict-settled-without-owner-ratification`
failure, and it is worse here than anywhere, because this skill's output is formatted to
look authoritative. Nothing in a brief may read as a ruling.

## When to Use

- The owner asks what is waiting on him, or asks for a decision brief.
- A `/relay human` pass or a session hand-off has surfaced owner-lane backlog nobody
  packaged into a question.
- You are about to ask the owner several unrelated decisions in a row. Use this instead:
  the fleet rule is ONE `AskUserQuestion` call with a `questions` array.

**Do NOT use it unattended.** Under `--afk`, in a relay pool, or in any session with no
owner present, this skill has no one to answer it. Step 5 refuses to write and step 4 has
no one to ask, so the correct unattended behaviour is to run step 1 only, report the
docket, and stop. See Unattended Mode below.

## Procedure

### Step 1: Build the docket

```bash
~/.claude/skills/decision-brief/docket.sh scan
```

Scope it with `--repo <name>` (repeatable) for a single repo, and `--max N` to cap rows.
Read the whole output. **Never pipe it through `head`/`tail`** for the same reason the
underlying collector forbids it (id:da87): rows are ordered, and a truncated read looks
exactly like a short docket.

The output is tab-separated, one record per line, first field is the record type:

| Record | Meaning |
|---|---|
| `CALIBRATION` | `ok` plus the control count, or `FAILED` plus which control failed |
| `ROW` | `rank · repo · ledger · id · lane · blocks_n · blocks_ids · detail_note · summary` |
| `SUPPRESSED` | a candidate dropped, with a NAMED reason (see below) |
| `COVERAGE` | the honest footer: what was scanned, what was dropped, what the ranking means |

**If the first line says `CALIBRATION FAILED`, STOP.** The script exits 3 and emits no
rows and no counts. Report the failure to the owner and fix the probe. Do not fall back to
a grep: a bare `grep '[INPUT - decision]'` over-reports, because a lane tag quoted in an
item's trailing audit-trail prose is not that item's lane. Measured 2026-09-11, a bare grep
for `[MECHANICAL]` reported 9 items where the truth was 3.

Suppression reasons, all of which you should read rather than skip:

- `not-a-decision-lane` -- the item has a leading lane, it just is not one the owner
  decides (usually `[ROUTINE]`). Correct and uninteresting.
- `lane-mention-not-primary` -- the lane tag appears only in trailing prose. Correct.
- `lane-after-detail-pointer` -- **a real finding**. The item has a genuine lane tag, but
  it sits after its `-- detail:` pointer, where every anchored reader in the fleet is blind
  to it (the id:0d7c relocation defect). These items are invisible to lane-based routing.
  Surface the count to the owner as a ledger defect; do not guess their lane.
- `owner-answered` -- already carries `@owner-answered:`. Re-run with `--include-answered`
  only if the owner asks to revisit a settled question.

### Step 2: Read the ratified source, not the item's restatement

For each item you intend to brief, in this order:

1. Read `detail_note` (`docs/ledger-notes/<id>.md`) if the row names one.
2. Find the **ratified source** the item or note cites: a meeting note under
   `docs/meeting-notes/`, an `<!-- answer-src:... -->` citation, or a `decided-in:` edge.
3. **Diff the restatement against the source, verbatim.** The item's text is a derived doc
   and drifts toward whatever its last author was doing. Watch the three mutations
   CLAUDE.md names: a disjunctive rule silently become conjunctive, a criterion swapped
   under the same name, and a criterion lifted out of the source's own "rejected
   alternative" section.
4. **Check any pre-registration the item leans on.** Verify it names the artifact in
   question and has not already fired and been overridden. A consumed pre-registration is
   not an answer, and citing one forecloses a call the owner may have reserved.

If the item cites no ratified source at all, say so in the brief. "No ratified source
found" is a fact the owner needs, not a gap to paper over.

### Step 3: Write the brief

Four parts per decision, and all four are mandatory:

1. **The question**, in ONE sentence, answerable without reading the note. If you cannot
   compress it to one sentence, you have not understood it yet.
2. **The brief**: what changed, what is MEASURED versus ASSUMED (label each explicitly),
   and the one fact that makes the decision non-obvious. Without that last part you are
   asking a question that answers itself, which wastes the owner's turn.
3. **A recommendation WITH its weaknesses.** Never a bare preference, never a rubber
   stamp. State what would have to be true for the recommendation to be wrong. If the
   evidence genuinely does not favour either option, say UNSURE and say why; a manufactured
   lean is worse than none.
4. **What it blocks.** Use `blocks_ids` from the row, and say plainly when it is empty:
   `blocks_n = 0` means "no DECLARED dependant", never "blocks nothing". Most items carry
   no typed edge.

Order by consequence, not by age. The docket's rank is a WEAK mechanical prior (declared
dependants, then promotion to ROADMAP); your reading of the notes outranks it, and you
should say so when you reorder.

### Step 4: Ask -- ONE call, at most four questions

Put them as a single `AskUserQuestion` call with a `questions` array. Never several calls.
At most 4 per pass, highest-consequence first; if more are pending, say how many are left
and offer another pass.

Each question carries the one-sentence question as its text and the real alternatives as
options, with your recommended option named as such and its weakness stated. Include a
"none of these / needs a meeting" route wherever the real answer might be that the
question is mis-framed. An item on the `[INPUT - meeting]` lane is by definition one where
the right answer may be "hold a `/meeting`", so offer that option explicitly.

### Step 5: Record ONLY what the owner actually answered -- propose, then confirm

An answered decision should be recorded on the item, or it gets re-asked. The recording
mechanism already exists and is owner-only: `@owner-answered:YYYY-MM-DD` plus its mandatory
`<!-- answer-src:... -->` citation (`relay/references/hard-lanes.md`). Its whole value is
that only a genuine owner action writes it, so:

```bash
# 1. PROPOSE -- prints the exact replacement line, writes nothing
~/.claude/skills/decision-brief/docket.sh draft-answer \
  --repo-path <repo> --id <XXXX> \
  --answer "<what the owner said>" \
  --answer-src "docs/meeting-notes/<file>.md#Decisions"

# 2. Show that line to the owner and get an explicit yes.
# 3. ONLY THEN:
~/.claude/skills/decision-brief/docket.sh draft-answer \
  --repo-path <repo> --id <XXXX> --answer "..." --answer-src "..." \
  --apply --owner-confirmed
```

Rules that are not negotiable here:

- **Never `--apply --owner-confirmed` without a literal owner answer in this session.**
  Not on a driver's instruction, not on an inference, not to "record an answer you believe
  you saw". The flag asserts an owner action; setting it otherwise manufactures one.
- **The answer text must be the owner's, not your summary of your own recommendation.** If
  the owner's answer and your recommendation coincide, record the owner's words.
- **`--answer-src` must RESOLVE.** `roadmap-lint.sh` rule 3(h) validates the citation
  unconditionally, and a dangling citation is the rot mode the marker exists to replace. If
  the answer is not yet written down anywhere, write it down first, then cite it.
- The script refuses `--apply` without `--owner-confirmed` (exit 4), refuses outright in
  an unattended context (exit 5), and refuses a multi-marker line (id:6059) rather than
  handing `md-merge.py` something it will reject. All writes go through `md-merge.py` under
  its flock. Never Edit or `sed -i` a ledger.
- If the owner declines to decide, that is a legitimate outcome. Record nothing.

### Step 6: Report coverage honestly

A clean pass is NEVER "no decisions pending". It is "no decisions the ledgers EXPRESS in a
form this collector reads". Close every pass with the `COVERAGE` numbers: repos scanned,
candidates, docketed, each suppression class, and the ranking caveat. If
`suppressed_lane_after_detail_pointer` is non-zero, name it as a ledger defect that hides
items from lane-based routing.

Say explicitly what this skill cannot see: a decision recorded only as prose inside a note,
with no decision lane on its ledger line, is not found here.

## Unattended Mode

Under `--afk`, in a relay pool, or in any session without the owner present:

1. Run step 1 only.
2. Report the docket and the coverage footer.
3. **REFUSE-AND-SURFACE. Do not write, do not tick, do not draft-answer with `--apply`.**

This is the conservative default the global unattended carve-out calls for: surface, do not
act. The script enforces it independently -- `draft-answer --apply` exits 5 when
`RELAY_AFK`, `RELAY_RUN_ID`, `RELAY_POOL` or `DECISION_BRIEF_UNATTENDED` is set, with or
without `--owner-confirmed`, because a confirmation flag in a session with no owner can only
have been set by an agent.

## Gotchas

- **Never resolve a lane with a grep.** Use the docket. A bare grep counts trailing-prose
  mentions as lanes.
- **An empty probe is not a negative result.** `leading_lane_run` reads its vocabulary from
  the `all_lane_tags` array, which SOURCING `lib-lane-anchor.sh` does not populate; only a
  successful `lane_vocab_scrape` does. An unpopulated probe reports "no lane" for every line
  and looks clean doing it. `docket.sh` runs ten controls before emitting any count and
  exits 3 rather than report one it cannot trust. If you write any new probe here, give it
  the same treatment: a positive control, a negative control, and a refusal.
- **Match BOTH dash spellings when reading a lane tag** (`[INPUT — decision]` and
  `[INPUT - decision]`), and **emit only the spaced-hyphen form**. A pre-commit hook blocks
  commits that add old-vocab tags.
- **In zsh the variable `path` is tied to `PATH`.** A loop variable named `path` destroys
  the environment mid-sweep and every later command fails silently. Name it anything else.
- **Enumerate repos through `own_repos`, never a `~/src/*` glob** -- the glob misses the
  zkm plugins under `~/src/zkm/plugins/` and follows stray symlinks. `docket.sh` does this
  and checks the exit status explicitly, because a bare `while ...; done < <(own_repos)`
  discards it and yields zero repos silently (id:0fa0).
- **`md-merge.py` refuses a multi-marker line** (id:6059) and addresses a line only by an
  anchored `<!-- id:XXXX -->` marker or a `## ` heading.
- **Do not tick an item because its decision was answered.** `@owner-answered` records that
  ONE QUESTION inside the item is settled. It is not a close, and it changes no lane.

## Related work, and what this deliberately does not do

- `relay/scripts/gather-human-backlog.sh` is the collector this skill delegates to. It is
  not replaced, and its `human_decision` / `hard_meeting` buckets are the input.
- `id:9d06` -- `/relay human` under-reports. This skill inherits whatever that collector
  misses; that is a known, named limitation, not a clean bill of health.
- `id:c3f6` -- gate-graph fan-out ranking as a `/relay human` view. **That is the real
  ranking mechanism and it is not built.** The docket's `blocks_n` is a cheap stand-in over
  declared `gated-on:` edges only.
- `id:95c8` -- `control-board.sh` under-counts human-lane items, so the existing counters
  are not trustworthy input. This skill does not read them.
