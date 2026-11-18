#!/usr/bin/env bash
# Orchestration (Heat) feature agent helper.
# Subcommands: state | enable | wait-ready | test | test-deep | disable
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../config.env"

FEATURE="orchestration"
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=15 ${BASTION_USER}@${BASTION_HOST}"

bast() { $SSH_CMD "$@"; }

gate_state() {
  local f="$1"
  bast "sunbeam list-features 2>/dev/null" | awk -F'│' -v f="$f" '
    { gsub(/^[ \t]+|[ \t]+$/, "", $2)
      if ($2 == f) { gsub(/^[ \t]+|[ \t]+$/, "", $3); print ($3 ~ /X/) ? "enabled" : "disabled" } }'
}

wait_ready() {
  local deadline=$((SECONDS + TIMEOUT_READY))
  while [ $SECONDS -lt $deadline ]; do
    local out n r_app r_unit
    out=$(bast "timeout 60 juju status -m ${JUJU_MODEL} heat 2>/dev/null") || true
    n=$(echo "$out" | grep -cE "^[[:space:]]+heat/[0-9]+")
    r_app=$(echo "$out" | grep -cE "^heat[[:space:]]+active")
    r_unit=$(echo "$out" | grep -E "^[[:space:]]+heat/[0-9]+" | grep -c "active.*idle\|idle.*active")
    if [ "$n" -gt 0 ] && [ "$r_app" -gt 0 ] && [ "$r_unit" -eq "$n" ]; then
      echo "READY"
      return 0
    fi
    sleep 15
  done
  echo "TIMEOUT"
  return 1
}

MINIMAL_HOT='heat_template_version: 2018-08-31
description: irtest minimal validation template
parameters:
  net_name:
    type: string
    default: irtest-validate-net
resources:
  irtest_net:
    type: OS::Neutron::Net
    properties:
      name: { get_param: net_name }'

write_template() {
  bast "cat > ~/irtest-hot.yaml <<'IRTEST_EOF'
${MINIMAL_HOT}
IRTEST_EOF"
}

do_test() {
  local rc ev="" fail=0
  write_template || { echo "TEST_RESULT: fail"; return 0; }
  echo "--- evidence begin"
  local out
  out=$(bast "source ${OPENSTACK_RC} >/dev/null 2>&1; openstack orchestration template validate -t ~/irtest-hot.yaml 2>&1") ; rc=$?
  ev="$ev
[stack validate rc=$rc]
$(echo "$out" | head -5)"
  if [ $rc -ne 0 ]; then fail=1; fi
  out=$(bast "source ${OPENSTACK_RC} >/dev/null 2>&1; openstack stack list 2>&1 | head -4") ; rc=$?
  ev="$ev
[stack list rc=$rc]
$out"
  if [ $rc -ne 0 ]; then fail=1; fi
  bast "rm -f ~/irtest-hot.yaml" >/dev/null 2>&1 || true
  echo "--- evidence end"
  echo "TEST_EVIDENCE:"
  echo "$ev"
  if [ $fail -eq 0 ]; then echo "TEST_RESULT: pass"; else echo "TEST_RESULT: fail"; fi
}

do_test_deep() {
  # Doc-exact flow: servers_in_existing_neutron_net stack (2 servers + FIPs).
  local rc ev="" fail=0 stack="irtest-stack-$(date +%s)"
  echo "--- evidence begin (DEEP)"
  local tmpl
  tmpl=$(bast "curl -fsSL --max-time 60 https://opendev.org/openstack/heat-templates/raw/branch/master/hot/servers_in_existing_neutron_net.yaml -o /tmp/irtest-deep.yaml && echo FETCHED || echo FETCH_FAIL")
  if ! echo "$tmpl" | grep -q FETCHED; then
    echo "[template fetch failed: $tmpl]"; echo "TEST_RESULT: fail"; return 0
  fi
  local cmd="source ${OPENSTACK_RC} >/dev/null 2>&1; openstack stack create -t /tmp/irtest-deep.yaml --wait"
  cmd+=" --parameter key_name=${DEEP_KEYPAIR} --parameter image=ubuntu --parameter flavor=m1.tiny"
  cmd+=" --parameter public_net_id=${DEEP_PUBLIC_NET} --parameter private_net_id=${DEEP_PRIVATE_NET}"
  cmd+=" --parameter private_subnet_id=${DEEP_PRIVATE_SUBNET} ${stack} 2>&1"
  local out
  out=$(bast "$cmd") ; rc=$?
  ev="$ev
[stack create rc=$rc]
$(echo "$out" | tail -5)"
  [ $rc -ne 0 ] && fail=1
  out=$(bast "source ${OPENSTACK_RC} >/dev/null 2>&1; openstack stack list 2>&1 | head -5")
  ev="$ev
[stack list]
$out"
  echo "$ev"
  if [ $fail -eq 0 ]; then
    out=$(bast "source ${OPENSTACK_RC} >/dev/null 2>&1; openstack stack delete --yes ${stack} --wait 2>&1") ; rc=$?
    ev="[stack delete rc=$rc]"; echo "$ev"
    [ $rc -ne 0 ] && fail=1
  fi
  bast "rm -f /tmp/irtest-deep.yaml" >/dev/null 2>&1 || true
  echo "--- evidence end"
  echo "TEST_EVIDENCE:"
  echo "$ev"
  if [ $fail -eq 0 ]; then echo "TEST_RESULT: pass"; else echo "TEST_RESULT: fail"; fi
}

case "${1:-help}" in
  state) gate_state "$FEATURE" ;;
  enable)
    out=$(bast "sunbeam enable ${FEATURE} 2>&1") ; rc=$?
    echo "$out" | tail -5; echo "ENABLE_RC=$rc"
    [ $rc -eq 0 ] || exit 1 ;;
  wait-ready) wait_ready ;;
  test) do_test ;;
  test-deep) do_test_deep ;;
  disable)
    out=$(bast "sunbeam disable ${FEATURE} 2>&1") ; rc=$?
    echo "$out" | tail -5; echo "DISABLE_RC=$rc"
    [ $rc -eq 0 ] || exit 1 ;;
  *) echo "usage: $0 {state|enable|wait-ready|test|test-deep|disable}"; exit 2 ;;
esac
