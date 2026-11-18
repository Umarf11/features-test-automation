# Secrets (Barbican) agent knowledge base

Accumulated knowledge about the Secrets feature on this Sunbeam deployment.

## Facts (from docs and recon 2026-11-13)

- Feature gate key: `secrets`; enable/disable via
  `sunbeam enable secrets` / `sunbeam disable secrets`.
- **Vault is a dependency**: per the docs, the Vault feature should be
  enabled before Barbican. This agent must verify the vault gate is enabled
  before enabling secrets.
- Docs usage requires the `creator` role to create/read/destroy secrets.
  The doc-exact test: `openstack secret store --payload ... -c "Secret href"`
  → `openstack secret get --payload <href>` → payload matches → delete.
- The `secret-decrypter` role allows service users in the `services` project
  to decrypt payloads; **Masakari gets this role by default** so instance
  recovery can rebuild servers with encrypted disks. The doc's audit check
  is part of our evidence: `openstack role assignment list --names --role
  secret-decrypter --project services --project-domain service_domain`.
- Deployment readiness: barbican + barbican-mysql-router apps active with
  units active/idle in juju model `openstack`.

## Open questions / watch-outs

- If `openstack secret store` returns 403 (missing creator role for the
  admin user), do NOT silently add roles — report it; adding a role is an
  identity change the user should approve.
- Confirm barbican endpoints appear in `openstack endpoint list` on first run.

## Solved issues

### 2026-11-18 — first live run findings (single-node vibrava deployment)

1. **Vault must be ACTIVE, not just gate-enabled.** `sunbeam enable secrets`
   fails with "Cannot enable secrets as Vault is not active" when the vault
   app is merely enabled but uninitialized. The dependency chain is:
   enable vault → `sunbeam vault init 1 1 -f json` → `sunbeam vault unseal
   <key>` → `sunbeam vault authorize-charm <token>` → vault app `active` →
   then enable secrets. Keys are ephemeral for test runs (discarded; never
   committed).
2. **`secret get --payload` prints a table** in this CLI version — use
   `-f json` and read `.Payload`; the raw-payload form in the docs does not
   appear verbatim here.
3. **Barbican readiness can exceed 600 s** on first deployment (single
   node): `TIMEOUT_READY` bumped to 900 s.
4. **`secret delete <href>` works** with the store-returned href; verify
   leftovers via `secret list -f json` (Name startswith the test prefix).
5. **`secret-decrypter` audit**: "No Role found" is the expected state when
   instance-recovery is NOT enabled (Masakari is the default holder of that
   role; this deployment has no masakari yet).
