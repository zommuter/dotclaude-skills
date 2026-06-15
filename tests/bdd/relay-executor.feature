# Surface: Claude Code executor session driven by CLAUDE.md §Relay contract.
# @manual — exercised by real executor sessions; the reviewer audits the results
# (test-file diffs against the last relay checkpoint tag — relay-ckpt-* or the historical
# fable-ckpt-*) on the next review turn.

Feature: Executor session works a ROADMAP item
  As a cheap executor session
  I want an unambiguous one-session task with a red test as the spec
  So that done means green, not plausible-looking prose

  @manual
  Scenario: Happy path — pick, implement, tick, green
    Given ROADMAP.md has an unticked [ROUTINE] item with RED tests
    When the executor implements the item and runs its done-check
    Then the item's test file passes
    And the executor ticks exactly that checkbox (no item text edited)
    And "make test" is fully green (no EXPECTED-RED left for ticked items, no regressions)
    And one self-report paragraph is appended to RELAY_LOG.md

  @manual
  Scenario: Ambiguous spec — block, don't game
    Given an item whose test looks wrong or whose spec reads two ways
    When the executor cannot make it pass without weakening a test
    Then the executor appends "BLOCKED: <item-id> <reason>" to RELAY_LOG.md
    And picks a different item instead of editing the test

  @manual
  Scenario: Gamed test is caught on review
    Given an executor weakened or deleted an assertion to go green
    When the reviewer diffs test files against the last relay checkpoint tag (relay-ckpt-* or legacy fable-ckpt-*) and re-runs the originals
    Then the original test fails, the item is reopened, and the weakening is reverted
