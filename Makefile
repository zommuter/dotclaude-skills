SRC_DIR  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEST_DIR := $(HOME)/.claude/skills
export DEST_DIR

SKILLS := meeting meeting-cross git-diary-workflow todo-update relay projects

HOOKS_DIR := $(HOME)/.claude/hooks

meeting_FILES := SKILL.md format.md personas.md broker-mode.md cross-mode.md append.sh cost-of.sh \
                 find-todos.sh orphan-scan.sh broker-curl.sh broker.py profile-active.sh \
                 persona-state.py retrieve-top-k.py md-merge.py gh-audit.sh classify.sh
meeting_EXEC  := append.sh cost-of.sh find-todos.sh orphan-scan.sh broker-curl.sh broker.py profile-active.sh \
                 persona-state.py retrieve-top-k.py md-merge.py gh-audit.sh classify.sh
meeting_ALLOW := append.sh cost-of.sh find-todos.sh orphan-scan.sh broker-curl.sh profile-active.sh \
                 persona-state.py retrieve-top-k.py md-merge.py gh-audit.sh classify.sh
meeting_LOCAL := discoveries.md user-profile.md

meeting-cross_FILES := SKILL.md
meeting-cross_EXEC  :=
meeting-cross_ALLOW :=
meeting-cross_LOCAL :=

git-diary-workflow_FILES := SKILL.md diary-append.sh git-lock-push.sh
git-diary-workflow_EXEC  := diary-append.sh git-lock-push.sh
git-diary-workflow_ALLOW := diary-append.sh git-lock-push.sh
git-diary-workflow_LOCAL :=

todo-update_FILES := SKILL.md archive-done.sh
todo-update_EXEC  := archive-done.sh
todo-update_ALLOW := archive-done.sh
todo-update_LOCAL :=

relay_FILES := SKILL.md \
               references/handoff.md references/review.md references/human.md \
               references/conventions.md references/templates.md \
               references/executor-contract.md \
               scripts/discover-repos.sh scripts/ckpt-tag.sh scripts/probe-fable.sh \
               scripts/gather-human-backlog.sh scripts/quota-stop.sh \
               scripts/relay-loop.js scripts/inject.sh scripts/claim.sh \
               scripts/sync-origin.sh scripts/force-push.sh scripts/relay-state-write.sh \
               scripts/gaming-scan.sh scripts/profile-run.sh scripts/profile-runs-batch.sh \
               scripts/relay-burn.sh
relay_EXEC  := scripts/discover-repos.sh scripts/ckpt-tag.sh scripts/probe-fable.sh \
               scripts/gather-human-backlog.sh scripts/quota-stop.sh scripts/inject.sh \
               scripts/claim.sh scripts/sync-origin.sh scripts/force-push.sh \
               scripts/relay-state-write.sh scripts/gaming-scan.sh scripts/profile-run.sh \
               scripts/profile-runs-batch.sh scripts/relay-burn.sh
relay_ALLOW := scripts/discover-repos.sh scripts/ckpt-tag.sh scripts/probe-fable.sh \
               scripts/gather-human-backlog.sh scripts/quota-stop.sh scripts/inject.sh \
               scripts/claim.sh scripts/sync-origin.sh scripts/force-push.sh \
               scripts/relay-state-write.sh scripts/gaming-scan.sh scripts/profile-run.sh \
               scripts/profile-runs-batch.sh scripts/relay-burn.sh
relay_LOCAL :=

# NOTE: the deprecated /fables-turn + /fables-executor alias stubs were untracked from this
# repo 2026-06-15 (migrated to /relay; no remaining cron/invocations). Their dirs are
# .gitignore'd and kept locally only as a fat-finger redirect — no longer installed by make.

projects_FILES := SKILL.md
projects_EXEC  :=
projects_ALLOW :=
projects_LOCAL :=

SETTINGS_JSON    := $(HOME)/.claude/settings.json
ALLOWLIST_SCRIPTS := $(foreach s,$(SKILLS),$(addprefix $(s)/,$($(s)_ALLOW)))

.PHONY: help install install-hooks install-statusline check-statusline-deps status-statusline uninstall-statusline \
        install-allowlist print-allowlist uninstall status test \
        $(addprefix install-,$(SKILLS)) \
        $(addprefix uninstall-,$(SKILLS)) \
        $(addprefix status-,$(SKILLS))

.DEFAULT_GOAL := help

help:
	@echo "Usage: make [TARGET]"
	@echo ""
	@echo "Targets:"
	@echo "  install              install all skills, hooks, and allowlist entries"
	@echo "  install-<skill>      install one skill"
	@echo "  install-hooks        install hooks (+ statusline) only"
	@echo "  install-statusline   install the quota/cost/model statusbar only (checks CLI deps)"
	@echo "  check-statusline-deps  warn/err on missing statusbar CLI deps (jq critical; bc/curl/... optional)"
	@echo "  print-allowlist      preview Bash allowlist entries (read-only)"
	@echo "  install-allowlist    merge allowlist entries into settings.json (idempotent)"
	@echo "  uninstall            remove symlinks for all skills (local-only files preserved)"
	@echo "  uninstall-<skill>    remove symlinks for one skill"
	@echo "  status               show symlink state for all skills"
	@echo "  test                 run the test suite (tests/run-tests.sh)"
	@echo ""
	@echo "Skills: $(SKILLS)"
	@echo ""
	@echo "Install location: $$DEST_DIR  (override: make DEST_DIR=/path install)"

