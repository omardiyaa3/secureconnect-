const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');
const sudo = require('sudo-prompt');
const { app } = require('electron');
const APIClient = require('./api');
const execAsync = promisify(exec);
const sudoExec = promisify(sudo.exec);

class VPNManager {
    constructor() {
        this.apiClient = new APIClient();
        this.configPath = path.join(os.homedir(), '.worldposta-vpn');
        this.connected = false;
        this.vpnConfig = null;
        this.platform = process.platform;

        // Get path to bundled binaries
        const isDev = !app.isPackaged;
        const resourcesPath = isDev
            ? path.join(__dirname, 'resources')
            : process.resourcesPath;

        const binPath = path.join(resourcesPath, 'bin', this.platform);

        // Cross-platform WireGuard path detection
        if (this.platform === 'darwin') {
            // macOS: Use bundled rebranded binaries
            this.wgQuickPath = path.join(binPath, 'secureconnect-vpn');
            this.wgPath = path.join(binPath, 'secureconnect-ctl');

            // Fallback to system paths if bundled binaries not found
            if (!require('fs').existsSync(this.wgQuickPath)) {
                console.warn('Bundled binaries not found, falling back to system paths');
                this.wgQuickPath = '/opt/homebrew/bin/wg-quick';
                this.wgPath = '/opt/homebrew/bin/wg';
            }
        } else if (this.platform === 'win32') {
            // Windows: WireGuard installation path (will be rebranded later)
            this.wgQuickPath = 'C:\\Program Files\\WireGuard\\wg.exe';
        } else {
            // Linux: Standard system path (will be rebranded later)
            this.wgQuickPath = '/usr/bin/wg-quick';
        }

        this.originalDNS = null;
        this.activeInterface = null;
    }

    setEndpoint(endpoint) {
        this.apiClient.setBaseUrl(endpoint);
    }

    async login(credentials) {
        const result = await this.apiClient.login(credentials.username, credentials.password);
        await this.ensureConfigDir();
        await fs.writeFile(
            path.join(this.configPath, 'session.json'),
            JSON.stringify({ token: this.apiClient.token, user: result.user }),
            { mode: 0o600 }
        );
        return result;
    }

    async getActiveNetworkInterface() {
        try {
            if (this.platform === 'darwin') {
                // macOS: networksetup
                const { stdout } = await execAsync('networksetup -listnetworkserviceorder');
                const lines = stdout.split('\n');
                for (const line of lines) {
                    if (line.includes('Wi-Fi')) return 'Wi-Fi';
                    if (line.includes('Ethernet')) return 'Ethernet';
                }
                return 'Wi-Fi';
            } else if (this.platform === 'win32') {
                // Windows: Get active interface name
                const { stdout } = await execAsync('netsh interface show interface');
                const lines = stdout.split('\n');
                for (const line of lines) {
                    if (line.includes('Connected') && (line.includes('Wi-Fi') || line.includes('Ethernet'))) {
                        return line.split(/\s+/).pop();
                    }
                }
                return 'Ethernet';
            } else {
                // Linux: Get default interface
                const { stdout } = await execAsync('ip route | grep default');
                const match = stdout.match(/dev\s+(\S+)/);
                return match ? match[1] : 'eth0';
            }
        } catch (error) {
            console.error('Failed to detect network interface:', error);
            return this.platform === 'darwin' ? 'Wi-Fi' : 'eth0';
        }
    }

    async saveDNSSettings() {
        try {
            this.activeInterface = await this.getActiveNetworkInterface();

            if (this.platform === 'darwin') {
                // macOS: networksetup
                const { stdout } = await execAsync(`networksetup -getdnsservers "${this.activeInterface}"`);
                this.originalDNS = stdout.includes("There aren't any DNS Servers") ? 'Empty' : stdout.trim().replace(/\n/g, ' ');
            } else if (this.platform === 'win32') {
                // Windows: netsh
                const { stdout } = await execAsync(`netsh interface ip show dns "${this.activeInterface}"`);
                this.originalDNS = stdout.trim();
            } else {
                // Linux: Read /etc/resolv.conf or use resolvectl
                try {
                    const { stdout } = await execAsync('resolvectl status');
                    this.originalDNS = stdout.trim();
                } catch {
                    this.originalDNS = await fs.readFile('/etc/resolv.conf', 'utf8');
                }
            }

            console.log(`Saved DNS settings for ${this.activeInterface}`);
        } catch (error) {
            console.error('Failed to save DNS settings:', error);
            this.originalDNS = null;
        }
    }

