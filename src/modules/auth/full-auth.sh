#!/bin/bash

# ===================================================================================
#                              FULL AUTH SHARED FUNCTIONS
# ===================================================================================

# Generate full auth specific secrets
generate_full_auth_secrets() {
    generate_panel_access_secret
    ANGIE_AUTH_USER=$(generate_readable_login)
    ANGIE_AUTH_PASSWORD=$(generate_secure_password 25)
}

# Save credentials for full auth
save_credentials_full_auth() {
    CREDENTIALS_FILE="$REMNAWAVE_DIR/credentials.txt"
    echo "PANEL URL: https://$PANEL_DOMAIN/auth/login" >>"$CREDENTIALS_FILE"
    echo >>"$CREDENTIALS_FILE"
    echo "REMNAWAVE ADMIN USERNAME: $SUPERADMIN_USERNAME" >>"$CREDENTIALS_FILE"
    echo "REMNAWAVE ADMIN PASSWORD: $SUPERADMIN_PASSWORD" >>"$CREDENTIALS_FILE"
    echo >>"$CREDENTIALS_FILE"
    echo "BASIC AUTH USERNAME: $ANGIE_AUTH_USER" >>"$CREDENTIALS_FILE"
    echo "BASIC AUTH PASSWORD: $ANGIE_AUTH_PASSWORD" >>"$CREDENTIALS_FILE"
    echo >>"$CREDENTIALS_FILE"

    chmod 600 "$CREDENTIALS_FILE"
}

display_full_auth_results() {
    local installation_type="${1:-panel}"
    local panel_url="https://$PANEL_DOMAIN/auth/login"

    # Calculate width based on longest line
    local max_width=${#panel_url}
    if [ -n "$USER_SUBSCRIPTION_URL" ] && [ "$installation_type" = "all-in-one" ]; then
        if [ ${#USER_SUBSCRIPTION_URL} -gt $max_width ]; then
            max_width=${#USER_SUBSCRIPTION_URL}
        fi
    fi
    local effective_width=$((max_width + 3))
    local border_line=$(printf '─%.0s' $(seq 1 $effective_width))

    print_text_line() {
        local text="$1"
        local padding=$((effective_width - ${#text} - 1))
        echo -e "\033[1m│ $text$(printf '%*s' $padding)│\033[0m"
    }

    print_empty_line() {
        echo -e "\033[1m│$(printf '%*s' $effective_width)│\033[0m"
    }

    echo -e "\033[1m┌${border_line}┐\033[0m"

    print_text_line "$(t results_panel_url)"
    print_text_line "$panel_url"
    print_empty_line

    # Show subscription URL only for all-in-one installation
    if [ "$installation_type" = "all-in-one" ] && [ -n "$USER_SUBSCRIPTION_URL" ] && [ "$USER_SUBSCRIPTION_URL" != "null" ]; then
        print_text_line "$(t results_user_subscription_url)"
        print_text_line "$USER_SUBSCRIPTION_URL"
        print_empty_line
    fi

    print_text_line "$(t results_basic_auth_login) $ANGIE_AUTH_USER"
    print_text_line "$(t results_basic_auth_password) $ANGIE_AUTH_PASSWORD"
    print_empty_line
    print_text_line "$(t results_remnawave_admin_login) $SUPERADMIN_USERNAME"
    print_text_line "$(t results_remnawave_admin_password) $SUPERADMIN_PASSWORD"
    print_empty_line
    echo -e "\033[1m└${border_line}┘\033[0m"

    echo
    show_success "$(t success_credentials_saved) $CREDENTIALS_FILE"
    echo -e "${BOLD_BLUE}$(t info_installation_directory) ${NC}$REMNAWAVE_DIR/"
    echo

    # Show QR code for subscription URL if available
    if [ "$installation_type" = "all-in-one" ] && [ -n "$USER_SUBSCRIPTION_URL" ] && [ "$USER_SUBSCRIPTION_URL" != "null" ]; then
        generate_qr_code "$USER_SUBSCRIPTION_URL" "$(t qr_subscription_url)"
        echo
    fi

    cd ~

    echo -e "${BOLD_GREEN}$(t success_installation_complete)${NC}"
    read -r
}
