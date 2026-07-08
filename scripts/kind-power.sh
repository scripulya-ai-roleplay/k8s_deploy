#!/usr/bin/env bash
# Stop / start / delete the local kind cluster so it releases (or re-binds) the
# host ports it occupies — the API NodePort mapping (e.g. :8000), the API server
# port, etc. Lets you run the Compose path (`make up`) without a kind clash.
#
#   scripts/kind-power.sh stop      docker-stop the kind node(s): ports freed,
#                                   cluster state preserved (undo with 'start')
#   scripts/kind-power.sh start     docker-start a stopped kind cluster again
#   scripts/kind-power.sh delete    kind delete cluster: ports freed, ALL state lost
#
# Cluster name (same rule as load-images-kind.sh):
#   $KIND_CLUSTER  ->  current kubectl context (kind-<name>)  ->  the only kind cluster
set -euo pipefail

ACTION="${1:-}"
case "$ACTION" in
  stop|start|delete) ;;
  *) echo "Usage: $0 {stop|start|delete}" >&2; exit 2 ;;
esac

command -v docker >/dev/null || { echo "❌ docker not found" >&2; exit 1; }
command -v kind  >/dev/null || { echo "❌ kind not found" >&2; exit 1; }

resolve_cluster() {
  if [ -n "${KIND_CLUSTER:-}" ]; then
    echo "$KIND_CLUSTER"; return 0
  fi
  if command -v kubectl >/dev/null; then
    ctx="$(kubectl config current-context 2>/dev/null || true)"
    if [ -n "$ctx" ] && [ "${ctx#kind-}" != "$ctx" ]; then
      echo "${ctx#kind-}"; return 0
    fi
  fi
  clusters="$(kind get clusters 2>/dev/null || true)"
  if [ -n "$clusters" ]; then
    set -- $clusters            # word-count via positional params
    if [ "$#" -eq 1 ]; then echo "$1"; return 0; fi
    echo "❌ Multiple kind clusters found:" >&2
    for c in $clusters; do echo "   - $c" >&2; done
    echo "   Set KIND_CLUSTER=<name> to pick one." >&2
    exit 1
  fi
  return 1
}

if ! cluster="$(resolve_cluster)"; then
  echo "❌ No kind cluster found to ${ACTION}." >&2
  echo "   Set KIND_CLUSTER=<name> or switch kubectl to a kind-* context." >&2
  exit 1
fi

# kind get nodes lists the node containers even when they are stopped.
nodes="$(kind get nodes --name "$cluster" 2>/dev/null || true)"
if [ -z "$nodes" ]; then
  echo "❌ kind cluster '$cluster' has no nodes." >&2
  exit 1
fi

case "$ACTION" in
  stop)
    echo "⏸  Stopping kind cluster '$cluster' (frees host ports; state preserved)..."
    docker stop $nodes >/dev/null
    echo "✅ Stopped:" $nodes
    echo "   Bring it back with: make kind-start"
    ;;
  start)
    echo "▶️  Starting kind cluster '$cluster'..."
    docker start $nodes >/dev/null
    echo "✅ Started:" $nodes
    ;;
  delete)
    echo "🗑  Deleting kind cluster '$cluster' (ALL cluster state will be lost)..."
    kind delete cluster --name "$cluster"
    echo "✅ Deleted kind cluster '$cluster'."
    ;;
esac
