# Team Guide — features-test-automation

## Overview

This repo contains the `test-features` orchestrator skill plus **one agent
skill per feature** (vault, secrets, orchestration, telemetry). The design
comes from the team decision that **every feature has its own agent**: when
a feature is being tested, that feature's agent runs, writes its own
report, and stops; the next feature's agent then starts. If a feature has
an issue, testing stops and you work directly with that feature's agent to
solve it — and whatever you learn is recorded in that agent's
`knowledge.md`, so it accumulates expertise about its feature over time.

## Architecture

```
features-test-automation/
├── install.sh                     # installs all 5 skills into ~/.agents/skills/
├── README.md · TEAM_GUIDE.md
├── reports/                       # reports land here (in your clone)
│   └── features/
│       ├── latest.json|md         # newest run summary
│       └── <date>/                # dated per-feature + summary reports
├── test-features/                 # ORCHESTRATOR skill
│   ├── SKILL.md                   # "test features" protocol + "report feature"
│   └── config.json                # feature order · report paths · schedule (deferred)
├── vault-agent/                   # FEATURE AGENT
│   ├── SKILL.md                   # procedure + failure + knowledge protocols
│   ├── knowledge.md               # accumulated vault knowledge (grows over time)
│   ├── config.env                 # bastion/user/model/timeouts
│   └── scripts/vault_helper.sh    # state|enable|wait-ready|test|disable
├── secrets-agent/                 # …same shape (depends on vault)
├── orchestration-agent/           # …same shape (light validate / deep doc stack)
└── telemetry-agent/               # …same shape (light metrics / deep doc alarm flow)
```

Key properties:

- **Per-agent isolation**: each agent is a self-contained skill (own config,
  own knowledge, own helpers). The orchestrator never runs feature steps
  itself.
- **Fail-fast**: the first feature failure stops the sequence; remaining
  features are recorded as SKIPPED; the failing feature's agent is the one
  you debug with.
- **Baseline preservation**: agents snapshot the feature state first and
  never disable a feature that was already enabled before the run.
- **Mutations via helpers only**: the agents execute their deterministic
  helper scripts; they interpret results and drive the sequence, but never
  invent sunbeam/juju commands.
- **No daily cron yet**: the owner deferred scheduling; `config.json`
  carries the intended `0 10 * * *` for later.

## Setup (each teammate)

```bash
git clone https://github.com/Umarf11/features-test-automation.git
cd features-test-automation
./install.sh
# restart your agent session
```

Then, in the session:

```
test features      # full sweep, fail-fast, ~40-70 min
report feature     # latest summary only
```

Prerequisites: passwordless ssh to the lab bastion; on the bastion
`sunbeam`, `juju`, and `~/admin-openrc`. Python 3 / bash only.

## Per-feature details

| Agent | Light test (default) | Deep test (explicit request only) |
|---|---|---|
| vault | service active + `sunbeam vault status` | init/unseal/authorize — NOT automated (sensitive keys) |
| secrets | doc-exact `secret store` → `get --payload` → `delete` + decrypter-role audit | same (the light test IS the doc flow) |
| orchestration | `stack validate` + `stack list` | doc-exact two-server stack on demo-network |
| telemetry | endpoints + `metric status` + `alarm list` | doc-exact alarm on `memory.usage` with its own instance |

## The knowledge protocol ("getting trained")

Every agent reads its `knowledge.md` before running. When you debug an
issue with an agent and something is confirmed (root cause, fix, quirk),
the agent proposes a dated entry and writes it after your approval. Commit
the updated `knowledge.md` to the repo — every teammate's copy of that
agent then benefits from the lesson.

## Reports

- Per-feature: `reports/features/<feature>/<date>/<feature>-<HHMMSS>.json|.md`
- Summary: `reports/features/<date>/summary-<HHMMSS>.json|.md`
- Always-current pointers: `reports/features/latest.json|md`
- Retention: prune reports older than 30 days when you commit new ones
  (the repo keeps history for archived copies).

## Troubleshooting

| Problem | Fix |
|---|---|
| Agent not recognized | Restart the session; check `ls ~/.agents/skills/` |
| `state` helper returns nothing | Check ssh access and `config.env`; run `sunbeam list-features` manually on the bastion |
| enable fails | Read the helper output tail; check `juju status -m openstack` for stuck units |
| secrets test 403 | The admin user lacks the `creator` role — decide with the team before adding roles |
| Fail-fast stopped the sweep | Open the failing feature's report, then work with that feature's agent; re-run `test features` afterwards (always a full re-run) |
| Wrong bastion | Edit the agent's `config.env` (or `FEATURES_BASTION_HOST` env var overrides) |

## Creating a new feature agent

1. Copy the shape of any existing agent folder (SKILL.md + knowledge.md +
   config.env + scripts/<feature>_helper.sh).
2. Read that feature's docs page; encode enable/usage/disable into the
   helper as subcommands.
3. Add the feature to `test-features/config.json` `feature_order`.
4. `./install.sh`, restart the session — the orchestrator picks it up.