    async restoreDNSSettings() {
        if (!this.originalDNS) {
            console.log('No DNS settings to restore');
            return;
        }

        try {
            const options = { name: 'SecureConnect' };

            if (this.platform === 'darwin') {
                // macOS: networksetup
                const dnsArgs = this.originalDNS === 'Empty' ? 'Empty' : this.originalDNS;
                await sudoExec(`networksetup -setdnsservers "${this.activeInterface}" ${dnsArgs}`, options);
            } else if (this.platform === 'win32') {
                // Windows: netsh - restore to DHCP
                await sudoExec(`netsh interface ip set dns "${this.activeInterface}" dhcp`, options);
            } else {
                // Linux: WireGuard handles DNS automatically via wg-quick down
                console.log('DNS restoration handled by wg-quick on Linux');
            }

            console.log(`Restored DNS settings for ${this.activeInterface}`);
            this.originalDNS = null;
            this.activeInterface = null;
        } catch (error) {
            console.error('Failed to restore DNS settings:', error);
        }
    }

    async connect() {
        // Save current DNS settings before connecting
        await this.saveDNSSettings();

        const config = await this.apiClient.connectVPN();
        this.vpnConfig = config;

        try {
            const options = { name: 'SecureConnect' };

            if (this.platform === 'darwin') {
                // macOS: Use simple wg commands directly (requires WireGuard app installed)
                const wgConfig = this.generateWireGuardConfig(config);
                const configFile = path.join(this.configPath, 'sc0.conf');
                await fs.writeFile(configFile, wgConfig, { mode: 0o600 });

                // Check if WireGuard.app is installed
                const wgPath = '/Applications/WireGuard.app/Contents/MacOS/WireGuard';
                if (require('fs').existsSync(wgPath)) {
                    // Use WireGuard.app
                    await sudoExec(`"${wgPath}" tunnel --activate "${configFile}"`, options);
                } else {
                    throw new Error('WireGuard app not installed. Please install from: https://apps.apple.com/app/wireguard/id1451685025');
                }
            } else {
                // Windows/Linux: Use original wg-quick approach
                const wgConfig = this.generateWireGuardConfig(config);
                const configFile = path.join(this.configPath, 'sc0.conf');
                await fs.writeFile(configFile, wgConfig, { mode: 0o600 });
                await sudoExec(`"${this.wgQuickPath}" up "${configFile}"`, options);
            }

            this.connected = true;
            return { success: true, message: 'Connected successfully' };
        } catch (error) {
            // Restore DNS if connection failed
            await this.restoreDNSSettings();
            throw new Error('VPN connection failed: ' + error.message);
        }
    }

    async disconnect() {
        if (!this.connected) return { success: true, message: 'Not connected' };
        try {
            const configFile = path.join(this.configPath, 'sc0.conf');
            const options = { name: 'SecureConnect' };
            await sudoExec(`"${this.wgQuickPath}" down "${configFile}"`, options);
            await this.apiClient.disconnectVPN();

            // Restore original DNS settings
            await this.restoreDNSSettings();

            this.connected = false;
            return { success: true, message: 'Disconnected successfully' };
        } catch (error) {
            // Even if disconnect fails, try to restore DNS
            await this.restoreDNSSettings();
            throw new Error('Disconnect failed: ' + error.message);
        }
    }

    async getStatus() {
        try {
            const apiStatus = await this.apiClient.getStatus();
            return {
                connected: apiStatus.connected,
                tunnelIP: apiStatus.tunnelIP,
                connectedAt: apiStatus.connectedAt
            };
        } catch (error) {
            return { connected: false, error: error.message };
        }
    }

    generateWireGuardConfig(config) {
        return '[Interface]\nPrivateKey = ' + config.privateKey + '\nAddress = ' + config.address + '\nDNS = ' + config.dns + '\n\n[Peer]\nPublicKey = ' + config.publicKey + '\nEndpoint = ' + config.endpoint + '\nAllowedIPs = ' + config.allowedIPs + '\nPersistentKeepalive = 25\n';
    }

    async ensureConfigDir() {
        try {
            await fs.mkdir(this.configPath, { recursive: true, mode: 0o700 });
        } catch (error) {
            if (error.code !== 'EEXIST') throw error;
        }
    }
}
module.exports = VPNManager;
