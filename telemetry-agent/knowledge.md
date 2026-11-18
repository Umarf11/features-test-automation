# Telemetry agent knowledge base

Accumulated knowledge about the Telemetry feature on this Sunbeam deployment.

## Facts (from docs and recon 2026-11-13)

- Feature gate key: `telemetry`; enable/disable via
  `sunbeam enable telemetry` / `sunbeam disable telemetry`.
- Deploys Ceilometer, Aodh, Gnocchi, and OpenStack Exporter
  (ceilometer, gnocchi + gnocchi-mysql-router, aodh + aodh-mysql-router).
- Docs usage needs an existing instance for alarms
  (`--resource-id <INSTANCE ID> --resource-type instance`); metric
  `memory.usage`, granularity 300, evaluation_periods 3.
- Alarm role note: managing alarms needs the `admin` role.
- **Disable semantics (docs)**: `sunbeam disable telemetry` terminates the
  applications but does not remove them from the model; docs offer an
  optional `juju remove-application --force --no-wait --no-prompt -m openstack
  ceilometer gnocchi gnocchi-mysql-router aodh aodh-mysql-router`. The
  feature gate state is the source of truth; repeated enable/disable cycles
  reuse the apps.
- Light daily test: endpoints present + `openstack metric status` +
  `openstack alarm list` — no instance needed.
- Deep doc-exact test: create own instance → create alarm on `memory.usage`
  → wait for measures (granularity 300 → up to ~10 min) → alarm-history →
  delete alarm + instance.

## Open questions / watch-outs

- Measures may take one 300s granularity window to appear; the deep test
  waits up to 12 minutes before declaring no-measures.
- OpenStack Exporter dashboards require the Observability feature — absence
  of Grafana dashboards is NOT a telemetry failure.

## Solved issues

### 2026-11-18 — telemetry FAILS on deployments without a metrics storage backend

**Observed:** after `sunbeam enable telemetry` (rc=0), gnocchi goes
`blocked` with "Need either s3-credentials or ceph relation", ceilometer
goes `waiting` ("Not all relations are ready"), and `openstack metric
status` returns HTTP 503. Readiness never converges.

**Root cause:** gnocchi requires a metrics storage backend — a Ceph
relation or S3 credentials. This single-node deployment (vibrava,
manifest `single-2026.1-edge.yml`) has **no microceph and no S3**, so
telemetry cannot become functional as-is. The docs' Telemetry page does
not document this prerequisite (worth an upstream docs bug report).
Note the docs' Telemetry page also confirms the exporter dashboards need
the Observability feature — absence of Grafana is NOT a failure, but the
gnocchi storage requirement IS.

**Fix options (deployment-level, not agent-level):**
1. Install microceph on the node(s) and relate it (how real labs do it),
2. Provide S3 credentials for gnocchi,
3. Accept telemetry as not-testable on this lab — agent records SKIP with
   this reason.

**Agent behavior after this finding:** the light test's endpoint/status
checks correctly report FAIL with this evidence; the sequence stops
(fail-fast); the sweep's environment is restored (telemetry disabled,
baseline clean) before reporting.

### 2026-11-18 — first live run mechanics (single-node vibrava deployment)

- JSON parsers must use `jq` on the bastion — bash `python3 -c "…\n…"`
  quoting passes literal backslash-n and breaks python.
- Readiness for a first-time charm deployment can exceed 600 s
  (ceilometer deployment included); `TIMEOUT_READY` bumped to 900 s.
- Light-test readiness definition for telemetry should also accept the
  observed intermediate states and keep polling (ceilometer `waiting`
  while relations settle).
