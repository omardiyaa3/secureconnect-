# SecureConnect - Build & Deploy Guide

## ✅ Setup Complete!

Your app is now configured for cross-platform building with automatic updates!

---

## 🚀 Quick Start

### Option 1: GitHub Actions (Recommended - Auto-Build)

**Setup once:**
1. Push code to GitHub:
   ```bash
   cd /path/to/worldposta-vpn-client
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/YOUR_USERNAME/secureconnect.git
   git push -u origin main
   ```

2. **That's it!** GitHub Actions will automatically build for all platforms when you push.

**To release a new version:**
```bash
# Update version in package.json
vim package.json  # Change version to "2.1.0"

# Commit and tag
git add .
git commit -m "Release v2.1.0"
git tag v2.1.0
git push && git push --tags
```

GitHub Actions will:
- ✅ Build for macOS, Windows, Linux
- ✅ Create installers automatically
- ✅ Upload as GitHub Release
- ✅ Generate update metadata files

**Download artifacts:**
- Go to your GitHub repo → Actions tab
- Click latest build
- Download artifacts (macos-installer, windows-installer, linux-installers)

---

### Option 2: Build Locally

**On your Mac:**
```bash
cd ~/Downloads/worldposta-vpn-client

# Install dependencies
npm install

# Build for all platforms (if on Mac)
npm run build

# Or build specific platforms
npm run build:mac      # macOS only
npm run build:win      # Windows only
npm run build:linux    # Linux only
```

**Output:** `dist/` folder will contain:
- `SecureConnect-2.0.0.dmg` (macOS)
- `SecureConnect-Setup-2.0.0.exe` (Windows)
- `SecureConnect-2.0.0.AppImage` (Linux universal)
- `SecureConnect_2.0.0_amd64.deb` (Linux Debian/Ubuntu)

---

## 📦 Deploy Updates

### 1. Upload Installers to Server

```bash
scp dist/*.{dmg,exe,AppImage,deb} root@37.61.219.190:/root/vpn-api/updates/
```

### 2. Update Database

**macOS:**
```bash
curl -X POST http://37.61.219.190:3000/api/admin/app-versions \
  -H "X-Admin-API-Key: worldposta-admin-2024-secure" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "2.1.0",
    "platform": "macos",
    "download_url": "http://37.61.219.190:3000/downloads/SecureConnect-2.1.0.dmg",
    "release_notes": "Bug fixes and improvements",
    "is_critical": false
  }'
```

**Windows:**
```bash
curl -X POST http://37.61.219.190:3000/api/admin/app-versions \
  -H "X-Admin-API-Key: worldposta-admin-2024-secure" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "2.1.0",
    "platform": "windows",
    "download_url": "http://37.61.219.190:3000/downloads/SecureConnect-Setup-2.1.0.exe",
    "release_notes": "Bug fixes and improvements",
    "is_critical": false
  }'
```

**Linux:**
```bash
curl -X POST http://37.61.219.190:3000/api/admin/app-versions \
  -H "X-Admin-API-Key: worldposta-admin-2024-secure" \
  -H "Content-Type: application/json" \
  -d '{
    "version": "2.1.0",
    "platform": "linux",
    "download_url": "http://37.61.219.190:3000/downloads/SecureConnect-2.1.0.AppImage",
    "release_notes": "Bug fixes and improvements",
    "is_critical": false
  }'
```

### 3. Clients Auto-Update

When users log in:
1. ✅ App checks for updates automatically
2. ✅ Shows update dialog if available
3. ✅ Downloads correct installer for their platform
4. ✅ Installs on quit or restart

---

## 🔧 What's Been Configured

### ✅ Cross-Platform Support
- **macOS:** Uses Homebrew WireGuard, networksetup for DNS
- **Windows:** Uses Program Files WireGuard, netsh for DNS
- **Linux:** Uses system WireGuard, resolvectl for DNS

### ✅ Installers with Auto-Configuration
- **macOS .dmg:** Drag-and-drop installer
- **Windows .exe:** NSIS installer with admin setup
- **Linux .AppImage:** Portable, no install needed
- **Linux .deb:** Debian/Ubuntu package with postinstall script

Each installer automatically configures passwordless admin/sudo access!

### ✅ Auto-Update System (electron-updater)
- Checks for updates after login
- Downloads in background
- Installs on quit
- Works on all platforms

### ✅ GitHub Actions CI/CD
- Builds on push to main
- Creates GitHub Releases on tags (v*)
- Uploads artifacts automatically

---

## 📋 Development Workflow

### Making Changes

1. **Edit code:**
   ```bash
   vim main.js  # or any file
   ```

2. **Test locally:**
   ```bash
   npm start
   ```

3. **Commit & push:**
   ```bash
   git add .
   git commit -m "Add new feature"
   git push
   ```

4. **GitHub Actions builds automatically!**

5. **Download & deploy:**
   - Download artifacts from GitHub Actions
   - Upload to server: `scp dist/* server:/vpn-api/updates/`
   - Update database versions
   - Done! Clients auto-update

### Version Bumping

Update `package.json`:
```json
{
  "version": "2.1.0"
}
```

Then commit and tag:
```bash
git add package.json
git commit -m "Bump version to 2.1.0"
git tag v2.1.0
git push && git push --tags
```

---

## 🎯 Distribution to Customers

### macOS
1. Send them: `SecureConnect-2.0.0.dmg`
2. They double-click, drag to Applications
3. Launch → automatically configured!

### Windows
1. Send them: `SecureConnect-Setup-2.0.0.exe`
2. They double-click, follow installer
3. Installer runs with admin rights → configures everything
4. Launch → works!

### Linux
**AppImage (Universal):**
1. Send them: `SecureConnect-2.0.0.AppImage`
2. They make executable: `chmod +x SecureConnect-2.0.0.AppImage`
3. Run: `./SecureConnect-2.0.0.AppImage`

**DEB (Ubuntu/Debian):**
1. Send them: `SecureConnect_2.0.0_amd64.deb`
2. They install: `sudo dpkg -i SecureConnect_2.0.0_amd64.deb`
3. Postinstall script configures sudo automatically
4. Launch from app menu

---

## 🔐 Security Notes

- All installers configure passwordless sudo/admin ONLY for WireGuard commands
- Limited scope - only VPN operations, not system-wide
- Safe and secure - same approach as GlobalProtect, Cisco AnyConnect

---

## 📞 Support

If clients report issues:
1. Check they have WireGuard installed
2. macOS: `brew install wireguard-tools`
3. Windows: Download from wireguard.com
4. Linux: `sudo apt install wireguard-tools` or `sudo yum install wireguard-tools`

---

## 🎉 You're All Set!

**One codebase → Change once → Build for all platforms → Auto-update everywhere!**
