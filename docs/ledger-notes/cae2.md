# id:cae2

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(owner 2026-07-21) — survey https://code.claude.com/docs/en/agent-sdk/overview and its subpages (todo/Task tools, subagents, custom tools, hooks, sessions, permissions, streaming) for first-party primitives the relay/drain/meeting machinery currently hand-rolls, and decide per-primitive KEEP-BESPOKE vs ADOPT-SDK vs REFACTOR-ONTO-SDK. Concrete candidates surfaced by drain dogfood run-2: (1) **Task tools** (`TaskCreate/TaskUpdate/TaskGet/TaskList`, CC≥2.1.142) as the drain/meeting live board — already scoped by id:2238/id:5c48, this is the general lens; (2) **subagents / custom agent types** vs the current `agent()` + custom-model tricks (id:931c, id:176f `model:"bash"`); (3) **SDK hooks** vs the bespoke `core.hooksPath` gate stack (privacy gate, lane-vocab ratchet id:9ef7); (4) **session management / `claude -p`** vs the id:b3cc orchestrator-launched-instance design + the af30 governor safeguards; (5) **custom tools / MCP** vs the meeting broker IPC (broker.py). Output = a per-primitive verdict table + any new adopt/refactor ids, NOT a rewrite. Constraint-archaeology: for each bespoke mechanism, name the constraint it dodged and whether an SDK primitive now dissolves it ([[relay-substrates]], [[sandbox-2ec4]]). Relates id:2238, id:5c48, id:931c, id:176f, id:b3cc, id:9ef7. <!-- id:cae2 -->
