#!/usr/bin/env bash
# Telemetry feature agent helper.
# Subcommands: state | enable | wait-ready | test | test-deep | disable
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../config.env"

FEATURE="telemetry"
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
    out=$(bast "timeout 60 juju status -m ${JUJU_MODEL} ceilometer 2>/dev/null") || true
    n=$(echo "$out" | grep -cE "^[[:space:]]+ceilometer/[0-9]+")
    r_app=$(echo "$out" | grep -cE "^ceilometer[[:space:]]+active")
    r_unit=$(echo "$out" | grep -E "^[[:space:]]+ceilometer/[0-9]+" | grep -c "active.*idle\|idle.*active")
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
  local rc ev="" fail=0
  local os="source ${OPENSTACK_RC} >/dev/null 2>&1; openstack"
  echo "--- evidence begin"
  local out
  out=$(bast "${os} endpoint list 2>/dev/null | grep -ciE 'ceilometer|aodh|gnocchi'") ; rc=$?
  ev="$ev
[telemetry endpoints found: ${out} (rc=$rc)]"
  if [ "${out:-0}" -lt 1 ]; then fail=1; fi
  out=$(bast "${os} metric status 2>&1 | head -8") ; rc=$?
  ev="$ev
[metric status rc=$rc]
$(echo "$out" | head -5)"
  if [ $rc -ne 0 ]; then fail=1; fi
  out=$(bast "${os} alarm list 2>&1 | head -4") ; rc=$?
  ev="$ev
[alarm list rc=$rc]"
  if [ $rc -ne 0 ]; then fail=1; fi
  echo "--- evidence end"
  echo "TEST_EVIDENCE:"
  echo "$ev"
  if [ $fail -eq 0 ]; then echo "TEST_RESULT: pass"; else echo "TEST_RESULT: fail"; fi
}

do_test_deep() {
  # Doc-exact: create own instance, alarm on memory.usage, measures, history.
  local rc ev="" fail=0
  local vm="irtest-telemetry-$(date +%s)" alarm="irtest-alarm-$(date +%s)"
  local os="source ${OPENSTACK_RC} >/dev/null 2>&1; openstack"
  echo "--- evidence begin (DEEP)"
  local out
  out=$(bast "${os} server create ${vm} --image ${DEEP_IMAGE} --flavor ${DEEP_FLAVOR} --network ${DEEP_NETWORK} --wait -f json 2>&1") ; rc=$?
  local vmid
  vmid=$(echo "$out" | jq -r 'if type=="array" then .[0]["id"] else .["id"] end' 2>/dev/null)
  ev="$ev
[server create rc=$rc id=${vmid}]"
  if [ $rc -ne 0 ] || [ -z "$vmid" ]; then
    echo "$ev"; echo "TEST_RESULT: fail"; return 0
  fi
  sleep 20
  out=$(bast "${os} alarm create --name ${alarm} --type gnocchi_resources_threshold --description 'irtest telemetry' --metric memory.usage --threshold 2000 --comparison-operator gt --aggregation-method mean --granularity 300 --evaluation-periods 3 --alarm-action 'log://' --resource-id ${vmid} --resource-type instance -f json 2>&1") ; rc=$?
  local alarmid
  alarmid=$(echo "$out" | jq -r 'if type=="array" then .[0]["alarm_id"] else .["alarm_id"] end' 2>/dev/null)
  ev="$ev
[alarm create rc=$rc id=${alarmid}]"
  if [ $rc -ne 0 ] || [ -z "$alarmid" ]; then
    ev="$ev"; echo "$ev"; echo "TEST_RESULT: fail"; return 0
  fi
  ev="$ev
[waiting up to 12 min for measures (300s granularity)]"
  echo "$ev"; echo "$ev" > /dev/null
  local measures_ok=0 deadline=$((SECONDS + 720))
  while [ $SECONDS -lt $deadline ]; do
    out=$(bast "${os} metric measures show -r ${vmid} memory.usage --granularity 300 2>&1 | head -4")
    if ! echo "$out" | grep -qiE "404|No measures|error"; then
      measures_ok=1; ev="$ev
[measures appeared]
$(echo "$out" | head -4)"; break
    fi
    sleep 60
  done
  [ $measures_ok -eq 0 ] && fail=1 && ev="$ev
[no measures within 12 min]"
  out=$(bast "${os} alarm-history show ${alarmid} 2>&1 | head -6") ; rc=$?
  ev="$ev
[alarm history rc=$rc]
$(echo "$out" | head -5)"
  bast "${os} alarm delete ${alarmid} 2>&1" >/dev/null || true
  bast "${os} server delete ${vm} --wait 2>&1" >/dev/null || true
  ev="$ev
[cleanup: alarm + instance deleted]"
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
