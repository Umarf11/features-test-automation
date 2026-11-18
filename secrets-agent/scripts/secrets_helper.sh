#!/usr/bin/env bash
# Secrets (Barbican) feature agent helper.
# Subcommands: dep-check | state | enable | wait-ready | test | disable
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../config.env"

FEATURE="secrets"
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=15 ${BASTION_USER}@${BASTION_HOST}"

bast() { $SSH_CMD "$@"; }

gate_state() {
  local f="$1"
  bast "sunbeam list-features 2>/dev/null" | awk -F'│' -v f="$f" '
    { gsub(/^[ \t]+|[ \t]+$/, "", $2)
      if ($2 == f) { gsub(/^[ \t]+|[ \t]+$/, "", $3); print ($3 ~ /X/) ? "enabled" : "disabled" } }'
}

dep_check() {
  local v app
  v=$(gate_state vault)
  if [ "$v" != "enabled" ]; then
    echo "DEP_FAIL vault-gate=$v"
    return 1
  fi
  # Sunbeam requires vault to be ACTIVE (initialized + unsealed) before
  # enabling secrets: "Cannot enable secrets as Vault is not active."
  app=$(bast "timeout 60 juju status -m ${JUJU_MODEL} vault 2>/dev/null | grep -E '^vault[[:space:]]'") || true
  if echo "$app" | grep -qE "active"; then
    echo "DEP_OK vault=enabled+active"
    return 0
  fi
  echo "DEP_FAIL vault-gate=enabled but vault app not active (needs init+unseal)"
  return 1
}

wait_ready() {
  local deadline=$((SECONDS + TIMEOUT_READY))
  while [ $SECONDS -lt $deadline ]; do
    local out n r_app r_unit
    out=$(bast "timeout 60 juju status -m ${JUJU_MODEL} barbican 2>/dev/null") || true
    n=$(echo "$out" | grep -cE "^[[:space:]]+barbican/[0-9]+")
    r_app=$(echo "$out" | grep -cE "^barbican[[:space:]]+active")
    r_unit=$(echo "$out" | grep -E "^[[:space:]]+barbican/[0-9]+" | grep -c "active.*idle\|idle.*active")
    if [ "$n" -gt 0 ] && [ "$r_app" -gt 0 ] && [ "$r_unit" -eq "$n" ]; then
      echo "READY"
      return 0
    fi
    sleep 15
  done
  echo "TIMEOUT"
  return 1
}

do_test() {
  local ts payload href stored rc ev="" fail=0
  ts=$(date +%s)
  payload="irtest-payload-${ts}"
  local os="source ${OPENSTACK_RC} >/dev/null 2>&1; openstack"
  echo "--- evidence begin"

  # doc-exact: store a secret and capture the Secret href
  out=$(bast "${os} secret store --name ${SECRET_NAME_PREFIX}-${ts} --payload ${payload} -f json 2>&1") ; rc=$?
  ev="$ev
[secret store rc=$rc]
$(echo "$out" | head -5)"
  if [ $rc -ne 0 ]; then
    echo "$ev"; echo "TEST_RESULT: fail"; return 0
  fi
  href=$(echo "$out" | jq -r 'if type=="array" then .[0]["Secret href"] else .["Secret href"] end' 2>/dev/null)
  if [ -z "$href" ]; then
    ev="$ev
[could not parse Secret href from store output]"
    echo "$ev"; echo "TEST_RESULT: fail"; return 0
  fi

  # doc-exact: get the payload back and compare (-f json: this CLI prints a
  # table without it, and the payload is in .Payload)
  got=$(bast "${os} secret get --payload ${href} -f json 2>&1" | jq -r '.Payload' 2>/dev/null) ; rc=$?
  ev="$ev
[secret get rc=$rc payload=${got}]"
  if [ $rc -ne 0 ] || [ "$got" != "$payload" ]; then
    ev="$ev
[payload mismatch or get failed: expected ${payload}]"
    fail=1
  fi

  # doc audit check (evidence, non-gating)
  audit=$(bast "${os} role assignment list --names --role secret-decrypter --project services --project-domain service_domain 2>&1 | head -6") || true
  ev="$ev
[secret-decrypter audit]
$audit"

  # cleanup our own secret
  bast "${os} secret delete ${href} 2>&1" >/dev/null || fail=1
  leftover=$(bast "${os} secret list -f json 2>/dev/null" | jq -r '[.[] | select(.Name // "" | startswith("'"${SECRET_NAME_PREFIX}"'"))] | length' 2>/dev/null) || true
  if [ "${leftover:-0}" -gt 0 ]; then
    ev="$ev
[leftover secrets: ${leftover}]"
    fail=1
  fi

  echo "--- evidence end"
  echo "TEST_EVIDENCE:"
  echo "$ev"
  if [ $fail -eq 0 ]; then echo "TEST_RESULT: pass"; else echo "TEST_RESULT: fail"; fi
}

case "${1:-help}" in
  dep-check) dep_check ;;
  state) gate_state "$FEATURE" ;;
  enable)
    out=$(bast "sunbeam enable ${FEATURE} 2>&1") ; rc=$?
    echo "$out" | tail -5; echo "ENABLE_RC=$rc"
    [ $rc -eq 0 ] || exit 1 ;;
  wait-ready) wait_ready ;;
  test) do_test ;;
  disable)
    out=$(bast "sunbeam disable ${FEATURE} 2>&1") ; rc=$?
    echo "$out" | tail -5; echo "DISABLE_RC=$rc"
    [ $rc -eq 0 ] || exit 1 ;;
  *) echo "usage: $0 {dep-check|state|enable|wait-ready|test|disable}"; exit 2 ;;
esac
