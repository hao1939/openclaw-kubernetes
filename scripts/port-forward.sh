#!/bin/bash
# Port-forward OpenClaw (18789) and noVNC (6080) from the cluster.
# Ctrl+C to stop both.
set -euo pipefail

NAMESPACE="openclaw"
POD="openclaw-0"

trap 'kill 0' EXIT

echo "Forwarding OpenClaw → http://localhost:18789"
echo "Forwarding noVNC    → http://localhost:6080/vnc.html"
echo ""
echo "Press Ctrl+C to stop."
echo ""

kubectl -n "$NAMESPACE" port-forward "$POD" 18789:18789 &
kubectl -n "$NAMESPACE" port-forward "$POD" 6080:6080 &

wait
