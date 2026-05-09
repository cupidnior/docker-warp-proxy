#!/bin/bash
set -e

echo "[*] Starting dnscrypt-proxy..."

dnscrypt-proxy \
  -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml &

echo "[*] Waiting for dnscrypt-proxy to initialize..."

for i in $(seq 1 15); do
    if ss -lun | grep -q ":53"; then
        echo "[*] dnscrypt-proxy is listening"
        break
    fi

    sleep 1
done

echo "[*] Switching container DNS to local DoH proxy..."

cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF

SOCKS_PORT=${SOCKS_PORT:-40000}
HTTP_PORT=${HTTP_PORT:-40002}

echo "[*] Starting warp-svc..."
warp-svc &

sleep 5

echo "[*] Registering WARP (first run only may take time)..."
warp-cli --accept-tos registration new || true

echo "[*] Setting WARP proxy mode..."
warp-cli --accept-tos mode proxy

echo "[*] Setting SOCKS5 proxy port ${SOCKS_PORT}..."
warp-cli --accept-tos proxy port ${SOCKS_PORT}

echo "[*] Connecting WARP..."
warp-cli --accept-tos connect
socat TCP-LISTEN:40001,fork,reuseaddr TCP:127.0.0.1:40000 &

sleep 5

echo "[*] Configuring Privoxy..."

cat >/etc/privoxy/config <<EOF
listen-address  0.0.0.0:${HTTP_PORT}

toggle 1
enable-remote-toggle 0
enable-remote-http-toggle 0

accept-intercepted-requests 1

forward-socks5t / 127.0.0.1:${SOCKS_PORT} .

permit-access 0.0.0.0/0
EOF

echo "[*] Starting Privoxy..."
privoxy --no-daemon /etc/privoxy/config
