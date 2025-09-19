#!/usr/bin/env bash
set -euo pipefail
OUT_DIR=${1:-"$(cd "$(dirname "$0")" && pwd)/../../certs"}
mkdir -p "$OUT_DIR"

openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -subj "/CN=localhost" \
  -keyout "$OUT_DIR/server.key" -out "$OUT_DIR/server.crt"
cat "$OUT_DIR/server.key" "$OUT_DIR/server.crt" > "$OUT_DIR/server.pem"
echo "Wrote certs to $OUT_DIR"

