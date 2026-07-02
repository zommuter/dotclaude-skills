SRC_DIR  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEST_DIR := $(HOME)/.claude/skills
export DEST_DIR

SKILLS := meeting meeting-cross git-diary-workflow todo-update relay projects

HOOKS_DIR := $(HOME)/.claude/hooks

meeting_FILES := SKILL.md format.md personas.md broker-mode.md cross-mode.md append.sh cost-of.sh \
                 find-todos.sh orphan-scan.sh broker-curl.sh broker.py profile-active.sh \
                 persona-state.py retrieve-top-k.py md-merge.py gh-audit.sh classify.sh \
                 memory-append.sh
meeting_EXEC  := append.sh cost-of.sh find-todos.sh orphan-scan.sh broker-curl.sh broker.py profile-active.sh \
                 persona-state.py retrieve-top-k.py md-merge.py gh-audit.sh classify.sh \
                 memory-append.sh
meeting_ALLOW := append.sh cost-of.sh find-todos.sh orphan-scan.sh broker-curl.sh profile-active.sh \
                 persona-state.py retrieve-top-k.py md-merge.py gh-audit.sh classify.sh \
                 memory-append.sh
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
               references/executor-contract.md references/hard-lanes.md \
               references/resource-claims.md references/todo-conversion-policies.md \
               references/recipe-manifest.md \
               scripts/discover-repos.sh scripts/ckpt-tag.sh scripts/probe-fable.sh \
               scripts/gather-human-backlog.sh scripts/quota-stop.sh \
               scripts/relay-loop.js scripts/inject.sh scripts/claim.sh \
               scripts/heartbeat.sh \
               scripts/sync-origin.sh scripts/clean-tree-gate.sh scripts/force-push.sh \
               scripts/relay-state-write.sh \
               scripts/gaming-scan.sh scripts/profile-run.sh scripts/profile-runs-batch.sh \
               scripts/relay-burn.sh scripts/relay-econ.py scripts/relay-reconcile.sh \
               scripts/loop-hint.sh scripts/discover-sig.sh scripts/migrate-state-dirs.sh \
               scripts/relay-status-publish.sh scripts/gather-repo-state.sh \
               scripts/handback-followup.py scripts/roadmap-archive.sh \
               scripts/roadmap-lint.sh scripts/redispatch-guard.mjs scripts/pool-args.mjs scripts/drain.mjs \
               scripts/relay-doctor.sh scripts/lint-workflow-templates.mjs \
               scripts/commit-ledger.sh scripts/acquire-resource.sh \
               scripts/unpromoted-scan.sh scripts/todo-conformance.sh \
               scripts/scan-routed.sh scripts/host-gate.sh scripts/recipe-validate.sh \
               scripts/classify-verdict.sh scripts/classify-repo.sh scripts/reconcile-repo.sh scripts/discover-repo.sh scripts/backtest-verdict.py \
               scripts/backtest-historical.py \
               scripts/decision-queue.sh scripts/resource-probe.sh \
               scripts/file-surface-decisions.sh scripts/stop-sentinel.sh \
               scripts/relay-intensity.sh scripts/mechanical-daemon.sh
relay_EXEC  := scripts/discover-repos.sh scripts/ckpt-tag.sh scripts/probe-fable.sh \
               scripts/gather-human-backlog.sh scripts/quota-stop.sh scripts/inject.sh \
               scripts/claim.sh scripts/heartbeat.sh scripts/sync-origin.sh scripts/clean-tree-gate.sh \
               scripts/force-push.sh \
               scripts/relay-state-write.sh scripts/gaming-scan.sh scripts/profile-run.sh \
               scripts/profile-runs-batch.sh scripts/relay-burn.sh scripts/relay-econ.py \
               scripts/relay-reconcile.sh scripts/loop-hint.sh scripts/discover-sig.sh \
               scripts/migrate-state-dirs.sh scripts/relay-status-publish.sh \
               scripts/gather-repo-state.sh scripts/roadmap-archive.sh \
               scripts/roadmap-lint.sh scripts/relay-doctor.sh \
               scripts/lint-workflow-templates.mjs scripts/commit-ledger.sh \
               scripts/acquire-resource.sh scripts/unpromoted-scan.sh \
               scripts/todo-conformance.sh scripts/scan-routed.sh \
               scripts/host-gate.sh scripts/recipe-validate.sh scripts/classify-verdict.sh scripts/classify-repo.sh scripts/reconcile-repo.sh scripts/discover-repo.sh scripts/backtest-verdict.py \
               scripts/backtest-historical.py \
               scripts/decision-queue.sh scripts/resource-probe.sh \
               scripts/file-surface-decisions.sh scripts/stop-sentinel.sh \
               scripts/relay-intensity.sh scripts/mechanical-daemon.sh
