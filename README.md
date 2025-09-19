HAProxy RPC/GRPC Failover Proxy (Dockerized)

[![CI](https://github.com/Zaydo123/GRPC-proxy/actions/workflows/ci.yml/badge.svg)](https://github.com/Zaydo123/GRPC-proxy/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![HAProxy 3.2](https://img.shields.io/badge/HAProxy-3.2-green.svg)](https://hub.docker.com/_/haproxy)

Purpose

- Provide a single local endpoint for multiple apps, while HAProxy handles failover/load-balancing across one or more upstream RPC nodes.
- Supports both JSON-RPC over HTTP and Geyser gRPC (TCP passthrough), with TCP health checks and a stats UI.

Quick start

0) Create a .env from template

```bash
cp env.example .env
# edit .env as needed
```

1) Bring it up

```bash
HAPROXY_TAG=3.2.4 docker compose up -d --build
```

This exposes:
- HTTP JSON-RPC on localhost:8899 → forwards to RPC_HTTP_UPSTREAMS
- gRPC on localhost:10000 → forwards to RPC_GRPC_UPSTREAMS
- HAProxy stats UI on localhost:8404 (admin/admin)
- Optional TLS listeners: HTTPS on localhost:8443, gRPC-TLS on localhost:10001

2) Add more upstreams (optional)

Provide comma-separated lists via environment variables. Example:

```bash
RPC_HTTP_UPSTREAMS=host1:8899,host2:8899 \
RPC_GRPC_UPSTREAMS=host1:10000,host2:10000 \
HAPROXY_TAG=3.2.4 docker compose up -d --build
```

3) Point your apps

- HTTP JSON-RPC: http://localhost:8899
- gRPC (Geyser): localhost:10000 (plaintext)

Features

- TCP pass-through for JSON-RPC and gRPC with health checks
- Optional HTTP-mode for JSON-RPC with POST getHealth check
- Upstream TLS (SNI/ALPN) and inbound TLS/mTLS listeners
- Runtime admin socket (TCP and UNIX) + stats UI
- Config via environment variables and Docker Compose
- Test suite with Dockerized mocks and CI workflow

Diagram

```mermaid
flowchart LR
  client[Clients<br/>Apps]
  fe_http[fe_rpc_http]
  fe_grpc[fe_rpc_grpc]
  be_http[be_rpc_http]
  be_grpc[be_rpc_grpc]
  stats[Stats UI :8404]
  admin[Admin Socket :9999/UNIX]

  client -->|HTTP JSON-RPC :8899| fe_http
  client -->|gRPC :10000| fe_grpc

  subgraph HAProxy
    fe_http --> be_http
    fe_grpc --> be_grpc
    stats
    admin
  end

  subgraph Upstreams
    be_http --> u1[RPC Node #1]
    be_http --> u2[RPC Node #2]
    be_grpc --> u1
    be_grpc --> u2
  end

  %% Optional TLS listeners
  client -.->|HTTPS :8443 (optional)| fe_http
  client -.->|gRPC-TLS :10001 (optional)| fe_grpc
```

Health checks

- Uses TCP health checks (port liveness) with rise=2, fall=3 by default. Adjust via HEALTH_RISE/HEALTH_FALL.
- Optionally enable HTTP-level health checks for JSON-RPC: set RPC_HTTP_ENABLE_HTTP_MODE=true and RPC_HTTP_HEALTH_HTTP=true. This will POST getHealth and expect "ok".
- If a node goes down, existing sessions are closed and new connections are routed to healthy nodes.

Stats/observability

- Stats UI: http://localhost:8404 (basic auth admin/admin by default)
- Change creds via STATS_USER/STATS_PASS. Change port via STATS_PORT.
- Runtime admin socket: enable TCP socket via ADMIN_SOCKET_TCP=true and ADMIN_SOCKET_PORT.

Configuration via environment

