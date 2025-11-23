# 🚀 Deploy SecureConnect - Simple 3-Step Process

GitHub Actions will automatically compile WireGuard and build installers for all platforms!

---

## Step 1: Push to GitHub (One Time Setup)

```bash
cd /root/worldposta-vpn-client

# Initialize git (if not already done)
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit - SecureConnect with rebranded WireGuard"

# Add your GitHub repo
git remote add origin https://github.com/YOUR_USERNAME/secureconnect.git

# Push to GitHub
git push -u origin main
```

**Note:** Replace `YOUR_USERNAME/secureconnect` with your actual GitHub repository.

---

## Step 2: GitHub Actions Builds Everything

Once you push, GitHub Actions will automatically:

1. ✅ **macOS build:**
   - Downloads WireGuard source
   - Compiles `wg` natively on macOS
   - Renames to `secureconnect-ctl`
   - Bundles both binaries in app
   - Creates `SecureConnect-2.0.0.dmg`

2. ✅ **Windows build:**
   - Creates `SecureConnect-Setup-2.0.0.exe`

3. ✅ **Linux build:**
   - Creates `SecureConnect-2.0.0.AppImage`
   - Creates `SecureConnect_2.0.0_amd64.deb`

**Where to find builds:**
1. Go to your GitHub repo
2. Click **"Actions"** tab
3. Click on the latest workflow run
4. Scroll down to **"Artifacts"** section
5. Download:
   - `macos-installer` - Contains .dmg file
   - `windows-installer` - Contains .exe file
   - `linux-installers` - Contains .AppImage and .deb files

---

## Step 3: Test the Installer

### On macOS:

```bash
# Download the macos-installer artifact from GitHub Actions
# Extract it and run:

# 1. Open the DMG
open SecureConnect-2.0.0.dmg

# 2. Drag SecureConnect to Applications
# 3. Launch SecureConnect
# 4. You'll be prompted for password ONCE (for sudo setup)
# 5. Log in and connect

# 6. Verify no WireGuard branding:
ps aux | grep secureconnect
# Should show: secureconnect-vpn up sc0

ps aux | grep wg | grep -v grep
# Should be EMPTY (no wg processes!)
```

---

## 🎯 That's It!

**Workflow:**
1. Make code changes
2. Push to GitHub
3. GitHub Actions builds for all platforms
4. Download installers from Actions artifacts
5. Test and distribute

**No manual compilation needed!** GitHub Actions does everything automatically.

---

## 📦 Making Updates

When you want to release a new version:

```bash
# 1. Update version in package.json
vim package.json
# Change "version": "2.0.0" to "2.1.0"

# 2. Commit and tag
git add package.json
git commit -m "Release v2.1.0"
git tag v2.1.0

# 3. Push with tags
git push && git push --tags
```

**GitHub Actions will:**
- Build all installers
- Create a GitHub Release (because of the tag)
- Attach installers to the release

You can then download directly from:
`https://github.com/YOUR_USERNAME/secureconnect/releases`

---

## ✅ What Users Get

**macOS installer will:**
- Bundle `secureconnect-vpn` and `secureconnect-ctl` (compiled natively)
- Configure passwordless sudo automatically
- Create `/etc/secureconnect` directory
- Show only "SecureConnect" branding
- NO WireGuard visible in processes!

**Process names users see:**
```bash
$ ps aux | grep secureconnect
user  1234  secureconnect-vpn up sc0
```

**What they DON'T see:**
- No `wg` or `wg-quick` processes
- No `/etc/wireguard` paths
- No WireGuard branding anywhere

---

## 🔍 Verify Build Success

After GitHub Actions completes:

1. **Check the build logs** - Look for:
   ```
   Downloading WireGuard tools source...
   Compiling WireGuard for macOS...
   Copying and renaming to secureconnect-ctl...
   Verifying binary...
   Mach-O 64-bit executable arm64
   ```

2. **Download and test** - Verify:
   - App installs without errors
   - Connects to VPN successfully
   - No password prompts after initial setup
   - Process names show "secureconnect" not "wg"

---

## 🎉 You're Done!

**One codebase → Push once → GitHub builds everything → Download installers!**

No manual compilation, no Mac needed for building, everything automated! 🚀
