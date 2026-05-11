SRC_DIR  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEST_DIR := $(HOME)/.claude/skills
export DEST_DIR

SKILLS := meeting git-diary-workflow

meeting_FILES := SKILL.md format.md personas.md append.sh cost-of.sh
meeting_EXEC  := append.sh cost-of.sh
meeting_LOCAL := discoveries.md user-profile.md

git-diary-workflow_FILES := SKILL.md diary-append.sh git-lock-push.sh
git-diary-workflow_EXEC  := diary-append.sh git-lock-push.sh
git-diary-workflow_LOCAL :=

.PHONY: help install uninstall status \
        $(addprefix install-,$(SKILLS)) \
        $(addprefix uninstall-,$(SKILLS)) \
        $(addprefix status-,$(SKILLS))

.DEFAULT_GOAL := help

help:
	@echo "Usage: make [TARGET]"
	@echo ""
	@echo "Targets:"
	@echo "  install              install all skills"
	@echo "  install-<skill>      install one skill"
	@echo "  uninstall            remove symlinks for all skills (local-only files preserved)"
	@echo "  uninstall-<skill>    remove symlinks for one skill"
	@echo "  status               show symlink state for all skills"
	@echo ""
	@echo "Skills: $(SKILLS)"
	@echo ""
	@echo "Install location: $$DEST_DIR  (override: make DEST_DIR=/path install)"

install: $(addprefix install-,$(SKILLS))

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
