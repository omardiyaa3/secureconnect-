# SecureConnect VPN Server Setup

Automated setup script for SecureConnect VPN server with AmneziaWG (DPI bypass) and API.

## Requirements

- Ubuntu 20.04+ or Debian 11+
- Root access
- Public IP address
- Ports 443 (UDP) and 3000 (TCP) available

## Quick Start

```bash
chmod +x setup-server.sh
sudo ./setup-server.sh
```

The script will prompt for:

**All VPN Types:**
1. **VPN Type** - Remote Access or Site-to-Site
2. **Public IP** - Your server's public IP address
3. **Admin Username** - First admin user
4. **Admin Password** - Admin password (min 8 characters)
5. **VPN Subnet** - Tunnel network (default: 10.10.0.0/24)

**Remote Access VPN:**
- Target network - The network clients will access (e.g., 192.168.10.0/24)

**Site-to-Site VPN:**
- Remote subnet - The other site's network
- Local subnet - This site's network

## What Gets Installed

- Node.js 20 LTS
- AmneziaWG (DPI-resistant WireGuard fork)
- SQLite database
- HTTPS API server with JWT authentication

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 443  | UDP      | WireGuard VPN (DPI bypass on standard HTTPS port) |
| 3000 | TCP      | HTTPS API |

## After Installation

The script will display:
- API URL and credentials
- Admin API key for user management
- Useful commands

## Managing Users

Add a user:
```bash
curl -k -X POST https://YOUR_IP:3000/api/admin/users \
  -H 'X-Admin-Api-Key: YOUR_API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"username": "newuser", "password": "password123"}'
```

List users:
```bash
curl -k https://YOUR_IP:3000/api/admin/users \
  -H 'X-Admin-Api-Key: YOUR_API_KEY'
```

Delete user:
```bash
curl -k -X DELETE https://YOUR_IP:3000/api/admin/users/USER_ID \
  -H 'X-Admin-Api-Key: YOUR_API_KEY'
```

## Service Management

```bash
# Check status
systemctl status secureconnect-api
systemctl status secureconnect-wg

# View logs
journalctl -u secureconnect-api -f
journalctl -u secureconnect-wg -f

# Restart services
systemctl restart secureconnect-wg
systemctl restart secureconnect-api
```

## Files

| Path | Description |
|------|-------------|
| /opt/secureconnect-server/ | Installation directory |
| /opt/secureconnect-server/server.js | API server |
| /opt/secureconnect-server/ssl/ | SSL certificates |
| /opt/secureconnect-server/.env | Environment config |
| /var/lib/wireguard/vpn.db | SQLite database |
| /etc/wireguard/awg0.conf | WireGuard config |

## Client Connection

Users connect using the SecureConnect client:

**CLI (Linux):**
```bash
secureconnect login --portal YOUR_IP --user username
secureconnect connect
```

**GUI (macOS/Windows/Linux):**
1. Enter portal address: YOUR_IP
2. Login with username/password
3. Click Connect

## Troubleshooting

**API not responding:**
```bash
journalctl -u secureconnect-api -n 50
```

**VPN interface not up:**
```bash
journalctl -u secureconnect-wg -n 50
ip link show awg0
```

**Check if ports are open:**
```bash
ss -tulpn | grep -E '443|3000'
```
