SRC_DIR  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEST_DIR := $(HOME)/.claude/skills
export DEST_DIR

SKILLS := meeting meeting-cross git-diary-workflow todo-update

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

SETTINGS_JSON    := $(HOME)/.claude/settings.json
ALLOWLIST_SCRIPTS := $(foreach s,$(SKILLS),$(addprefix $(s)/,$($(s)_ALLOW)))

.PHONY: help install install-hooks install-allowlist print-allowlist uninstall status \
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
	@echo "  install-hooks        install hooks only"
	@echo "  print-allowlist      preview Bash allowlist entries (read-only)"
	@echo "  install-allowlist    merge allowlist entries into settings.json (idempotent)"
	@echo "  uninstall            remove symlinks for all skills (local-only files preserved)"
	@echo "  uninstall-<skill>    remove symlinks for one skill"
	@echo "  status               show symlink state for all skills"
	@echo ""
	@echo "Skills: $(SKILLS)"
	@echo ""
	@echo "Install location: $$DEST_DIR  (override: make DEST_DIR=/path install)"

install: $(addprefix install-,$(SKILLS)) install-hooks install-allowlist

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

install-hooks:
	@echo "→ installing hooks"
	@mkdir -p $(HOOKS_DIR)
	@ln -sf $(SRC_DIR)/hooks/meeting-cost-logger.sh $(HOOKS_DIR)/meeting-cost-logger.sh
	@ln -sf $(SRC_DIR)/hooks/parallel-edit-detector.py $(HOOKS_DIR)/parallel-edit-detector.py
	@ln -sf $(SRC_DIR)/hooks/notify-hook.linux-x11.sh $(HOME)/.claude/notify-hook.sh

uninstall: $(addprefix uninstall-,$(SKILLS))

status: $(addprefix status-,$(SKILLS))

define SKILL_RULES

install-$(1):
	@echo "→ installing $(1)"
	@mkdir -p $$$$DEST_DIR/$(1)
	@for f in $($(1)_FILES); do \
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
	@for f in $($(1)_FILES); do \
		if [ -L $$$$DEST_DIR/$(1)/$$$$f ]; then \
			echo "  ok  $$$$f -> $$$$(readlink $$$$DEST_DIR/$(1)/$$$$f)"; \
		elif [ -e $$$$DEST_DIR/$(1)/$$$$f ]; then \
			echo "  --  $$$$f (exists, not a symlink)"; \
		else \
			echo "  !!  $$$$f (not installed)"; \
		fi; \
	done

endef

$(foreach skill,$(SKILLS),$(eval $(call SKILL_RULES,$(skill))))
