.PHONY: all compile fetch-cards example example-check oracle-build oracle-gen help

REBAR := rebar3
CARDS_DIR := ../../workbench/ai-engineering
CARDS_REPO := https://github.com/billosys/ai-engineering.git
CARDS_TAG := 0.1.0

all: compile

compile:
	@$(REBAR) compile

fetch-cards:
	@if [ -d "$(CARDS_DIR)" ]; then \
		echo "$(CARDS_DIR) already present; skipping clone."; \
	else \
		git clone --depth 1 --branch $(CARDS_TAG) $(CARDS_REPO) $(CARDS_DIR); \
	fi

example: fetch-cards compile
	@erl -noshell -pa _build/default/lib/*/ebin -eval 'erlc:main([]), halt().'

example-check: fetch-cards compile
	@$(REBAR) eunit --module=erlc_oracle_tests

oracle-build:
	@cd oracle && cargo build --release

oracle-gen: oracle-build fetch-cards
	@oracle/target/release/oracle $(CARDS_DIR)/knowledge/erlang/concept-cards > oracle/expected.json

help:
	@echo "erlang-concepts example — Available targets:"
	@echo "  make compile        - Compile the example project"
	@echo "  make fetch-cards    - Shallow-clone the concept-cards corpus"
	@echo "  make example        - Build and run the example query catalog"
	@echo "  make example-check  - Run the oracle-parity gate"
	@echo "  make oracle-build   - Build the Rust oracle binary"
	@echo "  make oracle-gen     - Regenerate oracle/expected.json"
	@echo "  make help           - Show this help message"
