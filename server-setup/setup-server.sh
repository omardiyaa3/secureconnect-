#!/bin/bash
#
# SecureConnect VPN Server Setup Script
# Sets up AmneziaWG VPN server with API
#
# Usage: sudo ./setup-server.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration paths
INSTALL_DIR="/opt/secureconnect-server"
DB_DIR="/var/lib/wireguard"
DB_PATH="${DB_DIR}/vpn.db"
WG_CONFIG="/etc/wireguard/awg0.conf"
SSL_DIR="${INSTALL_DIR}/ssl"
SYSTEMD_DIR="/etc/systemd/system"

# Fixed ports
WG_PORT=443
API_PORT=3000

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         SecureConnect VPN Server Setup                    ║"
    echo "║         AmneziaWG + API Server                            ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

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
        print_status error "This script must be run as root"
        echo "  sudo ./setup-server.sh"
        exit 1
    fi
}

# Check OS
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        print_status error "Cannot detect OS. This script supports Ubuntu/Debian only."
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        print_status warning "This script is tested on Ubuntu/Debian. Your OS: $ID"
        read -rp "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    print_status success "Detected OS: $PRETTY_NAME"
}

# Collect user inputs
collect_inputs() {
    echo ""
    echo -e "${CYAN}Select VPN Type:${NC}"
    echo "  1) Remote Access VPN (users connect from laptops/phones)"
    echo "  2) Site-to-Site VPN (connect two networks together)"
    echo ""
    read -rp "Choice [1]: " vpn_type
    vpn_type="${vpn_type:-1}"

    if [[ "$vpn_type" != "1" && "$vpn_type" != "2" ]]; then
        vpn_type="1"
    fi

    echo ""
    echo -e "${CYAN}Server Configuration:${NC}"

    # Public IP
    read -rp "Enter public IP address: " PUBLIC_IP
    if [[ -z "$PUBLIC_IP" ]]; then
        print_status error "Public IP is required"
        exit 1
    fi

    # Validate IP format (basic check)
    if ! [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_status error "Invalid IP address format"
        exit 1
    fi

    # Admin username
    read -rp "Enter admin username: " ADMIN_USER
    if [[ -z "$ADMIN_USER" ]]; then
        print_status error "Admin username is required"
        exit 1
    fi

    # Admin password
    while true; do
        read -rsp "Enter admin password: " ADMIN_PASS
        echo ""
        read -rsp "Confirm password: " ADMIN_PASS_CONFIRM
        echo ""

        if [[ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]]; then
            print_status error "Passwords do not match. Try again."
        elif [[ ${#ADMIN_PASS} -lt 8 ]]; then
            print_status error "Password must be at least 8 characters"
        else
            break
        fi
    done

    # VPN subnet
    read -rp "VPN subnet [10.10.0.0/24]: " VPN_SUBNET
    VPN_SUBNET="${VPN_SUBNET:-10.10.0.0/24}"

    # Network routing configuration
    if [[ "$vpn_type" == "2" ]]; then
        # Site-to-Site VPN
        echo ""
        echo -e "${CYAN}Site-to-Site Configuration:${NC}"

        read -rp "Remote subnet (other site's network, e.g., 192.168.10.0/24): " REMOTE_SUBNET
        if [[ -z "$REMOTE_SUBNET" ]]; then
            print_status error "Remote subnet is required for site-to-site VPN"
            exit 1
        fi

        read -rp "Local subnet (this site's network, e.g., 172.20.0.0/24): " LOCAL_SUBNET
        if [[ -z "$LOCAL_SUBNET" ]]; then
            print_status error "Local subnet is required for site-to-site VPN"
            exit 1
        fi
    else
        # Remote Access VPN
        echo ""
        read -rp "Target network to access (e.g., 192.168.10.0/24): " REMOTE_SUBNET
        if [[ -z "$REMOTE_SUBNET" ]]; then
            print_status error "Target network is required"
            exit 1
        fi
        LOCAL_SUBNET=""
    fi

    # Generate random values
    ADMIN_API_KEY=$(openssl rand -hex 32)
    JWT_SECRET=$(openssl rand -hex 64)

    # Generate AWG obfuscation parameters
    AWG_S1=$((RANDOM % 100 + 20))
    AWG_S2=$((RANDOM % 100 + 20))
    AWG_H1=$((RANDOM * RANDOM))
    AWG_H2=$((RANDOM * RANDOM))
    AWG_H3=$((RANDOM * RANDOM))
    AWG_H4=$((RANDOM * RANDOM))

    # Summary
    echo ""
    echo -e "${CYAN}Configuration Summary:${NC}"
    echo "  VPN Type:      $([ "$vpn_type" == "1" ] && echo "Remote Access" || echo "Site-to-Site")"
    echo "  Public IP:     $PUBLIC_IP"
    echo "  Admin User:    $ADMIN_USER"
    echo "  VPN Subnet:    $VPN_SUBNET"
    echo "  WireGuard:     UDP $WG_PORT"
    echo "  API Server:    TCP $API_PORT"
    if [[ "$vpn_type" == "2" ]]; then
        echo "  Remote Subnet: $REMOTE_SUBNET"
        echo "  Local Subnet:  $LOCAL_SUBNET"
    else
        echo "  Target Network: $REMOTE_SUBNET"
    fi
    echo ""

    read -rp "Proceed with installation? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
}

# Install dependencies
install_dependencies() {
    print_status info "Updating package lists..."
    apt-get update -qq

    print_status info "Installing dependencies..."
    apt-get install -y -qq \
        curl \
        gnupg \
        software-properties-common \
        build-essential \
        git \
        openssl \
        sqlite3 \
        iptables \
        > /dev/null 2>&1

    # Install Node.js 20
    if ! command -v node &> /dev/null; then
        print_status info "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
        apt-get install -y -qq nodejs > /dev/null 2>&1
    fi

    # Install WireGuard tools
    if ! command -v wg &> /dev/null; then
        print_status info "Installing WireGuard tools..."
        apt-get install -y -qq wireguard-tools > /dev/null 2>&1
    fi

    # Install AmneziaWG
    if ! command -v awg &> /dev/null; then
        print_status info "Installing AmneziaWG..."

        # Try to add AmneziaWG repository
        if [[ ! -f /etc/apt/sources.list.d/amnezia.list ]]; then
            curl -fsSL https://apt.amnezia.org/gpg.key | gpg --dearmor -o /usr/share/keyrings/amnezia-archive-keyring.gpg 2>/dev/null || true
            echo "deb [signed-by=/usr/share/keyrings/amnezia-archive-keyring.gpg] https://apt.amnezia.org/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/amnezia.list 2>/dev/null || true
            apt-get update -qq 2>/dev/null || true
        fi

        # Try to install amneziawg
        if apt-get install -y -qq amneziawg amneziawg-tools 2>/dev/null; then
            print_status success "AmneziaWG installed from repository"
        else
            # Build from source
            print_status info "Building AmneziaWG from source..."

            # Build amneziawg-tools
            cd /tmp
            rm -rf amneziawg-tools
            git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git > /dev/null 2>&1
            cd amneziawg-tools/src
            make > /dev/null 2>&1
            cp wg /usr/local/bin/awg
            chmod +x /usr/local/bin/awg
            # Also install awg-quick script
            cp wg-quick/linux.bash /usr/local/bin/awg-quick
            chmod +x /usr/local/bin/awg-quick
            # Fix awg-quick to use 'awg' instead of 'wg'
            sed -i 's/WG_QUICK_USERSPACE_IMPLEMENTATION=wg/WG_QUICK_USERSPACE_IMPLEMENTATION=awg/' /usr/local/bin/awg-quick
            sed -i 's/\bwg\b/awg/g' /usr/local/bin/awg-quick
            cd /tmp
            rm -rf amneziawg-tools

            # Build amneziawg-go (userspace)
            print_status info "Building AmneziaWG userspace daemon..."

            # Install Go if needed
            if ! command -v go &> /dev/null; then
                curl -fsSL https://go.dev/dl/go1.21.5.linux-amd64.tar.gz -o /tmp/go.tar.gz
                tar -C /usr/local -xzf /tmp/go.tar.gz
                export PATH=$PATH:/usr/local/go/bin
                echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh
            fi

            cd /tmp
            rm -rf amneziawg-go
            git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go.git > /dev/null 2>&1
            cd amneziawg-go
            /usr/local/go/bin/go build -o /usr/local/bin/amneziawg-go . > /dev/null 2>&1
            chmod +x /usr/local/bin/amneziawg-go
            cd /tmp
            rm -rf amneziawg-go

            print_status success "AmneziaWG built from source"
        fi
    fi

    print_status success "Dependencies installed"
}

# Generate WireGuard keys
generate_wg_keys() {
    print_status info "Generating WireGuard keys..."

    mkdir -p "${INSTALL_DIR}/keys"

    # Generate server keys
    wg genkey > "${INSTALL_DIR}/keys/server.key"
    cat "${INSTALL_DIR}/keys/server.key" | wg pubkey > "${INSTALL_DIR}/keys/server.pub"

    chmod 600 "${INSTALL_DIR}/keys/server.key"
    chmod 644 "${INSTALL_DIR}/keys/server.pub"

    SERVER_PRIVATE_KEY=$(cat "${INSTALL_DIR}/keys/server.key")
    SERVER_PUBLIC_KEY=$(cat "${INSTALL_DIR}/keys/server.pub")

    print_status success "WireGuard keys generated"
}

# Generate SSL certificates
generate_ssl_certs() {
    print_status info "Generating SSL certificates..."

    mkdir -p "$SSL_DIR"

    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "${SSL_DIR}/server.key" \
        -out "${SSL_DIR}/server.crt" \
        -subj "/CN=${PUBLIC_IP}" \
        -addext "subjectAltName=IP:${PUBLIC_IP}" \
        2>/dev/null

    chmod 600 "${SSL_DIR}/server.key"
    chmod 644 "${SSL_DIR}/server.crt"

    print_status success "SSL certificates generated"
}

# Create API server
create_api_server() {
    print_status info "Creating API server..."

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Create package.json
    cat > package.json << 'PKGJSON'
{
  "name": "secureconnect-server",
  "version": "1.0.0",
  "description": "SecureConnect VPN API Server",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "bcrypt": "^5.1.1",
    "jsonwebtoken": "^9.0.2",
    "sqlite3": "^5.1.6"
  }
}
PKGJSON

    # Install npm packages
    npm install --silent > /dev/null 2>&1

    # Create server.js
    cat > server.js << 'SERVERJS'
#!/usr/bin/env node
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const sqlite3 = require('sqlite3').verbose();
const { promisify } = require('util');
const { exec } = require('child_process');
const path = require('path');
const https = require('https');
const fs = require('fs');
const execAsync = promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;

const SSL_KEY = path.join(__dirname, 'ssl', 'server.key');
const SSL_CERT = path.join(__dirname, 'ssl', 'server.crt');
const JWT_SECRET = process.env.JWT_SECRET || 'change-me';
const ADMIN_API_KEY = process.env.ADMIN_API_KEY || 'change-me';
const JWT_EXPIRY = '24h';
const DB_PATH = '/var/lib/wireguard/vpn.db';

// Load AWG params from config
const AWG_PARAMS = JSON.parse(process.env.AWG_PARAMS || '{}');

app.use(cors());
app.use(bodyParser.json());
app.use('/downloads', express.static(path.join(__dirname, 'updates')));

const db = new sqlite3.Database(DB_PATH, (err) => {
    if (err) {
        console.error('Error opening database:', err);
        process.exit(1);
    }
    console.log('Connected to SQLite database');
});

const dbGet = promisify(db.get.bind(db));
const dbRun = promisify(db.run.bind(db));
const dbAll = promisify(db.all.bind(db));

async function generateWireGuardKeys() {
    const { stdout: privateKey } = await execAsync('wg genkey');
    const { stdout: publicKey } = await execAsync(`echo "${privateKey.trim()}" | wg pubkey`);
    return { privateKey: privateKey.trim(), publicKey: publicKey.trim() };
}

async function getNextTunnelIP() {
    const hub = await dbGet('SELECT tunnel_subnet FROM hubs WHERE is_active = 1 LIMIT 1');
    if (!hub) return '10.10.0.2';

    const baseIP = hub.tunnel_subnet.split('/')[0].split('.');
    const peers = await dbAll('SELECT tunnel_ip FROM active_peers ORDER BY id DESC LIMIT 1');

    if (peers.length === 0) {
        return `${baseIP[0]}.${baseIP[1]}.${baseIP[2]}.2`;
    }

    const lastIP = peers[0].tunnel_ip;
    const parts = lastIP.split('.');
    const lastOctet = parseInt(parts[3]) + 1;
    return `${parts[0]}.${parts[1]}.${parts[2]}.${lastOctet}`;
}

async function auditLog(userId, username, action, success, message = null, ipAddress = null) {
    await dbRun(
        `INSERT INTO audit_log (user_id, username, action, success, message, ip_address) VALUES (?, ?, ?, ?, ?, ?)`,
        [userId, username, action, success ? 1 : 0, message, ipAddress]
    );
}

async function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ success: false, error: 'No token provided' });
    }

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        const session = await dbGet(
            'SELECT s.*, u.is_active FROM sessions s JOIN users u ON s.user_id = u.id WHERE s.token = ? AND s.expires_at > ?',
            [token, Date.now()]
        );

        if (!session) {
            return res.status(401).json({ success: false, error: 'Session expired' });
        }

        if (!session.is_active) {
            await dbRun('DELETE FROM sessions WHERE token = ?', [token]);
            return res.status(403).json({ success: false, error: 'Account disabled' });
        }

        req.user = { userId: session.user_id, username: decoded.username, customerId: decoded.customerId };
        req.token = token;
        next();
    } catch (error) {
        return res.status(403).json({ success: false, error: 'Invalid token' });
    }
}

