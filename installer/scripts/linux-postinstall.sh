#!/bin/bash
# SecureConnect Linux Post-Installation Script
# Configures passwordless sudo for WireGuard operations

echo "Configuring SecureConnect VPN helper for Linux..."

# Get the user who is installing
INSTALL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"

# Create sudoers configuration
SUDOERS_FILE="/etc/sudoers.d/secureconnect"

cat > "$SUDOERS_FILE" << EOF
# SecureConnect VPN - Passwordless sudo access for WireGuard
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/wg-quick up *
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/wg-quick down *
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/wg
$INSTALL_USER ALL=(ALL) NOPASSWD: /usr/bin/resolvectl
$INSTALL_USER ALL=(ALL) NOPASSWD: /sbin/ip
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
