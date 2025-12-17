const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');
const os = require('os');
const { app } = require('electron');
const APIClient = require('./api');
const execAsync = promisify(exec);

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

        // Cross-platform AmneziaWG path detection (for DPI bypass)
        if (this.platform === 'darwin') {
            // macOS: Use bundled AmneziaWG binaries
            const arch = process.arch === 'arm64' ? 'arm64' : 'amd64';
            this.awgBinary = path.join(binPath, `amneziawg-${arch}`);
            this.awgQuickPath = path.join(binPath, 'awg-quick');

            // Legacy WireGuard paths for fallback
            this.wgQuickPath = path.join(binPath, 'secureconnect-vpn');
            this.wgPath = path.join(binPath, 'secureconnect-ctl');

            // Fallback to system paths if bundled binaries not found
            if (!require('fs').existsSync(this.awgBinary)) {
                console.warn('AmneziaWG binaries not found, falling back to WireGuard');
                this.awgBinary = null;
                this.awgQuickPath = null;
            }
        } else if (this.platform === 'win32') {
            // Windows: Use bundled AmneziaWG binary
            this.awgBinary = path.join(binPath, 'amneziawg.exe');

            // Legacy WireGuard paths
            this.wgPath = path.join(binPath, 'secureconnect-ctl.exe');
            this.wireguardExe = path.join(binPath, 'secureconnect-vpn.exe');

            // Fallback to system WireGuard if bundled not found
            if (!require('fs').existsSync(this.awgBinary)) {
                console.warn('AmneziaWG binary not found, falling back to WireGuard');
                this.awgBinary = null;
            }
        } else {
            // Linux: Standard system path
            this.wgQuickPath = '/usr/bin/wg-quick';
            this.awgBinary = null;
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
            if (this.platform === 'darwin') {
                // macOS: networksetup (passwordless via sudoers configuration)
                const dnsArgs = this.originalDNS === 'Empty' ? 'Empty' : this.originalDNS;
                await execAsync(`sudo networksetup -setdnsservers "${this.activeInterface}" ${dnsArgs}`);
            } else if (this.platform === 'win32') {
                // Windows: netsh - restore to DHCP
                await execAsync(`netsh interface ip set dns "${this.activeInterface}" dhcp`);
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
        const wgConfig = this.generateWireGuardConfig(config);
        const configFile = path.join(this.configPath, 'sc0.conf');
        await fs.writeFile(configFile, wgConfig, { mode: 0o600 });

        try {
            // Determine if we should use AmneziaWG (for DPI bypass)
            const useAwg = this.awgBinary && config.awg;

            if (this.platform === 'win32') {
                if (useAwg) {
                    // Windows: Use amneziawg.exe to install tunnel service
                    try {
                        await execAsync(`"${this.awgBinary}" /uninstalltunnelservice sc0`);
                    } catch (e) {
                        // Ignore - tunnel might not exist
                    }
                    await execAsync(`"${this.awgBinary}" /installtunnelservice "${configFile}"`);
                    console.log('AmneziaWG tunnel service installed');
                } else {
                    // Fallback to WireGuard
                    try {
                        await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
                    } catch (e) {
                        // Ignore - tunnel might not exist
                    }
                    await execAsync(`"${this.wireguardExe}" /installtunnelservice "${configFile}"`);
                }
            } else {
                // macOS/Linux: Always use wg-quick (secureconnect-vpn), but with AmneziaWG binary if available
                // awg-quick requires bash 4+ which macOS doesn't have by default
                const quickPath = this.wgQuickPath;

                // Clean up any existing interface before connecting
                try {
                    console.log('Checking for existing VPN interface...');
                    await execAsync(`sudo "${quickPath}" down "${configFile}" 2>/dev/null || true`);
                } catch (e) {
                    // Ignore errors - interface might not exist
                }

                // Use AmneziaWG binary for DPI bypass if available
                if (useAwg && this.awgBinary) {
                    const awgDir = path.dirname(this.awgBinary);
                    // Use sh -c to set environment variables (sudo blocks env vars directly)
                    const cmd = `sudo sh -c 'WG_QUICK_USERSPACE_IMPLEMENTATION="${this.awgBinary}" PATH="${awgDir}:$PATH" "${quickPath}" up "${configFile}"'`;
                    console.log('Using AmneziaWG for DPI bypass');
                    await execAsync(cmd);
                } else {
                    await execAsync(`sudo "${quickPath}" up "${configFile}"`);
                }
                console.log(`wg-quick up completed (AWG: ${useAwg})`);
            }

            this.connected = true;
            return { success: true, message: 'Connected successfully' };
        } catch (error) {
            // Restore DNS if connection failed
            await this.restoreDNSSettings();
            throw new Error('Connection failed: ' + error.message);
        }
    }

    async disconnect() {
        if (!this.connected) return { success: true, message: 'Not connected' };

        const configFile = path.join(this.configPath, 'sc0.conf');

        try {
            console.log('Disconnecting VPN...');
            // Check if AWG is being used
            const useAwg = this.awgBinary && this.vpnConfig && this.vpnConfig.awg;

            if (this.platform === 'win32') {
                // Windows: Uninstall the tunnel service
                if (useAwg) {
                    await execAsync(`"${this.awgBinary}" /uninstalltunnelservice sc0`);
                    console.log('AmneziaWG tunnel service uninstalled');
                } else {
                    await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
                    console.log('WireGuard tunnel service uninstalled');
                }
            } else {
                // macOS/Linux: Always use wg-quick (secureconnect-vpn)
                const quickPath = this.wgQuickPath;

                const { stdout, stderr } = await execAsync(`sudo "${quickPath}" down "${configFile}"`);
                console.log('wg-quick down output:', stdout);
                if (stderr) console.log('wg-quick down stderr:', stderr);

                // Verify interface is actually down
                if (this.platform === 'darwin') {
                    try {
                        await execAsync('ifconfig utun9 2>&1');
                        console.warn('Interface still exists after down, removing manually');
                        await execAsync('sudo ifconfig utun9 down 2>&1 || true');
                    } catch {
                        console.log('VPN interface removed successfully');
                    }
                }
            }

            await this.apiClient.disconnectVPN();
            await this.restoreDNSSettings();

            this.connected = false;
            return { success: true, message: 'Disconnected successfully' };
        } catch (error) {
            console.error('Disconnect error:', error);
            await this.restoreDNSSettings();

            // Force cleanup as last resort
            if (this.platform === 'darwin') {
                try {
                    await execAsync('sudo ifconfig utun9 down 2>&1 || true');
                } catch {}
            } else if (this.platform === 'win32') {
                try {
                    // Try both AmneziaWG and WireGuard for cleanup
                    if (this.awgBinary) {
                        await execAsync(`"${this.awgBinary}" /uninstalltunnelservice sc0`);
                    }
                } catch {}
                try {
                    await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
                } catch {}
            }

            this.connected = false;
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
        // Check if we have AmneziaWG obfuscation parameters
        if (config.awg && this.awgBinary) {
            // Generate AmneziaWG config with obfuscation parameters
            let awgConfig = '[Interface]\n';
            awgConfig += 'PrivateKey = ' + config.privateKey + '\n';
            awgConfig += 'Address = ' + config.address + '\n';
            awgConfig += 'DNS = ' + config.dns + '\n';
            // AmneziaWG obfuscation parameters (client-side)
            awgConfig += 'Jc = ' + config.awg.Jc + '\n';
            awgConfig += 'Jmin = ' + config.awg.Jmin + '\n';
            awgConfig += 'Jmax = ' + config.awg.Jmax + '\n';
            awgConfig += 'S1 = ' + config.awg.S1 + '\n';
            awgConfig += 'S2 = ' + config.awg.S2 + '\n';
            awgConfig += 'H1 = ' + config.awg.H1 + '\n';
            awgConfig += 'H2 = ' + config.awg.H2 + '\n';
            awgConfig += 'H3 = ' + config.awg.H3 + '\n';
            awgConfig += 'H4 = ' + config.awg.H4 + '\n';
            awgConfig += '\n[Peer]\n';
            awgConfig += 'PublicKey = ' + config.publicKey + '\n';
            awgConfig += 'Endpoint = ' + config.endpoint + '\n';
            awgConfig += 'AllowedIPs = ' + config.allowedIPs + '\n';
            awgConfig += 'PersistentKeepalive = 25\n';
            return awgConfig;
        }

        // Standard WireGuard config (fallback)
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
