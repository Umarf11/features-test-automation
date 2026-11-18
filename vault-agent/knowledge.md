# Vault agent knowledge base

Accumulated knowledge about the Vault feature on this Sunbeam deployment.
Every solved issue adds a dated entry. The agent reads this file before and
during every run; update it (with the user's approval) whenever a new root
cause or workaround is confirmed.

## Facts (from docs and recon 2026-11-13)

- Feature gate key: `vault`; enable/disable via `sunbeam enable vault` /
  `sunbeam disable vault`.
- Vault is a **dependency of the Secrets feature**: per the docs, Vault should
  be enabled before Barbican.
- Docs lifecycle: Enabling Vault -> Initializing Vault -> Unsealing Vault ->
  Authorizing Vault charm -> `sunbeam vault status` -> Disabling Vault.
- The deep init/unseal/authorize flow produces sensitive unseal keys; the
  daily light test intentionally does NOT initialize Vault. Deep flow is
  only run on explicit user request and keys are discarded afterwards.
- Deployment readiness: after enable the vault app is `blocked` (awaiting
  initialization) — that is the expected light-test state; `active` only
  appears once initialized+unsealed.

## Open questions / watch-outs

- Confirm the exact `sunbeam vault status` output format on first run; if the
  subcommand is unavailable in this CLI version, fall back to juju app health.
- Disable semantics for vault may leave apps in the model (same pattern as
  telemetry/orchestration docs) — the feature gate state is the source of
  truth, lingering apps are sunbeam-managed.

## Solved issues

### 2026-11-18 — vault lifecycle commands verified on the single-node deployment

- Init: `sunbeam vault init 1 1 -f json` (1 share, threshold 1 — minimal
  test config) → JSON with `unseal_keys_b64`, `recovery_keys_*`,
  `root_token`.
- Unseal: `sunbeam vault unseal <unseal_keys_b64[0]>` → "completed".
- Authorize: `sunbeam vault authorize-charm <root_token>` → "Vault charm is
  authorized."
- After unseal: vault/0 → Initialized=True, Sealed=False, juju `active`.
- Keys/tokens are ephemeral for test runs: hold in a remote /tmp file
  (0600), use, then delete — never print raw, never commit.
- **Secrets dependency quirk**: `sunbeam enable secrets` fails with
  "Cannot enable secrets as Vault is not active" if vault is enabled but
  uninitialized — the dependency requires an ACTIVE vault, which is why
  this agent's `init` flow may be invoked by the secrets agent path.

### 2026-11-18 — vault goes "blocked" after enable; light test must not require "active"

**Observed:** right after `sunbeam enable vault`, the vault application is
`blocked` with message "Please initialize Vault or integrate with an
auto-unseal provider". The original light test required `active` and the
readiness wait timed out after 600 s.

**Root cause:** this is the documented lifecycle, not a failure — Vault is
unusable until initialized+unsealed (Enabling → Initializing → Unsealing).
An *uninitialized* vault stays `blocked` by design.

**Fix:** light test readiness and pass criteria now accept
`active` OR `blocked` (with the initialize message) as the expected
post-enable state; `sunbeam vault status` responding with the unit table
(vault/0: Initialized=False, Sealed=True pre-init) is the real check.
Recorded on first live run against the single-node deployment (vibrava).
