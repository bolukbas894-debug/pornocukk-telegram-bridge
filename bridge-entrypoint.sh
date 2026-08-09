#!/bin/sh
set -eu

: "${TELEGRAM_API_ID:?TELEGRAM_API_ID gerekli}"
: "${TELEGRAM_API_HASH:?TELEGRAM_API_HASH gerekli}"
: "${BRIDGE_SECRET:?BRIDGE_SECRET gerekli}"

PUBLIC_PORT="${PORT:-10000}"

case "$BRIDGE_SECRET" in
  *[!A-Za-z0-9_-]*)
    echo "BRIDGE_SECRET sadece A-Z, a-z, 0-9, _ ve - içerebilir."
    exit 1
    ;;
esac

cat >/etc/nginx/http.d/default.conf <<EOF
server {
    listen ${PUBLIC_PORT};
    server_name _;

    client_max_body_size 0;
    proxy_request_buffering off;
    proxy_buffering off;

    location = /health {
        default_type application/json;
        return 200 '{"ok":true}';
    }

    location /bot {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /file/ {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /bridge/${BRIDGE_SECRET}/ {
        alias /var/lib/telegram-bot-api/;
        autoindex off;
        sendfile on;
        limit_except GET HEAD { deny all; }
    }

    location / {
        default_type application/json;
        return 404 '{"ok":false,"error_code":404,"description":"Not Found"}';
    }
}
EOF

echo "Telegram Bot API başlatılıyor..."

telegram-bot-api \
  --api-id="${TELEGRAM_API_ID}" \
  --api-hash="${TELEGRAM_API_HASH}" \
  --dir=/var/lib/telegram-bot-api \
  --temp-dir=/tmp/telegram-bot-api \
  --username=telegram-bot-api \
  --groupname=telegram-bot-api \
  --http-port=8081 \
  --http-ip-address=127.0.0.1 \
  --local \
  >/tmp/telegram-bot-api.log 2>&1 &

TG_PID=$!

sleep 3

if ! kill -0 "$TG_PID" 2>/dev/null; then
    echo "Telegram Bot API başlatılamadı:"
    cat /tmp/telegram-bot-api.log || true
    exit 1
fi

echo "Telegram Bot API çalışıyor."
echo "Bridge dış portu: ${PUBLIC_PORT}"

exec nginx -g 'daemon off;'
