# Orchestration (Heat) agent knowledge base

Accumulated knowledge about the Orchestration feature on this Sunbeam deployment.

## Facts (from docs and recon 2026-11-13)

- Feature gate key: `orchestration`; enable/disable via
  `sunbeam enable orchestration` / `sunbeam disable orchestration`.
- Deploys Heat (heat, heat-cfn + mysql routers).
- Docs usage: create a stack from
  `heat-templates/.../hot/servers_in_existing_neutron_net.yaml` with params
  key_name=sunbeam, image=ubuntu, flavor=m1.tiny, public_net_id=external-network,
  private_net_id=demo-network, private_subnet_id=demo-subnet — creates TWO
  servers with floating IPs; verify `stack list` → CREATE_COMPLETE and
  `server list` shows them.
- Light daily test: `openstack stack validate -t <minimal HOT>` (no
  deployment) + `openstack stack list` — validates the service without
  creating resources.
- Disabling terminates the apps but does not remove them from the model
  (docs give optional `juju remove-application` for heat heat-cfn
  heat-mysql-router heat-cfn-mysql-router) — feature gate state is the
  source of truth.

## Open questions / watch-outs

- Template validation requires the Heat API; if validate fails transiently
  right after enable, wait for all heat units idle first.
- The deep stack flow needs the `sunbeam` keypair and named networks to
  exist; if missing, report SKIP-with-reason instead of creating them.

## Solved issues

### 2026-11-18 — first live run findings (single-node vibrava deployment)

1. **`openstack stack validate` does not exist** in this CLI version — the
   correct command is `openstack orchestration template validate -t <file>`
   (the suggestion list confirms: orchestration build info, resource type
   list/show, service list, template function/version list, template
   validate).
2. **The `openstack` snap is strictly confined with a PRIVATE /tmp**: a
   template written to the host's /tmp is invisible to the CLI
   ("urlopen error ... No such file or directory"). Fix: write the template
   to `$HOME` (the snap's `home` interface reads non-hidden files there) —
   `~/irtest-hot.yaml` works.
3. **Heat readiness can exceed 600 s** on first deployment (single node):
   `TIMEOUT_READY` bumped to 900 s. Disable semantics match the docs:
   apps terminated, gate state is the source of truth.
