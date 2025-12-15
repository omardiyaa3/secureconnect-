const { app, Tray, Menu, BrowserWindow, ipcMain, nativeImage, dialog, shell } = require('electron');
const { autoUpdater } = require('electron-updater');
const path = require('path');
const fs = require('fs').promises;
const fsSync = require('fs');
const os = require('os');
const sudo = require('sudo-prompt');
const VPNManager = require('./vpn');

const APP_VERSION = '2.0.31';

// Enable transparent visuals for Linux
if (process.platform === 'linux') {
    app.commandLine.appendSwitch('enable-transparent-visuals');
    app.commandLine.appendSwitch('disable-gpu');
}

// Configure auto-updater
autoUpdater.autoDownload = false;
autoUpdater.autoInstallOnAppQuit = true;

// Accept self-signed certificates for HTTPS connections
app.on('certificate-error', (event, webContents, url, error, certificate, callback) => {
    // Allow self-signed certificates
    event.preventDefault();
    callback(true);
});

// Also handle Node.js fetch/https requests
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

let tray = null;
let mainWindow = null;
let vpnManager = new VPNManager();
let isConnected = false;
let currentPortal = null;
let currentUser = null;
let portals = [];

const CONFIG_DIR = path.join(os.homedir(), '.worldposta-vpn');
const PORTALS_FILE = path.join(CONFIG_DIR, 'portals.json');

// VPN icon for menu bar - WorldPosta cloud icon
const createVPNIcon = (connected) => {
    const isDev = !app.isPackaged;
    const resourcesPath = isDev
        ? path.join(__dirname, 'resources')
        : process.resourcesPath;

    // Connected = filled cloud, Disconnected = outline cloud
    const iconBase = connected ? 'wp-connected' : 'wp-disconnected';
    const iconPath = path.join(resourcesPath, 'icons', `${iconBase}.png`);
    const icon2xPath = path.join(resourcesPath, 'icons', `${iconBase}@2x.png`);

    // Create image with @1x and @2x support for retina displays
    const img = nativeImage.createEmpty();

    // Add @1x representation
    if (fsSync.existsSync(iconPath)) {
        const buffer1x = fsSync.readFileSync(iconPath);
        img.addRepresentation({
            scaleFactor: 1.0,
            buffer: buffer1x
        });
    }

    // Add @2x representation for retina
    if (fsSync.existsSync(icon2xPath)) {
        const buffer2x = fsSync.readFileSync(icon2xPath);
        img.addRepresentation({
            scaleFactor: 2.0,
            buffer: buffer2x
        });
    }

    // Set as template image for macOS (renders as black/white based on menu bar theme)
    img.setTemplateImage(true);

    return img;
};

async function loadPortals() {
    try {
        await fs.mkdir(CONFIG_DIR, { recursive: true, mode: 0o700 });
        const data = await fs.readFile(PORTALS_FILE, 'utf8');
        portals = JSON.parse(data);
    } catch (error) {
        portals = [];
    }
}

async function savePortals() {
    try {
        await fs.mkdir(CONFIG_DIR, { recursive: true, mode: 0o700 });
        await fs.writeFile(PORTALS_FILE, JSON.stringify(portals, null, 2), { mode: 0o600 });
    } catch (error) {
        console.error('Failed to save portals:', error);
    }
}

function createTray() {
    const icon = createVPNIcon(false);
    tray = new Tray(icon);
    tray.setToolTip('SecureConnect VPN - Disconnected');

    tray.on('click', () => {
        if (mainWindow) {
            if (mainWindow.isVisible()) {
                mainWindow.hide();
            } else {
                showWindow();
            }
        } else {
            createWindow();
        }
    });
}

function updateTrayIcon() {
    const icon = createVPNIcon(isConnected);
    tray.setImage(icon);
    tray.setToolTip(isConnected ? 'SecureConnect VPN - Connected' : 'SecureConnect VPN - Disconnected');
}

