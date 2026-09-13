# MD Reader — local CI/CD entry points. Run `make help`.
SHELL := /bin/zsh
DD    := build/DerivedData
APP   := build/MD Reader.app
SCHEME := MDReader

.PHONY: help gen build test smoke ci install release bump hooks clean

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-10s\033[0m %s\n",$$1,$$2}'

gen: ## regenerate MDReader.xcodeproj from project.yml
	xcodegen generate >/dev/null

build: gen ## Debug build
	set -o pipefail; xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DD) build 2>&1 | Scripts/xcfilter.sh

test: gen ## unit tests (XCTest)
	set -o pipefail; xcodebuild -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DD) test 2>&1 | Scripts/xcfilter.sh

smoke: ## launch the Debug app with a sample, verify it renders, quit
	Scripts/smoke.sh "$(DD)/Build/Products/Debug/MD Reader.app"

ci: build test smoke ## everything the pre-push hook runs
	@echo "✔ CI green"

install: ## Release build → /Applications
	Scripts/build.sh --install

release: ## sign, notarize, publish GitHub release + cask (needs clean tree)
	Scripts/release.sh --publish

bump: ## bump version: make bump V=0.2.0
	Scripts/bump.sh $(V)

hooks: ## enable git hooks in .githooks
	git config core.hooksPath .githooks
	@echo "hooks enabled (pre-push runs make ci)"

clean: ## remove build products
	rm -rf build
