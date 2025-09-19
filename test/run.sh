#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Fast mode: skip some scenarios for quick local testing
if [ "${FAST_MODE:-}" = "1" ]; then
  SCENARIOS=(
    scenarios/http_basic.env
    scenarios/upstream_https.env
  )
else
  SCENARIOS=(
    scenarios/http_basic.env
    scenarios/upstream_https.env
    scenarios/upstream_tls.env
    scenarios/tls_inbound.env
  )
fi

echo "[test] Generating test certs (if needed)"
if [ -f ./certs/gen.sh ]; then
  # For mock HTTPS server (mounted from test/certs)
  bash ./certs/gen.sh ./certs || true
  # For HAProxy TLS inbound (mounted from project root certs)
  bash ./certs/gen.sh ../certs || true
else
  echo "[test] cert generator not found; skipping"
fi

echo "[test] Building mocks and haproxy (parallel)"
docker compose -f docker-compose.test.yml build --parallel

# Start services once and keep running (much faster!)
echo "[test] Starting shared services"
COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml up -d mock1 mock2 mock_https

# Wait for mocks to be ready (only once)
echo "[test] Waiting for mock services"
SECONDS=0
until nc -z 127.0.0.1 18899 && nc -z 127.0.0.1 28899 && nc -z 127.0.0.1 38899 || [ $SECONDS -gt 10 ]; do sleep 0.2; done

for s in "${SCENARIOS[@]}"; do
  echo "[test] Running scenario: $s"
  set -a
  # shellcheck disable=SC1090
  . "$s"
  set +a

  # Compute listen port and scheme based on inbound TLS flags
  SCHEME="http"
  PORT="${LISTEN_HTTP_PORT:-18999}"
  if [ "${LISTEN_HTTP_TLS_ENABLE:-false}" = "true" ]; then
    SCHEME="https"
    PORT="${LISTEN_HTTP_TLS_PORT:-18443}"
  fi

  # Only restart HAProxy (much faster than full stack restart)
  echo "[test] Reconfiguring HAProxy"
  COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml up -d haproxy

  # Wait for HAProxy only (shorter timeout since mocks are ready)
  SECONDS=0
  until nc -z 127.0.0.1 "$PORT" || [ $SECONDS -gt 8 ]; do sleep 0.2; done
  
  # Give HAProxy a moment to complete health checks
  sleep 1

  echo "[test] Health check via JSON-RPC getHealth"
  CURL_EXTRA=""
  if [ "$SCHEME" = "https" ]; then
    CURL_EXTRA="--insecure"
  fi
  curl -sS $CURL_EXTRA --http1.1 --retry 3 --retry-connrefused --retry-delay 1 --max-time 5 \
    -X POST "$SCHEME://127.0.0.1:$PORT" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | tee /dev/stderr | grep -q '"result":"ok"'

  echo "[test] Admin socket check"
  echo "show servers state" | nc -w 1 127.0.0.1 "${ADMIN_SOCKET_PORT:-19999}" | head -n 3 || true

  # Clean env vars for next scenario
  unset RPC_HTTP_UPSTREAMS RPC_HTTP_ENABLE_HTTP_MODE RPC_HTTP_HEALTH_HTTP RPC_HTTP_HEALTH_HOST LISTEN_HTTP_PORT ADMIN_SOCKET_TCP ADMIN_SOCKET_PORT || true
  unset RPC_HTTP_UPSTREAMS_TLS RPC_HTTP_UPSTREAMS_VERIFY LISTEN_HTTP_TLS_ENABLE LISTEN_HTTP_TLS_PORT || true
  unset LISTEN_GRPC_TLS_ENABLE LISTEN_GRPC_TLS_PORT TLS_CERT_FILE || true

done

echo "[test] Cleaning up all services"
COMPOSE_PROJECT_NAME=haproxy-test docker compose -f docker-compose.test.yml down -v

echo "[test] All scenarios passed."

