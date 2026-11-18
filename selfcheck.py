#!/usr/bin/env python3
import json
import os
import subprocess


def main():
    repo = os.path.dirname(os.path.abspath(__file__))
    print("== features-test-automation self-check ==")
    checks = []

    def check(name, ok, detail=""):
        checks.append((name, ok, detail))
        print(f"  {'OK  ' if ok else 'FAIL'} {name} {detail}")

    skills = ["test-features", "vault-agent", "secrets-agent", "orchestration-agent", "telemetry-agent"]
    for s in skills:
        check(f"SKILL.md: {s}", os.path.isfile(os.path.join(repo, s, "SKILL.md")))
    for s in skills[1:]:
        check(f"knowledge.md: {s}", os.path.isfile(os.path.join(repo, s, "knowledge.md")))
        check(f"config.env: {s}", os.path.isfile(os.path.join(repo, s, "config.env")))
    for s in skills[1:]:
        check(f"helper: {s}", os.path.isfile(os.path.join(repo, s, f"scripts/{s.split('-')[0]}_helper.sh")))

    with open(os.path.join(repo, "test-features", "config.json")) as f:
        cfg = json.load(f)
    check("orchestrator config parses", True)
    check("feature_order has 4 agents", cfg.get("feature_order") == ["vault", "secrets", "orchestration", "telemetry"])
    check("schedule not installed", cfg.get("schedule", {}).get("installed") is False)

    helpers = [
        "vault-agent/scripts/vault_helper.sh",
        "secrets-agent/scripts/secrets_helper.sh",
        "orchestration-agent/scripts/orchestration_helper.sh",
        "telemetry-agent/scripts/telemetry_helper.sh",
    ]
    for h in helpers:
        p = subprocess.run(["bash", "-n", os.path.join(repo, h)], capture_output=True, text=True)
        check(f"bash syntax: {h}", p.returncode == 0, p.stderr[:120])
    p = subprocess.run(["bash", "-n", os.path.join(repo, "install.sh")], capture_output=True, text=True)
    check("bash syntax: install.sh", p.returncode == 0, p.stderr[:120])

    for sh in ["vault", "secrets", "orchestration", "telemetry"]:
        path = os.path.join(repo, f"{sh}-agent/scripts/{sh}_helper.sh")
        st = os.stat(path)
        check(f"executable: {sh}_helper.sh", bool(st.st_mode & 0o111))

    bad = [c for c in checks if not c[1]]
    print("\nself-check: %s (%d/%d passed)" % ("PASS" if not bad else "FAIL", len(checks) - len(bad), len(checks)))
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())
