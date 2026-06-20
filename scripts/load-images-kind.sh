#!/usr/bin/env bash
# Build the app images from the sibling repos and load them into a kind cluster.
# kind has no registry, so it pulls from the node's local image store (imagePullPolicy: Never).
#
#   WITH_MOCK=1  ...also build+load the optional mock-google-api image
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="${APPS_DIR:-$REPO_ROOT/..}"
IMAGE_TAG="${IMAGE_TAG:-dev}"

command -v docker >/dev/null || { echo "❌ docker not found" >&2; exit 1; }
command -v kind  >/dev/null || { echo "❌ kind not found" >&2; exit 1; }

AI_DIR="$APPS_DIR/scripulya_ai"
AGENT_DIR="$APPS_DIR/scripulya_agent"

for d in "$AI_DIR" "$AGENT_DIR"; do
  [ -f "$d/Dockerfile" ] || { echo "❌ Dockerfile not found in $d" >&2; exit 1; }
done

echo "🔨 Building images..."
docker build -t "scripulya-ai:${IMAGE_TAG}"     "$AI_DIR"
docker build -t "scripulya-agent:${IMAGE_TAG}"  "$AGENT_DIR"

IMAGES="scripulya-ai:${IMAGE_TAG} scripulya-agent:${IMAGE_TAG}"

if [ "${WITH_MOCK:-0}" = "1" ]; then
  docker build -t "scripulya-mock-google-api:${IMAGE_TAG}" "$AI_DIR" -f "$AI_DIR/google_api_mock/Dockerfile"
  IMAGES="$IMAGES scripulya-mock-google-api:${IMAGE_TAG}"
fi

KIND_NAME_ARG=()
if [ -z "${KIND_CLUSTER:-}" ]; then
  # Auto-detect from the current kubectl context (kind-<name> -> <name>).
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  if [ "${ctx#kind-}" != "$ctx" ]; then
    KIND_CLUSTER="${ctx#kind-}"
  fi
fi
if [ -n "${KIND_CLUSTER:-}" ]; then
  KIND_NAME_ARG=(--name "$KIND_CLUSTER")
fi
echo "📦 kind cluster: ${KIND_CLUSTER:-<default 'kind'>}"

echo "📥 Loading images into kind..."
# shellcheck disable=SC2086
kind load docker-image ${IMAGES} "${KIND_NAME_ARG[@]}"

echo "✅ Loaded: ${IMAGES}"