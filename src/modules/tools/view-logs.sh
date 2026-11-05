#!/bin/bash

# ===================================================================================
#                              VIEW LOGS FUNCTION
# ===================================================================================

# View logs from Docker containers
view_logs() {
    local dir=""
    local has_panel=false
    local has_node=false

    # Check what's installed
    [ -d "$REMNAWAVE_DIR" ] && has_panel=true
    [ -d "$LOCAL_REMNANODE_DIR" ] && has_node=true
    # Also check standalone node installation
    [ -d "$REMNANODE_DIR" ] && has_node=true

    # Nothing installed
    if [ "$has_panel" = false ] && [ "$has_node" = false ]; then
        echo
        show_error "$(t logs_dir_not_found)"
        echo -e "${BOLD_YELLOW}$(t prompt_enter_to_return)${NC}"
        read -r
        return 1
    fi

    # If both panel and node exist (all-in-one), show menu
    if [ "$has_panel" = true ] && [ -d "$LOCAL_REMNANODE_DIR" ]; then
        echo
        echo -e "${BOLD_GREEN}$(t logs_select_component)${NC}"
        echo
        echo -e "${GREEN}1.${NC} $(t logs_option_panel)"
        echo -e "${GREEN}2.${NC} $(t logs_option_node)"
        echo
        echo -e "${GREEN}0.${NC} $(t logs_option_back)"
        echo
        echo -ne "${BOLD_BLUE_MENU}$(t main_menu_select_option) ${NC}"
        read -r choice

        case $choice in
            1) dir="$REMNAWAVE_DIR" ;;
            2) dir="$LOCAL_REMNANODE_DIR" ;;
            0) return 0 ;;
            *) return 0 ;;
        esac
    elif [ "$has_panel" = true ]; then
        dir="$REMNAWAVE_DIR"
    elif [ -d "$REMNANODE_DIR" ]; then
        dir="$REMNANODE_DIR"
    fi

    cd "$dir"

    # Check if any containers are running
    if ! docker compose ps -q 2>/dev/null | grep -q .; then
        echo
        show_error "$(t logs_container_not_running)"
        echo -e "${BOLD_YELLOW}$(t prompt_enter_to_return)${NC}"
        read -r
        return 1
    fi

    echo
    show_info "$(t logs_viewing)" "$YELLOW"
    show_info "$(t logs_exit_hint)" "$ORANGE"
    echo

    docker compose logs -f -t
}