function createWindow() {
    const windowOptions = {
        width: 300,
        height: 380,
        resizable: false,
        show: false,
        frame: false,
        transparent: true,
        alwaysOnTop: true,
        skipTaskbar: true,
        hasShadow: true,
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false
        }
    };

    // Platform-specific glassmorphism/blur effects
    if (process.platform === 'darwin') {
        // macOS: Use vibrancy for native blur effect
        windowOptions.vibrancy = 'fullscreen-ui';
        windowOptions.visualEffectState = 'active';
        windowOptions.backgroundColor = '#00000000'; // Fully transparent
    } else if (process.platform === 'win32') {
        // Windows: Solid dark background with slight transparency for glass effect
        windowOptions.transparent = false; // Disable transparency to fix edge issues
        windowOptions.backgroundColor = '#1e293b'; // Solid dark background
        windowOptions.roundedCorners = true;
    } else {
        // Linux: Transparent background (blur handled by compositor if available)
        windowOptions.backgroundColor = '#00000000';
    }

    mainWindow = new BrowserWindow(windowOptions);

    mainWindow.loadFile('login.html');

    mainWindow.once('ready-to-show', () => {
        showWindow();
    });

    mainWindow.on('blur', () => {
        if (!mainWindow.webContents.isDevToolsOpened()) {
            mainWindow.hide();
        }
    });

    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

function showWindow() {
    if (!mainWindow) return;

    const trayBounds = tray.getBounds();
    const windowBounds = mainWindow.getBounds();
    const x = Math.round(trayBounds.x + (trayBounds.width / 2) - (windowBounds.width / 2));

    let y;
    if (process.platform === 'win32') {
        // Windows: taskbar at bottom, open window above tray icon
        y = Math.round(trayBounds.y - windowBounds.height - 5);
    } else {
        // macOS: menu bar at top, open window below tray icon
        y = Math.round(trayBounds.y + trayBounds.height + 5);
    }

    mainWindow.setPosition(x, y);
    mainWindow.show();
    mainWindow.focus();
}

// Auto-updater event handlers
autoUpdater.on('update-available', (info) => {
    console.log('[AUTO-UPDATE] Update available:', info.version);
    dialog.showMessageBox(mainWindow, {
        type: 'info',
        title: 'Update Available',
        message: 'A new version of SecureConnect is available!',
        detail: `Version ${info.version} is ready to download.\n\nCurrent: ${APP_VERSION}\nLatest: ${info.version}\n\nWould you like to download it now?`,
        buttons: ['Download', 'Later'],
        defaultId: 0,
        cancelId: 1
    }).then(result => {
        if (result.response === 0) {
            autoUpdater.downloadUpdate();
        }
    });
});

autoUpdater.on('update-not-available', () => {
    console.log('[AUTO-UPDATE] No update available. Current version is latest.');
});

autoUpdater.on('download-progress', (progressInfo) => {
    console.log(`[AUTO-UPDATE] Download progress: ${Math.round(progressInfo.percent)}%`);
});

autoUpdater.on('update-downloaded', (info) => {
    console.log('[AUTO-UPDATE] Update downloaded');
    dialog.showMessageBox(mainWindow, {
        type: 'info',
        title: 'Update Ready',
        message: 'Update downloaded successfully!',
        detail: `Version ${info.version} has been downloaded and is ready to install.\n\nThe update will be installed when you quit the application.`,
        buttons: ['Restart Now', 'Later'],
        defaultId: 0,
        cancelId: 1
    }).then(result => {
        if (result.response === 0) {
            autoUpdater.quitAndInstall();
        }
    });
});

autoUpdater.on('error', (err) => {
    console.error('[AUTO-UPDATE] Error:', err);
});

function checkForUpdates() {
    console.log('[AUTO-UPDATE] Checking for updates...');
    autoUpdater.checkForUpdates().catch(err => {
        console.error('[AUTO-UPDATE] Check failed:', err.message);
    });
}

async function downloadUpdate(downloadUrl, version) {
    return new Promise((resolve, reject) => {
        const fileName = `SecureConnect-${version}-mac.zip`;
        const tempPath = path.join(os.tmpdir(), fileName);
        const file = require('fs').createWriteStream(tempPath);

        const protocol = downloadUrl.startsWith('https') ? https : http;

        protocol.get(downloadUrl, (response) => {
            if (response.statusCode !== 200) {
                reject(new Error(`Failed to download: ${response.statusCode}`));
                return;
            }

            response.pipe(file);

            file.on('finish', () => {
                file.close();
                resolve(tempPath);
            });

            file.on('error', (err) => {
                require('fs').unlink(tempPath, () => {});
                reject(err);
            });
        }).on('error', (err) => {
            require('fs').unlink(tempPath, () => {});
            reject(err);
        });
    });
}

