#!/bin/bash
# SecureConnect DPI Bypass Wrapper
# This script sets up environment for DPI bypass and runs secureconnect-vpn

ACTION="$1"
CONFIG="$2"

if [ -z "$ACTION" ] || [ -z "$CONFIG" ]; then
    echo "Usage: secureconnect-dpi.sh <up|down> <config-file>"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Set up environment for DPI bypass (AmneziaWG userspace implementation)
export WG_QUICK_USERSPACE_IMPLEMENTATION="${SCRIPT_DIR}/secureconnect-go"
export PATH="${SCRIPT_DIR}:${PATH}"

# Run secureconnect-vpn with the action and config
exec "${SCRIPT_DIR}/secureconnect-vpn" "$ACTION" "$CONFIG"
