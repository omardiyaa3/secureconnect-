#!/bin/bash
# SecureConnect Linux Post-Installation Script
# Configures passwordless sudo for VPN operations

echo "Configuring SecureConnect VPN helper for Linux..."

# Paths to bundled binaries
APP_PATH="/opt/SecureConnect/resources/bin/linux"

# Create sudoers configuration - allow ALL users (simpler, works for everyone)
SUDOERS_FILE="/etc/sudoers.d/secureconnect"

cat > "$SUDOERS_FILE" << EOF
# SecureConnect VPN - Passwordless sudo access for all users
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-vpn
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-vpn *
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-dpi.sh
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-dpi.sh *
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-ctl
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-ctl *
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-go
ALL ALL=(ALL) NOPASSWD: ${APP_PATH}/secureconnect-go *
ALL ALL=(ALL) NOPASSWD: /usr/bin/resolvectl
ALL ALL=(ALL) NOPASSWD: /usr/bin/resolvectl *
ALL ALL=(ALL) NOPASSWD: /usr/bin/ip
ALL ALL=(ALL) NOPASSWD: /usr/bin/ip *
ALL ALL=(ALL) NOPASSWD: /sbin/ip
ALL ALL=(ALL) NOPASSWD: /sbin/ip *
ALL ALL=(ALL) NOPASSWD: /usr/bin/pkill
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
