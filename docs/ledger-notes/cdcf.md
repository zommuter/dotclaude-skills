# id:cdcf

Relocated from the ledger by `tools/ledger-shrink.py`. Conventions, the verbatim
claim and backlinks: `docs/ledger-notes/README.md`.

## From TODO

(relay human 2026-07-23, follow-up to the id:7681 confirmation) — the /relay branch scopes correctly (invocation fence minus `inject|stop` + Configuration-knobs col 1), but the `meeting` branch is `scoped="$(grep -i "skill argument" "$skillmd")"` (`relay/scripts/validate-flags.sh:~136`). If that prose sentence is ever reworded, `$scoped` becomes EMPTY, `found` becomes empty, `missing` stays empty and `--coverage` **exits 0 having checked nothing** — a drift guard that cannot fail. Two fixes, both needed: (a) replace the prose grep with a real anchored marker (an HTML-comment fence such as `<!-- invocation-flags:start/end -->`, or a formal Invocation code-fence mirroring relay's) so the region is structural, not incidental; (b) **assert the scoped region is non-empty and every skill in the manifest yields ≥1 flag** — an empty scope must be a LOUD nonzero, never a silent pass. RED spec extends `tests/test_unknown_switch_guard.sh`. Relates id:7681 (confirmed), id:7e87 (`--fabled`, gated-on 7681 — it lands via this same marker), id:0e56. <!-- id:cdcf -->
