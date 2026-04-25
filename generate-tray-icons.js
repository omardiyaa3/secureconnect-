// Generate proper PNG tray icons from SVG using sharp
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

// Shield SVG designs
const shieldSVG = {
    filled: `<svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <path d="M16 4 L26 7 L26 16 C26 22 22 26 16 28 C10 26 6 22 6 16 L6 7 Z" fill="black"/>
    </svg>`,
    hollow: `<svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <path d="M16 4 L26 7 L26 16 C26 22 22 26 16 28 C10 26 6 22 6 16 L6 7 Z"
              fill="none" stroke="black" stroke-width="2.5"/>
    </svg>`
};

async function generateIcons() {
    const iconsDir = path.join(__dirname, 'resources', 'icons');
    fs.mkdirSync(iconsDir, { recursive: true });

    // Generate @1x (16x16) and @2x (32x32) versions
    for (const [name, svg] of Object.entries(shieldSVG)) {
        // @1x version (16x16)
        await sharp(Buffer.from(svg))
            .resize(16, 16)
            .png()
            .toFile(path.join(iconsDir, `shield-${name}.png`));

        // @2x version (32x32) for retina
        await sharp(Buffer.from(svg))
            .resize(32, 32)
            .png()
            .toFile(path.join(iconsDir, `shield-${name}@2x.png`));
    }

    console.log('✓ Generated PNG tray icons:');
    console.log('  - shield-filled.png (16x16)');
    console.log('  - shield-filled@2x.png (32x32)');
    console.log('  - shield-hollow.png (16x16)');
    console.log('  - shield-hollow@2x.png (32x32)');
}

generateIcons().catch(console.error);
