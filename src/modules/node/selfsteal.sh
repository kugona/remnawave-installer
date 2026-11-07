#!/bin/bash

# ===================================================================================
#                              INSTALLATION OF STEAL ONESELF SITE (Node-Only)
# ===================================================================================

# SELFSTEAL_PORT is defined in constants.sh

# vless_mode - reality (Angie serves TLS for REALITY) or tls (Xray serves TLS itself)
setup_selfsteal() {
    local vless_mode="${1:-reality}"

    mkdir -p "$SELFSTEAL_DIR"
    cd "$SELFSTEAL_DIR"

    write_angie_base_config "$SELFSTEAL_DIR"
    if [ "$vless_mode" = "tls" ]; then
        write_angie_tls_fallback_sites "$SELFSTEAL_DIR" "selfsteal" "$SELF_STEAL_DOMAIN"
    else
        write_angie_sites "$SELFSTEAL_DIR" "xray" "selfsteal:$SELF_STEAL_DOMAIN:deny"
    fi
    write_angie_docker_compose "$SELFSTEAL_DIR" "xray" "angie-selfsteal"

    if ! start_container "$SELFSTEAL_DIR" "Angie"; then
        show_error "$(t selfsteal_installation_stopped)"
        exit 1
    fi

    if ! wait_for_angie_certificates "$SELFSTEAL_DIR" "selfsteal" && [ "$vless_mode" = "tls" ]; then
        show_warning "$(t node_tls_certificate_missing)"
    fi

    ANGIE_STATUS=$(docker compose ps --services --filter "status=running" | grep -q "angie" && echo "running" || echo "stopped")

    if [ "$ANGIE_STATUS" = "running" ]; then
        echo -e "${LIGHT_GREEN}$(t selfsteal_domain_info) ${BOLD_GREEN}$SELF_STEAL_DOMAIN${NC}"
        echo -e "${LIGHT_GREEN}$(t selfsteal_directory_info) ${BOLD_GREEN}$SELFSTEAL_DIR${NC}"
        echo
    fi
}
