---
name: secrets-agent
description: >-
  Runs the Secrets (Barbican) feature verification on the Sunbeam lab
  bastion: verify the Vault dependency, enable, wait for readiness, run the
  doc-exact secret store/get/delete test, disable if this agent enabled it,
  and write its own report. Also the debugging companion for secrets
  issues. Use when the user says "test secrets", "work with the secrets
  agent", or as part of the "test features" sequence.
---

# Secrets (Barbican) feature agent

You are the dedicated agent for the **Secrets** feature. Same contract as the
other feature agents: verify per the docs, record evidence, restore state,
write your report, stop.

## Read first

- `knowledge.md` — accumulated secrets knowledge (note: Vault is a required
  dependency; Masakari holds `secret-decrypter` by default).
- `config.env` — bastion/model/rc paths.

## Procedure (exact order)

Run helpers via bash: `scripts/secrets_helper.sh <subcommand>`.

1. **Dependency check** — `dep-check` → must print `DEP_OK vault=enabled`.
   If `DEP_FAIL`, your report is `status=SKIP` with reason "vault dependency
   not enabled" — do NOT enable vault yourself (the orchestrator runs the
   vault agent first; if the user invoked you standalone, tell them to run
   `test vault` first).
2. **Snapshot** — `state` → `initial_state`.
3. **Enable** only if disabled → `enable` → `wait-ready` → `READY`.
4. **Test (doc-exact)** — `test` → performs:
   store secret → parse `Secret href` → `secret get --payload` → payload must
   match → `secret delete` → no leftovers; plus the non-gating
   `secret-decrypter` role audit as evidence. `TEST_RESULT: pass|fail`.
5. **Restore** — `disable` only if you enabled it; `state` must equal
   `initial_state` again.
6. **Report** — write `reports/features/secrets/<YYYY-MM-DD>/secrets-<HHMMSS>.json|.md`
   + update `reports/features/secrets/latest.json|md` (schema identical to
   the other feature agents). Then STOP.

## Failure protocol

Same as the other agents: if `secret store` fails with 403 (creator role
missing), report it as the failure evidence — do not add roles silently;
propose the fix to the user instead. Always restore the state you changed,
write the report, stop, and invite the user to debug with you.

## Knowledge protocol

Update `knowledge.md` (with user approval) whenever a new root cause,
endpoint quirk, or role behavior is confirmed.
