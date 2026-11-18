# features-test-automation

Per-feature **AI agent** automation for verifying optional features of a
Sunbeam OpenStack deployment. Every feature has its own dedicated agent
(skill): when a feature is being tested, that feature's agent runs, writes
its own report, and stops — then the next feature's agent starts. If a
feature fails, testing stops and you work directly with that feature's
agent to fix the issue together; whatever you learn is accumulated in the
agent's `knowledge.md` so it gets better at its feature over time.

## Triggers

| Phrase | What happens |
|---|---|
| `test features` | Runs every feature agent **sequentially** (vault → secrets → orchestration → telemetry). Fail-fast: the first failing feature stops the sequence and tells you which agent to debug with |
| `report feature` | Shows the **latest** run summary (no tests executed) |
| `test vault` / `test secrets` / `test orchestration` / `test telemetry` | Runs that single feature agent alone |
| `work with the <feature> agent` | Interactive debugging session with that feature's agent |

## The four feature agents

| Agent | Enable → Test (per docs) → Disable |
|---|---|
| `vault-agent` | `sunbeam enable vault` → service/status checks → `sunbeam disable vault` (if we enabled it) |
| `secrets-agent` | **depends on vault** → `sunbeam enable secrets` → doc-exact `secret store/get/delete` roundtrip → disable |
| `orchestration-agent` | `sunbeam enable orchestration` → `stack validate` + `stack list` (light) / doc-exact two-server stack (deep, on request) → disable |
| `telemetry-agent` | `sunbeam enable telemetry` → endpoints + `metric status` + `alarm list` (light) / doc-exact alarm flow with its own instance (deep, on request) → disable |

Rules every agent enforces: snapshot the feature state first, never disable
a feature that was already enabled, always restore what it changed, write
its own report, stop.

## Quickstart

```bash
git clone https://github.com/Umarf11/features-test-automation.git
cd features-test-automation
./install.sh              # installs the 5 skills (orchestrator + 4 agents)
# restart your agent session, then:
#   test features   /   report feature
```

Reports land in `reports/features/` in this repo clone; commit and push
them like any other file.

## Requirements

- Passwordless ssh from your machine to the lab bastion (default
  `ubuntu@10.149.133.31` — edit each agent's `config.env` for other labs).
- On the bastion: `sunbeam`, `juju`, and `~/admin-openrc` for the OpenStack CLI.
- Python 3 / bash only — no pip installs.
- Daily scheduling (10:00 UTC) is **intentionally not installed yet**; the
  config carries the schedule for when the owner opts in.

See `TEAM_GUIDE.md` for the full guide.