install: $(addprefix install-,$(SKILLS)) install-hooks install-allowlist

test:
	@bash $(SRC_DIR)/tests/run-tests.sh

ALLOWLIST_EXTRA := $(SRC_DIR)/tools/allow-extra.txt

print-allowlist:
	@python3 $(SRC_DIR)/tools/allowlist.py --mode print \
		--home $(HOME) \
		--src-dir $(SRC_DIR) \
		--dest-dir $(DEST_DIR) \
		--settings $(SETTINGS_JSON) \
		--extra-file $(ALLOWLIST_EXTRA) \
		$(ALLOWLIST_SCRIPTS)

install-allowlist:
	@python3 $(SRC_DIR)/tools/allowlist.py --mode merge \
		--home $(HOME) \
		--src-dir $(SRC_DIR) \
		--dest-dir $(DEST_DIR) \
		--settings $(SETTINGS_JSON) \
		--extra-file $(ALLOWLIST_EXTRA) \
		$(ALLOWLIST_SCRIPTS)

install-hooks: install-statusline
	@echo "→ installing hooks"
	@mkdir -p $(HOOKS_DIR)
	@ln -sf $(SRC_DIR)/hooks/meeting-cost-logger.sh $(HOOKS_DIR)/meeting-cost-logger.sh
	@ln -sf $(SRC_DIR)/hooks/parallel-edit-detector.py $(HOOKS_DIR)/parallel-edit-detector.py
	@ln -sf $(SRC_DIR)/hooks/notify-hook.linux-x11.sh $(HOME)/.claude/notify-hook.sh

# statusline is a first-class target (mirrors install-<skill>): the quota/cost/model statusbar
# lives in this repo (statusline/) and is symlinked into ~/.claude. install-hooks depends on it
# for back-compat ("hooks + statusline"), but it can be installed/checked/removed on its own.
install-statusline:
	@echo "→ installing statusline"
	@mkdir -p $(HOME)/.claude
	@ln -sf $(SRC_DIR)/statusline/statusline-command.sh $(HOME)/.claude/statusline-command.sh
	@bash $(SRC_DIR)/statusline/check-deps.sh   # WARN on optional deps; ERROR (non-zero) on a missing CRITICAL dep

# Standalone dependency check (also run by install-statusline): WARN on optional deps that
# degrade a feature, ERROR on a missing CRITICAL dep (jq) without which the statusbar is dead.
check-statusline-deps:
	@bash $(SRC_DIR)/statusline/check-deps.sh

status-statusline:
	@echo "statusline:"
	@if [ -L $(HOME)/.claude/statusline-command.sh ]; then \
		echo "  ok  statusline-command.sh -> $$(readlink $(HOME)/.claude/statusline-command.sh)"; \
	elif [ -e $(HOME)/.claude/statusline-command.sh ]; then \
		echo "  --  statusline-command.sh (exists, not a symlink)"; \
	else \
		echo "  !!  statusline-command.sh (not installed)"; \
	fi

uninstall-statusline:
	@echo "→ removing statusline symlink"
	@[ -L $(HOME)/.claude/statusline-command.sh ] && rm $(HOME)/.claude/statusline-command.sh || true

uninstall: $(addprefix uninstall-,$(SKILLS)) uninstall-statusline

status: $(addprefix status-,$(SKILLS)) status-statusline

define SKILL_RULES

install-$(1):
	@echo "→ installing $(1)"
	@[ -L $$$$DEST_DIR/$(1) ] && rm -f $$$$DEST_DIR/$(1) || true
	@mkdir -p $$$$DEST_DIR/$(1)
	@for f in $($(1)_FILES); do \
		mkdir -p $$$$DEST_DIR/$(1)/$$$$(dirname $$$$f); \
		ln -sfn $(SRC_DIR)/$(1)/$$$$f $$$$DEST_DIR/$(1)/$$$$f; \
	done
	@for f in $($(1)_EXEC); do \
		chmod +x $(SRC_DIR)/$(1)/$$$$f; \
	done
	@for f in $($(1)_LOCAL); do \
		[ -e $$$$DEST_DIR/$(1)/$$$$f ] || touch $$$$DEST_DIR/$(1)/$$$$f; \
	done

uninstall-$(1):
	@echo "→ removing symlinks for $(1)"
	@for f in $($(1)_FILES); do \
		[ -L $$$$DEST_DIR/$(1)/$$$$f ] && rm $$$$DEST_DIR/$(1)/$$$$f || true; \
	done

status-$(1):
	@echo "$(1):"
	@trap '' PIPE; for f in $($(1)_FILES); do \
		if [ -L $$$$DEST_DIR/$(1)/$$$$f ]; then \
			echo "  ok  $$$$f -> $$$$(readlink $$$$DEST_DIR/$(1)/$$$$f)"; \
		elif [ -e $$$$DEST_DIR/$(1)/$$$$f ]; then \
			echo "  --  $$$$f (exists, not a symlink)"; \
		else \
			echo "  !!  $$$$f (not installed)"; \
		fi; \
	done || true

endef

$(foreach skill,$(SKILLS),$(eval $(call SKILL_RULES,$(skill))))
