---
name: test-features
description: >-
  Orchestrator for the Sunbeam feature-testing agents. Use this skill when
  the user says "test features" — it runs each feature agent (vault,
  secrets, orchestration, telemetry) SEQUENTIALLY: the currently-testing
  feature's agent does its work, writes its own report, stops, then the
  next agent starts. It stops the whole sequence at the first failed
  feature (fail-fast) and tells the user which agent to work with. Also
  use when the user says "report feature" — that shows the output of the
  latest test run instead of running anything.
---

# test-features — orchestrator of the feature agents

You are the orchestrator. You do NOT run feature steps yourself; you run
the four feature agents one at a time, in order, and aggregate their
reports. Each agent has its own skill in this repository:
`vault-agent`, `secrets-agent`, `orchestration-agent`, `telemetry-agent`.

## Reading "test features" (the run mode)

Execute this protocol exactly, in order:

1. **Run the feature agents sequentially.** For each feature in
   `test-features/config.json` `feature_order` (vault → secrets →
   orchestration → telemetry):
   - Load that agent's SKILL.md and execute its procedure **as that agent**,
     writing its own per-feature report.
   - The agent must respect its failure protocol: if it fails, it restores
     the state it changed, writes its report, and returns a failing result.
   - After the agent finishes, read its per-feature report and record the
     outcome.
2. **Fail-fast rule.** As soon as an agent reports `FAIL` or `ERROR`:
   - Do NOT start the next agent.
   - Mark every remaining feature as `SKIPPED` with reason
     `"not tested — sequence stopped after <feature> failure"`.
   - Write the partial summary immediately and tell the user:
     "<feature> failed — I wrote the report; say 'work with the <feature>
     agent' and we will debug it together. Re-run 'test features' afterwards
     (always a full re-run)."
   - Note: SKIP-worthy conditions an agent itself reports (e.g. locked
     feature gate, missing dependency) do NOT fail the sequence — they are
     recorded as SKIP and the sequence continues.
3. **Write the summary report** after the last agent or a fail-fast stop:
   - `reports/features/<YYYY-MM-DD>/summary-<HHMMSS>.json|.md`
   - `reports/features/latest.json|md` (copy of the newest summary)
   - Paths are relative to the repository root (two levels above this
     skill folder). Schema:

   ```json
   {
     "kind": "features-summary",
     "started": "<UTC ISO>", "ended": "<UTC ISO>", "duration_seconds": 0,
     "status": "completed|stopped_on_failure",
     "features": [
       {"feature": "vault", "status": "PASS|FAIL|ERROR|SKIP",
        "report_path": "reports/features/vault/<date>/vault-<ts>.json",
        "reason": "…"}
     ],
     "environment_restored": true
   }
   ```

   The `.md` renders the same as a checklist: one line per feature
   (✅/❌/⏭️ + status + duration + one-line reason), plus pointers to each
   per-feature report.

## Reading "report feature" (the report mode)

Do not run anything. Find the newest summary:
`reports/features/latest.md` (or `latest.json`). Print its content and
point the user to the per-feature reports it references. If no report
exists yet, say so and offer to run `test features`.

## Rules

- Never run feature steps yourself — always through the feature agents'
  skills and their helper scripts.
- Never disable a feature that was already enabled before the run (the
  agents enforce this; you enforce it across the sequence).
- One failure stops the sequence (fail-fast). A full re-run always tests
  all features again — there is no resume memory.
- Daily automation is intentionally NOT scheduled yet (owner decision);
  do not install cron unless the user asks.
