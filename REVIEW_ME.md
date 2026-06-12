# Human review queue <!-- budget: 15 min -->

Judgment calls encoded in red tests — confirm or correct the interpretation.
Max ~10 open boxes; the reviewer prunes resolved ones each review turn.

- [ ] tests/test_broker_say.sh::say batching (roadmap:3b02) — TODO offered three
  options (allowlist, batching, /dev/null wrapper); the test encodes option (b)
  as a `say` subcommand that batches at the *Bash-tool-call* level but still
  POSTs one HTTP /event per line, so renderer per-line painting and TTFL
  granularity survive. Options (a)/(c) are deliberately not implemented.
- [ ] tests/test_statusline_tokens.sh::format (roadmap:2520) — token total is
  embedded in the context segment as `58%(115k)` with humanizing rules
  115000→`115k`, 9500→`9.5k`, 730→`730`; alternative (own segment, raw digits)
  rejected to keep line length stable.
- [ ] tests/test_ctx_budget.sh::advisory exit (roadmap:32d6) — ctx-budget.sh
  always exits 0 (WARN lines only), per the "observe before preventing"
  heuristic; if you want it as a CI gate it needs a `--strict` flag instead.
  Gate fixed at 2000 tokens ≈ bytes/4, matching the cost-of.sh convention.
- [ ] tests/test_makefile_skills.sh::nested paths (roadmap:1ec1) — fables-turn
  keeps its `references/` + `scripts/` subdirectories under
  ~/.claude/skills/fables-turn/ (SKILL_RULES learns mkdir-dirname) rather than
  flattening file names; `projects` is promoted to a first-class SKILLS member.
- [ ] tests/test_fable_caveat.sh::placement (roadmap:44ba) — the test requires
  the Fable note *inside* the γ-branch section (adjacent to the table), and
  accepts either a footnote marker or a blockquote; prose elsewhere in the file
  does not satisfy it.
- [ ] tests/run-tests.sh::expected-red semantics (infrastructure) — failing
  tests whose roadmap checkbox is unticked do NOT fail the suite; ticking the
  box arms them. This reconciles "red tests are the spec" with the contract's
  "full suite green" definition of done. Confirm you're happy that `make test`
  is green on a repo full of open items.
- [ ] tests/test_id_ecosystem.sh::ledger set (roadmap:de9c) — the id-token
  ledger now includes ROADMAP.md but deliberately NOT RELAY_LOG.md or
  REVIEW_ME.md (they only ever cite existing tokens, never originate them);
  `# roadmap:XXXX` test comments don't match the `id:XXXX` pattern by design.
- [ ] tests/test_id_ecosystem.sh::classify RELAY class (roadmap:de9c) — the
  TODO.md mirror line `Relay: N open ROADMAP items` gets its own `RELAY` class
  so `/meeting` no-arg dispatch never proposes a meeting on executor work;
  alternative (classify it C3 like any line) rejected as recurring noise.
