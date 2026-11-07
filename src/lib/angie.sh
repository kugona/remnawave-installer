#!/bin/bash

# ===================================================================================
#                                 ANGIE CONFIGURATION
# ===================================================================================

# Layout of an Angie directory:
#   angie.conf          - base config (TLS, proxy defaults, Server header)
#   docker-compose.yml
#   conf.d/             - ACME clients, server blocks, panel auth secrets
#   snippets/           - error responses and per-site locations

write_angie_base_config() {
    local dir="$1"

    mkdir -p "$dir/conf.d" "$dir/snippets"

    cat >"$dir/angie.conf" <<'EOF'
load_module modules/ngx_http_headers_more_filter_module.so;

user angie;
worker_processes auto;
worker_rlimit_nofile 65536;
error_log /var/log/angie/error.log notice;
pid /run/angie/angie.pid;

events {
    worker_connections 4096;
}

http {
    default_type application/octet-stream;

    # URIs may carry panel secrets and subscription identifiers
    access_log off;

    server_tokens off;
    more_set_headers "Server: nginx";

    server_names_hash_bucket_size 64;

    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100m;

    # Remnawave does not compress response bodies itself
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_types application/javascript application/json application/manifest+json application/xml application/wasm
        font/eot font/otf font/ttf image/svg+xml text/css text/javascript text/plain text/xml;

    # Used by the ACME clients to resolve the CA
    resolver conf ipv6=off;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1:secp384r1;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ""      close;
    }

    include /etc/angie/conf.d/*.conf;
}
EOF

    # A fixed path would answer 404 where every other path answers 401 or 403,
    # which would identify servers set up by this public installer
    local error_prefix="/.$(openssl rand -hex 8)"

    write_angie_error_responses "$dir" "$error_prefix"
    write_angie_site_snippets "$dir" "$error_prefix"
}

# Response body matching a stock nginx page: the built-in ones would name Angie
angie_stock_page() {
    local title="$1 $2"
    printf '%s' "<html>\r\n<head><title>$title</title></head>\r\n<body>\r\n<center><h1>$title</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>\r\n"
}

# Internal URIs rather than named locations: a malformed request line has an empty URI,
# which cannot be redirected to a named location and would end in a stock 500 page.
# Server blocks must not use server-level return or rewrite, it would run here as well.
write_angie_error_responses() {
    local file="$1/snippets/errors.conf"
    local error_prefix="$2"
    local page code reason

    : >"$file"
    for page in "400:Bad Request" "401:Authorization Required" "403:Forbidden" \
        "404:Not Found" "405:Not Allowed" "413:Request Entity Too Large" \
        "414:Request-URI Too Large" "500:Internal Server Error" "502:Bad Gateway" \
        "503:Service Temporarily Unavailable" "504:Gateway Time-out"; do
        code="${page%%:*}"
        reason="${page#*:}"
        cat >>"$file" <<EOF
error_page $code $error_prefix/$code;
location = $error_prefix/$code {
    internal;
    default_type text/html;
    return $code "$(angie_stock_page "$code" "$reason")";
}
EOF
    done

    # Oversized headers and TLS client errors, including plain HTTP sent to an HTTPS port
    echo "error_page 494 495 496 497 =400 $error_prefix/400;" >>"$file"
}

write_angie_site_snippets() {
    local dir="$1"
    local error_prefix="$2"

    # "return 301" would add a stock page, and "return" cannot set both this status and
    # a custom body. The status comes from error_page, it overrides the one set by "return".
    cat >"$dir/snippets/redirect.conf" <<EOF
error_page 418 =301 $error_prefix/301;
location = $error_prefix/301 {
    internal;
    default_type text/html;
    more_set_headers "Location: https://\$host\$request_uri";
    return 200 "$(angie_stock_page 301 "Moved Permanently")";
}

location / {
    return 418;
}
EOF

    cat >"$dir/snippets/proxy.conf" <<'EOF'
proxy_http_version 1.1;
proxy_read_timeout 300s;
proxy_set_header Host $host;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
EOF

    cat >"$dir/snippets/deny.conf" <<'EOF'
location / {
    return 403;
}
EOF

    cat >"$dir/snippets/subscription.conf" <<'EOF'
location = / {
    return 403;
}

location / {
    include /etc/angie/snippets/proxy.conf;
    proxy_intercept_errors on;
    proxy_pass http://127.0.0.1:3010;
}
EOF
}

# Protect the panel according to the chosen auth type:
#   cookie - 403 until the secret link has been opened once
#   full   - 401 until the Basic Auth credentials have been entered once
# The panel UI sends "Authorization: Bearer" to its API, which replaces the Basic
# credentials, so both types keep the session in a cookie.
write_angie_panel_auth() {
    local dir="$1"
    local auth_type="$2"
    local cookie_attrs="Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=2592000"
    local auth_file="$dir/conf.d/panel-auth.conf"

    # Only the master process reads the config, so the secrets can stay root-only
    touch "$auth_file"
    chmod 600 "$auth_file"

    if [ "$auth_type" = "full" ]; then
        printf '%s:%s\n' "$ANGIE_AUTH_USER" \
            "$(printf '%s\n' "$ANGIE_AUTH_PASSWORD" | openssl passwd -apr1 -stdin)" \
            >"$dir/snippets/.htpasswd"
        # Workers read this file on each request; it holds only a password hash
        chmod 644 "$dir/snippets/.htpasswd"

        cat >"$auth_file" <<EOF
map \$cookie_$PANEL_COOKIE_NAME \$panel_auth_realm {
    "$PANEL_SECRET_KEY" off;
    default "Restricted";
}

map \$host \$panel_set_cookie {
    default "$PANEL_COOKIE_NAME=$PANEL_SECRET_KEY; $cookie_attrs";
}

map \$http_authorization \$panel_upstream_authorization {
    "~*^basic " "";
    default \$http_authorization;
}
EOF

        cat >"$dir/snippets/panel.conf" <<'EOF'
location / {
    auth_basic $panel_auth_realm;
    auth_basic_user_file /etc/angie/snippets/.htpasswd;
    add_header Set-Cookie $panel_set_cookie;

    include /etc/angie/snippets/proxy.conf;
    proxy_set_header Authorization $panel_upstream_authorization;
    proxy_pass http://127.0.0.1:3000;
}
EOF
    else
        cat >"$auth_file" <<EOF
map \$cookie_$PANEL_COOKIE_NAME \$panel_cookie_allowed {
    "$PANEL_SECRET_KEY" 1;
    default 0;
}

map \$arg_$PANEL_COOKIE_NAME \$panel_allowed {
    "$PANEL_SECRET_KEY" 1;
    default \$panel_cookie_allowed;
}

map \$arg_$PANEL_COOKIE_NAME \$panel_set_cookie {
    "$PANEL_SECRET_KEY" "$PANEL_COOKIE_NAME=$PANEL_SECRET_KEY; $cookie_attrs";
    default "";
}
EOF

        cat >"$dir/snippets/panel.conf" <<'EOF'
location / {
    if ($panel_allowed = 0) {
        return 403;
    }
    add_header Set-Cookie $panel_set_cookie;

    include /etc/angie/snippets/proxy.conf;
    proxy_pass http://127.0.0.1:3000;
}
EOF
    fi

    # OAuth providers redirect back without the cookie: SameSite=Strict withholds it on
    # cross-site navigation. Every real callback carries both "code" and "state".
    cat >>"$dir/snippets/panel.conf" <<'EOF'

location ^~ /oauth2/ {
    if ($arg_code = "") {
        return 403;
    }
    if ($arg_state = "") {
        return 403;
    }

    include /etc/angie/snippets/proxy.conf;
    proxy_pass http://127.0.0.1:3000;
}
EOF
}

# Let's Encrypt prefers IPv6 when a domain has an AAAA record, so also listen on it.
# Binding [::] fails on hosts with IPv6 disabled, hence the check.
angie_has_ipv6() {
    grep -q . /proc/net/if_inet6 2>/dev/null
}

# Print "listen" lines for port 80
angie_http_listens() {
    local params="$1"

    echo "    listen 80$params;"
    if angie_has_ipv6; then
        echo "    listen [::]:80$params;"
    fi
}

# Print "listen" lines for TLS. Behind Xray only loopback is served: Xray owns
# 0.0.0.0:443 and passes everything its core cannot handle to this port as plain TLS.
angie_tls_listens() {
    local mode="$1"
    local params="$2"

    if [ "$mode" = "xray" ]; then
        echo "    listen 127.0.0.1:$SELFSTEAL_PORT ssl$params;"
    else
        echo "    listen 443 ssl$params;"
        if angie_has_ipv6; then
            echo "    listen [::]:443 ssl$params;"
        fi
    fi
}

# Write ACME clients and server blocks.
#   mode    - direct (Angie owns port 443) or xray (Xray owns port 443 and falls back)
#   sites   - "client:domain:snippet", one certificate per client so that the
#             selfsteal certificate never reveals the panel and subscription domains
# Certificates are validated over port 80 and never pass through Xray.
write_angie_sites() {
    local dir="$1"
    local mode="$2"
    shift 2

    local site client domain snippet domains=""

    {
        # A failed challenge is retried after 15 minutes: 4 attempts per hour stay
        # under the Let's Encrypt limit of 5 failed validations per hour
        for site in "$@"; do
            IFS=: read -r client domain snippet <<<"$site"
            domains+=" $domain"
            echo "acme_client $client $ACME_DIRECTORY_URL retry_after_error=15m;"
        done

        cat <<EOF

server {
$(angie_http_listens " default_server")
    server_name _;
    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/deny.conf;
}

server {
$(angie_http_listens "")
    server_name$domains;
    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/redirect.conf;
}

server {
$(angie_tls_listens "$mode" " default_server")
    server_name _;
    ssl_reject_handshake on;
}
EOF

        for site in "$@"; do
            IFS=: read -r client domain snippet <<<"$site"
            cat <<EOF

server {
$(angie_tls_listens "$mode" "")
    http2 on;
    server_name $domain;

    acme $client;
    ssl_certificate \$acme_cert_$client;
    ssl_certificate_key \$acme_cert_key_$client;

    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/$snippet.conf;
}
EOF
        done
    } >"$dir/conf.d/sites.conf"
}

# Write the config for a VLESS TLS node: Xray owns port 443 with the certificate issued
# here and falls back to 127.0.0.1:$SELFSTEAL_PORT as plain HTTP, so Angie serves no TLS.
# A client that negotiated h2 with Xray falls back as h2c, which "http2 on" accepts
# next to HTTP/1.1 on the same port.
write_angie_tls_fallback_sites() {
    local dir="$1"
    local client="$2"
    local domain="$3"

    cat >"$dir/conf.d/sites.conf" <<EOF
acme_client $client $ACME_DIRECTORY_URL retry_after_error=15m;

server {
$(angie_http_listens " default_server")
    server_name _;
    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/deny.conf;
}

server {
$(angie_http_listens "")
    server_name $domain;

    acme $client;

    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/redirect.conf;
}

server {
    listen 127.0.0.1:$SELFSTEAL_PORT default_server;
    http2 on;
    server_name _;
    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/deny.conf;
}
EOF
}

write_angie_docker_compose() {
    local dir="$1"
    local mode="$2"
    local container="$3"

    local healthcheck=""
    if [ "$mode" = "xray" ]; then
        healthcheck="        healthcheck:
            test: [\"CMD\", \"nc\", \"-z\", \"127.0.0.1\", \"$SELFSTEAL_PORT\"]
            interval: 2s
            timeout: 5s
            retries: 15
            start_period: 5s"$'\n'
    fi

    cat >"$dir/docker-compose.yml" <<EOF
services:
    angie:
        image: $ANGIE_IMAGE
        container_name: $container
        hostname: $container
        restart: unless-stopped
        volumes:
            - ./angie.conf:/etc/angie/angie.conf:ro
            - ./conf.d:/etc/angie/conf.d:ro
            - ./snippets:/etc/angie/snippets:ro
            - $ANGIE_ACME_VOLUME:$ANGIE_ACME_DIR
        network_mode: host
${healthcheck}        logging:
            driver: 'json-file'
            options:
                max-size: '100m'
                max-file: '5'

volumes:
    $ANGIE_ACME_VOLUME:
        driver: local
        external: false
        name: $ANGIE_ACME_VOLUME
EOF

    create_makefile "$dir"
}

# Setting up Angie for the panel and subscription page, directly on port 443
setup_angie_panel_only() {
    local auth_type="$1"
    local dir="$REMNAWAVE_DIR/angie"

    write_angie_base_config "$dir"
    write_angie_panel_auth "$dir" "$auth_type"
    write_angie_sites "$dir" "direct" \
        "panel:$PANEL_DOMAIN:panel" \
        "subscription:$SUB_DOMAIN:subscription"
    write_angie_docker_compose "$dir" "direct" "angie-remnawave"
}

# Setting up Angie for All-in-One: Xray owns port 443 and falls back to Angie
setup_angie_all_in_one() {
    local auth_type="$1"
    local dir="$REMNAWAVE_DIR/angie"

    write_angie_base_config "$dir"
    write_angie_panel_auth "$dir" "$auth_type"
    write_angie_sites "$dir" "xray" \
        "panel:$PANEL_DOMAIN:panel" \
        "subscription:$SUB_DOMAIN:subscription" \
        "selfsteal:$SELF_STEAL_DOMAIN:deny"
    write_angie_docker_compose "$dir" "xray" "angie-remnawave"
}

start_angie() {
    if ! start_container "$REMNAWAVE_DIR/angie" "Angie"; then
        show_error "$(t services_installation_stopped)"
        exit 1
    fi
}

# Wait for the first issuance. Angie keeps retrying on its own, so a timeout (usually
# DNS or port 80 not ready yet) is a warning rather than a reason to stop the install.
wait_for_angie_certificates() {
    local dir="$1"
    shift

    local pending=("$@") still_pending client
    local max_wait=180 poll=3 elapsed=0

    show_info "$(t waiting_for_certificates)" "$ORANGE"

    while true; do
        still_pending=()
        for client in "${pending[@]}"; do
            if ! docker compose -f "$dir/docker-compose.yml" exec -T angie \
                test -s "$ANGIE_ACME_DIR/$client/certificate.pem" >/dev/null 2>&1; then
                still_pending+=("$client")
            fi
        done
        pending=("${still_pending[@]}")

        if [ ${#pending[@]} -eq 0 ]; then
            show_success "$(t certificates_ready)"
            return 0
        fi
        if [ $elapsed -ge $max_wait ]; then
            show_warning "$(t certificates_timeout) ${pending[*]}"
            show_warning "$(t certificates_timeout_hint) cd $dir && docker compose logs angie"
            docker compose -f "$dir/docker-compose.yml" logs --no-log-prefix --tail=200 angie 2>&1 |
                grep -E 'acme_client|ACME' | tail -n 10
            return 1
        fi

        sleep $poll
        ((elapsed += poll))
    done
}