relay_ALLOW := scripts/discover-repos.sh scripts/ckpt-tag.sh scripts/probe-fable.sh \
               scripts/gather-human-backlog.sh scripts/quota-stop.sh scripts/inject.sh \
               scripts/claim.sh scripts/heartbeat.sh scripts/sync-origin.sh scripts/clean-tree-gate.sh \
               scripts/force-push.sh \
               scripts/relay-state-write.sh scripts/gaming-scan.sh scripts/profile-run.sh \
               scripts/profile-runs-batch.sh scripts/relay-burn.sh scripts/relay-econ.py \
               scripts/relay-reconcile.sh scripts/loop-hint.sh scripts/discover-sig.sh \
               scripts/migrate-state-dirs.sh scripts/relay-status-publish.sh \
               scripts/gather-repo-state.sh scripts/roadmap-archive.sh \
               scripts/roadmap-lint.sh scripts/relay-doctor.sh \
               scripts/lint-workflow-templates.mjs scripts/commit-ledger.sh \
               scripts/acquire-resource.sh scripts/unpromoted-scan.sh \
               scripts/todo-conformance.sh scripts/scan-routed.sh \
               scripts/host-gate.sh scripts/recipe-validate.sh scripts/classify-verdict.sh scripts/classify-repo.sh scripts/reconcile-repo.sh scripts/discover-repo.sh scripts/backtest-verdict.py \
               scripts/backtest-historical.py \
               scripts/decision-queue.sh scripts/resource-probe.sh \
               scripts/file-surface-decisions.sh scripts/stop-sentinel.sh \
               scripts/relay-intensity.sh scripts/mechanical-daemon.sh
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
        install-allowlist print-allowlist install-relay-env print-relay-env uninstall status test gaming-canary shard-canary \
        install-quota-timer status-quota-timer uninstall-quota-timer \
        install-relay-watchdog status-relay-watchdog uninstall-relay-watchdog \
        install-mechanical-daemon status-mechanical-daemon uninstall-mechanical-daemon \
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
	@echo "  install-quota-timer  install the 15-min usage-quota sampler systemd user timer"
	@echo "  install-relay-watchdog install the relay outage watchdog systemd user timer (notify on a dead loop)"
	@echo "  install-mechanical-daemon install the mechanical-run daemon systemd user path+service unit (id:b3d0)"
	@echo "  check-statusline-deps  warn/err on missing statusbar CLI deps (jq critical; bc/curl/... optional)"
	@echo "  print-allowlist      preview Bash allowlist entries (read-only)"
	@echo "  install-allowlist    merge allowlist entries into settings.json (idempotent)"
	@echo "  install-relay-env    merge relay env policy (quota decay) into settings.json (idempotent)"
	@echo "  print-relay-env      preview the relay env policy entries (read-only)"
	@echo "  uninstall            remove symlinks for all skills (local-only files preserved)"
	@echo "  uninstall-<skill>    remove symlinks for one skill"
	@echo "  status               show symlink state for all skills"
	@echo "  test                 run the test suite (tests/run-tests.sh)"
	@echo "  gaming-canary        Tier B model anti-gaming canary harness (on-demand; costs tokens)"
	@echo "  shard-canary         discover-shard classifier behavior canary (on-demand; costs tokens)"
	@echo ""
	@echo "Skills: $(SKILLS)"
	@echo ""
	@echo "Install location: $$DEST_DIR  (override: make DEST_DIR=/path install)"

