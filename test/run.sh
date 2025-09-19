#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SCENARIOS=(
  scenarios/http_basic.env
  scenarios/upstream_https.env
)

echo "[test] Generating test certs (if needed)"
./certs/gen.sh || true

echo "[test] Building mocks and haproxy"
docker compose -f docker-compose.test.yml build

for s in "${SCENARIOS[@]}"; do
  echo "[test] Running scenario: $s"
  export $(grep -v '^#' "$s" | xargs -d '\n' -0 2>/dev/null || true)
  # Bring up mocks + haproxy (test overlay extends base haproxy service)
  # Use a unique project name to avoid clashing with dev container names
  COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml up -d --build
  sleep 2
  # Basic checks
  echo "[test] Health check via JSON-RPC getHealth"
  curl -sS -X POST http://localhost:${LISTEN_HTTP_PORT:-18999} \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | tee /dev/stderr | grep -q '"result":"ok"'

  echo "[test] Admin socket 'show servers state' (first 5 lines)"
  echo "show servers state" | nc -w 1 localhost ${ADMIN_SOCKET_PORT:-19999} | head -n 5 || true

  echo "[test] Tearing down scenario: $s"
  COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml down -v
done

echo "[test] All scenarios passed."

