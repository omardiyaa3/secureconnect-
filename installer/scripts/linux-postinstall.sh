#!/bin/bash
# SecureConnect Linux Post-Installation Script
# Configures passwordless sudo for VPN operations

echo "Configuring SecureConnect VPN helper for Linux..."

# Get the user who is installing
INSTALL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"

# Paths to bundled binaries
APP_PATH="/opt/SecureConnect/resources/bin/linux"
SECURECONNECT_VPN="${APP_PATH}/secureconnect-vpn"
SECURECONNECT_DPI="${APP_PATH}/secureconnect-dpi.sh"
SECURECONNECT_CTL="${APP_PATH}/secureconnect-ctl"
SECURECONNECT_GO="${APP_PATH}/secureconnect-go"

# Create sudoers configuration
SUDOERS_FILE="/etc/sudoers.d/secureconnect"

cat > "$SUDOERS_FILE" << EOF
# SecureConnect VPN - Passwordless sudo access
# Bundled SecureConnect binaries
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_VPN
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_VPN up *
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_VPN down *
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_DPI
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_DPI up *
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_DPI down *
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_CTL
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_CTL *
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_GO
$INSTALL_USER ALL=(ALL) NOPASSWD: $SECURECONNECT_GO *

# System tools needed for VPN
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/resolvectl
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/resolvectl *
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/ip
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/ip *
$INSTALL_USER ALL=(ALL) NOPASSWD: /sbin/ip
$INSTALL_USER ALL=(ALL) NOPASSWD: /sbin/ip *
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill
EOF

# Set proper permissions
chmod 0440 "$SUDOERS_FILE"

# Verify syntax
if visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
    echo "✓ SecureConnect VPN helper configured successfully"
    exit 0
else
    echo "✗ Error: Invalid sudoers syntax"
    rm -f "$SUDOERS_FILE"
    exit 1
fi
