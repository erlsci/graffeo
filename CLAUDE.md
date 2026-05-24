# CLAUDE.md — graffeo

Standing instructions for Claude (including Claude Code / "CC") working in this
repository. Auto-loaded each session. Keep it short; keep it followed.

## What graffeo is

graffeo is an Erlang graph library: it wraps the stdlib `digraph` / `digraph_utils`
modules and carries them toward petgraph-level "batteries included" — weighted
shortest paths (Dijkstra, A\*), composable traversal, and richer connectivity. Two
commitments shape it: **one algorithm layer over many backends** — algorithms are
written once against a read-half *behaviour* (`graffeo_backend`) and run over any
backend that satisfies it — and **two tiers faithful to Erlang's value/handle
split**: a default immutable, map-backed value tier (`graffeo_map`) and a mutable
`digraph`/ETS handle tier (`graffeo_digraph`), with a `dets` on-disk tier on the
roadmap. The `graffeo` façade is the public surface; algorithms live behind it in
domain modules (`graffeo_path`, `graffeo_conn`, `graffeo_traverse`). graffeo models
*simple* directed graphs — at most one edge per ordered pair.

## House style — load this first

Before writing or reviewing Erlang, read **`priv/ai/erlang/SKILL.md`** and follow
its own loading instructions (it indexes `priv/ai/erlang/guides/`).

## Locked decisions

- **Coverage gate:** **95%** of executable lines, enforced by `make coverage`
  (`scripts/check_coverage.escript` merges eunit + ct + proper coverdata and exits
  non-zero below threshold). **Per-module, not just aggregate:** a module may not
  lean on a high-coverage sibling to clear an aggregate line. **"Unreachable"
  requires line-level proof** that the code cannot be driven from any test;
  *"we didn't write the test yet"* is **covered** (write it), and *"this function
  is dead"* is **deleted** (dead code hides bugs). A genuine ceiling is closed by a
  **raised amendment that names the exact uncovered lines**, never a blanket sub-95
  `done`.
- **Error handling:** validate at the edge, crash in the interior. The public
  surface uses tagged returns — `{ok, _}` / `{error, _}` for graffeo-native
  functions, and the stdlib's own shapes (`false` / `none` / `[]`) for faithfully
  ported `digraph` / `digraph_utils` functions. No defensive `try/catch` that
  swallows bugs; let supervised callers see the crash.
- **Release discipline:** SemVer + published release notes (GitHub releases) + the
  git history. **No hand-maintained `CHANGELOG`** — it's a holdover from before
  queryable version control; the git log and published release notes cover it. Don't
  write a CHANGELOG requirement into ledgers or docs checklists.

## How we work (process rigour)

Two roles. **CC** implements and self-assesses. **CDC** (a separate context /
reviewer) independently verifies — re-running Verify commands and reading diffs,
not summaries. The implementer does not mark its own work verified.

Every milestone has a **ledger**: the contract of what "done" means, one row per
acceptance criterion with a grep/test-verifiable Verify command. Read
**`priv/ai/LEDGER_DISCIPLINE.md`** and the relevant spec, ledger file, and/or prompt **before writing code**. Then:

- Work against the prompt's ledger. Update each row's `Status`/`Evidence` (commit SHA +
  Verify output) in the commit that closes it.
- If a criterion is wrong, impossible, or needs a later milestone, **raise an
  amendment** — never silently work around it.
- Closing report = a **per-row walk**: a final disposition for every row
  (`done`+evidence / `deferred`+reason+re-entry / `no-op`+rationale). No prose
  summaries; never "deviations: none". Name uncertainty.
- **Iteration cap: 5** per milestone.

Write to the floor, not the ceiling: state what the work actually achieves, name
what is not done, and distinguish "verified by running X" from "I believe X".

## Subagent Delegation Policy

(full text: `priv/ai/SUBAGENT-DELEGATION-POLICY.md`)

- **Do not delegate thinking work to subagents** — code edits, design/architecture
  decisions, tradeoff reasoning, judging whether a finding is real, planning,
  evaluating correctness.
- **Subagents are for lookup only** — finding files/symbols, grepping, reading a
  file, fetching docs: retrieval that needs no judgment about the result.
- Serial on thinking (main context); parallel on lookup. Quality over wall-clock
  on the thinking path.

## Collaboration posture

Peer frame: equal contributors, mutual intellectual humility, honest engagement
over agreeable hedging. Being corrected is a contribution, not a defeat. See
`priv/ai/AI-CONSTITUTION-SUPPLEMENT.md` and `priv/ai/AI-ENGINEERING-METHODOLOGY.md`.

## Before submitting

- [ ] `rebar3 compile` clean, **zero warnings**.
- [ ] `rebar3 xref` clean.
- [ ] `rebar3 eunit` + Common Test green; PropEr properties pass where defined.
- [ ] `rebar3 dialyzer` clean.
- [ ] `make coverage` passes (**≥95%** executable lines via `scripts/check_coverage.escript`).
- [ ] Ledger rows updated with evidence; per-row closing report written.
- [ ] Self-reviewed against the Erlang skill (`priv/ai/erlang/SKILL.md`).