- RPC_HTTP_UPSTREAMS: comma-separated host:port list
- RPC_GRPC_UPSTREAMS: comma-separated host:port list
- LISTEN_HTTP_PORT: local listen port for HTTP JSON-RPC (default 8899)
- LISTEN_GRPC_PORT: local listen port for gRPC (default 10000)
- LISTEN_HTTP_TLS_ENABLE: enable HTTPS listener (default false)
- LISTEN_HTTP_TLS_PORT: HTTPS port (default 8443)
- LISTEN_GRPC_TLS_ENABLE: enable gRPC-TLS listener (default false)
- LISTEN_GRPC_TLS_PORT: gRPC-TLS port (default 10001)
- STATS_PORT: stats UI port (default 8404)
- STATS_USER / STATS_PASS: stats UI auth (default admin/admin)
- HEALTH_RISE / HEALTH_FALL: health thresholds (default 2/3)
- ADMIN_SOCKET_TCP: expose runtime admin socket over TCP (default true)
- ADMIN_SOCKET_PORT: TCP admin port (default 9999)
- MAXCONN: HAProxy maxconn (default 30000)
- ULIMIT_N: HAProxy ulimit-n (default 65000)
- TLS_CERT_FILE: PEM bundle for inbound TLS (default /etc/haproxy/certs/server.pem)
- TLS_CLIENT_CA_FILE: CA file for client cert validation (optional)
- TLS_CLIENT_VERIFY: none/optional/required for mTLS (default none)
- TLS_MIN_VER: TLS minimum version (default TLSv1.2)
- RPC_HTTP_UPSTREAMS_TLS: enable TLS to HTTP upstreams (default false)
- RPC_HTTP_UPSTREAMS_VERIFY: upstream TLS verify mode (default none)
- RPC_GRPC_UPSTREAMS_TLS: enable TLS to gRPC upstreams (default false)
- RPC_GRPC_UPSTREAMS_VERIFY: upstream TLS verify mode (default none)
- RPC_HTTP_BALANCE / RPC_GRPC_BALANCE: load-balance algo (default roundrobin)
- RPC_HTTP_ENABLE_HTTP_MODE: switch HTTP frontend/backend to HTTP mode (default false)
- RPC_HTTP_HEALTH_HTTP: use HTTP POST getHealth check if HTTP mode (default false)
- RPC_HTTP_HEALTH_HOST: Host header for health check (default localhost)

Notes

- This setup defaults to TCP passthrough for compatibility. Enable HTTP mode only if your upstream JSON-RPC strictly behaves as HTTP.
- DNS is resolved using Docker's internal resolver (127.0.0.11). Hostname changes are picked up automatically.

Testing

HTTP JSON-RPC (Solana example):

```bash
curl -sS -X POST http://localhost:8899 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
```

gRPC: use your gRPC client pointed at localhost:10000. For plaintext gRPC with grpcurl:

```bash
grpcurl -plaintext localhost:10000 list
```

For TLS gRPC, if enabled on 10001 with a PEM cert bundle:

```bash
grpcurl -authority your.server.name -cacert /path/to/ca.pem your.server.name:10001 list
```

Troubleshooting

- View live logs: docker logs -f haproxy-rpc-proxy
- Validate config in container: docker exec -it haproxy-rpc-proxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
- Check stats UI for backend/server states.

Simulate failover via admin socket

You can mark a server down to force failover using the runtime API:

```bash
# List backends/servers
echo "show servers state" | nc -w 1 localhost 9999 | head -n 20

# Disable first HTTP server (example backend name be_rpc_http)
echo "disable server be_rpc_http/srv1" | nc -w 1 localhost 9999

# Re-enable it
echo "enable server be_rpc_http/srv1" | nc -w 1 localhost 9999
```

CI and local test suite

- Local test runner:

```bash
cd test
bash ./run.sh
```

- The runner brings up mock JSON-RPC servers and runs haproxy with scenario env files under `test/scenarios/`.
- CI via GitHub Actions is included at `.github/workflows/ci.yml`.
- Secrets and local overrides are ignored via `.gitignore` (use `.env` locally, not committed).

Contributing

See CONTRIBUTING.md.

License

MIT — see LICENSE.

