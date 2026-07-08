# 2026-07-08 — Subject clouds / cross-project overlap detection ("connecting the dots")

**Started:** 2026-07-08 14:46
**Session:** 08fa5378-42bd-4c54-9c9b-8fc0fbc8e90c
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), 🗄️ Cassi (derived-data persistence / build-cache), 🗺️ Flora (information-flow architecture / corpus classification)
**Topic:** Mechanize discovery of cross-project conceptual overlap (id:dc60): decide the HOME, then scope the deterministic slice-0 edge graph vs. the gated semantic layer.

## Surfaced discoveries / prior art
- **[[ledger-derived-index-decision-2840]]** — derived-index doctrine (md=SSOT, index=CACHE, generated-never-hand-kept). id:2840 already ratified a unified cross-repo derived index in `project_manager/scan.py` (id:0fc7, cross-project query id:69f4), currently unpromoted because "the artifact/CLI schema the relay consumes is undecided."
- **[[cross-project-coupling-design]]** — `[[coupling]]` array in `relay.toml` is human-declared cross-repo edges (one edge source already curated).
- **[[inflownistration-term]]** — the worked ground-truth case: a *concept* node (id:aae4) spanning the .mw/toesnail/ChidiAI triad that the id:23ab session had to re-discover by hand.
- **toesnail `docs/se-corpus.md`** — sibling use-case: hand-mined mapping of the owner's StackExchange posts → toesnail project steps (external-corpus ↔ project-subject overlap, 100% manual today).

## Agenda
1. HOME — project_manager vs zkm vs dotclaude-skills vs new project.
2. Slice-0 scope — edge sources, node model, the private-`[[link]]` leak boundary.
3. Render target + cadence.
4. Semantic-layer gating + the SE-corpus sibling.

## Discussion

### 1 — HOME
🏗️ **Archie:** Four of the five explicit edge sources are already read by `scan.py` or the config it mirrors — `relay.toml` (authoritative own-repo set + `# path:`), meeting-note cross-refs (`_last_meeting_note`/`_meeting_orphans` already glob `docs/meeting-notes/*.md`), shared-`id:` citations (already parsed for lane/orphan counts), and `[[coupling]]`. scan.py is already a cross-repo md→JSON cache with a render surface (`proj relay`). id:2840 didn't just suggest this home — it ratified it (id:0fc7 + cross-project slot id:69f4). Building elsewhere re-implements the scanner.

🗺️ **Flora:** Name what zkm is genuinely better at so we don't foreclose it: content-semantics (entity/embedding graph over document *content*). The *semantic* layer ("same thing, zero explicit edge") is zkm-shaped. Honest split: slice-0 (explicit edges over repo-metadata) → project_manager; semantic layer → zkm, *if the gap warrants*. Two homes, sequenced.

✂️ **Petra:** Then the real decision is "where does slice-0 live," and it's project_manager by the N=2-reuse rule (scanner + config + cockpit + hermetic tests + a pre-earmarked slot). dotclaude-skills is wrong on charter (stdlib-only bash harness tooling; this is Python portfolio-semantics — the item says so). A new project duplicates all of that. Reject both outright.

😈 **Riku:** Two risks. **(a) Leak boundary:** `[[name]]` memory links live in `~/.claude/projects/*/memory/` — private, never committed. project_manager is a public repo (`PROJECTS.md` is committed). Emitting private links into a committed artifact is exactly the [[feedback-no-leak-specifics-in-public-files]] violation. **(b)** id:0fc7 is explicitly unpromoted because its consumer schema is undecided — are we building on an open contract?

🏗️ **Archie:** On the leak: the producer may read private sources but writes to `~/.cache/project_manager/` (already gitignored); only a redacted repo-only projection is ever committed. On id:0fc7: dc60 doesn't inherit its blocker, it *dissolves* it — the edge-graph is the concrete consumer whose absence left the schema undecided. Build them together, dc60 leading.

🗄️ **Cassi:** From cache-topology: the edge graph is a *cross-repo* derivation (all repos in memory at once) → not a per-repo `ScanResult` field but a *second* derived artifact at fold time (new output file, not a new column). Caution: it's low-cardinality (a handful of repos, dozens of edges) — a flat generated JSON rebuilt from scratch is correct; do NOT reach for a graph DB / zkm entity store in slice-0.

**→ Decision D1** (see below).

### 2 — slice-0 scope
🏗️ **Archie:** The five explicit edge sources by extraction/direction/trust:

| Source | Extraction | Direction | Trust |
|---|---|---|---|
| `routed:XXXX` | grep notes/TODO/inbox; source→target named | directed | committed |
| shared `id:XXXX` | same token in ≥2 repos | undirected co-citation | committed |
| `relay.toml [[coupling]]` | parse TOML `repos=[a,b]` | undirected pair | config |
| repo-name mentions in prose | grep for basenames / `~/src/<repo>` | directed (mention) | committed |
| `[[name]]` memory links | grep `~/.claude/projects/*/memory/*.md` | directed | **private** |