function showUpdateDialog(updateInfo) {
    const buttons = updateInfo.is_critical ? ['Update'] : ['Update', 'Dismiss'];
    const message = `A new version of SecureConnect is available!\n\nCurrent: ${updateInfo.current_version}\nLatest: ${updateInfo.latest_version}\n\n${updateInfo.release_notes || 'Bug fixes and improvements'}`;

    dialog.showMessageBox(mainWindow, {
        type: 'info',
        title: 'Update Available',
        message: 'SecureConnect Update',
        detail: message,
        buttons: buttons,
        defaultId: 0,
        cancelId: 1,
        noLink: true
    }).then(async result => {
        if (result.response === 0) {
            // User clicked "Update"
            try {
                // Show downloading dialog
                const progressDialog = dialog.showMessageBox(mainWindow, {
                    type: 'info',
                    title: 'Downloading Update',
                    message: 'Please wait...',
                    detail: `Downloading SecureConnect ${updateInfo.latest_version}`,
                    buttons: []
                });

                // Download the update
                const downloadedFile = await downloadUpdate(updateInfo.download_url, updateInfo.latest_version);

                // Show success message
                await dialog.showMessageBox(mainWindow, {
                    type: 'info',
                    title: 'Update Downloaded',
                    message: 'Update downloaded successfully!',
                    detail: `The update has been downloaded to:\n${downloadedFile}\n\nPlease extract and install the update manually.\n\nThe app will now quit.`,
                    buttons: ['OK']
                });

                // Open the downloads folder
                shell.showItemInFolder(downloadedFile);

                // Quit the app
                app.quit();

            } catch (error) {
                dialog.showErrorBox('Update Failed', `Failed to download update:\n${error.message}`);
            }
        }
    });
}

// Setup SecureConnect permissions on first launch
async function setupPermissions() {
    const sudoersFile = '/private/etc/sudoers.d/secureconnect-vpn';

    // Check if sudoers file exists (don't try to read it - we don't have permission)
    // The PKG installer creates this file, so if it exists, we're good
    if (fsSync.existsSync(sudoersFile)) {
        console.log('[SETUP] Sudoers file exists - configured by installer');
        return true;
    }

    const response = await dialog.showMessageBox({
        type: 'info',
        title: 'SecureConnect Setup',
        message: 'First-time setup required',
        detail: 'SecureConnect needs to configure passwordless VPN access. You will be asked for your password once.',
        buttons: ['Setup Now', 'Later'],
        defaultId: 0
    });

    if (response.response !== 0) return false;

    const username = os.userInfo().username;
    const appPath = '/Applications/SecureConnect.app';
    const sudoersContent = `# SecureConnect VPN
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-vpn
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-vpn up *
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-vpn down *
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-ctl
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-ctl *
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-go
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-go *
${username} ALL=(ALL) NOPASSWD: ${appPath}/Contents/Resources/bin/darwin/secureconnect-bash
${username} ALL=(ALL) NOPASSWD: /usr/sbin/networksetup
${username} ALL=(ALL) NOPASSWD: /usr/sbin/networksetup *
${username} ALL=(ALL) NOPASSWD: /sbin/ifconfig
${username} ALL=(ALL) NOPASSWD: /sbin/ifconfig *
${username} ALL=(ALL) NOPASSWD: /sbin/route
${username} ALL=(ALL) NOPASSWD: /sbin/route *
${username} ALL=(ALL) NOPASSWD: /usr/sbin/sysctl
${username} ALL=(ALL) NOPASSWD: /usr/bin/pkill
${username} ALL=(ALL) NOPASSWD: /bin/rm
${username} ALL=(ALL) NOPASSWD: /bin/mkdir
`;

    const tmpFile = `/tmp/secureconnect-sudoers-${Date.now()}`;
    fsSync.writeFileSync(tmpFile, sudoersContent);
    const setupScript = `cp "${tmpFile}" "${sudoersFile}" && chmod 0440 "${sudoersFile}" && mkdir -p /etc/secureconnect && chmod 755 /etc/secureconnect && rm "${tmpFile}"`;

    return new Promise((resolve) => {
        sudo.exec(setupScript, { name: 'SecureConnect Setup' }, (error) => {
            if (!error) {
                dialog.showMessageBox({ type: 'info', title: 'Setup Complete', message: 'SecureConnect configured successfully!' });
                resolve(true);
            } else {
                dialog.showErrorBox('Setup Failed', 'Please try again');
                resolve(false);
            }
        });
    });
}

