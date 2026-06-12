# Surface: CLI (make). Non-automatable journeys are tagged @manual — they touch
# the real ~/.claude and a live settings.json; automated coverage of the
# DEST_DIR-overridden variant lives in tests/test_makefile_skills.sh.

Feature: Install the toolkit into a live Claude Code config
  As a user cloning dotclaude-skills
  I want make install to wire skills, hooks, and permissions
  So that the live skill is the published version with no drift

  @manual
  Scenario: Fresh full install
    Given a clean clone at ~/src/dotclaude-skills
    And an existing ~/.claude/settings.json
    When I run "make install"
    Then every skill file is a symlink under ~/.claude/skills/<skill>/ pointing into the clone
    And "make status" reports "ok" for every file of every skill
    And ~/.claude/settings.json contains the generated Bash(...) allowlist entries
    And a backup settings.json.bak exists next to it
    And local-only files (discoveries.md, user-profile.md) exist under ~/.claude/skills/meeting/ but not in the repo

  @manual
  Scenario: Idempotent allowlist merge
    Given "make install" has already been run
    When I run "make install-allowlist" again
    Then it prints "nothing to add (all entries already present)"
    And settings.json is byte-identical to before

  @manual
  Scenario: Uninstall preserves personal data
    Given an installed toolkit with a non-empty ~/.claude/skills/meeting/discoveries.md
    When I run "make uninstall"
    Then all repo symlinks are removed
    And discoveries.md and user-profile.md remain untouched