function authenticateAdmin(req, res, next) {
    const apiKey = req.headers['x-admin-api-key'] || req.headers['authorization']?.replace('Bearer ', '');
    if (!apiKey || apiKey !== ADMIN_API_KEY) {
        return res.status(401).json({ success: false, error: 'Unauthorized' });
    }
    next();
}

// Health check
app.get('/api/health', (req, res) => {
    res.json({ success: true, message: 'VPN API Server running' });
});

// Login
app.post('/api/auth/login', async (req, res) => {
    const { username, password } = req.body;
    const clientIP = req.ip;

    if (!username || !password) {
        return res.status(400).json({ success: false, error: 'Username and password required' });
    }

    try {
        const user = await dbGet('SELECT * FROM users WHERE username = ?', [username]);

        if (!user) {
            await auditLog(null, username, 'login_failed', false, 'User not found', clientIP);
            return res.status(401).json({ success: false, error: 'Invalid credentials' });
        }

        if (!user.is_active) {
            await auditLog(user.id, username, 'login_failed', false, 'Account disabled', clientIP);
            return res.status(401).json({ success: false, error: 'Account disabled' });
        }

        const passwordMatch = await bcrypt.compare(password, user.password_hash);
        if (!passwordMatch) {
            await auditLog(user.id, username, 'login_failed', false, 'Wrong password', clientIP);
            return res.status(401).json({ success: false, error: 'Invalid credentials' });
        }

        await dbRun('DELETE FROM sessions WHERE user_id = ?', [user.id]);

        const token = jwt.sign(
            { userId: user.id, username: user.username, customerId: user.customer_id },
            JWT_SECRET,
            { expiresIn: JWT_EXPIRY }
        );

        const expiresAt = Date.now() + (24 * 60 * 60 * 1000);
        await dbRun('INSERT INTO sessions (user_id, token, expires_at) VALUES (?, ?, ?)', [user.id, token, expiresAt]);

        await auditLog(user.id, username, 'login_success', true, null, clientIP);

        res.json({
            success: true,
            token,
            user: { id: user.id, username: user.username, email: user.email, customerId: user.customer_id }
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ success: false, error: 'Server error' });
    }
});

