#!/bin/sh
set -eu

# Environment with sensible defaults
RPC_HTTP_UPSTREAMS="${RPC_HTTP_UPSTREAMS:-chi1.cracknode.com:8899}"
RPC_GRPC_UPSTREAMS="${RPC_GRPC_UPSTREAMS:-chi1.cracknode.com:10000}"
LISTEN_HTTP_PORT="${LISTEN_HTTP_PORT:-8899}"
LISTEN_GRPC_PORT="${LISTEN_GRPC_PORT:-10000}"
LISTEN_HTTP_TLS_ENABLE="${LISTEN_HTTP_TLS_ENABLE:-false}"
LISTEN_HTTP_TLS_PORT="${LISTEN_HTTP_TLS_PORT:-8443}"
LISTEN_GRPC_TLS_ENABLE="${LISTEN_GRPC_TLS_ENABLE:-false}"
LISTEN_GRPC_TLS_PORT="${LISTEN_GRPC_TLS_PORT:-10001}"
STATS_PORT="${STATS_PORT:-8404}"
STATS_USER="${STATS_USER:-admin}"
STATS_PASS="${STATS_PASS:-admin}"
HEALTH_RISE="${HEALTH_RISE:-2}"
HEALTH_FALL="${HEALTH_FALL:-3}"
ADMIN_SOCKET_TCP="${ADMIN_SOCKET_TCP:-false}"
ADMIN_SOCKET_PORT="${ADMIN_SOCKET_PORT:-9999}"
MAXCONN="${MAXCONN:-30000}"
ULIMIT_N="${ULIMIT_N:-65000}"
TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/haproxy/certs/server.pem}"
TLS_CLIENT_CA_FILE="${TLS_CLIENT_CA_FILE:-}"
TLS_CLIENT_VERIFY="${TLS_CLIENT_VERIFY:-none}"
TLS_MIN_VER="${TLS_MIN_VER:-TLSv1.2}"

# Upstream TLS options
RPC_HTTP_UPSTREAMS_TLS="${RPC_HTTP_UPSTREAMS_TLS:-false}"
RPC_HTTP_UPSTREAMS_VERIFY="${RPC_HTTP_UPSTREAMS_VERIFY:-none}"
RPC_GRPC_UPSTREAMS_TLS="${RPC_GRPC_UPSTREAMS_TLS:-false}"
RPC_GRPC_UPSTREAMS_VERIFY="${RPC_GRPC_UPSTREAMS_VERIFY:-none}"
RPC_HTTP_BALANCE="${RPC_HTTP_BALANCE:-roundrobin}"
RPC_GRPC_BALANCE="${RPC_GRPC_BALANCE:-roundrobin}"

# HTTP mode and health-check (JSON-RPC only)
RPC_HTTP_ENABLE_HTTP_MODE="${RPC_HTTP_ENABLE_HTTP_MODE:-false}"
RPC_HTTP_HEALTH_HTTP="${RPC_HTTP_HEALTH_HTTP:-false}"
RPC_HTTP_HEALTH_HOST="${RPC_HTTP_HEALTH_HOST:-localhost}"

CONFIG_PATH="/usr/local/etc/haproxy/haproxy.cfg"
# Ensure directories exist and are writable at runtime
mkdir -p "/usr/local/etc/haproxy" "/var/run/haproxy"

gen_servers() {
  # $1 = comma-separated upstreams, $2 = indentation spaces
  upstreams="$1"
  indent="$2"
  mode_tag="${3:-tcp}"
  verify_tag="${4:-none}"
  alpn_tag="${5:-}"
  oldIFS="$IFS"
  IFS=','
  set -- $upstreams
  IFS="$oldIFS"
  i=1
  for upstream in "$@"; do
    # Trim spaces
    u=$(echo "$upstream" | tr -d ' ')
    if [ -n "$u" ]; then
      host_part=$(echo "$u" | cut -d: -f1)
      if [ "$mode_tag" = "tcp-tls" ]; then
        if [ -n "$alpn_tag" ]; then
          printf "%sserver srv%s %s ssl verify %s sni str(%s) alpn %s check resolvers docker resolve-prefer ipv4 init-addr last,libc,none rise %s fall %s\n" "$indent" "$i" "$u" "$verify_tag" "$host_part" "$alpn_tag" "$HEALTH_RISE" "$HEALTH_FALL"
        else
          printf "%sserver srv%s %s ssl verify %s sni str(%s) check resolvers docker resolve-prefer ipv4 init-addr last,libc,none rise %s fall %s\n" "$indent" "$i" "$u" "$verify_tag" "$host_part" "$HEALTH_RISE" "$HEALTH_FALL"
        fi
      else
        printf "%sserver srv%s %s check resolvers docker resolve-prefer ipv4 init-addr last,libc,none rise %s fall %s\n" "$indent" "$i" "$u" "$HEALTH_RISE" "$HEALTH_FALL"
      fi
      i=$((i+1))
    fi
  done
}

