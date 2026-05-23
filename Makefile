.PHONY: all compile clean test dialyzer xref format lint docs console check coverage

REBAR := rebar3
APP_NAME := graffeo
APP_VERSION := $(shell grep vsn src/$(APP_NAME).app.src | cut -d'"' -f2)

all: compile

compile:
	@$(REBAR) compile

clean:
	@$(REBAR) clean
	@rm -rf _build logs erl_crash.dump

test:
	@mkdir -p logs
	@$(REBAR) do eunit --cover, ct --cover, proper -c
	@$(REBAR) cover

coverage: test
	@escript scripts/check_coverage.escript

dialyzer:
	@$(REBAR) dialyzer

xref:
	@$(REBAR) xref

format:
	@$(REBAR) fmt

lint:
	@$(REBAR) lint

console:
	@$(REBAR) shell

check: clean compile xref dialyzer lint coverage
	@echo "All checks passed!"

# Testing helpers
test-unit:
	@$(REBAR) eunit

test-integration:
	@$(REBAR) ct

test-property:
	@$(REBAR) proper -c

# Coverage report
coverage-report:
	@$(REBAR) cover
	@echo "Coverage report generated in _build/test/cover/index.html"

# Static analysis
analyze: xref dialyzer lint
	@echo "Static analysis complete"

# Clean everything including deps
distclean: clean
	@rm -rf _build
	@echo "Deep clean complete"

publish:
	@echo "Publishing $(APP_NAME) v$(APP_VERSION)..."
	@$(REBAR) hex publish package

# Help
help:
	@echo "$(APP_NAME) v$(APP_VERSION) - Available targets:"
	@echo "  make compile        - Compile the project"
	@echo "  make test           - Run all tests"
	@echo "  make dialyzer       - Run Dialyzer"
	@echo "  make xref           - Run xref analysis"
	@echo "  make format         - Format code"
	@echo "  make lint           - Run linter (elvis)"
	@echo "  make console        - Start Erlang shell with app loaded"
	@echo "  make check          - Run all checks (xref, dialyzer, lint, tests)"
	@echo "  make analyze        - Run static analysis (xref, dialyzer, lint)"
	@echo "  make coverage       - Run tests and assert >=95% executable-line coverage"
	@echo "  make coverage-report - Generate coverage report"
	@echo "  make publish        - Publish to Hex"
	@echo "  make help           - Show this help message"