// Logout
app.post('/api/auth/logout', authenticateToken, async (req, res) => {
    try {
        await dbRun('DELETE FROM sessions WHERE token = ?', [req.token]);
        res.json({ success: true, message: 'Logged out' });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Logout failed' });
    }
});

// VPN Connect
app.post('/api/vpn/connect', authenticateToken, async (req, res) => {
    const { userId, customerId } = req.user;
    const clientIP = req.ip;

    try {
        const hub = await dbGet('SELECT * FROM hubs WHERE is_active = 1 ORDER BY id ASC LIMIT 1');
        if (!hub) {
            return res.status(400).json({ success: false, error: 'No active hub configured' });
        }

        // Clean up existing peer
        const existingPeer = await dbGet('SELECT * FROM active_peers WHERE user_id = ?', [userId]);
        if (existingPeer) {
            try {
                await execAsync(`awg set awg0 peer ${existingPeer.public_key} remove`);
            } catch (e) {}
            await dbRun('DELETE FROM active_peers WHERE user_id = ?', [userId]);
        }

        const { privateKey, publicKey } = await generateWireGuardKeys();
        const tunnelIP = await getNextTunnelIP();

        await execAsync(`awg set awg0 peer ${publicKey} allowed-ips ${tunnelIP}/32 persistent-keepalive 25`);

        await dbRun(
            `INSERT INTO active_peers (user_id, customer_id, public_key, private_key, tunnel_ip, wg_interface) VALUES (?, ?, ?, ?, ?, ?)`,
            [userId, customerId, publicKey, privateKey, tunnelIP, 'awg0']
        );

        const hubPublicKey = (await execAsync('awg show awg0 public-key')).stdout.trim();

        const allowedIPs = [hub.tunnel_subnet, hub.remote_subnet, hub.local_subnet]
            .filter(s => s && s.trim())
            .join(', ');

        await auditLog(userId, null, 'vpn_connect', true, `IP: ${tunnelIP}`, clientIP);

        res.json({
            success: true,
            config: {
                privateKey,
                address: `${tunnelIP}/32`,
                publicKey: hubPublicKey,
                endpoint: `${hub.public_ip}:${hub.port}`,
                allowedIPs: allowedIPs || hub.tunnel_subnet,
                dns: hub.dns_servers,
                awg: AWG_PARAMS
            }
        });
    } catch (error) {
        console.error('VPN connect error:', error);
        await auditLog(userId, null, 'vpn_connect', false, error.message, clientIP);
        res.status(500).json({ success: false, error: 'Failed to provision VPN' });
    }
});