🗺️ **Flora:** Node model can't be repo-only — the inflownistration edge is repo↔concept↔repo, invisible if nodes are only repos. Want three node types eventually (repo / concept / external), but slice-0 can *derive* concept nodes cheaply and deterministically: a shared `id:` cited in ≥2 repos IS a concept node, no NLP.

✂️ **Petra:** Keep slice-0 to *literal token* edges. `routed:`/shared-`id:`/`[[coupling]]`/`[[link]]` are literal → in. **Prose repo-mention is the odd one out** — a noisy grep heuristic, not a literal edge, and blurs "deterministic" into "fuzzy text matching" which is the semantic layer's job. Cut it from slice-0.

😈 **Riku:** Leak boundary, three options for `[[link]]`: (a) exclude it — cleanest but drops the richest "X is Y's sibling" source; (b) include, output local-only — the whole artifact lives in `~/.cache/`, never committed, no public surface to leak into; (c) two-tier output. Mechanical instinct: (b) — the *entire* subject-cloud artifact is a derived local cache anyway (id:2840); what consumer needs it in git?

🗄️ **Cassi:** Resolves cleanly on the sync-vs-backup axis. A derived artifact should never be committed ([[ledger-derived-index-decision-2840]]). Put it in `~/.cache/project_manager/edges.json`, gitignored, rebuilt on refresh — Riku's (b) falls out for free, the leak boundary disappears at the data layer and moves to the **render** layer: the cache is all-sources + local; any committed/shared *render* is repo-and-public-token only. One filter, one place.

🗺️ **Flora:** Keep concept nodes via the shared-`id:` derivation specifically — that's what makes it "connect the dots" rather than a repo-dependency diagram (which `[[coupling]]` already gives). The dots are the *concepts* that span repos.

😈 **Riku:** Minimum-viable slice-0: nodes {repo, concept-from-shared-id}; edges {routed:, shared-id:, [[coupling]], [[link]]}; prose-mention + external deferred; all-sources cache local-only; committed/shared renders public-filtered. Survives the checklist — a wrong graph is recoverable (regenerated); over-counting mitigated by showing the supporting token on every edge.

**→ Decision D2.**

### 3 — render + cadence
🏗️ **Archie:** Producer → `edges.json`. Render surfaces: (1) `proj` CLI subcommand — adjacency + "candidate synergy" report; (2) DOT/mermaid; (3) HTML Artifact. slice-0 ships (1) — the CLI + synergy report is the product ("what dots am I missing?"); visuals gated.

🗄️ **Cassi:** Cadence is determined by id:2840: regenerate on `proj refresh`, scratch-rebuild, md=SSOT. Content-hash staleness (id:c3a6 `discover-sig`) is optional polish over scratch-rebuild.

😈 **Riku:** Pin the synergy semantics: a candidate = two nodes with a *derivable* relationship (shared concept, transitive `routed:` path) but *no direct declared edge* — literally "the dot nobody connected." Risk: false-synergy spam (two repos share `id:2840` because both cite the doctrine, not a missed synergy). Mitigate: rank by edge-support, ALWAYS show supporting tokens → human-triage list, not auto-action ([[mechanization-decision-rule-415b]] posture).

✂️ **Petra:** slice-0 render = exactly one `proj` subcommand (adjacency + ranked synergy report, `--public` flag). DOT/mermaid/HTML are second consumers of the same `edges.json` — defer each.

**Mid-discussion finding (verified):** the "existing vis item" is **id:36f1 in dotclaude-skills** (the dc60 item text mis-attributed "cockpit viz id:3536/36f1" to project_manager). id:3536 is a different thing (surface the /meeting claim in the cockpit, routed:f125). **id:36f1** is the user's demand-pulled (2026-06-25) "flashy web-based overview of all tasks + blockings — a graph maybe," `[HARD — meeting]`, whose stated prereq is *"id:2840 must emit the dependency EDGES, not just node states."*

🏗️ **Archie:** That's the convergence. id:36f1 has been blocked on an edge-emitter that doesn't exist. dc60's producer IS that emitter. The subject-cloud graph and the task-blocking DAG are two renders over one edge substrate. dc60 slice-0 builds producer + CLI/synergy report; id:36f1 becomes the web/graph visual over the same `edges.json`, prereq discharged when the producer ships.

🗄️ **Cassi:** One canonical `edges.json` (superset: node-states + dependency edges + concept/routed edges), N renders. The user's steer "#2 → the existing vis item" = don't build a visual inside dc60; feed dc60's edges into id:36f1's visual.

**→ Decision D3.**

### 4 — semantic-layer gate + SE sibling
😈 **Riku:** What stops "slice-0 ships, gap analysis never happens, semantic layer forever-TODO"? Need a concrete gate artifact.

🗺️ **Flora:** The gate falls out of slice-0's output. The synergy report's inverse is the gap measurement: known overlaps slice-0 *cannot* represent. Two are in hand as ground truth — the inflownistration triad (a concept spanning .mw/toesnail/ChidiAI with no shared `id:` and no `routed:` linking all three) and the id:23ab relay↔chidiAI↔.mw overlap. If slice-0 fails to connect those, that failure IS the gap evidence. Gate = "run slice-0 against the ground-truth cases; misses define the semantic layer's spec" — unskippable because it's slice-0's acceptance demo.

