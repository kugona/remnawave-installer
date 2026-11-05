#!/bin/bash

# ===================================================================================
#                          EMERGENCY PANEL ACCESS (PORT 8443)
# ===================================================================================

PANEL_ACCESS_CONF="$REMNAWAVE_DIR/angie/conf.d/zz-emergency.conf"

# Check if panel is installed
check_panel_for_access() {
    if [ ! -f "$REMNAWAVE_DIR/angie/docker-compose.yml" ]; then
        show_error "$(t panel_access_dir_not_found)"
        return 1
    fi
    return 0
}

# Check if UFW is available and active
is_ufw_active() {
    if ! command -v ufw >/dev/null 2>&1; then
        return 1
    fi
    if ! ufw status | grep -q "Status: active"; then
        return 1
    fi
    return 0
}

# Open port 8443 in firewall
open_firewall_port() {
    if is_ufw_active; then
        ufw allow 8443/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    fi
}

# Close port 8443 in firewall
close_firewall_port() {
    if is_ufw_active; then
        if ufw status | grep -q "8443.*ALLOW"; then
            ufw delete allow 8443/tcp >/dev/null 2>&1
            ufw reload >/dev/null 2>&1
            return 0
        fi
    fi
    return 1
}

# Check if port 8443 is open in firewall
is_firewall_port_open() {
    if is_ufw_active; then
        ufw status | grep -q "8443.*ALLOW"
        return $?
    fi
    # If UFW is not active, consider port as open (no firewall blocking)
    return 0
}

# Get authentication type (cookie or full)
get_auth_type() {
    if [ -f "$REMNAWAVE_DIR/angie/snippets/.htpasswd" ]; then
        echo "full"
    else
        echo "cookie"
    fi
}

# Get panel domain from credentials
get_panel_domain() {
    grep "PANEL URL:" "$REMNAWAVE_DIR/credentials.txt" | sed 's|PANEL URL: https://||' | cut -d'/' -f1 | cut -d'?' -f1
}

# Get panel access link with secret key
get_panel_access_link() {
    local credentials_file="$REMNAWAVE_DIR/credentials.txt"

    if [ ! -f "$credentials_file" ]; then
        echo ""
        return 1
    fi

    local panel_domain=$(get_panel_domain)

    if [ "$(get_auth_type)" = "cookie" ]; then
        # For cookie-auth reuse the secret query from credentials URL
        local secret_query=$(grep "PANEL URL:" "$credentials_file" | sed 's/.*?//')
        echo "https://${panel_domain}:8443/auth/login?${secret_query}"
    else
        # For full-auth the Basic Auth credentials are requested by the browser
        echo "https://${panel_domain}:8443/auth/login"
    fi
}

# Check if the 8443 server block exists
has_8443_section() {
    [ -f "$PANEL_ACCESS_CONF" ]
}

# Add the 8443 server block, reusing the certificate of the panel domain
add_8443_section() {
    local panel_domain=$(get_panel_domain)

    cat >"$PANEL_ACCESS_CONF" <<EOF
server {
    listen 8443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}

server {
    listen 8443 ssl;
    http2 on;
    server_name $panel_domain;

    ssl_certificate \$acme_cert_panel;
    ssl_certificate_key \$acme_cert_key_panel;

    include /etc/angie/snippets/errors.conf;
    include /etc/angie/snippets/panel.conf;
}
EOF
}

# Remove the 8443 server block
remove_8443_section() {
    rm -f "$PANEL_ACCESS_CONF"
}

# Restart Angie container
restart_angie() {
    docker compose -f "$REMNAWAVE_DIR/angie/docker-compose.yml" restart angie >/dev/null 2>&1
}

# Open panel access via port 8443
open_panel_access() {
    if ! check_panel_for_access; then
        return 1
    fi

    # Check if already fully open (section exists and firewall allows)
    if has_8443_section && is_firewall_port_open; then
        show_warning "$(t panel_access_already_open)"
        local access_link=$(get_panel_access_link)
        if [ -n "$access_link" ]; then
            echo
            echo -e "${BOLD_GREEN}$(t panel_access_link)${NC}"
            echo -e "${access_link}"
            echo
        fi
        return 0
    fi

    # Run enabling with spinner
    (
        # Add 8443 server block if not exists
        if ! has_8443_section; then
            add_8443_section
            restart_angie
            sleep 2
        fi

        # Open port in firewall
        open_firewall_port
    ) &
    spinner $! "$(t panel_access_enabling)"

    local access_link=$(get_panel_access_link)

    echo
    show_success "$(t panel_access_port_opened)"
    echo
    if [ -n "$access_link" ]; then
        echo -e "${BOLD_GREEN}$(t panel_access_link)${NC}"
        echo -e "${access_link}"
        echo
    fi
    show_warning "$(t panel_access_warning)"
    echo
}

# Close panel access via port 8443
close_panel_access() {
    if ! check_panel_for_access; then
        return 1
    fi

    # Check if already closed
    if ! has_8443_section && ! is_firewall_port_open; then
        show_info "$(t panel_access_already_closed)"
        return 0
    fi

    # Run disabling with spinner
    (
        # Remove 8443 server block if exists
        if has_8443_section; then
            remove_8443_section
            restart_angie
        fi

        # Close port in firewall
        close_firewall_port
    ) &
    spinner $! "$(t panel_access_disabling)"

    echo
    show_success "$(t panel_access_port_closed)"
}

# Show panel access menu
show_panel_access_menu() {
    clear
    echo -e "${BOLD_GREEN}$(t panel_access_menu_title)${NC}"
    echo
    echo -e "${GREEN}1.${NC} $(t panel_access_open)"
    echo -e "${GREEN}2.${NC} $(t panel_access_close)"
    echo
    echo -e "${GREEN}0.${NC} $(t panel_access_back)"
    echo
    echo -ne "${BOLD_BLUE_MENU}$(t main_menu_select_option) ${NC}"
}

# Handle panel access menu
manage_panel_access() {
    # Check if panel is installed first
    if ! check_panel_for_access; then
        echo -e "${BOLD_YELLOW}$(t prompt_enter_to_return)${NC}"
        read -r
        return
    fi

    while true; do
        show_panel_access_menu
        read choice

        case $choice in
        1)
            open_panel_access
            echo -e "${BOLD_YELLOW}$(t prompt_enter_to_return)${NC}"
            read -r
            ;;
        2)
            close_panel_access
            echo -e "${BOLD_YELLOW}$(t prompt_enter_to_return)${NC}"
            read -r
            ;;
        0)
            return
            ;;
        *)
            show_error "$(t error_invalid_choice)"
            sleep 1
            ;;
        esac
    done
}
