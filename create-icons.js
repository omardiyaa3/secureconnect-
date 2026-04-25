// Simple script to create menu bar icons as PNG files
const fs = require('fs');
const path = require('path');

// Minimal PNG files as base64 - simple black circles on transparent background
// These are 22x22 template icons for macOS menu bar

// Disconnected icon - hollow circle (22x22, black stroke on transparent)
const disconnectedPNG = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhkiAAAAAlwSFlz' +
    'AAAD3QAAA90BHJZbKAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAADfSURB' +
    'VEiJtZXBDcIwDEVfqrowAhvQTdqN2g3aCcoIbAAbMEJXgBPiQKVaapzE4X8SUnJ4L3YS/ykRERHp' +
    'ABfgCTyAO3AEFmBetL4ZQBs4GdYBboYdgdawx7EzsBlmB7qfwE2wJ3AxbPsL3Ap7ABfDHn+B22BP' +
    '4GrY4y9wM+wJXAx7/AVuhT2Ai2GPv8DNsCdwMezxF7gV9gAuT2Bv2OMvcDPsCVwMe/wFboU9gMsT' +
    '2Bv2+AvcDHsCV8Mef4FbYXfg/AR2hz1+BzfDrsDFsMfv4FbYFTh/AVsPcwD7H+YbXC45H8boMQoA' +
    'AAAASUVORK5CYII=',
    'base64'
);

// Connected icon - filled circle (22x22, black fill on transparent)
const connectedPNG = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABHNCSVQICAgIfAhkiAAAAAlwSFlz' +
    'AAAD3QAAA90BHJZbKAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAADySURB' +
    'VEiJrZWxDcIwEEXPqChYgQ3CBmQjsoHZhGxCNiEbhA3IBmGErkBBgYREss52fNhfiiLl/vvOd/bP' +
    'RkTEYAM8gRfwBh7AFdgD67T1owPowMWxHnAzrAccDXscO0ebYXZg/xO8GfYE9oY9/gK3wx7A3rDH' +
    'X+DNsCewN+zxF7gd9gD2hj3+Am+GPYG9YY+/wO2wB7A37PEXeDPsCewNe/wFboc9gL1hj7/Am2FP' +
    'YG/Y4y9wO+wB7A17/AXeDHsCe8Mef4HbYXdg/wZ2hz1+BzfDrsDOsMfv4HbYFdh9AduAuYP9j/MN' +
    '5xQ5H7RpOO0AAAAASUVORK5CYII=',
    'base64'
);

// Create icon files
const iconsDir = path.join(__dirname, 'resources', 'icons');
fs.mkdirSync(iconsDir, { recursive: true });

fs.writeFileSync(path.join(iconsDir, 'tray-disconnected.png'), disconnectedPNG);
fs.writeFileSync(path.join(iconsDir, 'tray-connected.png'), connectedPNG);

console.log('✓ Created menu bar icons:');
console.log('  - resources/icons/tray-disconnected.png');
console.log('  - resources/icons/tray-connected.png');
