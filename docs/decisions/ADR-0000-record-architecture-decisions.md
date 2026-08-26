# ADR-0000: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

Foldscale makes several performance- and correctness-critical decisions that are only defensible with
evidence — e.g. the file-node memory layout, the tree-view rendering backend, and the scan-cache
format (see the handoff, §7). Contributors reading the code later need to understand *why* a fork was
taken, not just *what* was chosen, so they don't relitigate settled trade-offs or regress them.

## Decision

We record every significant architectural or benchmarked decision as an **Architecture Decision
Record (ADR)** in `docs/decisions/`, numbered sequentially (`ADR-000N-title.md`).

- Each benchmarked "fork" from handoff §7 gets an ADR containing the **measured numbers** and the
  chosen option: `ADR-0001` node layout, `ADR-0002` tree-view backend, `ADR-0003` cache format.
- The PR that makes a decision links its ADR and quotes the key numbers.
- ADRs are immutable once Accepted; to change a decision, add a new ADR that supersedes the old one
  (note the supersession in both).

Format per ADR: **Context** (the forces), **Decision** (what we chose), **Consequences** (the
trade-offs we accept), and — for benchmarked forks — a **Results** table.

## Consequences

- A small, steady documentation cost per major decision.
- New contributors can understand the architecture's rationale from `docs/decisions/` alone.
- Benchmarked claims stay honest: the numbers live next to the decision they justify.
