#!/usr/bin/env bash
# Super-fast development test runner
# Reuses existing containers and skips rebuilds
set -euo pipefail
cd "$(dirname "$0")"

echo "[dev-test] Quick test (reusing containers if possible)"

# Only test one scenario for speed
SCENARIO="scenarios/http_basic.env"
set -a
# shellcheck disable=SC1090
. "$SCENARIO"
set +a

# Try to start HAProxy only (mocks might already be running)
echo "[dev-test] Starting/restarting HAProxy only"
COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml up -d haproxy --no-build 2>/dev/null || {
  echo "[dev-test] Starting full stack (first time)"
  COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml up -d --no-build
}

# Quick health check
sleep 2
echo "[dev-test] Quick health check"
curl -sS --max-time 3 \
  -X POST "http://127.0.0.1:${LISTEN_HTTP_PORT:-18999}" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | grep -q '"result":"ok"' && echo "✅ PASS" || echo "❌ FAIL"

echo "[dev-test] Done! (containers left running for next test)"
echo "[dev-test] To clean up: docker compose -f docker-compose.test.yml down"
