FROM aiogram/telegram-bot-api:latest

USER root

RUN apk add --no-cache nginx

COPY bridge-entrypoint.sh /bridge-entrypoint.sh
RUN chmod +x /bridge-entrypoint.sh \
    && mkdir -p /run/nginx

EXPOSE 10000

ENTRYPOINT ["/bridge-entrypoint.sh"]
