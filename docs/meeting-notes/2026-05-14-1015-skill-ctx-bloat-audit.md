# 2026-05-14 — Skill context bloat audit

**Started:** 2026-05-14 10:15
**Session:** c28f746d-2152-4bc3-ba68-1286a6382e25
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** Audit context-bloat pitfalls across user-defined skills. Decide caching/script strategy for `/meeting`'s orphan scan, whether `/todo-update` S1+S2 archival should be prioritized given end-of-session ctx pressure, and whether other skills carry similar risks.

## Surfaced discoveries

- [2026-05-08 .claude] Claude Code `Stop` hooks receive `transcript_path` — usable for end-of-session cache invalidation if we go down a cache route (ultimately didn't).
- [2026-05-10 .claude] Bash allow-patterns are shape-sensitive — new helper-script allowlist entries must match invocation shape exactly.
- [2026-05-08 .claude] Claude Code follows symlinks in `~/.claude/skills/` — P2 symlink pattern is already proven for new helpers.
- [2026-05-11 dotclaude-skills] meeting/README.md is NOT in the P2 symlink loop — new helper scripts live in dotclaude-skills and are symlinked into `~/.claude/skills/meeting/`.

## Agenda

1. Ctx-cost audit — quantify which `/meeting` setup files and audit passes are heaviest.
2. `/meeting` orphan-scan strategy — script-based digest (A), cached digest (B), Stop-hook prefill (C), no-op (D)?
3. `/todo-update` archival priority — S1+S2 sequencing given end-of-session ctx pressure.
4. Forward scope — discoveries.md RAG trigger, user-profile.md size, other skills audit.

## Discussion

### Item 1 — Ctx-cost audit

**Numbers gathered this session:**

`/meeting` setup files — loaded every invocation:
| File | Lines | Note |
|---|---|---|
| user-profile.md | **390** | 52 % of setup ctx; 27 traits |
| format.md | 165 | spec |
| discoveries.md | 109 | ~65 entries; RAG trigger at ≥100 entries or ≥800 lines |
| SKILL.md | 68 | spec |
| personas.md | 22 | light |
| **subtotal** | **~754** | every meeting |

`/meeting` orphan-scan additional ctx — per invocation (this repo):
| Source | Lines |
|---|---|
| 12 meeting notes | **~1,300** (71–170 each) |
| TODO.md | 37 |
| **subtotal** | **~1,340** |

→ `/meeting` total: **~2,100 lines** in this repo. In `~/src/zkm/` it will be much higher (more notes; TODO.md alone 364 lines).

`/todo-update` — mandatory after every substantive prompt:
- SKILL.md: 83 lines
- TODO.md reads: zkm **364**, helferli 77, dotclaude-skills 37, .claude 21, claude-diary 13.

🏗️ **Archie:** Three distinct bloat classes:
- **Class α — setup load:** user-profile.md dominant at 390 lines (52 % of meeting setup ctx). Hard to fix without RAG or topic filtering.
- **Class β — audit-pass waste:** orphan-scan reads ~1,300 lines just to extract `## Action items` lines. Pure waste — script stdout is the win.
- **Class γ — consumer-file growth:** TODO.md Done-section growth (zkm 364 lines) multiplied by /todo-update's per-prompt frequency.

😈 **Riku:** We have the numbers — empirical-pilot preference satisfied. Name failure modes for any solution: cache-miss orphans (silent degradation), stale-cache orphans (false "all good"), false-positive noise. Minimum evidence to change design: one orphan the script missed that the old read-all approach would have caught.

✂️ **Petra:** No generic ctx-instrumentation framework — no N=2 consumer. Address only the three classes, one at a time, minimum machinery.

⚙️ **Sage:** Bash script stdout is the only thing entering ctx. Script can read 1,300 lines and return 5 — that's the whole win. Match `meeting/append.sh` and `meeting/cost-of.sh` pattern.

😈 **Riku — drift-aversion pre-emption:** a cache file is a second source of truth alongside the meeting notes — invites drift. Prefer no cache file; re-scan each call, return tiny stdout.

✂️ **Petra:** user-profile.md at 390 lines is hardest to fix — entries are interlinked, pre-emption depends on full presence, trimming requires RAG or topic filtering. Park as forward-flag (Item 4).

**Decision 1 (user):** β + γ now, α deferred.

### Item 2 — `/meeting` orphan-scan design

🏗️ **Archie:** New helper: `~/src/dotclaude-skills/meeting/orphan-scan.sh`, P2 symlinked to `~/.claude/skills/meeting/orphan-scan.sh`. Args: optional repo-root (default cwd). Behaviour:
1. Find `<root>/docs/meeting-notes/*.md` (skipping `meeting-style.md`).
2. Scan all `- [ ] …` lines (whole file, not just Action items section — simpler regex, fewer parse errors).
3. Read `<root>/TODO.md`.
4. Substring-match each unchecked line against TODO.md using first 4 words of the stripped title (case-insensitive).
5. Print **candidate orphans only** as `<basename>:<lineno>  <text>`. Exit 0 on zero results.

SKILL.md change: "Past-meetings audit" step becomes `Run ~/.claude/skills/meeting/orphan-scan.sh — any output line is a candidate orphan; verify each against TODO.md (in ctx) before flagging. If exit ≠ 0, fall back to read-all behaviour.`

😈 **Riku:** Three failure modes:
- **F1 — key too loose (4w shares word with unrelated TODO):** false-negative. Mitigation: model verification step.
- **F2 — key too strict (TODO paraphrases):** false-positive (flags tracked item). Mitigation: tolerable, model verifies and discards.
- **F3 — silent script failure:** parse error → empty stdout → false "all good." Mitigation: exit-code discipline; SKILL.md fallback.

This is the **two-stage gate** pattern: script does cheap first-pass (reads ~1,300 lines, returns ~10), model does final verification against in-ctx TODO.md.

⚙️ **Sage — lever-first-instinct pre-emption (eligible, high):** you'd prefer extending the `meeting/` sibling-script lever. Confirmed: orphan-scan.sh is exactly a sibling of append.sh and cost-of.sh.

✂️ **Petra:** Out of scope — no cache file, no fuzzy semantic match, no GH-Issues scan, no grep beyond `- [ ]` lines.

😈 **Riku — edge cases:**
- Amendment session `- [ ]` items: scan whole file → covered automatically.
- `[x]` lines: skipped (grep pattern `'^- \[ \] '` exact).
- Class 2 planning records: same `## Action items` structure — no special-case.
- Multi-line action items: accept undercount on continuation lines; contract is "candidate orphans, model verifies."

🏗️ **Archie — implementation sketch with instrumentation logger:**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"
NOTES_DIR="$ROOT/docs/meeting-notes"; TODO="$ROOT/TODO.md"
LOG="$HOME/.claude/logs/meeting-orphan-scan.log"
[[ -d "$NOTES_DIR" && -f "$TODO" ]] || {
  printf '%s\t%s\tnotes=0\tunchecked=0\tcand4=0\tcand5=0\truntime_ms=0\n' \
    "$(date -Iseconds)" "$(basename "$ROOT")" >> "$LOG" 2>/dev/null || true; exit 0; }
mkdir -p "$(dirname "$LOG")"
start_ms=$(date +%s%3N)
todo="$(cat "$TODO")"
notes=0; unchecked=0; cand4=0; cand5=0
declare -a output_lines
for f in "$NOTES_DIR"/*.md; do
  [[ "$(basename "$f")" == "meeting-style.md" ]] && continue
  notes=$((notes+1))
  while IFS=: read -r lineno text; do
    unchecked=$((unchecked+1))
    stripped="$(echo "$text" | sed 's/^- \[ \] //; s/\*\*//g')"
    key4="$(echo "$stripped" | awk '{print $1,$2,$3,$4}')"
    key5="$(echo "$stripped" | awk '{print $1,$2,$3,$4,$5}')"
    grep -qiF "$key4" <<<"$todo" || { cand4=$((cand4+1)); output_lines+=("$(basename "$f"):$lineno  $text"); }
    grep -qiF "$key5" <<<"$todo" || cand5=$((cand5+1))
  done < <(grep -n '^- \[ \] ' "$f")
done
runtime_ms=$(( $(date +%s%3N) - start_ms ))
printf '%s\t%s\tnotes=%d\tunchecked=%d\tcand4=%d\tcand5=%d\truntime_ms=%d\n' \
  "$(date -Iseconds)" "$(basename "$ROOT")" "$notes" "$unchecked" "$cand4" "$cand5" "$runtime_ms" >> "$LOG"
printf '%s\n' "${output_lines[@]:-}"
```

Log fields: `<iso8601>  <repo>  notes=N  unchecked=U  cand4=C4  cand5=C5  runtime_ms=T`. Captures cand4-vs-cand5 divergence for calibration of the 4→5-word threshold question.

**Decision 2a (user):** Option 1 (candidates only, model verifies) **plus** instrumentation; re-evaluate after 10 invocations.

#### Measurement framing

😈 **Riku — reframe caching benefit:** Option 1's stdout is already the minimal-ctx output. A cache file does NOT reduce ctx — only stdout enters ctx, cached or not. The only saving is **wall-clock time**. **Caching for ctx is a category error; caching for wall-clock is empirically gateable.** The log gives us runtime data within 10 invocations.

⚙️ **Sage:** Word-count threshold v0 = **4** (per Archie's sketch). cand4 vs cand5 both logged → question "would 5 have changed outcomes?" answerable from data. No separate calibration script needed.

😈 **Riku:** Failure-cost asymmetry — false-negative (missed orphan) is expensive; false-positive is cheap (model discards). If cand5 < cand4 in any log row → 5-word throws out real orphans → keep 4. Direction is toward 4, not 5.

**Decision 2b (user):** Logger approved; trigger raised to **10** invocations.

**Decision 2c (user):** Add long-horizon meeting-note **archival skill** forward-flag (volume-triggered, parallel to S1 TODO archival).

😈 **Riku:** Growth rate this repo: ~2 notes/day. Volume trigger: **≥50 notes in any `<root>/docs/meeting-notes/`** → open `/meeting meeting-note-archival`. At current rate ~4 weeks away.

### Item 3 — `/todo-update` archival priority (S1+S2 sequencing)

**S4 verification:**
- `~/.claude/skills/todo-update/SKILL.md` → symlink to `~/src/dotclaude-skills/todo-update/SKILL.md` ✓
- `~/src/dotclaude-skills/todo-update/` contains SKILL.md + README.md ✓
- Skill loads (confirmed in available-skills list at meeting setup) ✓
- Contract from 2026-05-13 D5 satisfied. **S4 marked done.**

⚙️ **Sage:** `/todo-update` mandatory after every substantive prompt — bloat multiplied by per-session prompt count. zkm 364 lines × ~10 prompts/session = ~3,600 lines/session from `/todo-update` alone, vs `/meeting`'s ~2,100/invocation. **Higher cumulative impact than orphan-scan.**

🏗️ **Archie:** Impact ranking: zkm 364 lines (clear winner), helferli 77 (marginal), others ≤37 (negligible). zkm alone justifies S1+S2 priority.

😈 **Riku — failure modes:**
- **F1 archive-done.sh deletes data:** safe-default-keep on undated entries; append-only to TODO.archive.md; idempotent.
- **F2 Step 4 archive call triggers permission prompt:** would amplify ctx instead of reducing. Allowlist path must be `~/.claude/skills/todo-update/archive-done.sh` (symlinked path) — confirmed correct in D2 spec.
- **F3 grep-before-add procedure-skip:** known risk, not worse than today.

Out of scope (re-confirming 2026-05-13 D2): non-date-suffix archival, retention-threshold tuning, year-bucketed sections.

**Decision 3 (user):** S4 confirmed; S1+S2 and orphan-scan ship in **parallel order** over next two sessions (either order).

### Item 4 — Forward scope

🏗️ **Archie — other-skills line-counts:**
- `projects/SKILL.md` 35 lines — light.
- `git-diary-workflow/SKILL.md` **166 lines** — mandatory after every substantive prompt; surprisingly hefty. Forward-flag.
- `todo-update/SKILL.md` 83 lines — bloat is in the TODO.md it reads, addressed by S1+S2.
- Domain skills — load on trigger only; no audit needed.

😈 **Riku:** No `git-diary-workflow` audit meeting yet — no concrete bloat complaint, no N=2 consumer for "audit skill sizes" tooling. Forward-flag only.

✂️ **Petra — forward flags (volume/symptom-triggered, no v0 implementation):**
- **F1** `git-diary-workflow` SKILL.md trim — trigger: growth past 200 lines OR concrete bloat episode.
- **F2** `user-profile.md` ctx strategy — trigger: file exceeds **600 lines** OR setup feels slow. Directions: topic-filter, RAG, archive low-confidence-untouched entries.
- **F3** `discoveries.md` RAG — existing TODO; current **65 entries, 109 lines** (35 entries shy of trigger).
- **F4** Meeting-note archival skill — ≥50 notes in any `<root>/docs/meeting-notes/`.

😈 **Riku — systemic observation (saved as discovery + CLAUDE.md heuristic):** **Every "mandatory after every prompt" skill is a ctx multiplier** — loaded size × per-session prompt count. Any future after-every-prompt skill must pass an explicit ctx-budget review before going mandatory.

## Decisions

- **D1** — Address β (orphan-scan) + γ (TODO Done growth) now; defer α (setup load, user-profile.md dominant).
- **D2** — `orphan-scan.sh` helper script: sibling to append.sh/cost-of.sh, P2 symlinked, 4-word substring key, candidate-only stdout, model verifies against in-ctx TODO.md.
- **D3** — Instrumentation logger: 7-field tab-separated line per invocation in `~/.claude/logs/meeting-orphan-scan.log`.
- **D4** — Re-evaluation trigger: **10 logged invocations**. Gate (a) runtime <500ms → no cache; (b) cand5<cand4 ever → keep 4-word key.
- **D5** — Allowlist (next session): `Bash(~/.claude/skills/meeting/orphan-scan.sh)` + `Bash(~/.claude/skills/meeting/orphan-scan.sh *)`.
- **D6** — SKILL.md "Past-meetings audit" amendment (next session): one-liner Bash call + fallback to read-all on non-zero exit.
- **D7** — S4 confirmed done (verified this session).
- **D8** — S1+S2 and orphan-scan ship in parallel order over next two sessions.
- **D9** — Long-horizon forward flags: F1 git-diary-workflow trim (>200 lines), F2 user-profile ctx strategy (>600 lines), F3 discoveries RAG (existing, 65/109 now), F4 meeting-note archival (≥50 notes).

## Action items

- [x] **Mark S4 done** — verified by user 2026-05-14.
- [ ] **Implement `orphan-scan.sh`** (next session): `~/src/dotclaude-skills/meeting/orphan-scan.sh` per D2/D3 sketch; chmod +x; P2 symlink; allowlist additions (D5); SKILL.md amendment (D6). Contract: synthetic run returns ≤2 candidates, writes one log line, runtime <500ms.
- [ ] **Add re-evaluation TODO entry** (this session, dotclaude-skills TODO.md).
- [ ] **Add F1, F2, F4 forward-flag TODO entries** (this session, dotclaude-skills TODO.md; F3 already exists).
- [ ] **Ship S1+S2** (separate session, either order vs. orphan-scan): per 2026-05-13 D2+D3 spec.