🏗️ **Archie:** The SE-corpus is the same shape one axis over: external nodes (SE posts) → project subjects, via *content* similarity (no `routed:` from a StackExchange post). It's a natural first customer of the *semantic* layer, and it hands that layer a free hand-labeled eval set (the owner already mined which posts feed which steps).

🗄️ **Cassi:** So SE-corpus is neither slice-0 nor the semantic layer's first build — it's the layer's **eval fixture**. Keep it recorded, firmly out of slice-0.

🗺️ **Flora:** Recorded caveat: node-identity is trivial in slice-0 (opaque tokens) and becomes the hard problem when external content nodes arrive ("is this SE 'Noether' the same node as the .mw 'Noether'?"). That difficulty is paid only for genuine misses — a feature of the gate.

**→ Decision D4.**

## Decisions

- **D1 — HOME.** slice-0 → **project_manager/scan.py NOW** (reuse-maximal; id:2840 already earmarked the cross-project derived-index slot id:0fc7/id:69f4). Semantic/embedding layer → **zkm, GATED** on gap analysis. Rejected: a new "subject-clouds" project (duplicates the scanner) and dotclaude-skills (bash-only harness tooling — wrong charter). *Out of scope:* committing zkm's build now (it stays gated).
- **D2 — slice-0 scope.** Nodes = {`repo`, `concept` from a shared `id:` cited in ≥2 repos}. Edges = {`routed:`, shared-`id:` co-citation, relay.toml `[[coupling]]`, private `[[link]]`}. **Leak boundary:** all-sources graph → `~/.cache/project_manager/edges.json`, gitignored, never committed; the private `[[link]]` source is safe to read because nothing is committed; the boundary lives at the **render** layer via a `--public` filter dropping private-`[[link]]` edges and concept nodes supported only by a private source. *Out of scope:* prose repo-name-mention edges; external/SE nodes; repo-only node model.
- **D3 — render + cadence.** slice-0 = producer (`edges.json`, superset node-states + dependency edges) + one `proj` CLI subcommand (adjacency + ranked candidate-synergy report = derivable-but-undeclared node pairs, supporting tokens shown, `--public` filter). Regenerate on `proj refresh`, scratch-rebuild, md=SSOT. The graph **visual (#2)** is folded onto existing **id:36f1** (dotclaude-skills), gated on the producer landing; ONE canonical producer superset-serving dc60 + id:36f1 blocking-DAG + id:0fc7 index needs. dc60 **decides id:0fc7's output-contract schema**, unblocking id:0fc7/id:f80b. *Out of scope:* DOT/mermaid/HTML visuals inside dc60; content-hash staleness (optional polish).
- **D4 — semantic-layer gate + SE sibling.** Gate = slice-0's own acceptance: run the graph against ground-truth overlaps (inflownistration .mw/toesnail/ChidiAI triad; id:23ab relay↔chidiAI↔.mw); misses = the semantic layer's spec. SE-corpus (`toesnail/docs/se-corpus.md`) = the semantic layer's hand-labeled eval fixture. *Out of scope:* any NLP/embedding in slice-0; building the semantic layer before the miss-set is non-empty; fuzzy node-identity resolution until external nodes arrive.

## Action items
- [ ] **[project_manager]** Build dc60 slice-0: edge-graph producer in `scan.py` (extract {`routed:`, shared-`id:` co-citation, relay.toml `[[coupling]]`, private `[[link]]`}; nodes {repo, concept-from-shared-id}; write `~/.cache/project_manager/edges.json` all-sources/local/gitignored, scratch-rebuild on `proj refresh`) + `proj` CLI subcommand (adjacency + ranked candidate-synergy report + `--public` filter, supporting tokens shown) + ground-truth acceptance run (inflownistration triad; id:23ab triad) recording the miss-set. Superset the edge schema to also serve id:36f1's blocking-DAG + id:0fc7 index needs (ONE producer). Contract: DECIDES id:0fc7's output-contract schema; unblocks id:36f1/id:f80b; nothing derived is committed. → routed to project_manager inbox <!-- routed:e494 -->
- [ ] **[zkm]** Semantic/embedding overlap layer — build ONLY for overlaps slice-0's ground-truth run provably misses; SE-corpus (`toesnail/docs/se-corpus.md`) = its hand-labeled eval fixture. GATED on the slice-0 miss-set being non-empty. → routed to zkm inbox <!-- routed:b46d -->
- [ ] **[dotclaude-skills]** Fold the subject-cloud graph VISUAL onto **id:36f1**; record that its "id:2840 must emit dependency edges" prereq is discharged by dc60's project_manager `edges.json` producer; the web/graph render consumes the stable `edges.json` contract (never `import scan.py`). (edit to the existing id:36f1 line — no new id)
- [ ] **[dotclaude-skills]** Mark **id:dc60** decided with a pointer to this note; record that it unblocks id:0fc7 (project_manager) + id:36f1 (dotclaude-skills) and cites routed:e494 / routed:b46d. (annotation to the existing id:dc60 line)