// VPN Disconnect
app.post('/api/vpn/disconnect', authenticateToken, async (req, res) => {
    const { userId } = req.user;

    try {
        const peer = await dbGet('SELECT * FROM active_peers WHERE user_id = ?', [userId]);
        if (!peer) {
            return res.json({ success: true, message: 'No active connection' });
        }

        await execAsync(`awg set awg0 peer ${peer.public_key} remove`);
        await dbRun('DELETE FROM active_peers WHERE user_id = ?', [userId]);

        await auditLog(userId, null, 'vpn_disconnect', true, null, req.ip);
        res.json({ success: true, message: 'Disconnected' });
    } catch (error) {
        console.error('Disconnect error:', error);
        res.status(500).json({ success: false, error: 'Disconnect failed' });
    }
});

// VPN Status
app.get('/api/vpn/status', authenticateToken, async (req, res) => {
    const { userId } = req.user;

    try {
        const peer = await dbGet('SELECT * FROM active_peers WHERE user_id = ?', [userId]);
        if (!peer) {
            return res.json({ success: true, connected: false });
        }

        try {
            const { stdout } = await execAsync('awg show awg0 peers');
            const isConnected = stdout.includes(peer.public_key);
            res.json({ success: true, connected: isConnected, tunnelIP: peer.tunnel_ip, connectedAt: peer.connected_at });
        } catch (e) {
            res.json({ success: true, connected: false });
        }
    } catch (error) {
        res.status(500).json({ success: false, error: 'Status check failed' });
    }
});

