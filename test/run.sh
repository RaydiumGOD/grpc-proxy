#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

SCENARIOS=(
  scenarios/http_basic.env
  scenarios/upstream_https.env
)

echo "[test] Generating test certs (if needed)"
if [ -f ./certs/gen.sh ]; then
  bash ./certs/gen.sh ./certs || true
else
  echo "[test] cert generator not found; skipping"
fi

echo "[test] Building mocks and haproxy"
docker compose -f docker-compose.test.yml build

for s in "${SCENARIOS[@]}"; do
  echo "[test] Running scenario: $s"
  set -a
  # shellcheck disable=SC1090
  . "$s"
  set +a
  # Use a unique project name to avoid clashing with dev container names
  COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml up -d --build

  echo "[test] Waiting for services to be ready"
  SECONDS=0
  # Wait up to 20s for haproxy port
  until nc -z 127.0.0.1 "${LISTEN_HTTP_PORT:-18999}" || [ $SECONDS -gt 20 ]; do sleep 1; done
  # Wait up to 20s for mocks
  until nc -z 127.0.0.1 18899 || [ $SECONDS -gt 20 ]; do sleep 1; done
  until nc -z 127.0.0.1 28899 || [ $SECONDS -gt 20 ]; do sleep 1; done

  echo "[test] Health check via JSON-RPC getHealth"
  echo "[test] DEBUG: Checking HAProxy config and logs before curl"
  docker exec haproxy-test-proxy cat /usr/local/etc/haproxy/haproxy.cfg | grep -A5 -B5 "server srv" || true
  docker logs haproxy-test-proxy | tail -n 20 || true
  curl -sS --http1.1 --retry 5 --retry-connrefused --retry-delay 1 --max-time 10 \
    -X POST "http://127.0.0.1:${LISTEN_HTTP_PORT:-18999}" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | tee /dev/stderr | grep -q '"result":"ok"'

  echo "[test] Admin socket 'show servers state' (first 5 lines)"
  echo "show servers state" | nc -w 1 127.0.0.1 "${ADMIN_SOCKET_PORT:-19999}" | head -n 5 || true

  echo "[test] Tearing down scenario: $s"
  COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml down -v
  unset RPC_HTTP_UPSTREAMS RPC_HTTP_ENABLE_HTTP_MODE RPC_HTTP_HEALTH_HTTP RPC_HTTP_HEALTH_HOST LISTEN_HTTP_PORT ADMIN_SOCKET_TCP ADMIN_SOCKET_PORT || true
  unset RPC_HTTP_UPSTREAMS_TLS RPC_HTTP_UPSTREAMS_VERIFY || true

done

echo "[test] All scenarios passed."