app.whenReady().then(async () => {
    await loadPortals();
    createTray();
    createWindow();

    // Run setup on first launch (macOS only)
    if (process.platform === 'darwin') {
        setTimeout(() => setupPermissions(), 1000);
    }

    // Note: Update check now happens after login, not on startup
});

app.on('window-all-closed', (e) => {
    e.preventDefault();
});

// Disconnect VPN when app is quitting
app.on('before-quit', async (e) => {
    if (isConnected) {
        e.preventDefault();
        console.log('Disconnecting VPN before quit...');
        try {
            await vpnManager.disconnect();
            isConnected = false;
        } catch (error) {
            console.error('Error disconnecting on quit:', error);
        }
        app.quit();
    }
});

// Also handle SIGINT/SIGTERM for command-line termination
process.on('SIGINT', async () => {
    if (isConnected) {
        console.log('Disconnecting VPN on SIGINT...');
        try {
            await vpnManager.disconnect();
        } catch (error) {
            console.error('Error disconnecting:', error);
        }
    }
    process.exit(0);
});

process.on('SIGTERM', async () => {
    if (isConnected) {
        console.log('Disconnecting VPN on SIGTERM...');
        try {
            await vpnManager.disconnect();
        } catch (error) {
            console.error('Error disconnecting:', error);
        }
    }
    process.exit(0);
});

if (app.dock) app.dock.hide();

// IPC Handlers
ipcMain.handle('getPortals', () => {
    return portals;
});

ipcMain.handle('getCurrentPortal', () => {
    return currentPortal;
});

ipcMain.handle('getConnectionStatus', () => {
    return { isConnected, user: currentUser, portal: currentPortal };
});

ipcMain.handle('removePortal', async (event, portalId) => {
    try {
        portals = portals.filter(p => p.id !== portalId);

        // If removed portal was current, clear it
        if (currentPortal && currentPortal.id === portalId) {
            currentPortal = null;
        }

        await savePortals();
        return { success: true, portals };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.handle('addPortal', async (event, data) => {
    try {
        if (!data || !data.name || !data.ip) {
            return { success: false, error: 'Portal name and IP are required' };
        }

        const { name, ip } = data;

        // Construct HTTPS endpoint with port 3000
        const endpoint = `https://${ip}:3000`;

        // Check if portal already exists
        const exists = portals.find(p => p.endpoint === endpoint);
        if (exists) {
            return { success: false, error: 'Portal already exists' };
        }

        // Add new portal
        portals.push({
            id: Date.now().toString(),
            name: name,
            endpoint: endpoint
        });

        await savePortals();
        return { success: true, portals };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.handle('selectPortal', (event, portalId) => {
    currentPortal = portals.find(p => p.id === portalId);
    if (currentPortal) {
        vpnManager.setEndpoint(currentPortal.endpoint);
    }
    return { success: true, portal: currentPortal };
});

ipcMain.handle('login', async (event, credentials) => {
    try {
        const result = await vpnManager.login(credentials);
        currentUser = result.user;

        // Set update server URL dynamically based on portal endpoint
        if (currentPortal && currentPortal.endpoint) {
            const updateUrl = `${currentPortal.endpoint}/downloads/`;
            console.log(`[AUTO-UPDATE] Setting feed URL to: ${updateUrl}`);
            autoUpdater.setFeedURL({
                provider: 'generic',
                url: updateUrl
            });
        }

        // Check for updates after successful login
        console.log('✓ Login successful - will check for updates in 1 second');
        setTimeout(() => {
            checkForUpdates();
        }, 1000);

        return { success: true, data: result };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.handle('connect', async (event) => {
    try {
        const result = await vpnManager.connect();
        isConnected = true;
        updateTrayIcon();
        return { success: true, data: result };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.handle('disconnect', async (event) => {
    try {
        await vpnManager.disconnect();
        isConnected = false;
        currentUser = null;
        updateTrayIcon();
        return { success: true };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.handle('getVPNStatus', async () => {
    try {
        const status = await vpnManager.getStatus();
        return { success: true, data: status };
    } catch (error) {
        return { success: false, error: error.message };
    }
});

ipcMain.handle('close', () => {
    if (mainWindow) mainWindow.hide();
});
