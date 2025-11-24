// Create proper tray icons with shield logo
const fs = require('fs');
const path = require('path');

// Create SVG shield logos
const createShieldSVG = (connected) => {
    if (connected) {
        // Green shield with checkmark
        return `<svg width="22" height="22" viewBox="0 0 22 22" xmlns="http://www.w3.org/2000/svg">
            <path d="M11 2 L18 4.5 L18 10 C18 14.5 15 17.5 11 19.5 C7 17.5 4 14.5 4 10 L4 4.5 Z"
                  fill="#10b981" stroke="#059669" stroke-width="1"/>
            <path d="M7 11 L10 14 L15 8"
                  stroke="white" stroke-width="2.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>`;
    } else {
        // Gray shield with lock
        return `<svg width="22" height="22" viewBox="0 0 22 22" xmlns="http://www.w3.org/2000/svg">
            <path d="M11 2 L18 4.5 L18 10 C18 14.5 15 17.5 11 19.5 C7 17.5 4 14.5 4 10 L4 4.5 Z"
                  fill="#9ca3af" stroke="#6b7280" stroke-width="1"/>
            <rect x="9" y="11" width="4" height="4.5" rx="0.5" fill="white"/>
            <path d="M9.5 11 L9.5 9.5 C9.5 8.7 10 8 11 8 C12 8 12.5 8.7 12.5 9.5 L12.5 11"
                  stroke="white" stroke-width="1.2" fill="none" stroke-linecap="round"/>
        </svg>`;
    }
};

// Save SVG files (we'll use SVG directly in the app)
const iconsDir = path.join(__dirname, 'resources', 'icons');
fs.mkdirSync(iconsDir, { recursive: true });

fs.writeFileSync(path.join(iconsDir, 'tray-connected.svg'), createShieldSVG(true));
fs.writeFileSync(path.join(iconsDir, 'tray-disconnected.svg'), createShieldSVG(false));

console.log('✓ Created SVG shield icons:');
console.log('  - resources/icons/tray-connected.svg (green shield with checkmark)');
console.log('  - resources/icons/tray-disconnected.svg (gray shield with lock)');
