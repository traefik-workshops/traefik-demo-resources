# Gate telemetry-emitting services on the collector ACCEPTING OTLP writes.
# Contract, budget rationale and caller rules: see
# terraform/cloud-init-snippets/README.md. Keep this file LEAN — it is pasted
# inline into cloud-init user data, and EC2 caps that at 16384 bytes.
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

  echo "otlp-gate: EXHAUSTED -- $otlp_gate_addr never accepted an OTLP write in $((otlp_gate_rounds * 10))s." >&2
  echo "otlp-gate: telemetry from this host will be missing or late." >&2
  return 1
}

otlp_gate_status=0
otlp_collector_gate || otlp_gate_status=$?
