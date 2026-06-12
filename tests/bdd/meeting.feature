# Surface: Claude Code skill invocation (/meeting). All journeys require a live
# Claude session and human judgment — @manual checklist, no automation harness.

Feature: Structured design meeting
  As the repo owner
  I want /meeting to scrutinize non-trivial decisions with named personas
  So that decisions get recorded with rationale and traceable action items

  @manual
  Scenario: Subject-mode meeting end to end
    Given a git repo with a TODO.md and docs/meeting-notes/
    When I invoke "/meeting <some design question>"
    Then the skill runs the orphan scan and surfaces any candidates before the agenda
    And the discussion shows named personas (Archie, Riku, Petra) with distinct lenses
    And every decision point shows the verbatim discussion before asking
    And a meeting note YYYY-MM-DD-HHMM-<slug>.md is written at the end
    And every action item that outlives the session appears in TODO.md with a matching <!-- id:XXXX --> token in both files

  @manual
  Scenario: No-arg dispatch classifies the TODO backlog
    Given a TODO.md with a mix of linked, gated, and bare items
    When I invoke "/meeting" with no subject
    Then classify.sh output is presented grouped by class (C1/C2/C3)
    And gated items show a [GATED] marker
    And the top candidate of the highest non-empty class is proposed with a one-line rationale

  @manual
  Scenario: Live broker meeting suppresses chat transcript
    Given a renderer attached to the broker (subscribers > 0)
    When a meeting agenda item is discussed
    Then persona lines stream to the renderer one event per line
    And the chat shows no verbatim discussion (token saving)
    And decision answers submitted in the renderer unblock the meeting

  @manual
  Scenario: Headless fallback keeps the user in the loop
    Given MEETING_LIVE is unset and no broker is running
    When a meeting reaches a decision point
    Then the full verbatim discussion is printed to chat
    And the decision uses AskUserQuestion (or inline-prose numbered options on a Fable-class harness)

  @manual
  Scenario: Cross-repo action item routes to the shared inbox
    Given a meeting action item whose natural home is another repo
    When the end-of-meeting steps run
    Then the item is appended to ~/.claude/todo-inbox.md with a routed:XXXX token
    And it is NOT written to this repo's TODO.md
    And the meeting note records "→ routed to <target-repo> inbox"
