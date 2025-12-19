#!/bin/bash
# SecureConnect VPN CLI Installer
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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
        print_status error "This installer must be run as root (use sudo)"
        echo "  sudo ./install.sh"
        exit 1
    fi
}

# Check for required system tools
check_system_deps() {
    local missing=()

    # Check for ip command
    if ! command -v ip &> /dev/null; then
        missing+=("iproute2")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_status warning "Missing system tools: ${missing[*]}"
        echo "Please install them first"
    fi
}

# Install binaries
install_binaries() {
    print_status info "Installing SecureConnect CLI to ${INSTALL_DIR}..."

    # List of files to install
    local files=(
        "secureconnect"
        "secureconnect-vpn"
        "secureconnect-dpi.sh"
        "secureconnect-go"
        "secureconnect-ctl"
    )

    for file in "${files[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
            cp "${SCRIPT_DIR}/${file}" "${INSTALL_DIR}/"
            chmod +x "${INSTALL_DIR}/${file}"
            print_status success "Installed ${file}"
        else
            print_status warning "File not found: ${file}"
        fi
    done
}

# Setup sudoers for passwordless VPN operations
setup_sudoers() {
    print_status info "Configuring passwordless sudo access..."

    cat > "$SUDOERS_FILE" << EOF
# SecureConnect VPN - Passwordless sudo access for all users
# Installed by SecureConnect CLI installer

ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-vpn
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-vpn *
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-dpi.sh
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-dpi.sh *
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-ctl
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-ctl *
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-go
ALL ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/secureconnect-go *
ALL ALL=(ALL) NOPASSWD: /usr/bin/ip
ALL ALL=(ALL) NOPASSWD: /usr/bin/ip *
ALL ALL=(ALL) NOPASSWD: /sbin/ip
ALL ALL=(ALL) NOPASSWD: /sbin/ip *
ALL ALL=(ALL) NOPASSWD: /usr/bin/resolvectl
ALL ALL=(ALL) NOPASSWD: /usr/bin/resolvectl *
ALL ALL=(ALL) NOPASSWD: /usr/bin/pkill
EOF

    chmod 0440 "$SUDOERS_FILE"

    # Verify sudoers syntax
    if visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
        print_status success "Sudoers configured successfully"
    else
        print_status error "Sudoers configuration failed"
        rm -f "$SUDOERS_FILE"
        exit 1
    fi
}

# Create necessary directories
create_directories() {
    # Create config directory for wireguard configs
    mkdir -p /etc/secureconnect
    chmod 755 /etc/secureconnect
}

# Print post-install instructions
print_instructions() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         SecureConnect CLI installed successfully!          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Usage:"
    echo "  secureconnect login --portal vpn.company.com --user yourname"
    echo "  secureconnect connect"
    echo "  secureconnect connect --dpi    # With DPI bypass"
    echo "  secureconnect status"
    echo "  secureconnect disconnect"
    echo
    echo "For help: secureconnect help"
    echo
}

# Main installation
main() {
    echo
    echo -e "${BLUE}SecureConnect VPN CLI Installer${NC}"
    echo "================================"
    echo

    check_root
    check_system_deps
    install_binaries
    setup_sudoers
    create_directories
    print_instructions
}

main "$@"
