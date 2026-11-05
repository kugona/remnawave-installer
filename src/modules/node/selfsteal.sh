#!/bin/bash

# ===================================================================================
#                              INSTALLATION OF STEAL ONESELF SITE (Node-Only)
# ===================================================================================

# SELFSTEAL_PORT is defined in constants.sh

setup_selfsteal() {
    local connection_type="${1:-socket}"

    mkdir -p "$SELFSTEAL_DIR"
    cd "$SELFSTEAL_DIR"

    write_angie_base_config "$SELFSTEAL_DIR"
    write_angie_sites "$SELFSTEAL_DIR" "$connection_type" "selfsteal:$SELF_STEAL_DOMAIN:deny"
    write_angie_docker_compose "$SELFSTEAL_DIR" "$connection_type" "angie-selfsteal"

    if ! start_container "$SELFSTEAL_DIR" "Angie"; then
        show_error "$(t selfsteal_installation_stopped)"
        exit 1
    fi

    wait_for_angie_certificates "$SELFSTEAL_DIR" "selfsteal"

    ANGIE_STATUS=$(docker compose ps --services --filter "status=running" | grep -q "angie" && echo "running" || echo "stopped")

    if [ "$ANGIE_STATUS" = "running" ]; then
        echo -e "${LIGHT_GREEN}$(t selfsteal_domain_info) ${BOLD_GREEN}$SELF_STEAL_DOMAIN${NC}"
        if [ "$connection_type" = "port" ]; then
            echo -e "${LIGHT_GREEN}$(t selfsteal_port_info) ${BOLD_GREEN}$SELFSTEAL_PORT${NC}"
        fi
        echo -e "${LIGHT_GREEN}$(t selfsteal_directory_info) ${BOLD_GREEN}$SELFSTEAL_DIR${NC}"
        echo
    fi
}
