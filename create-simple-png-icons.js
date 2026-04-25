// Create minimal PNG icons that are guaranteed to work
const fs = require('fs');
const path = require('path');

// Minimal 16x16 green PNG (for connected)
const greenPNG = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR42mNk+M/wn4EIwDiqYdQA' +
    'AADBAAN/pdL1AAAAAElFTkSuQmCC',
    'base64'
);

// Minimal 16x16 gray PNG (for disconnected)
const grayPNG = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAF0lEQVR42mNkYGD4z0AEYBzVMGrA' +
    'QAAA//8DAAGAAf+KCH0AAAAASUVORK5CYII=',
    'base64'
);

const iconsDir = path.join(__dirname, 'resources', 'icons');
fs.mkdirSync(iconsDir, { recursive: true });

fs.writeFileSync(path.join(iconsDir, 'tray-connected-simple.png'), greenPNG);
fs.writeFileSync(path.join(iconsDir, 'tray-disconnected-simple.png'), grayPNG);

console.log('✓ Created minimal PNG icons for testing');
console.log('  - tray-connected-simple.png (16x16 green)');
console.log('  - tray-disconnected-simple.png (16x16 gray)');
