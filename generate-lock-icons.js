// Generate proper lock/unlock icons for tray
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

// Lock icon SVG designs - monochrome for template images
const lockSVG = {
    locked: `<svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <!-- Lock body -->
        <rect x="10" y="16" width="12" height="10" rx="1" fill="black" stroke="black" stroke-width="1"/>
        <!-- Lock shackle (closed) -->
        <path d="M12 16 L12 11 C12 8.8 13.8 7 16 7 C18.2 7 20 8.8 20 11 L20 16"
              stroke="black" stroke-width="2.5" fill="none" stroke-linecap="round"/>
    </svg>`,
    unlocked: `<svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
        <!-- Lock body -->
        <rect x="10" y="16" width="12" height="10" rx="1" fill="black" stroke="black" stroke-width="1"/>
        <!-- Lock shackle (open) -->
        <path d="M12 16 L12 11 C12 8.8 13.8 7 16 7 C18.2 7 20 8.8 20 11 L20 13"
              stroke="black" stroke-width="2.5" fill="none" stroke-linecap="round"/>
    </svg>`
};

async function generateIcons() {
    const iconsDir = path.join(__dirname, 'resources', 'icons');
    fs.mkdirSync(iconsDir, { recursive: true });

    // Generate @1x (16x16) and @2x (32x32) versions
    for (const [name, svg] of Object.entries(lockSVG)) {
        // @1x version (16x16)
        await sharp(Buffer.from(svg))
            .resize(16, 16)
            .png()
            .toFile(path.join(iconsDir, `lock-${name}.png`));

        // @2x version (32x32) for retina
        await sharp(Buffer.from(svg))
            .resize(32, 32)
            .png()
            .toFile(path.join(iconsDir, `lock-${name}@2x.png`));
    }

    console.log('✓ Generated lock/unlock PNG icons:');
    console.log('  - lock-locked.png (16x16) - for connected state');
    console.log('  - lock-locked@2x.png (32x32)');
    console.log('  - lock-unlocked.png (16x16) - for disconnected state');
    console.log('  - lock-unlocked@2x.png (32x32)');
}

generateIcons().catch(console.error);
