ARG HAPROXY_TAG=3.2.4
FROM haproxy:${HAPROXY_TAG}

# Copy entrypoint that generates haproxy.cfg from environment variables
COPY docker-entrypoint.sh /docker-entrypoint.sh
USER root
RUN chmod +x /docker-entrypoint.sh \
    && mkdir -p /usr/local/etc/haproxy \
    && mkdir -p /var/run/haproxy \
    && chown -R haproxy:haproxy /usr/local/etc/haproxy /var/run/haproxy

USER haproxy
ENTRYPOINT ["/docker-entrypoint.sh"]

