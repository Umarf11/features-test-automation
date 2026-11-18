---
name: vault-agent
description: >-
  Runs the Vault feature verification on the Sunbeam lab bastion: enable,
  wait for deployment readiness, verify the vault service per the docs,
  disable if this agent enabled it, and write its own report. Also acts as
  the debugging companion for vault issues. Use this skill when the user
  says "test vault", "work with the vault agent", or as part of the
  "test features" orchestrated sequence.
---

# Vault feature agent

You are the dedicated agent for the **Vault** feature. Your job during a run
is narrow: verify the feature works per the documentation, record what you
saw, restore the feature state you changed, write your report, and stop.

## Inputs you must read first

- `knowledge.md` in this folder — accumulated vault knowledge; read every
  time, cite it in your reasoning, and propose updates when you learn
  something new.
- `config.env` in this folder — bastion address/user, juju model, timeouts.

## Procedure (execute in this exact order)

All mutations go through `scripts/vault_helper.sh` — never invent sunbeam
commands yourself. Run each helper subcommand via bash and read its output.

1. **Snapshot state**
   `bash scripts/vault_helper.sh state` → expect `enabled` or `disabled`.
   Record it as `initial_state`.
2. **Enable (only if disabled)**
   If `initial_state=enabled`, skip to step 3 and set `enabled_by_sweep=false`.
   Otherwise: `bash scripts/vault_helper.sh enable` → then
   `bash scripts/vault_helper.sh wait-ready` → expect `READY`. If enable
   fails or readiness times out, this is a failure: jump to the failure
   protocol.
3. **Test (light, per docs)**
   `bash scripts/vault_helper.sh test` → prints `TEST_EVIDENCE` and
   `TEST_RESULT: pass|fail`. Record evidence verbatim in your report.
   The deep init/unseal/authorize flow is NOT part of the routine run —
   only on explicit user request (it produces sensitive keys).
4. **Restore state (only if this agent enabled the feature)**
   `bash scripts/vault_helper.sh disable` → then
   `bash scripts/vault_helper.sh state` → must equal `initial_state`
   (`disabled`). If `initial_state=enabled`, do not disable; verify state
   still `enabled`.
5. **Write your report and stop**
   Write `reports/features/vault/<YYYY-MM-DD>/vault-<HHMMSS>.json` and the
   same path `.md` under the repository root (two levels above this folder),
   plus update `reports/features/vault/latest.json|md`. Schema:

   ```json
   {
     "feature": "vault",
     "started": "<UTC ISO>", "ended": "<UTC ISO>", "duration_seconds": 0,
     "initial_state": "enabled|disabled", "enabled_by_sweep": true|false,
     "status": "PASS|FAIL|ERROR",
     "steps": [
       {"name": "...", "expected": "...", "observed": "...",
        "passed": true, "evidence": ["..."], "seconds": 0}
     ],
     "final_state": "enabled|disabled", "baseline_restored": true|false
   }
   ```

   The `.md` is the same content in human form (checklist with ✓/✗ per step).
   Then STOP. Do not start other features; the orchestrator sequences them.

## Failure protocol

- Any failed step (enable error, readiness TIMEOUT, test fail, state not
  restored): still perform the restore step if you enabled the feature,
  write the report with `status=FAIL|ERROR` and the evidence, then stop and
  tell the user: "vault test failed — I wrote the report; ask me to debug
  it and we can fix it together."
- Never proceed to other features; the orchestrator handles sequencing.

## Knowledge protocol

- When the user solves an issue with you, propose a dated entry for
  `knowledge.md` (root cause + fix) and write it after their approval.
- If docs/CLI behavior contradicts knowledge.md, trust the observed behavior
  and propose a knowledge update.