install: $(addprefix install-,$(SKILLS)) install-hooks install-allowlist install-relay-env

# Relay fleet env policy → settings.json (idempotent, like install-allowlist). settings.json
# is PER-MACHINE (not synced — each machine's ~/.claude is its own branch), so this SHARED repo
# is the source of truth and `make install` applies it on each machine. RELAY_QUOTA_DECAY_7D
# = strict-proportional time-decaying 7d quota cap (front-load early, taper to ~8% near reset),
# so a self-looping --afk pool can't blow the weekly budget on day 1 (user policy 2026-06-16).
RELAY_ENV_DEFAULTS := RELAY_QUOTA_DECAY_7D=0.30:0.08

install-relay-env:
	@python3 $(SRC_DIR)/tools/settings-env.py --settings $(SETTINGS_JSON) $(RELAY_ENV_DEFAULTS)

print-relay-env:
	@python3 $(SRC_DIR)/tools/settings-env.py --mode print --settings $(SETTINGS_JSON) $(RELAY_ENV_DEFAULTS)

test:
	@bash $(SRC_DIR)/tests/run-tests.sh

# Tier B model canary harness (id:414a) — on-demand, costs tokens, NOT in `make test`.
# Verifies the review procedure's JUDGMENT anti-gaming checks (resurrection-rewrite,
# fixture-special-casing) fire, with a negative control. Override the agent with
# CANARY_AGENT=... for a token-free plumbing smoke test (see tests/gaming-canary/README.md).
gaming-canary:
	@bash $(SRC_DIR)/tests/gaming-canary/run.sh

# id:3ea3 — discover-shard classifier behavior canary. On-demand (spawns a real
# classifier agent, costs tokens); use it to prove a thinned shard prompt preserves
# verdicts. Plumbing is guarded zero-token by tests/test_shard_canary.sh.
shard-canary:
	@bash $(SRC_DIR)/tests/shard-canary/run.sh

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
	@ln -sf $(SRC_DIR)/hooks/pathspec-drop-guard.py $(HOOKS_DIR)/pathspec-drop-guard.py
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

# Quota sampler: a systemd USER timer (15 min) that records Claude usage-limit
# utilization into a git-versioned JSONL, so an idle quota spike (cf. 2026-06-18) is
# captured for forensics/visualization. Units are symlinked from this repo into
# ~/.config/systemd/user/ (mem-logger pattern); the data lands in ~/src/claude-diary/quota/.
SYSTEMD_USER := $(HOME)/.config/systemd/user
install-quota-timer:
	@echo "→ installing quota-sample timer"
	@mkdir -p $(SYSTEMD_USER)
	@ln -sf $(SRC_DIR)/tools/quota-sample.service $(SYSTEMD_USER)/quota-sample.service
	@ln -sf $(SRC_DIR)/tools/quota-sample.timer   $(SYSTEMD_USER)/quota-sample.timer
	@systemctl --user daemon-reload
	@systemctl --user enable --now quota-sample.timer
	@echo "  enabled. next runs: systemctl --user list-timers quota-sample.timer"

status-quota-timer:
	@echo "quota-sample.timer:"
	@if [ -L $(SYSTEMD_USER)/quota-sample.timer ]; then \
		systemctl --user is-active quota-sample.timer >/dev/null 2>&1 \
			&& echo "  ok  active -> $$(readlink $(SYSTEMD_USER)/quota-sample.timer)" \
			|| echo "  --  installed but not active (systemctl --user enable --now quota-sample.timer)"; \
	else echo "  !!  not installed (make install-quota-timer)"; fi

uninstall-quota-timer:
	@echo "→ removing quota-sample timer"
	@systemctl --user disable --now quota-sample.timer 2>/dev/null || true
	@rm -f $(SYSTEMD_USER)/quota-sample.timer $(SYSTEMD_USER)/quota-sample.service
	@systemctl --user daemon-reload 2>/dev/null || true

