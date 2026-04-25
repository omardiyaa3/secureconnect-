# SecureConnect - WorldPosta VPN Client

A professional macOS VPN client with portal-based configuration and biometric authentication.

## Features

- 🔐 **Biometric Authentication** - Touch ID/Face ID support on macOS
- 🌐 **Portal Management** - Import and save multiple VPN portals
- 🔒 **Menu Bar App** - Quick access from the menu bar with lock/unlock icons
- 🛡️ **DNS Protection** - Automatically saves and restores DNS settings
- ✨ **Modern UI** - Clean, professional GlobalProtect-style interface

## Installation

### 1. Install WireGuard Tools (macOS)
```bash
brew install wireguard-tools
```

### 2. Install Dependencies
```bash
cd worldposta-vpn-client
npm install
```

### 3. Run the App
```bash
npm start
```

## Portal Configuration

### Adding a Portal

1. Create a portal configuration file (JSON format):
```json
{
  "name": "My Company VPN - Primary",
  "endpoint": "http://your-vpn-server.com:3000"
}
```

2. Click the menu bar icon and select **"Add Portal..."**
3. Select your portal configuration file
4. The portal will be saved to your Recent Portals

### Example Portal File

See `example-portal.json` for a template:
```json
{
  "name": "My Company VPN - Primary",
  "endpoint": "http://37.61.219.190:3000"
}
```

## Usage

1. **Add a Portal** - Click the lock icon → "Add Portal..." → Select your `.json` config file
2. **Connect** - Click a portal from Recent Portals → Enter username/password → Click "Connect"
3. **Disconnect** - Click the lock icon → "Disconnect"

### Test Credentials

- **Username:** mostafa
- **Password:** SecurePass123

## Menu Bar Icons

- 🔓 **Unlocked** - Not connected to VPN
- 🔒 **Locked** - Connected to VPN

## Building for Distribution

```bash
# macOS
npm run build:mac

# Windows
npm run build:win

# Linux
npm run build:linux
```

The distributable files will be in the `dist/` folder.

## Requirements

- **macOS**: WireGuard tools (`brew install wireguard-tools`)
- **Touch ID**: Configured in System Preferences for sudo authentication
- **Node.js**: 16.x or higher

## Security Features

- All credentials transmitted securely to VPN server
- JWT token-based session management
- Passwords hashed with bcrypt on server
- DNS settings preserved and restored after disconnect
- Portal configurations stored securely in `~/.worldposta-vpn/`
- Touch ID/Face ID for privileged operations

## Files

- `main.js` - Electron main process (menu bar app)
- `api.js` - Backend API client
- `vpn.js` - VPN manager with DNS preservation
- `preload.js` - Security bridge
- `login.html` - Modern login UI
- `renderer.js` - UI logic
- `logo.jpeg` - WorldPosta logo
- `package.json` - App configuration
- `example-portal.json` - Sample portal configuration

## License

Proprietary - WorldPosta
