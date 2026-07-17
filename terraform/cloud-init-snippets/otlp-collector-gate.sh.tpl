# Gate the telemetry-emitting services on the collector endpoint actually
# accepting OTLP writes. First boot can race the collector: the DNS record
# may not exist yet, or may still point at a PREVIOUS deploy's LB (stale
# record until dns-traefiker refreshes it) — and exporters that start
# against a dead endpoint were observed to stay dark long after it healed
# (aws-unified-ingress validation, 2026-07). Bounded: 30 min, then start anyway.
for i in $(seq 1 180); do
  curl -skf --max-time 5 -X POST -H 'Content-Type: application/json' \
    -d '{"resourceMetrics":[]}' "${otlp_address}/v1/metrics" > /dev/null && { echo "OTLP collector ready."; break; }
  echo "Waiting for OTLP collector ${otlp_address} ($i/180)..."
  sleep 10
done