// Admin: List users
app.get('/api/admin/users', authenticateAdmin, async (req, res) => {
    try {
        const users = await dbAll('SELECT id, username, email, customer_id, is_active, created_at FROM users ORDER BY created_at DESC');
        res.json({ success: true, users });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to fetch users' });
    }
});

// Admin: Create user
app.post('/api/admin/users', authenticateAdmin, async (req, res) => {
    const { username, password, email, customer_id } = req.body;

    if (!username || !password) {
        return res.status(400).json({ success: false, error: 'Username and password required' });
    }

    try {
        const passwordHash = await bcrypt.hash(password, 10);
        const result = await dbRun(
            'INSERT INTO users (username, password_hash, email, customer_id) VALUES (?, ?, ?, ?)',
            [username, passwordHash, email || null, customer_id || 'default']
        );
        res.json({ success: true, message: 'User created', user_id: result.lastID });
    } catch (error) {
        if (error.message.includes('UNIQUE constraint')) {
            return res.status(400).json({ success: false, error: 'Username already exists' });
        }
        res.status(500).json({ success: false, error: 'Failed to create user' });
    }
});

// Admin: Delete user
app.delete('/api/admin/users/:id', authenticateAdmin, async (req, res) => {
    try {
        const user = await dbGet('SELECT * FROM active_peers WHERE user_id = ?', [req.params.id]);
        if (user) {
            try {
                await execAsync(`awg set awg0 peer ${user.public_key} remove`);
            } catch (e) {}
        }
        await dbRun('DELETE FROM active_peers WHERE user_id = ?', [req.params.id]);
        await dbRun('DELETE FROM sessions WHERE user_id = ?', [req.params.id]);
        await dbRun('DELETE FROM users WHERE id = ?', [req.params.id]);
        res.json({ success: true, message: 'User deleted' });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to delete user' });
    }
});

