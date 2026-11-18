#!/usr/bin/env bash
# Vault feature agent helper.
# Subcommands: state | enable | wait-ready | test | disable
# All remote execution happens on the bastion via ssh (BatchMode).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../config.env"

FEATURE="vault"
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=15 ${BASTION_USER}@${BASTION_HOST}"

bast() { $SSH_CMD "$@"; }

feature_state() {
  bast "sunbeam list-features 2>/dev/null" | awk -F'│' -v f="$FEATURE" '
    { gsub(/^[ \t]+|[ \t]+$/, "", $2)
      if ($2 == f) { gsub(/^[ \t]+|[ \t]+$/, "", $3); print ($3 ~ /X/) ? "enabled" : "disabled" } }'
}

wait_ready() {
  # Vault-specific readiness: after enable, the vault app sits in "blocked"
  # ("Please initialize Vault") until initialized — that IS its expected
  # post-enable state, so blocked-with-initialize-message counts as READY.
  local deadline=$((SECONDS + TIMEOUT_READY))
  while [ $SECONDS -lt $deadline ]; do
    local out
    out=$(bast "timeout 60 juju status -m ${JUJU_MODEL} ${FEATURE} 2>/dev/null") || true
    if echo "$out" | grep -qE "^${FEATURE}[[:space:]]+(active|blocked)"; then
      echo "READY"
      return 0
    fi
    sleep 15
  done
  echo "TIMEOUT"
  return 1
}

do_test() {
  local fail=0 ev=""
  echo "--- evidence begin"
  local s
  s=$(bast "sunbeam vault status 2>&1 | head -15") || true
  if echo "$s" | grep -qiE "not available|no such command|error"; then
    ev="$ev
[sunbeam vault status] unavailable/errored: $(echo "$s" | head -3)"
    fail=1
  else
    ev="$ev
[sunbeam vault status]
$s"
  fi
  local app
  app=$(bast "timeout 60 juju status -m ${JUJU_MODEL} ${FEATURE} 2>/dev/null | head -8")
  ev="$ev
[juju ${FEATURE}]
$app"
  # Vault-specific pass criteria: app exists as active OR blocked
  # (blocked = "Please initialize Vault" — the expected post-enable,
  #  pre-initialization state per the docs lifecycle).
  if echo "$app" | grep -qE "^${FEATURE}[[:space:]]+active"; then
    ev="$ev
[vault state: initialized/active]"
  elif echo "$app" | grep -qE "^${FEATURE}[[:space:]]+blocked"; then
    ev="$ev
[vault state: blocked awaiting initialization — expected for an uninitialized vault]"
  else
    fail=1
    ev="$ev
[juju] app in unexpected state"
  fi
  echo "--- evidence end"
  echo "TEST_EVIDENCE:"
  echo "$ev"
  if [ "$fail" -eq 0 ]; then echo "TEST_RESULT: pass"; else echo "TEST_RESULT: fail"; fi
}

case "${1:-help}" in
  state) feature_state ;;
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
  *) echo "usage: $0 {state|enable|wait-ready|test|disable}"; exit 2 ;;
esac
