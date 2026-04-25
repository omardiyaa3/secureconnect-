#!/bin/bash
# Build SecureConnect.pkg installer for macOS

set -e

echo "🔨 Building SecureConnect Installer..."

# Clean previous builds
rm -rf dist
rm -rf installer/root
rm -rf installer/component.pkg
rm -f SecureConnect.pkg

# Step 1: Package the Electron app
echo "📦 Packaging Electron app..."
npx electron-packager . SecureConnect \
  --platform=darwin \
  --arch=x64 \
  --out=dist \
  --overwrite \
  --icon=logo.jpeg \
  --app-bundle-id=com.worldposta.secureconnect \
  --app-version=2.0.0

# Step 2: Prepare installer root directory
echo "📂 Preparing installer payload..."
mkdir -p installer/root/Applications
cp -R "dist/SecureConnect-darwin-x64/SecureConnect.app" "installer/root/Applications/"

# Step 3: Build component package
echo "🔧 Building component package..."
pkgbuild \
  --root installer/root \
  --scripts installer/scripts \
  --identifier com.worldposta.secureconnect \
  --version 2.0.0 \
  --install-location / \
  installer/component.pkg

# Step 4: Build final product package
echo "📦 Building final installer..."
productbuild \
  --package installer/component.pkg \
  SecureConnect.pkg

# Clean up intermediate files
rm -rf installer/root
rm -f installer/component.pkg

echo "✅ Installer built successfully: SecureConnect.pkg"
echo ""
echo "To install on Mac:"
echo "1. Copy SecureConnect.pkg to your Mac"
echo "2. Double-click to install"
echo "3. Enter your password when prompted"
echo "4. SecureConnect will be installed with passwordless sudo configured"
