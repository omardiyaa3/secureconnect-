#!/bin/bash
# SecureConnect VPN CLI Uninstaller
# Works on all Linux distributions

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
SUDOERS_FILE="/etc/sudoers.d/secureconnect"

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        success) echo -e "${GREEN}✓${NC} $message" ;;
        error)   echo -e "${RED}✗${NC} $message" ;;
        info)    echo -e "${BLUE}ℹ${NC} $message" ;;
        warning) echo -e "${YELLOW}!${NC} $message" ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status error "This uninstaller must be run as root (use sudo)"
        echo "  sudo ./uninstall.sh"
        exit 1
    fi
}

# Disconnect VPN if connected
disconnect_vpn() {
    if ip link show sc0 &>/dev/null 2>&1; then
        print_status info "Disconnecting active VPN connection..."
        "${INSTALL_DIR}/secureconnect" disconnect 2>/dev/null || true
        # Force cleanup
        ip link delete sc0 2>/dev/null || true
    fi
}

# Remove binaries
remove_binaries() {
    print_status info "Removing SecureConnect binaries..."

    local files=(
        "secureconnect"
        "secureconnect-vpn"
        "secureconnect-dpi.sh"
        "secureconnect-go"
        "secureconnect-ctl"
    )

    for file in "${files[@]}"; do
        if [[ -f "${INSTALL_DIR}/${file}" ]]; then
            rm -f "${INSTALL_DIR}/${file}"
            print_status success "Removed ${file}"
        fi
    done
}

# Remove sudoers configuration
remove_sudoers() {
    if [[ -f "$SUDOERS_FILE" ]]; then
        print_status info "Removing sudoers configuration..."
        rm -f "$SUDOERS_FILE"
        print_status success "Removed sudoers file"
    fi
}

# Remove system directories
remove_directories() {
    if [[ -d "/etc/secureconnect" ]]; then
        print_status info "Removing system configuration..."
        rm -rf /etc/secureconnect
        print_status success "Removed /etc/secureconnect"
    fi
}

# Ask about user config
handle_user_config() {
    echo
    read -rp "Remove user configuration (~/.secureconnect)? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        # Remove for all users
        for user_home in /home/*; do
            if [[ -d "${user_home}/.secureconnect" ]]; then
                rm -rf "${user_home}/.secureconnect"
                print_status success "Removed ${user_home}/.secureconnect"
            fi
        done
        # Also check root
        if [[ -d "/root/.secureconnect" ]]; then
            rm -rf "/root/.secureconnect"
            print_status success "Removed /root/.secureconnect"
        fi
    else
        print_status info "User configuration preserved"
    fi
}

# Main uninstallation
main() {
    echo
    echo -e "${BLUE}SecureConnect VPN CLI Uninstaller${NC}"
    echo "=================================="
    echo

    check_root
    disconnect_vpn
    remove_binaries
    remove_sudoers
    remove_directories
    handle_user_config

    echo
    print_status success "SecureConnect CLI has been uninstalled"
    echo
}

main "$@"