// Admin: Update user
app.put('/api/admin/users/:id', authenticateAdmin, async (req, res) => {
    const { password, email, is_active } = req.body;

    try {
        const updates = [];
        const values = [];

        if (password) {
            updates.push('password_hash = ?');
            values.push(await bcrypt.hash(password, 10));
        }
        if (email !== undefined) {
            updates.push('email = ?');
            values.push(email);
        }
        if (is_active !== undefined) {
            updates.push('is_active = ?');
            values.push(is_active ? 1 : 0);
        }

        if (updates.length === 0) {
            return res.status(400).json({ success: false, error: 'No updates provided' });
        }

        values.push(req.params.id);
        await dbRun(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`, values);
        res.json({ success: true, message: 'User updated' });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to update user' });
    }
});

// Admin: List hubs
app.get('/api/admin/hubs', authenticateAdmin, async (req, res) => {
    try {
        const hubs = await dbAll('SELECT * FROM hubs ORDER BY created_at DESC');
        res.json({ success: true, hubs });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to fetch hubs' });
    }
});

// Admin: Create hub
app.post('/api/admin/hubs', authenticateAdmin, async (req, res) => {
    const { name, public_ip, port, remote_subnet, local_subnet, tunnel_subnet, dns_servers, location } = req.body;

    if (!name || !public_ip || !tunnel_subnet) {
        return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    try {
        const result = await dbRun(
            `INSERT INTO hubs (name, public_ip, port, remote_subnet, local_subnet, tunnel_subnet, dns_servers, location) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [name, public_ip, port || 443, remote_subnet || '', local_subnet || '', tunnel_subnet, dns_servers || '1.1.1.1, 8.8.8.8', location || '']
        );
        res.json({ success: true, message: 'Hub created', hub_id: result.lastID });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to create hub' });
    }
});

// Admin: Update hub
app.put('/api/admin/hubs/:id', authenticateAdmin, async (req, res) => {
    const { name, public_ip, port, remote_subnet, local_subnet, tunnel_subnet, dns_servers, location, is_active } = req.body;

    try {
        const updates = [];
        const values = [];

        if (name !== undefined) { updates.push('name = ?'); values.push(name); }
        if (public_ip !== undefined) { updates.push('public_ip = ?'); values.push(public_ip); }
        if (port !== undefined) { updates.push('port = ?'); values.push(port); }
        if (remote_subnet !== undefined) { updates.push('remote_subnet = ?'); values.push(remote_subnet); }
        if (local_subnet !== undefined) { updates.push('local_subnet = ?'); values.push(local_subnet); }
        if (tunnel_subnet !== undefined) { updates.push('tunnel_subnet = ?'); values.push(tunnel_subnet); }
        if (dns_servers !== undefined) { updates.push('dns_servers = ?'); values.push(dns_servers); }
        if (location !== undefined) { updates.push('location = ?'); values.push(location); }
        if (is_active !== undefined) { updates.push('is_active = ?'); values.push(is_active ? 1 : 0); }

        if (updates.length === 0) {
            return res.status(400).json({ success: false, error: 'No updates provided' });
        }

        values.push(req.params.id);
        await dbRun(`UPDATE hubs SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE id = ?`, values);
        res.json({ success: true, message: 'Hub updated' });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to update hub' });
    }
});

// Admin: Delete hub
app.delete('/api/admin/hubs/:id', authenticateAdmin, async (req, res) => {
    try {
        await dbRun('DELETE FROM hubs WHERE id = ?', [req.params.id]);
        res.json({ success: true, message: 'Hub deleted' });
    } catch (error) {
        res.status(500).json({ success: false, error: 'Failed to delete hub' });
    }
});

// Start server
if (fs.existsSync(SSL_KEY) && fs.existsSync(SSL_CERT)) {
    const httpsOptions = { key: fs.readFileSync(SSL_KEY), cert: fs.readFileSync(SSL_CERT) };
    https.createServer(httpsOptions, app).listen(PORT, () => {
        console.log(`SecureConnect API running on HTTPS port ${PORT}`);
    });
} else {
    console.warn('SSL certificates not found, using HTTP');
    app.listen(PORT, () => {
        console.log(`SecureConnect API running on HTTP port ${PORT}`);
    });
}

process.on('SIGINT', () => {
    db.close();
    process.exit(0);
});
SERVERJS

    print_status success "API server created"
}

# Create database schema
create_database() {
    print_status info "Creating database..."

    mkdir -p "$DB_DIR"

    # Create schema
    cat > "${INSTALL_DIR}/schema.sql" << 'SCHEMA'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    customer_id VARCHAR(50) DEFAULT 'default',
    is_active BOOLEAN DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS active_peers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    public_key VARCHAR(255) UNIQUE NOT NULL,
    private_key VARCHAR(255) NOT NULL,
    tunnel_ip VARCHAR(45) NOT NULL,
    wg_interface VARCHAR(50) NOT NULL,
    connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    username VARCHAR(255),
    action VARCHAR(50) NOT NULL,
    ip_address VARCHAR(45),
    success BOOLEAN,
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS hubs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(255) NOT NULL,
    public_ip VARCHAR(45) NOT NULL,
    port INTEGER DEFAULT 443,
    remote_subnet VARCHAR(50) DEFAULT '',
    local_subnet VARCHAR(50) DEFAULT '',
    tunnel_subnet VARCHAR(50) NOT NULL,
    dns_servers VARCHAR(255) DEFAULT '1.1.1.1, 8.8.8.8',
    is_active BOOLEAN DEFAULT 1,
    location VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token);
