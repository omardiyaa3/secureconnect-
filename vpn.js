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
        this.scProcess = null; // For Windows userspace SecureConnect

        // Get path to bundled binaries
        const isDev = !app.isPackaged;
        const resourcesPath = isDev
            ? path.join(__dirname, 'resources')
            : process.resourcesPath;

        const binPath = path.join(resourcesPath, 'bin', this.platform);

        // Cross-platform SecureConnect binary detection
        if (this.platform === 'darwin') {
            // macOS: Use bundled SecureConnect binaries
            this.scGoBinary = path.join(binPath, 'secureconnect-go');
            this.wgQuickPath = path.join(binPath, 'secureconnect-vpn');
            this.wgPath = path.join(binPath, 'secureconnect-ctl');

            // Check if binaries exist
            if (!require('fs').existsSync(this.scGoBinary)) {
                console.warn('SecureConnect Go binary not found, DPI bypass disabled');
                this.scGoBinary = null;
            }
        } else if (this.platform === 'win32') {
            // Windows: Use bundled binaries
            this.scGoBinary = path.join(binPath, 'secureconnect-go.exe');
            this.scQuickScript = path.join(binPath, 'secureconnect-quick.ps1');
            this.wgPath = path.join(binPath, 'secureconnect-ctl.exe');
            this.wireguardExe = path.join(binPath, 'secureconnect-vpn.exe');

            // Check if SecureConnect Go binary exists
            if (!require('fs').existsSync(this.scGoBinary)) {
                console.warn('SecureConnect Go binary not found, DPI bypass disabled');
                this.scGoBinary = null;
            }
        } else if (this.platform === 'linux') {
            // Linux: Use bundled binaries
            this.scGoBinary = path.join(binPath, 'secureconnect-go');
            this.wgQuickPath = path.join(binPath, 'secureconnect-vpn');
            this.wgPath = path.join(binPath, 'secureconnect-ctl');

            // Fallback to system wg-quick if bundled not found
            if (!require('fs').existsSync(this.wgQuickPath)) {
                console.warn('Bundled wg-quick not found, using system wg-quick');
                this.wgQuickPath = '/usr/bin/wg-quick';
            }
            if (!require('fs').existsSync(this.scGoBinary)) {
                console.warn('SecureConnect Go binary not found, DPI bypass disabled');
                this.scGoBinary = null;
            }
        } else {
            // Unknown platform: Use system defaults
            this.wgQuickPath = '/usr/bin/wg-quick';
            this.scGoBinary = null;
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
            // Determine if we should use SecureConnect Go (for DPI bypass)
            const useDpiBypass = this.scGoBinary && config.awg;

            if (this.platform === 'win32') {
                await this.connectWindows(configFile, useDpiBypass, config);
            } else {
                await this.connectUnix(configFile, useDpiBypass);
            }

            this.connected = true;
            return { success: true, message: 'Connected successfully' };
        } catch (error) {
            // Restore DNS if connection failed
            await this.restoreDNSSettings();
            throw new Error('Connection failed: ' + error.message);
        }
    }

    async connectWindows(configFile, useDpiBypass, config) {
        if (useDpiBypass && this.scQuickScript) {
            // Use SecureConnect PowerShell script for DPI bypass
            console.log('Starting SecureConnect with DPI bypass...');

            const binDir = path.dirname(this.scQuickScript);
            const cmd = `powershell -ExecutionPolicy Bypass -File "${this.scQuickScript}" up "${configFile}"`;

            try {
                await execAsync(cmd, { cwd: binDir, timeout: 30000 });
            } catch (error) {
                const details = error.stderr || error.stdout || error.message;
                throw new Error(`Connection failed: ${details}`);
            }

            console.log('SecureConnect tunnel active with DPI bypass');
        } else {
            // Standard WireGuard: Use tunnel service approach
            try {
                await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
            } catch (e) {
                // Ignore - tunnel might not exist
            }
            await execAsync(`"${this.wireguardExe}" /installtunnelservice "${configFile}"`);
            console.log('SecureConnect tunnel service installed');
        }
    }

    async connectUnix(configFile, useDpiBypass) {
        // macOS/Linux: Use secureconnect-vpn (wg-quick) with optional userspace daemon
        const quickPath = this.wgQuickPath;

        // Clean up any existing interface before connecting
        try {
            console.log('Checking for existing VPN interface...');
            await execAsync(`sudo "${quickPath}" down "${configFile}" 2>/dev/null || true`);
        } catch (e) {
            // Ignore errors - interface might not exist
        }

        // Use SecureConnect Go binary for DPI bypass if available
        if (useDpiBypass && this.scGoBinary) {
            const scGoDir = path.dirname(this.scGoBinary);
            const ctlDir = path.dirname(this.wgPath);
            // Use sh -c to set environment variables (sudo blocks env vars directly)
            const cmd = `sudo sh -c 'WG_QUICK_USERSPACE_IMPLEMENTATION="${this.scGoBinary}" PATH="${scGoDir}:${ctlDir}:$PATH" "${quickPath}" up "${configFile}"'`;
            console.log('Using SecureConnect with DPI bypass');
            await execAsync(cmd);
        } else {
            await execAsync(`sudo "${quickPath}" up "${configFile}"`);
        }
        console.log(`SecureConnect tunnel active (DPI bypass: ${useDpiBypass})`);
    }

    async disconnect() {
        if (!this.connected) return { success: true, message: 'Not connected' };

        const configFile = path.join(this.configPath, 'sc0.conf');

        try {
            console.log('Disconnecting VPN...');
            // Check if DPI bypass was used
            const usedDpiBypass = this.scGoBinary && this.vpnConfig && this.vpnConfig.awg;

            if (this.platform === 'win32') {
                await this.disconnectWindows(usedDpiBypass, configFile);
            } else {
                await this.disconnectUnix(configFile);
            }

            await this.apiClient.disconnectVPN();
            await this.restoreDNSSettings();

            this.connected = false;
            return { success: true, message: 'Disconnected successfully' };
        } catch (error) {
            console.error('Disconnect error:', error);
            await this.restoreDNSSettings();

            // Force cleanup as last resort
            await this.forceCleanup();

            this.connected = false;
            throw new Error('Disconnect failed: ' + error.message);
        }
    }

    async disconnectWindows(usedDpiBypass, configFile) {
        if (usedDpiBypass && this.scQuickScript) {
            // Use PowerShell script to disconnect
            console.log('Stopping SecureConnect tunnel...');
            const cmd = `powershell -ExecutionPolicy Bypass -File "${this.scQuickScript}" down "${configFile}"`;
            await execAsync(cmd);
            console.log('SecureConnect tunnel stopped');
        } else {
            // Standard: Uninstall tunnel service
            await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
            console.log('SecureConnect tunnel service uninstalled');
        }
    }

    async disconnectUnix(configFile) {
        // macOS/Linux: Use wg-quick down
        const quickPath = this.wgQuickPath;

        const { stdout, stderr } = await execAsync(`sudo "${quickPath}" down "${configFile}"`);
        console.log('wg-quick down output:', stdout);
        if (stderr) console.log('wg-quick down stderr:', stderr);

        // Verify interface is actually down on macOS
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

    async forceCleanup() {
        // Force cleanup as last resort
        if (this.platform === 'darwin') {
            try {
                await execAsync('sudo ifconfig utun9 down 2>&1 || true');
            } catch {}
        } else if (this.platform === 'win32') {
            // Kill AWG process if running
            if (this.scProcess) {
                try { this.scProcess.kill(); } catch {}
                this.scProcess = null;
            }
            // Try to uninstall tunnel service
            try {
                await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
            } catch {}
        } else if (this.platform === 'linux') {
            try {
                await execAsync('sudo ip link delete sc0 2>/dev/null || true');
            } catch {}
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
        // Check if we have DPI bypass obfuscation parameters
        if (config.awg && this.scGoBinary) {
            // Generate config with obfuscation parameters for DPI bypass
            let scConfig = '[Interface]\n';
            scConfig += 'PrivateKey = ' + config.privateKey + '\n';
            scConfig += 'Address = ' + config.address + '\n';
            scConfig += 'DNS = ' + config.dns + '\n';
            // DPI bypass obfuscation parameters
            scConfig += 'Jc = ' + config.awg.Jc + '\n';
            scConfig += 'Jmin = ' + config.awg.Jmin + '\n';
            scConfig += 'Jmax = ' + config.awg.Jmax + '\n';
            scConfig += 'S1 = ' + config.awg.S1 + '\n';
            scConfig += 'S2 = ' + config.awg.S2 + '\n';
            scConfig += 'H1 = ' + config.awg.H1 + '\n';
            scConfig += 'H2 = ' + config.awg.H2 + '\n';
            scConfig += 'H3 = ' + config.awg.H3 + '\n';
            scConfig += 'H4 = ' + config.awg.H4 + '\n';
            scConfig += '\n[Peer]\n';
            scConfig += 'PublicKey = ' + config.publicKey + '\n';
            scConfig += 'Endpoint = ' + config.endpoint + '\n';
            scConfig += 'AllowedIPs = ' + config.allowedIPs + '\n';
            scConfig += 'PersistentKeepalive = 25\n';
            return scConfig;
        }

        // Standard config (fallback)
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
