# ===================================================================================
#                              REMNAWAVE NODE INSTALLATION (Node-Only)
# ===================================================================================

# Select which VLESS transport Angie is set up for
select_node_vless_mode() {
    echo -e "${BOLD_BLUE}$(t node_vless_mode_title)${NC}"
    echo
    echo -e "  ${BOLD_GREEN}1)${NC} $(t node_vless_mode_reality)"
    echo -e "     ${YELLOW}$(t node_vless_mode_reality_desc)${NC}"
    echo
    echo -e "  ${BOLD_GREEN}2)${NC} $(t node_vless_mode_tls)"
    echo -e "     ${YELLOW}$(t node_vless_mode_tls_desc)${NC}"
    echo

    while true; do
        read -p "$(echo -e "${ORANGE}$(t main_menu_select_option) ${NC}")" choice
        case $choice in
        1)
            NODE_VLESS_MODE="reality"
            break
            ;;
        2)
            NODE_VLESS_MODE="tls"
            break
            ;;
        *)
            echo -e "${BOLD_RED}$(t error_invalid_choice)${NC}"
            ;;
        esac
    done
    echo
}

# Create docker-compose for Node
create_node_docker_compose() {
    local certificate="$1"
    local vless_mode="${2:-reality}"

    # VLESS TLS: Xray reads the certificate Angie issues and renews. It reloads
    # certificate files every hour, so renewals need no restart.
    local acme_volume="" acme_volume_definition=""
    if [ "$vless_mode" = "tls" ]; then
        acme_volume="            - $ANGIE_ACME_VOLUME:$ANGIE_ACME_DIR:ro"$'\n'
        acme_volume_definition="
volumes:
    $ANGIE_ACME_VOLUME:
        external: true
        name: $ANGIE_ACME_VOLUME"
    fi

    mkdir -p "$REMNANODE_DIR"
    cd "$REMNANODE_DIR"

    cat >docker-compose.yml <<EOF
services:
    remnanode:
        container_name: remnanode
        hostname: remnanode
        image: remnawave/node:$REMNAWAVE_NODE_TAG
        network_mode: host
        restart: always
        cap_add:
            - NET_ADMIN
        ulimits:
            nofile:
                soft: 1048576
                hard: 1048576
        environment:
            - NODE_PORT=$NODE_PORT
            - SECRET_KEY=$certificate
        volumes:
            - /dev/shm:/dev/shm
            - /var/log/remnanode:/var/log/remnanode
${acme_volume}        logging:
            driver: 'json-file'
            options:
                max-size: '100m'
                max-file: '5'
${acme_volume_definition}
EOF

    create_makefile "$REMNANODE_DIR"
}

collect_node_selfsteal_domain() {
    SELF_STEAL_DOMAIN=$(prompt_domain "$(t node_enter_selfsteal_domain)" "$ORANGE" true false false)
}

check_node_ports() {
    # Check required Node API port 2222
    if NODE_PORT=$(check_required_port "2222"); then
        show_info "$(t config_node_port_available)"
    else
        show_error "$(t node_port_2222_in_use)"
        show_error "$(t node_separate_port_2222)"
        show_error "$(t node_free_port_2222)"
        show_error "$(t node_cannot_continue_2222)"
        exit 1
    fi
}

# Collect SSL certificate for node
collect_node_ssl_certificate() {
    while true; do
        echo -e "${ORANGE}$(t node_enter_ssl_cert) ${NC}"
        CERTIFICATE=""
        while IFS= read -r line; do
            if [ -z "$line" ]; then
                if [ -n "$CERTIFICATE" ]; then
                    break
                fi
            else
                CERTIFICATE="${CERTIFICATE}${line}"
            fi
        done

        # Validate SSL certificate format
        if validate_ssl_certificate "$CERTIFICATE"; then
            echo -e "${BOLD_GREEN}$(t node_ssl_cert_valid)${NC}"
            echo
            break
        else
            echo -e "${BOLD_RED}$(t node_ssl_cert_invalid)${NC}"
            echo -e "${YELLOW}$(t node_ssl_cert_expected)${NC}"
            echo
        fi
    done
}

collect_panel_ip() {
    while true; do
        PANEL_IP=$(simple_read_domain_or_ip "$(t node_enter_panel_ip)" "" "ip_only")
        if [ -n "$PANEL_IP" ]; then
            break
        fi
    done
}

allow_ufw_node_port_from_panel_ip() {
    echo "$(t node_allow_connections)"
    echo
    ufw allow from "$PANEL_IP" to any port 2222 proto tcp
    echo
    ufw reload >/dev/null 2>&1
}

# Start node container and show results
start_node_and_show_results() {
    # Wait for Angie before starting Node
    if ! wait_for_angie 30; then
        show_error "$(t error_angie_timeout)"
        exit 1
    fi

    if ! start_container "$REMNANODE_DIR" "Remnawave Node"; then
        show_error "$(t services_installation_stopped)"
        exit 1
    fi

    echo -e "${LIGHT_GREEN}$(t node_port_info) ${BOLD_GREEN}$NODE_PORT${NC}"
    echo -e "${LIGHT_GREEN}$(t node_directory_info) ${BOLD_GREEN}$REMNANODE_DIR${NC}"
    echo
}

# Print the inbound to use in the panel's config profile for a VLESS TLS node
show_node_tls_inbound() {
    local cert_dir="$ANGIE_ACME_DIR/selfsteal"

    echo -e "${BOLD_GREEN}$(t node_tls_profile_title)${NC}"
    echo -e "${YELLOW}$(t node_tls_profile_hint)${NC}"
    echo
    cat <<EOF
{
  "tag": "VLESS_TLS",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none",
    "fallbacks": [
      { "dest": "127.0.0.1:$SELFSTEAL_PORT", "xver": 0 }
    ]
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "serverName": "$SELF_STEAL_DOMAIN",
      "alpn": ["h2", "http/1.1"],
      "certificates": [
        {
          "certificateFile": "$cert_dir/certificate.pem",
          "keyFile": "$cert_dir/private.key"
        }
      ]
    }
  }
}
EOF
    echo
    echo -e "${YELLOW}$(t node_tls_profile_host) ${BOLD_GREEN}$SELF_STEAL_DOMAIN${NC}"
    echo
}

setup_node() {
    clear

    # Preparation for node-only installation
    if ! prepare_node_installation; then
        return 1
    fi

    collect_node_selfsteal_domain

    collect_panel_ip

    allow_ufw_node_port_from_panel_ip

    check_node_ports

    select_node_vless_mode

    collect_node_ssl_certificate

    # Create node docker-compose
    create_node_docker_compose "$CERTIFICATE" "$NODE_VLESS_MODE"

    setup_node_log_rotation

    # Setup and start Angie (in selfsteal.sh); it creates the certificate volume first
    setup_selfsteal "$NODE_VLESS_MODE"

    # Start node (waits for Angie)
    start_node_and_show_results

    if [ "$NODE_VLESS_MODE" = "tls" ]; then
        show_node_tls_inbound
    fi

    unset CERTIFICATE
    unset NODE_PORT
    unset SELF_STEAL_DOMAIN
    unset NODE_VLESS_MODE

    echo -e "\n${BOLD_GREEN}$(t node_press_enter_return)${NC}"
    read -r
}