# Relay outage watchdog (id:98f0) — same --user-timer pattern. Detects a dead relay loop via the
# shared run-heartbeat (id:e149) and NOTIFIES (no claude -p, no permission wall). import-environment
# makes the graphical session bus available so notify-send works; for off-host push instead, set
# RELAY_WATCHDOG_NOTIFY_CMD in the unit's environment.
install-relay-watchdog:
	@echo "→ installing relay-watchdog timer"
	@mkdir -p $(SYSTEMD_USER)
	@ln -sf $(SRC_DIR)/tools/relay-watchdog.service $(SYSTEMD_USER)/relay-watchdog.service
	@ln -sf $(SRC_DIR)/tools/relay-watchdog.timer   $(SYSTEMD_USER)/relay-watchdog.timer
	@systemctl --user import-environment DISPLAY DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
	@systemctl --user daemon-reload
	@systemctl --user enable --now relay-watchdog.timer
	@echo "  enabled. next runs: systemctl --user list-timers relay-watchdog.timer"

status-relay-watchdog:
	@echo "relay-watchdog.timer:"
	@if [ -L $(SYSTEMD_USER)/relay-watchdog.timer ]; then \
		systemctl --user is-active relay-watchdog.timer >/dev/null 2>&1 \
			&& echo "  ok  active -> $$(readlink $(SYSTEMD_USER)/relay-watchdog.timer)" \
			|| echo "  --  installed but not active (systemctl --user enable --now relay-watchdog.timer)"; \
	else echo "  !!  not installed (make install-relay-watchdog)"; fi

uninstall-relay-watchdog:
	@echo "→ removing relay-watchdog timer"
	@systemctl --user disable --now relay-watchdog.timer 2>/dev/null || true
	@rm -f $(SYSTEMD_USER)/relay-watchdog.timer $(SYSTEMD_USER)/relay-watchdog.service
	@systemctl --user daemon-reload 2>/dev/null || true

# Mechanical-run daemon (id:b3d0) — same --user-unit pattern, but a .path unit (not a
# .timer): the oneshot service fires on writes to the recipe pending/ drop-dir instead of
# polling. Runs relay-authored recipes OUTSIDE the Workflow (pure mechanical script -> no
# permission wall). See relay/scripts/mechanical-daemon.sh + recipe-manifest.md.
install-mechanical-daemon:
	@echo "→ installing mechanical-daemon path+service unit"
	@mkdir -p $(SYSTEMD_USER) $(HOME)/.config/relay/recipes/pending $(HOME)/.config/relay/recipes/running $(HOME)/.config/relay/recipes/done
	@ln -sf $(SRC_DIR)/tools/mechanical-daemon.path    $(SYSTEMD_USER)/mechanical-daemon.path
	@ln -sf $(SRC_DIR)/tools/mechanical-daemon.service  $(SYSTEMD_USER)/mechanical-daemon.service
	@systemctl --user daemon-reload
	@systemctl --user enable --now mechanical-daemon.path
	@echo "  enabled. status: systemctl --user status mechanical-daemon.path"

status-mechanical-daemon:
	@echo "mechanical-daemon.path:"
	@if [ -L $(SYSTEMD_USER)/mechanical-daemon.path ]; then \
		systemctl --user is-active mechanical-daemon.path >/dev/null 2>&1 \
			&& echo "  ok  active -> $$(readlink $(SYSTEMD_USER)/mechanical-daemon.path)" \
			|| echo "  --  installed but not active (systemctl --user enable --now mechanical-daemon.path)"; \
	else echo "  !!  not installed (make install-mechanical-daemon)"; fi

uninstall-mechanical-daemon:
	@echo "→ removing mechanical-daemon path+service unit"
	@systemctl --user disable --now mechanical-daemon.path 2>/dev/null || true
	@rm -f $(SYSTEMD_USER)/mechanical-daemon.path $(SYSTEMD_USER)/mechanical-daemon.service
	@systemctl --user daemon-reload 2>/dev/null || true

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