CREATE INDEX IF NOT EXISTS idx_active_peers_user ON active_peers(user_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
SCHEMA

    # Initialize database
    sqlite3 "$DB_PATH" < "${INSTALL_DIR}/schema.sql"

    # Create admin user - hash password using node
    ADMIN_HASH=$(cd "$INSTALL_DIR" && node -e "const bcrypt=require('bcrypt');console.log(bcrypt.hashSync(process.argv[1],10));" "$ADMIN_PASS")

    sqlite3 "$DB_PATH" "INSERT INTO users (username, password_hash, customer_id, is_active) VALUES ('$ADMIN_USER', '$ADMIN_HASH', 'admin', 1);"

    # Create hub
    sqlite3 "$DB_PATH" "INSERT INTO hubs (name, public_ip, port, remote_subnet, local_subnet, tunnel_subnet, dns_servers, location) VALUES ('Primary Hub', '$PUBLIC_IP', $WG_PORT, '$REMOTE_SUBNET', '$LOCAL_SUBNET', '$VPN_SUBNET', '1.1.1.1, 8.8.8.8', 'Default');"

    chmod 600 "$DB_PATH"

    print_status success "Database initialized"
}

# Configure AmneziaWG
configure_amneziawg() {
    print_status info "Configuring AmneziaWG..."

    mkdir -p /etc/wireguard

    # Get gateway IP (first IP in subnet)
    GATEWAY_IP=$(echo "$VPN_SUBNET" | sed 's/\.[0-9]*\//.1\//')

    cat > "$WG_CONFIG" << WGCONF
# SecureConnect AmneziaWG Configuration
# Generated by setup script

[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${GATEWAY_IP}
ListenPort = ${WG_PORT}
Table = off

# AmneziaWG obfuscation parameters
S1 = ${AWG_S1}
S2 = ${AWG_S2}
H1 = ${AWG_H1}
H2 = ${AWG_H2}
H3 = ${AWG_H3}
H4 = ${AWG_H4}

# Peers are added dynamically by the API
WGCONF

    chmod 600 "$WG_CONFIG"

    print_status success "AmneziaWG configured"
}

# Configure networking
configure_networking() {
    print_status info "Configuring networking..."

    # Enable IP forwarding
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-secureconnect.conf
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    # Get default interface
    DEFAULT_IF=$(ip route | grep default | awk '{print $5}' | head -1)

    # Configure NAT
    iptables -t nat -A POSTROUTING -s "$VPN_SUBNET" -o "$DEFAULT_IF" -j MASQUERADE

    # Allow forwarding
    iptables -A FORWARD -i awg0 -j ACCEPT
    iptables -A FORWARD -o awg0 -j ACCEPT

    # Allow WireGuard and API ports
    iptables -A INPUT -p udp --dport "$WG_PORT" -j ACCEPT
    iptables -A INPUT -p tcp --dport "$API_PORT" -j ACCEPT

    # Save iptables rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save > /dev/null 2>&1
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables.rules
        echo '#!/bin/sh' > /etc/network/if-pre-up.d/iptables
        echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-pre-up.d/iptables
        chmod +x /etc/network/if-pre-up.d/iptables
    fi

    print_status success "Networking configured"
}

# Create systemd services
create_services() {
    print_status info "Creating systemd services..."

    # Find awg binary location
    AWG_BIN=$(command -v awg 2>/dev/null || echo "/usr/local/bin/awg")
    AMNEZIAWG_GO_BIN=$(command -v amneziawg-go 2>/dev/null || echo "/usr/local/bin/amneziawg-go")

    # Create environment file
    cat > "${INSTALL_DIR}/.env" << ENVFILE
PORT=${API_PORT}
JWT_SECRET=${JWT_SECRET}
ADMIN_API_KEY=${ADMIN_API_KEY}
AWG_PARAMS={"Jc":4,"Jmin":40,"Jmax":70,"S1":${AWG_S1},"S2":${AWG_S2},"H1":${AWG_H1},"H2":${AWG_H2},"H3":${AWG_H3},"H4":${AWG_H4}}
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENVFILE
    chmod 600 "${INSTALL_DIR}/.env"

    # API service
    cat > "${SYSTEMD_DIR}/secureconnect-api.service" << SERVICE
[Unit]
Description=SecureConnect VPN API Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${INSTALL_DIR}/.env
ExecStart=/usr/bin/node ${INSTALL_DIR}/server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

    # AmneziaWG service - prefer awg-quick (kernel module) over userspace
    AWG_QUICK_BIN=$(command -v awg-quick 2>/dev/null)
    if [[ -z "$AWG_QUICK_BIN" ]]; then
        # Check common locations
        for path in /usr/local/bin/awg-quick /usr/bin/awg-quick; do
            if [[ -x "$path" ]]; then
                AWG_QUICK_BIN="$path"
                break
            fi
        done
    fi

    if [[ -n "$AWG_QUICK_BIN" && -x "$AWG_QUICK_BIN" ]]; then
        # Use awg-quick (kernel module) - preferred method
        print_status info "Using awg-quick (kernel module)"
        cat > "${SYSTEMD_DIR}/secureconnect-wg.service" << SERVICE
[Unit]
Description=SecureConnect AmneziaWG Interface
After=network.target
Before=secureconnect-api.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${AWG_QUICK_BIN} up ${WG_CONFIG}
ExecStop=${AWG_QUICK_BIN} down ${WG_CONFIG}

[Install]
WantedBy=multi-user.target
SERVICE
    elif [[ -x "$AMNEZIAWG_GO_BIN" ]]; then
        # Fallback to userspace daemon (when kernel module not available)
        print_status info "Using amneziawg-go (userspace fallback)"
        cat > "${SYSTEMD_DIR}/secureconnect-wg.service" << SERVICE
[Unit]
Description=SecureConnect AmneziaWG Interface
After=network.target
Before=secureconnect-api.service

[Service]
Type=simple
ExecStart=${AMNEZIAWG_GO_BIN} awg0
ExecStartPost=/bin/sleep 2
ExecStartPost=/bin/sh -c 'grep -v "^Address\\|^Table\\|^DNS" ${WG_CONFIG} > /tmp/awg0-stripped.conf && ${AWG_BIN} setconf awg0 /tmp/awg0-stripped.conf'
ExecStartPost=/sbin/ip address add ${GATEWAY_IP} dev awg0
ExecStartPost=/sbin/ip link set awg0 up
ExecStop=/sbin/ip link delete awg0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
    else
        print_status error "No AmneziaWG runtime found (awg-quick or amneziawg-go)"
        exit 1
    fi

    systemctl daemon-reload

    print_status success "Systemd services created"
}

# Start services
start_services() {
    print_status info "Starting services..."

    systemctl enable secureconnect-wg > /dev/null 2>&1
    systemctl enable secureconnect-api > /dev/null 2>&1

    systemctl start secureconnect-wg
    sleep 2
    systemctl start secureconnect-api

    print_status success "Services started"
}

# Print completion message
print_completion() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         SecureConnect Server Setup Complete!              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Server Details:${NC}"
    echo "  API URL:        https://${PUBLIC_IP}:${API_PORT}"
    echo "  WireGuard:      ${PUBLIC_IP}:${WG_PORT} (UDP)"
    echo "  VPN Subnet:     ${VPN_SUBNET}"
    echo "  Target Network: ${REMOTE_SUBNET}"
    echo ""
    echo -e "${CYAN}Admin Credentials:${NC}"
    echo "  Username:       ${ADMIN_USER}"
    echo "  Password:       (as entered)"
    echo "  API Key:        ${ADMIN_API_KEY}"
    echo ""
    echo -e "${CYAN}Important Files:${NC}"
    echo "  API Server:     ${INSTALL_DIR}/server.js"
    echo "  Database:       ${DB_PATH}"
    echo "  WG Config:      ${WG_CONFIG}"
    echo "  SSL Certs:      ${SSL_DIR}/"
    echo ""
    echo -e "${YELLOW}Port Forwarding Required (if behind NAT):${NC}"
    echo "  UDP ${WG_PORT} → this server (WireGuard)"
    echo "  TCP ${API_PORT} → this server (API)"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo "  Check status:   systemctl status secureconnect-api"
    echo "  View logs:      journalctl -u secureconnect-api -f"
    echo "  Restart API:    systemctl restart secureconnect-api"
    echo ""
    echo -e "${CYAN}Add Users via API:${NC}"
    echo "  curl -k -X POST https://${PUBLIC_IP}:${API_PORT}/api/admin/users \\"
    echo "    -H 'X-Admin-Api-Key: ${ADMIN_API_KEY}' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"username\": \"newuser\", \"password\": \"password123\"}'"
    echo ""
}

# Main
main() {
    print_banner
    check_root
    check_os
    collect_inputs

    echo ""
    print_status info "Starting installation..."
    echo ""

    install_dependencies
    generate_wg_keys
    generate_ssl_certs
    create_api_server
    create_database
    configure_amneziawg
    configure_networking
    create_services
    start_services

    print_completion
}

main "$@"
