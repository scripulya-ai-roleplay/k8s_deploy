#!/usr/bin/env bash
# Generate the `postgres-init-sql` ConfigMap from the sibling repo's init.sql,
# so the k8s path seeds Postgres from the SAME file the compose path uses (no drift).
# Idempotent (kubectl apply).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="${APPS_DIR:-$REPO_ROOT/..}"
NAMESPACE="${NAMESPACE:-scripulya}"

INIT_SQL="$APPS_DIR/scripulya_ai/scripts/init.sql"

if [ ! -f "$INIT_SQL" ]; then
  echo "❌ init.sql not found at $INIT_SQL" >&2
  echo "   Set APPS_DIR to the dir containing scripulya_ai/ (default: repo parent)." >&2
  exit 1
fi

command -v kubectl >/dev/null || { echo "❌ kubectl not found" >&2; exit 1; }

kubectl create configmap postgres-init-sql -n "$NAMESPACE" \
  --from-file=init.sql="$INIT_SQL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ ConfigMap postgres-init-sql synced from $INIT_SQL"