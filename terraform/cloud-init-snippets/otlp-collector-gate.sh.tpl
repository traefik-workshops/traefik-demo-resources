# Gate the telemetry-emitting services on the collector endpoint actually
# accepting OTLP writes. First boot can race the collector: the DNS record
# may not exist yet, or may still point at a PREVIOUS deploy's LB (stale
# record until dns-traefiker refreshes it) — and exporters that start
# against a dead endpoint were observed to stay dark long after it healed
# (aws-unified-ingress validation, 2026-07).
#
# CONTRACT — read this before rendering the snippet anywhere new.
#
#   * It defines otlp_collector_gate() and calls it exactly once, so a caller
#     cannot render the gate and then forget to arm it.
#   * The result is left in $otlp_gate_status: 0 = the collector accepted a
#     write, 1 = the budget was exhausted. Exhaustion is LOUD on stderr.
#   * It NEVER runs `exit`, and its own last statement is an assignment, so
#     the snippet always ends with status 0. That is deliberate: on the VM
#     legs this text is pasted inline into a cloud-init runcmd entry, where
#     `exit` would abandon the rest of the boot — `systemctl enable --now
#     traefik-hub` runs AFTER this — and a stray non-zero status would mark
#     the whole runcmd module failed.
#   * A caller that needs exhaustion to be FATAL opts in by reading the
#     variable: compute/aws/ecs appends `exit $otlp_gate_status`, which turns
#     an exhausted gate into a failed container and (with `dependsOn: SUCCESS`)
#     a task that never releases its gateway. A caller that must come up
#     regardless just ignores it, which is what both cloud-init templates do
#     on purpose — see the comment at each of those call sites.
#
# BUDGET — `rounds` x 10s, and it is the CALLER's decision because the two
# families of caller fail differently.
#
#   The number to beat is 1800s: that is the SOA MINIMUM on traefik.ai, which
#   is exactly how long a resolver may keep serving the NXDOMAIN it cached
#   before dns-traefiker published the collector's record. A gate is there to
#   outlast that cache, so a budget OF 1800s has no margin by construction —
#   it expires in the same breath as the thing it is waiting on.
#
#   VM legs pass 180 (1800s) anyway, and that is not an oversight: they ignore
#   $otlp_gate_status, so an under-budgeted gate there degrades to "boots,
#   reports late" and the VM still provisions. Container legs pass more and
#   make it fatal, because "started anyway" there means an exporter that is
#   dark for the life of the task with nothing left to retry it.
otlp_collector_gate() {
  otlp_gate_addr="${otlp_address}"
  otlp_gate_rounds=${rounds}
  otlp_gate_i=1

  while [ "$otlp_gate_i" -le "$otlp_gate_rounds" ]; do
    if curl -skf --max-time 5 -X POST -H 'Content-Type: application/json' \
         -d '{"resourceMetrics":[]}' "$otlp_gate_addr/v1/metrics" > /dev/null; then
      echo "otlp-gate: $otlp_gate_addr accepted an OTLP write on round $otlp_gate_i -- releasing."
      return 0
    fi
    echo "otlp-gate: waiting for $otlp_gate_addr to accept OTLP ($otlp_gate_i/$otlp_gate_rounds)..."
    otlp_gate_i=$((otlp_gate_i + 1))
    sleep 10
  done

  # Every failure path walks the whole budget — a missing curl exits 127 just as
  # slowly as a dead endpoint times out — so an exhausted gate is always a
  # multi-minute event, never a fast spin. Callers that make this fatal depend on
  # that: it is what keeps a restart from becoming a hot loop.
  echo "otlp-gate: EXHAUSTED -- $otlp_gate_addr never accepted an OTLP write in $((otlp_gate_rounds * 10))s." >&2
  echo "otlp-gate: telemetry from this host will be missing or late." >&2
  return 1
}

# `|| otlp_gate_status=$?` rather than a bare call plus `$?`, so this is safe even
# under `set -e`: the failure is TESTED, which is what stops a shell in errexit mode
# from taking a non-zero gate as a reason to abandon the boot.
otlp_gate_status=0
otlp_collector_gate || otlp_gate_status=$?
