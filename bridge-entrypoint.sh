#!/bin/sh
set -eu

: "${TELEGRAM_API_ID:?TELEGRAM_API_ID gerekli}"
: "${TELEGRAM_API_HASH:?TELEGRAM_API_HASH gerekli}"
: "${BRIDGE_SECRET:?BRIDGE_SECRET gerekli}"

# Telegram API sadece container içinde 8081'de çalışsın.
export TELEGRAM_HTTP_PORT=8081
export TELEGRAM_HTTP_IP_ADDRESS=127.0.0.1
export TELEGRAM_LOCAL=1

# Render dışarıya PORT verir; yoksa 10000.
PUBLIC_PORT="${PORT:-10000}"

# Secret sadece güvenli karakterler içersin.
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

    # Telegram Bot API çağrıları
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

    # Telegram local modunda /var/lib/telegram-bot-api altına inen dosyalar.
    # Gizli BRIDGE_SECRET olmadan erişilemez.
    location /bridge/${BRIDGE_SECRET}/ {
        alias /var/lib/telegram-bot-api/;
        autoindex off;
        sendfile on;
        aio threads;
        directio 8m;
        limit_except GET HEAD { deny all; }
    }

    location / {
        default_type application/json;
        return 404 '{"ok":false,"error_code":404,"description":"Not Found"}';
    }
}
EOF

echo "Telegram Bot API başlatılıyor..."
/docker-entrypoint.sh >/tmp/telegram-bot-api.log 2>&1 &
TG_PID=$!

# API'nin ayağa kalkmasına kısa süre ver.
sleep 2

if ! kill -0 "$TG_PID" 2>/dev/null; then
    cat /tmp/telegram-bot-api.log || true
    exit 1
fi

echo "Bridge hazır. Public port: ${PUBLIC_PORT}"
exec nginx -g 'daemon off;'
