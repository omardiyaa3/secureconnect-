// Create a proper shield icon using SVG and save as PNG
const fs = require('fs');
const path = require('path');

// Simple shield SVG - monochrome for macOS template image
const shieldSVG = (filled) => {
    if (filled) {
        // Filled shield for connected state
        return `<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
            <path d="M8 1 L14 3 L14 8 C14 11.5 11.5 13.5 8 15 C4.5 13.5 2 11.5 2 8 L2 3 Z"
                  fill="black"/>
        </svg>`;
    } else {
        // Hollow shield for disconnected state
        return `<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
            <path d="M8 1 L14 3 L14 8 C14 11.5 11.5 13.5 8 15 C4.5 13.5 2 11.5 2 8 L2 3 Z"
                  fill="none" stroke="black" stroke-width="1.5"/>
        </svg>`;
    }
};

// For now, save as SVG files (we'll use these directly)
const iconsDir = path.join(__dirname, 'resources', 'icons');
fs.mkdirSync(iconsDir, { recursive: true });

fs.writeFileSync(path.join(iconsDir, 'shield-filled.svg'), shieldSVG(true));
fs.writeFileSync(path.join(iconsDir, 'shield-hollow.svg'), shieldSVG(false));

// Also create base64 encoded versions for embedding
const filledBase64 = Buffer.from(shieldSVG(true)).toString('base64');
const hollowBase64 = Buffer.from(shieldSVG(false)).toString('base64');

console.log('\n=== Shield Icon Base64 (for embedding) ===\n');
console.log('Filled shield (connected):');
console.log(filledBase64);
console.log('\nHollow shield (disconnected):');
console.log(hollowBase64);
console.log('\n✓ SVG files created in resources/icons/');
