# 2026-05-10 — Publishing the meeting skill: refresh the gist (and is a gist the right venue?)

**Started:** 2026-05-10 16:58
**Session:** d1172885-518c-4932-84a2-f50fe2b34503
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill-runtime — project-standing)
**Topic:** The published gist (https://gist.github.com/zommuter/8245028a4d15efb8d41251e89d61f565, last updated 2026-05-08) is now ~2 days behind. Decide what to publish, where, and how to keep it in sync — plus a small allowlist tweak for gist-read.

## Surfaced discoveries

- 2026-05-08 (.claude): symlink-discovery — Claude Code follows symlinks in `~/.claude/skills/`. Load-bearing for the chosen approach.
- 2026-05-10 (.claude): Bash allow-patterns are shape-sensitive. Load-bearing for designing the gist-read allowlist patterns.
- 2026-05-08 (.claude): `$CLAUDE_SESSION_ID` env-var fix and heredoc shell-expansion rule — relevant if any setup-code snippets in the public README reference these patterns.

## Snapshot: gist vs. live skill (2026-05-10 16:58)

| File | Gist (2026-05-08) | Live (~/.claude/skills/meeting/) |
|---|---|---|
| SKILL.md | 6 setup steps, no Class 1/2/3 dispatch, no profile observations step, no `append.sh` use | 6 setup steps incl. user-profile load, Class 1/2/3 no-arg dispatch, profile observations step, `append.sh` for discoveries/personas |
| format.md | personas table (no emoji), no interactive-mode spec, no effort-estimate units, no user-profile pre-emption | personas with emoji, interactive-mode protocol, v0 effort-estimate table + cost-of.sh pointer, user-profile pre-emption rule |
| personas.md | 4 ad-hoc personas, no emoji | 5 ad-hoc personas (adds Lexi), all emoji-prefixed |
| append.sh | absent | present (executable) |
| cost-of.sh | absent | present (executable) |
| discoveries.md | absent | present (~12 KB, ~30 entries — many `(local)`) |
| user-profile.md | absent | present (~10 KB, behavioural observations about a specific person) |

Gist metadata: public, 0 forks, 1 comment, 1 history revision.

## Agenda

1. **Venue:** is a gist still the right place — vs. a dedicated repo, a section in `~/.claude` (already public), or a blog post?
2. **Scope:** which of the 7 live files should appear in the public artifact, and what (if anything) needs sanitising?
3. **Sync mechanism:** how do we stop the published version from going stale again — manual on-demand, hook on skill change, periodic, none?
4. **Side item:** allowlist `gh gist` read operations; keep writes on prompt.

## Discussion

### Items 1+2 — Venue and scope (entangled)

🏗️ **Archie:** `~/.claude` is **not** a public GitHub repo — `git remote -v` shows `fievel.local:src/claude.git`. So the published artifact is a curated copy by definition.

That curation has a hard boundary: `user-profile.md` is behavioural observations about Tobias (110+ lines about scope tolerance, persona pre-emption eligibility, identity-resolution conservatism, etc.). Publishing it verbatim would dump personal-fit notes onto the public internet.

`discoveries.md` is softer: most entries are technical (heredoc rules, hook patterns, IDF version pinning), but several are tagged `(local)` to specific stacks and reference internal paths. Per the *Low-paranoia infra disclosure* profile observation, Tobias is comfortable with home paths and machine names appearing publicly — so the practical decision is "publish as-is" or "strip `(local)` entries"; redaction is not strictly required.

⚙️ **Sage:** Skill-runtime correctness check — a third party trying to *use* the published artifact needs SKILL.md, format.md, personas.md, append.sh, cost-of.sh, plus *empty seed* discoveries.md and user-profile.md. The shell scripts also need an executable bit — gist preserves text but not file-mode metadata.

😈 **Riku:** Two sharp risks:
- **(R1) Drift, not staleness, is the real problem.** The gist was correct when published. Whatever venue we pick, if we don't fix the sync mechanism, we'll be back here in 2 weeks. Don't conflate "update once" with "publish sustainably."
- **(R2) Format fragmentation.** The gist's existing comment thread is a reader's connection to v1. Migrating to a new repo abandons that thread.

✂️ **Petra:** Three plausible venues:

| Option | Files | URL stable? | Sync ergonomics | Visibility |
|---|---|---|---|---|
| **A: Update gist in place** | flat list, no exec bit | yes | `gh gist edit` per file | reasonable |
| **B: New public repo** (e.g. `zommuter/claude-meeting-skill`) | full tree, exec bit | new URL | `git push` | better discoverability |
| **C: `dotclaude-skills` repo** for many skills | full tree | new URL | one push per skill change | best for the long arc — N=2 if more skills merit publishing |

😈 **Riku:** Pre-emption (per profile, *Empirical-pilot preference*, high, eligible): Option C is the maximalist case but only one skill is currently merit-of-publication. The "observe before preventing" instinct says C is speculation. Option A is the minimum step that closes today's gap.

✂️ **Petra:** The question isn't really "is gist *the* right venue forever," it's "is gist the right venue *for this update cycle*?" Defer venue change until the second skill is on the table.

⚙️ **Sage:** Concrete file plan for Option A: 5 live files copied + 2 stubs (discoveries.md and user-profile.md as header+explanation only).

### Decision (Items 1+2)

**User overrode the personas' "defer venue change" recommendation** and chose Option C with a key twist: leverage the symlink-discovery (Claude Code follows symlinks in `~/.claude/skills/`) so the live skill *literally is* the published version for spec files, while keeping personal data (discoveries.md, user-profile.md) as un-symlinked local-only files. This dissolves the drift problem entirely for spec files.

Notable: this matches the user's existing *Scope tolerance* profile observation (escalates scope when systemic — drift is systemic across spec files, so address it once via the venue change rather than incremental gist-update cycles).

### Item 3 — Implementation mechanics under the symlink approach

⚙️ **Sage:** Two symlink patterns:

**(P1) Whole-directory symlink**: `~/.claude/skills/meeting` → `~/src/dotclaude-skills/meeting/`. All files end up inside the public repo; personal files have to be `.gitignore`d. Risk: a `git add -A` accidentally stages them.

**(P2) Per-file symlinks**: `~/.claude/skills/meeting/` is a real directory; the spec files (SKILL.md, format.md, personas.md, append.sh, cost-of.sh) are symlinks pointing into `~/src/dotclaude-skills/meeting/`; the personal files (discoveries.md, user-profile.md) are real files in the live dir, never anywhere near the repo. No gitignore rope to trip on.

P2 is structurally safer and matches the user's framing ("core symlinked, private un-symlinked"). Recommended.

🏗️ **Archie:** Mechanic concerns under P2:
- **append.sh writes to discoveries.md (local) and personas.md (symlinked).** discoveries.md writes land locally; personas.md writes land in the public repo and ship with the next git-diary-workflow push. That's the desired sync for personas.md, but means **every saved persona goes public** — current registry is generic facilitator lenses with no PII; future personas already gated by save-time AskUserQuestion.
- **cost-of.sh references `~/.claude/projects/`** — standard install location, portable.
- **format.md references `~/.claude/skills/meeting/` paths** — correct for any user who installs at the standard location.

😈 **Riku:** Three risks:
- **(R1)** git-diary-workflow now needs a Step 1c for the third repo (mirror the existing Step 1b skip-if-clean pattern).
- **(R2)** append.sh's "no git operations" contract still holds — caller's git-diary-workflow picks up changes wherever they land.
- **(R3)** A user cloning `meeting/` directly (not via symlink) gets shell scripts. Default git mode-preservation keeps the +x bit. Worth a one-line install note in the README.

✂️ **Petra:** Three residual decisions:
- **(D1) Repo scope** — only `meeting/` now, or also seed `git-diary-workflow/`?
- **(D2) personas.md placement** — symlink (auto-published) or local-only?
- **(D3) Existing gist** — leave + comment, edit to pointer, or delete?

🏗️ **Archie:** Recommend (D1) meeting/ only, (D2) symlink, (D3) edit to pointer. Gists rank in search; readers get the redirect immediately.

### Decisions (Item 3)

- **(D1)** meeting/ only. Adding more skills is one `git mv` away.
- **(D2)** personas.md symlinked (auto-publish via append.sh).
- **(D3)** Leave gist as v1 snapshot + add one comment pointing to the new repo. **And** seed the new repo's *first commit* with the identical gist content so anyone diffing repo↔gist can verify they began from the same baseline. The migration to current-live is the second commit. (User-added refinement; clean migration pattern.)

### Item 4 — Allowlist: gh gist read-only

🏗️ **Archie:** Existing allowlist already covers `git -C *` for read-only patterns. Need equivalents for `gh gist`.

😈 **Riku:** Pre-emption (profile *Permission-model fluency*, med): the user routinely asks for narrow-shape, zero-cost patterns. Risk to flag: `Bash(gh api gists/*)` is **too loose** — `*` is glob and would match `gh api gists/<ID> -X POST` (the `*` swallows ` -X POST`). Patterns must include a discriminating flag like `--jq` (read-only by construction) or be constrained to subresources known-read-only (e.g., `/comments`).

⚙️ **Sage:** Concrete proposed entries:

```
"Bash(gh gist view *)",
"Bash(gh gist list)",
"Bash(gh gist list *)",
"Bash(gh api gists/* --jq *)",
"Bash(gh api gists/*/comments)",
"Bash(gh api gists/*/comments --jq *)"
```

✂️ **Petra:** Out of scope: gh repo / pr / issue allowlists. Out of scope: gh gist write patterns. Out of scope: broader allowlist audit.

### Decision (Item 4)

Add the 6 read-only patterns above to `~/.claude/settings.json`. Writes continue to prompt.

### Item 5 (amendment) — Allowlist for the new repo

While we're touching settings.json: the new `~/src/dotclaude-skills` repo will need add/commit/push entries mirroring the existing `~/src/claude-diary` entries:

```
"Bash(git -C ~/src/dotclaude-skills add *)",
"Bash(git -C ~/src/dotclaude-skills commit *)",
"Bash(git -C ~/src/dotclaude-skills fetch *)",
"Bash(git -C ~/src/dotclaude-skills rebase origin/*)",
"Bash(git -C ~/src/dotclaude-skills push)",
"Bash(git -C ~/src/dotclaude-skills push origin)",
"Bash(~/src/claude-diary/git-lock-push.sh ~/src/dotclaude-skills)"
```

(`git -C * <readonly>` patterns already cover status/log/diff/etc.)

## Decisions

- **Create `zommuter/dotclaude-skills` GitHub repo** with `meeting/` as the only subdir initially. Top-level README explains the multi-skill publishing pattern; `meeting/README.md` covers the skill itself + install instructions (clone or symlink, `chmod +x` on the .sh files).
- **First commit:** identical content to gist 8245028a4d15efb8d41251e89d61f565 (SKILL.md, format.md, personas.md, exactly as-of 2026-05-08). Provenance baseline.
- **Second commit:** replace with current live spec files: SKILL.md, format.md, personas.md (5 ad-hoc personas, emoji-prefixed), append.sh, cost-of.sh, README.md.
- **Symlink pattern P2** (per-file): `~/.claude/skills/meeting/{SKILL.md,format.md,personas.md,append.sh,cost-of.sh}` → `~/src/dotclaude-skills/meeting/$same`. `discoveries.md` and `user-profile.md` remain real local files in `~/.claude/skills/meeting/`, never in the public repo.
- **Existing gist:** leave files as v1 snapshot; add one comment from Tobias's account pointing to `https://github.com/zommuter/dotclaude-skills/tree/main/meeting`.
- **git-diary-workflow Step 1c:** add a third repo (`~/src/dotclaude-skills/`) using the same skip-if-clean + lock-push pattern as the existing Step 1b. (Out of scope to actually edit git-diary-workflow during this meeting — that's a follow-up TODO.)
- **settings.json allowlist:** add the 6 `gh gist` read-only patterns + 7 `dotclaude-skills` git/lock-push patterns. Writes continue to prompt.
- **Out of scope (explicit):**
  - Publishing `git-diary-workflow` or any other skill — defer to a future meeting (`/meeting publish-git-diary-workflow`) when warranted.
  - Tagging the repo — no v0.1 tag yet; wait for a deliberate version cut.
  - Editing the gist files (D3=leave, not D3=edit-to-pointer).
  - CI on the new repo.

## Action items

- [ ] **Create local repo** `~/src/dotclaude-skills/` with first commit containing the gist-snapshot SKILL.md, format.md, personas.md (verbatim from gist API). Contract: `git log --oneline` shows commit 1 == gist content.
- [ ] **Second commit**: copy current live `~/.claude/skills/meeting/{SKILL.md,format.md,personas.md,append.sh,cost-of.sh}` into `~/src/dotclaude-skills/meeting/`, add `meeting/README.md` (install + `chmod +x` instructions), add top-level `README.md` (publishing-pattern explainer). Contract: `diff -r ~/src/dotclaude-skills/meeting <(curated subset of live)` shows no differences in the 5 spec files.
- [ ] **Create GitHub repo** `zommuter/dotclaude-skills` (public, MIT or CC-BY licence — pick at create time), push initial history. Contract: `gh repo view zommuter/dotclaude-skills --json visibility` returns `public`.
- [ ] **Replace live files with symlinks**: for each of SKILL.md/format.md/personas.md/append.sh/cost-of.sh, `rm ~/.claude/skills/meeting/$f && ln -s ~/src/dotclaude-skills/meeting/$f ~/.claude/skills/meeting/$f`. Contract: `ls -la ~/.claude/skills/meeting/` shows symlinks for the 5 files; discoveries.md and user-profile.md remain regular files.
- [ ] **Verify skill still loads**: run `/meeting` (no args) on a trivial dispatch path or just inspect that file paths in SKILL.md still resolve. Contract: skill executes without "file not found" errors.
- [ ] **Add gist comment** pointing to `https://github.com/zommuter/dotclaude-skills/tree/main/meeting`. Contract: `gh api gists/8245028a4d15efb8d41251e89d61f565/comments --jq 'length'` returns 2.
- [ ] **Update settings.json allowlist** with the 6 `gh gist` read patterns + 7 `dotclaude-skills` repo patterns. Contract: a fresh `gh api gists/$ID --jq .description` runs without permission prompt.
- [ ] **Add Step 1c to `~/.claude/skills/git-diary-workflow/SKILL.md`** for the third repo. Contract: a substantive commit affecting any spec file in `~/src/dotclaude-skills/meeting/` is automatically committed and pushed by the diary workflow.
- [ ] **Add to `~/src/dotclaude-skills/.gitignore`**: `.git-lock-push.lock` (per global git-sync strategy).
- [ ] **Update `~/.claude/TODO.md`**: close any superseded items, add follow-up items, and add a new tracking item: **".claude meetings trigger the 'allow changing its own settings' prompt"** — observation: any meeting in `~/.claude` that produces settings.json allowlist changes (like this one) hits the "Allow editing settings?" guard because Claude Code recognises self-modification of its permission config. Recurring friction; not yet investigated. Investigate options: (a) accept as a hard guard (security-justified, leave as-is), (b) bypass via the existing `update-config` skill if it already handles this, (c) add a narrow allowlist exception for append-only allowlist additions. Defer to a future meeting / observation window.
- [x] **Write this meeting note.**
