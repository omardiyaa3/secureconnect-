# SecureConnect Bundled Binaries

This directory contains rebranded WireGuard binaries that are bundled with the SecureConnect app.

## Directory Structure

```
resources/bin/
├── darwin/              # macOS binaries
│   ├── secureconnect-vpn    (rebranded wg-quick)
│   └── secureconnect-ctl    (rebranded wg command)
├── win32/               # Windows binaries (TODO)
└── linux/               # Linux binaries (TODO)
```

## macOS Binaries (darwin/)

### secureconnect-vpn
- **Original:** wg-quick (WireGuard quick configuration script)
- **Modified:** Bash script that manages VPN connections
- **Changes:**
  - Config path: `/etc/wireguard` → `/etc/secureconnect`
  - Command references: `wg` → `secureconnect-ctl`
  - Interface name: `wg0` → `sc0`
- **Status:** ✅ Ready (platform-independent bash script)

### secureconnect-ctl
- **Original:** wg (WireGuard command-line tool)
- **Modified:** Compiled C binary for WireGuard operations
- **Status:** ⚠️ Needs macOS compilation
- **Current:** Linux x86-64 binary (won't work on macOS)
- **Required:** Must be compiled on macOS using instructions in `/root/secureconnect-wg/COMPILE-MAC.md`

## How It Works

1. **App Detection:** vpn.js detects bundled binaries at runtime:
   ```javascript
   const resourcesPath = app.isPackaged
       ? process.resourcesPath
       : path.join(__dirname, 'resources');
   const binPath = path.join(resourcesPath, 'bin', process.platform);
   ```

2. **Binary Paths:**
   - Development: `worldposta-vpn-client/resources/bin/darwin/secureconnect-vpn`
   - Production: `SecureConnect.app/Contents/Resources/bin/darwin/secureconnect-vpn`

3. **Permissions:** Configured by postinstall script:
   ```bash
   # /private/etc/sudoers.d/secureconnect-vpn
   user ALL=(ALL) NOPASSWD: /Applications/SecureConnect.app/Contents/Resources/bin/darwin/secureconnect-vpn
   ```

## User Experience

**What users see:**
```bash
$ ps aux | grep secureconnect
user  1234  secureconnect-vpn up sc0
```

**What users DON'T see:**
- No "wg" or "wg-quick" processes
- No "/etc/wireguard" config path
- No WireGuard branding anywhere

## Compilation Instructions

### macOS (Required)
See `/root/secureconnect-wg/COMPILE-MAC.md` for detailed instructions.

**Quick steps:**
```bash
# 1. Copy source to Mac
scp -r root@37.61.219.190:/root/wireguard-tools ~/Downloads/

# 2. Compile
cd ~/Downloads/wireguard-tools/src
make clean && make

# 3. Replace binary
cp wg /path/to/worldposta-vpn-client/resources/bin/darwin/secureconnect-ctl
chmod +x /path/to/worldposta-vpn-client/resources/bin/darwin/secureconnect-ctl
```

### Windows (TODO)
Windows binaries need to be compiled and rebranded.

### Linux (TODO)
Linux binaries need to be compiled and rebranded.

## Legal & Licensing

- WireGuard is GPL-licensed open source
- Rebranding and redistribution is allowed under GPL
- Original GPL license preserved in source code
- This is the same approach used by commercial VPN providers

## Testing

After compilation, verify the binaries work:

```bash
# Test in development
npm start
# Connect to VPN, then check:
ps aux | grep secureconnect    # Should show secureconnect-vpn
ps aux | grep wg               # Should show nothing

# Test process names
ls -la /etc/secureconnect      # Should exist with sc0.conf
```

## Notes

- Binaries are 100% functional WireGuard - only renamed
- No functionality changes - same security and performance
- Process names show "secureconnect" not "wireguard"
- Users never see WireGuard branding
