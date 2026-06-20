#!/usr/bin/env bash
# Port-forward the k8s services to localhost for local access:
#   http://localhost:${AI_PORT:-8000}       -> scripulya-ai (API + /docs)
#   http://localhost:${RABBIT_MGMT_PORT:-15673} -> rabbitmq management UI (guest/guest)
# Defaults avoid clashing with a host-installed RabbitMQ. Ctrl-C stops both.
# (On kind you can instead reach the API via NodePort 30080 if the cluster was
# created with that extraPortMapping — see README.)
set -euo pipefail

NAMESPACE="${NAMESPACE:-scripulya}"
AI_LOCAL="${AI_PORT:-8000}"
RB_LOCAL="${RABBIT_MGMT_PORT:-15673}"
command -v kubectl >/dev/null || { echo "❌ kubectl not found" >&2; exit 1; }

kubectl -n "$NAMESPACE" port-forward svc/scripulya-ai "${AI_LOCAL}:8000" &
AI_PID=$!
kubectl -n "$NAMESPACE" port-forward svc/rabbitmq "${RB_LOCAL}:15672" &
RB_PID=$!

cleanup() {
  kill "$AI_PID" "$RB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "➜ API:    http://localhost:${AI_LOCAL}/docs"
echo "➜ Rabbit: http://localhost:${RB_LOCAL}  (guest/guest)"
echo "   (Ctrl-C to stop)"
wait
