const { execSync } = require('child_process');

exports.default = async function (configuration) {
    const signtool = '"C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.28000.0\\arm64\\signtool.exe"';
    execSync(
        `${signtool} sign /tr http://timestamp.sectigo.com /td sha256 /fd sha256 /a "${configuration.path}"`,
        { stdio: 'inherit' }
    );
};