cat > "$CONFIG_PATH" <<EOF
global
  log stdout format raw local0 info
  maxconn ${MAXCONN}
  ulimit-n ${ULIMIT_N}
  stats socket /var/run/haproxy/haproxy.sock mode 600 level admin expose-fd listeners
EOF

if [ "$ADMIN_SOCKET_TCP" = "true" ]; then
  cat >> "$CONFIG_PATH" <<EOF
  stats socket ipv4@0.0.0.0:${ADMIN_SOCKET_PORT} level admin
EOF
fi

cat >> "$CONFIG_PATH" <<EOF

defaults
  log     global
  mode    tcp
  option  dontlognull
  option  tcp-smart-accept
  option  tcp-smart-connect
  option  tcpka
  timeout connect 10s
  timeout client  15m
  timeout server  15m
  retries 3

resolvers docker
  nameserver dns1 127.0.0.11:53
  resolve_retries 3
  timeout retry   1s
  hold valid      10s

frontend fe_rpc_http
  mode $( [ "$RPC_HTTP_ENABLE_HTTP_MODE" = "true" ] && echo http || echo tcp )
  bind *:${LISTEN_HTTP_PORT}
  option $( [ "$RPC_HTTP_ENABLE_HTTP_MODE" = "true" ] && echo httplog || echo tcplog )
  default_backend be_rpc_http
$( if [ "$LISTEN_HTTP_TLS_ENABLE" = "true" ]; then
     echo "  bind *:${LISTEN_HTTP_TLS_PORT} ssl crt ${TLS_CERT_FILE} alpn h2,http/1.1 ssl-min-ver ${TLS_MIN_VER}"
   fi )

backend be_rpc_http
  mode $( [ "$RPC_HTTP_ENABLE_HTTP_MODE" = "true" ] && echo http || echo tcp )
  balance ${RPC_HTTP_BALANCE}
$( if [ "$RPC_HTTP_ENABLE_HTTP_MODE" = "true" ] && [ "$RPC_HTTP_HEALTH_HTTP" = "true" ]; then
     cat <<EOT
  option httpchk
  http-check send meth POST uri / ver HTTP/1.1 hdr Host ${RPC_HTTP_HEALTH_HOST} hdr Content-Type application/json body '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
  http-check expect string ok
EOT
   else
     echo "  option tcp-check"
   fi )
  default-server inter 3s rise ${HEALTH_RISE} fall ${HEALTH_FALL}
$( if [ "$RPC_HTTP_UPSTREAMS_TLS" = "true" ]; then
     gen_servers "$RPC_HTTP_UPSTREAMS" "  " "tcp-tls" "$RPC_HTTP_UPSTREAMS_VERIFY" "h2,http/1.1"
   else
     gen_servers "$RPC_HTTP_UPSTREAMS" "  " "tcp"
   fi )

frontend fe_rpc_grpc
  mode tcp
  bind *:${LISTEN_GRPC_PORT}
  option tcplog
  default_backend be_rpc_grpc
$( if [ "$LISTEN_GRPC_TLS_ENABLE" = "true" ]; then
     verify_line="ssl crt ${TLS_CERT_FILE} alpn h2 ssl-min-ver ${TLS_MIN_VER}"
     if [ -n "$TLS_CLIENT_CA_FILE" ] && [ "$TLS_CLIENT_VERIFY" != "none" ]; then
       verify_line="$verify_line ca-file ${TLS_CLIENT_CA_FILE} verify ${TLS_CLIENT_VERIFY}"
     fi
     echo "  bind *:${LISTEN_GRPC_TLS_PORT} ${verify_line}"
   fi )

backend be_rpc_grpc
  mode tcp
  balance ${RPC_GRPC_BALANCE}
  option tcp-check
  default-server inter 3s rise ${HEALTH_RISE} fall ${HEALTH_FALL}
$( if [ "$RPC_GRPC_UPSTREAMS_TLS" = "true" ]; then
     gen_servers "$RPC_GRPC_UPSTREAMS" "  " "tcp-tls" "$RPC_GRPC_UPSTREAMS_VERIFY" "h2"
   else
     gen_servers "$RPC_GRPC_UPSTREAMS" "  " "tcp"
   fi )

listen stats
  bind *:${STATS_PORT}
  mode http
  stats enable
  stats uri /
  stats refresh 5s
  stats realm HAProxy\ Stats
  stats auth ${STATS_USER}:${STATS_PASS}
EOF

echo "Generated HAProxy config:" >&2
echo "----------------------------------------" >&2
cat "$CONFIG_PATH" >&2
echo "----------------------------------------" >&2

exec haproxy -W -db -f "$CONFIG_PATH"

