#!/bin/bash
# Setup passwordless sudo for WireGuard commands
# This allows SecureConnect to connect/disconnect without password prompts

echo "Setting up passwordless sudo for WireGuard..."

# Get current user
CURRENT_USER=$(whoami)

# Get full path to wg-quick
WG_QUICK_PATH="/opt/homebrew/bin/wg-quick"

if [ ! -f "$WG_QUICK_PATH" ]; then
    echo "Error: wg-quick not found at $WG_QUICK_PATH"
    echo "Please install: brew install wireguard-tools"
    exit 1
fi

# Create sudoers file for WireGuard
SUDOERS_FILE="/private/etc/sudoers.d/secureconnect-wireguard"

echo "Creating sudoers configuration..."

# Create sudoers entry
cat > /tmp/secureconnect-wireguard << EOF
# SecureConnect - Passwordless WireGuard access
# This allows the user to run wg-quick without password
$CURRENT_USER ALL=(ALL) NOPASSWD: $WG_QUICK_PATH
EOF

# Install with proper permissions
sudo install -m 0440 /tmp/secureconnect-wireguard "$SUDOERS_FILE"

# Verify syntax
if sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
    echo "✓ Successfully configured passwordless sudo for WireGuard"
    echo "✓ You can now connect/disconnect without password prompts"
    rm /tmp/secureconnect-wireguard
else
    echo "✗ Error: Invalid sudoers syntax"
    sudo rm -f "$SUDOERS_FILE"
    rm /tmp/secureconnect-wireguard
    exit 1
fi

echo ""
echo "Configuration complete!"
echo "You can now use SecureConnect without password prompts."
