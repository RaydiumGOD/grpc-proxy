#!/usr/bin/env bash
set -euo pipefail

# Simple failover test using HAProxy runtime API and basic connectivity checks.
# Requires: nc, curl. Will use grpcurl if present, otherwise runs a temporary docker grpcurl.

ADMIN_HOST=${ADMIN_HOST:-localhost}
ADMIN_PORT=${ADMIN_PORT:-9999}
HTTP_URL=${HTTP_URL:-http://localhost:8899}
GRPC_ADDR=${GRPC_ADDR:-localhost:10000}

say() { echo "[test] $*"; }
run() { say "+ $*"; eval "$*"; }

say "Listing servers state (first 20 lines):"
echo "show servers state" | nc -w 2 "$ADMIN_HOST" "$ADMIN_PORT" | head -n 20 || true

say "Testing HTTP JSON-RPC health (getHealth):"
curl -sS -X POST "$HTTP_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' | sed -e 's/.\{120\}/&\n/g' || true

if command -v grpcurl >/dev/null; then
  say "Testing gRPC connectivity (list services):"
  grpcurl -plaintext "$GRPC_ADDR" list || true
else
  say "grpcurl not found locally, attempting via docker..."
  docker run --rm --network host fullstorydev/grpcurl:latest -plaintext "$GRPC_ADDR" list || true
fi

BACKEND_HTTP=${BACKEND_HTTP:-be_rpc_http}
BACKEND_GRPC=${BACKEND_GRPC:-be_rpc_grpc}

say "Disabling first server in HTTP backend to simulate failure..."
echo "disable server ${BACKEND_HTTP}/srv1" | nc -w 2 "$ADMIN_HOST" "$ADMIN_PORT" || true
sleep 1

say "Re-testing HTTP JSON-RPC after disabling srv1:"
curl -sS -X POST "$HTTP_URL" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"getHealth"}' | sed -e 's/.\{120\}/&\n/g' || true

say "Re-enabling server..."
echo "enable server ${BACKEND_HTTP}/srv1" | nc -w 2 "$ADMIN_HOST" "$ADMIN_PORT" || true

say "Done. Inspect HAProxy stats UI or logs for backend routing details."

