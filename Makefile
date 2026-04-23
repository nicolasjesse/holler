# Holler — common development tasks
#
# Quick start:
#   make install     # one-shot install (system deps + venv + desktop entry)
#   make run         # run Holler in the foreground
#   make dev         # install dev dependencies (ruff, pytest)
#   make lint        # ruff check + format check
#   make fix         # ruff --fix + format (auto-apply safe edits)
#   make test        # pytest (will skip gracefully if tests/ is empty)
#   make service     # install systemd --user unit (auto-start on login)
#   make uninstall   # remove venv, service, desktop entry

.DEFAULT_GOAL := help

VENV      := .env
PY        := $(VENV)/bin/python
PIP       := $(VENV)/bin/python -m pip
RUFF      := $(VENV)/bin/python -m ruff
PYTEST    := $(VENV)/bin/python -m pytest

.PHONY: help install dev run lint format fix test clean service uninstall venv

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nHoller — Makefile targets\n\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo

##@ Install

install: ## Run install.sh (system deps, venv, desktop entry, optional service)
	@./install.sh

venv: ## Create the .env virtualenv if it doesn't exist
	@test -d $(VENV) || python3 -m venv $(VENV)
	@$(PIP) install --quiet --upgrade pip

dev: venv ## Install dev dependencies (ruff, pytest) into the venv
	@$(PIP) install --quiet -e ".[dev]"
	@echo "Dev deps installed."

##@ Run

run: venv ## Run Holler in the foreground
	@$(PY) run.py

##@ Quality

lint: dev ## Ruff check + format check (no changes)
	@$(RUFF) check .
	@$(RUFF) format --check .

fix: dev ## Auto-fix with ruff (safe fixes + reformat)
	@$(RUFF) check --fix .
	@$(RUFF) format .

format: dev ## Reformat with ruff (no lint changes)
	@$(RUFF) format .

test: dev ## Run pytest (skips if no tests/ dir)
	@if [ -d tests ]; then \
		$(PYTEST) -m "not integration and not gui and not audio"; \
	else \
		echo "No tests/ directory yet — skipping."; \
	fi

##@ Service

service: ## Install systemd --user unit so Holler starts on login
	@./install.sh --no-dotool --yes || true
	@echo "If the service isn't running yet, run:"
	@echo "  systemctl --user start holler"

service-logs: ## Follow the systemd service logs
	@journalctl --user -u holler -f

##@ Uninstall / clean

clean: ## Remove venv + caches
	@rm -rf $(VENV) build dist *.egg-info
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned."

uninstall: ## Remove venv, systemd service, desktop entry (config.json is preserved)
	@./uninstall.sh
