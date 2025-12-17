const { exec, spawn } = require('child_process');
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

        // Proxy state
        this.proxyProcess = null;
        this.proxyLocalPort = 51820;
        this.useProxy = false;

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

            // UDP obfuscation proxy - detect architecture
            const arch = process.arch === 'arm64' ? 'arm64' : 'amd64';
            this.proxyPath = path.join(binPath, 'udp-obfs-' + arch);

            // Fallback to system paths if bundled binaries not found
            if (!require('fs').existsSync(this.wgQuickPath)) {
                console.warn('Bundled binaries not found, falling back to system paths');
                this.wgQuickPath = '/opt/homebrew/bin/wg-quick';
                this.wgPath = '/opt/homebrew/bin/wg';
            }
        } else if (this.platform === 'win32') {
            // Windows: Use bundled rebranded binaries
            this.wgPath = path.join(binPath, 'secureconnect-ctl.exe');
            this.wireguardExe = path.join(binPath, 'secureconnect-vpn.exe');
            this.proxyPath = path.join(binPath, 'udp-obfs.exe');

            // Fallback to system WireGuard if bundled not found
            if (!require('fs').existsSync(this.wgPath)) {
                console.warn('Bundled binaries not found, falling back to system WireGuard');
                this.wgPath = 'C:\\Program Files\\WireGuard\\wg.exe';
                this.wireguardExe = 'C:\\Program Files\\WireGuard\\wireguard.exe';
            }
        } else {
            // Linux: Standard system path (will be rebranded later)
            this.wgQuickPath = '/usr/bin/wg-quick';
            this.proxyPath = '/usr/local/bin/udp-obfs';
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

    async startProxy(remoteHost, remotePort, obfsKey) {
        // Check if proxy binary exists
        if (!require('fs').existsSync(this.proxyPath)) {
            console.log('Proxy binary not found at:', this.proxyPath);
            return false;
        }

        if (this.proxyProcess) {
            console.log('Proxy already running');
            return true;
        }

        const remoteAddr = remoteHost + ':' + remotePort;
        const listenAddr = '127.0.0.1:' + this.proxyLocalPort;

        console.log('Starting UDP obfuscation proxy:', listenAddr, '->', remoteAddr);

        return new Promise((resolve) => {
            try {
                const args = [
                    '-mode', 'client',
                    '-listen', listenAddr,
                    '-remote', remoteAddr,
                    '-key', obfsKey
                ];

                this.proxyProcess = spawn(this.proxyPath, args, {
                    stdio: ['ignore', 'pipe', 'pipe'],
                    detached: false,
                    windowsHide: true
                });

                this.proxyProcess.stdout.on('data', (data) => {
                    console.log('[proxy]', data.toString().trim());
                });

                this.proxyProcess.stderr.on('data', (data) => {
                    console.error('[proxy]', data.toString().trim());
                });

                this.proxyProcess.on('error', (err) => {
                    console.error('Proxy spawn error:', err.message);
                    this.proxyProcess = null;
                    resolve(false);
                });

                this.proxyProcess.on('exit', (code) => {
                    console.log('Proxy exited with code:', code);
                    this.proxyProcess = null;
                });

                // Give proxy time to start
                setTimeout(() => {
                    if (this.proxyProcess && !this.proxyProcess.killed) {
                        console.log('Proxy started successfully');
                        resolve(true);
                    } else {
                        resolve(false);
                    }
                }, 500);
            } catch (err) {
                console.error('Failed to start proxy:', err.message);
                this.proxyProcess = null;
                resolve(false);
            }
        });
    }

    stopProxy() {
        if (!this.proxyProcess) {
            return;
        }

        console.log('Stopping proxy...');
        try {
            this.proxyProcess.kill();
        } catch (err) {
            console.error('Error stopping proxy:', err.message);
        }
        this.proxyProcess = null;
        this.useProxy = false;
    }

    async connect() {
        // Save current DNS settings before connecting
        await this.saveDNSSettings();

        const config = await this.apiClient.connectVPN();
        this.vpnConfig = config;

        // Determine endpoint - use proxy if obfsKey provided
        let endpoint = config.endpoint;
        this.useProxy = false;

        if (config.obfsKey) {
            const parts = config.endpoint.split(':');
            const remoteHost = parts[0];
            const remotePort = parts[1] || '443';

            const proxyStarted = await this.startProxy(remoteHost, remotePort, config.obfsKey);
            if (proxyStarted) {
                endpoint = '127.0.0.1:' + this.proxyLocalPort;
                this.useProxy = true;
                console.log('Using obfuscated connection via proxy');
            } else {
                console.log('Proxy failed, using direct connection');
            }
        }

        const wgConfig = this.generateWireGuardConfig(config, endpoint);
        const configFile = path.join(this.configPath, 'sc0.conf');
        await fs.writeFile(configFile, wgConfig, { mode: 0o600 });

        try {
            if (this.platform === 'win32') {
                // Windows: Use wireguard.exe to install tunnel service
                // First try to uninstall any existing tunnel
                try {
                    await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
                } catch (e) {
                    // Ignore - tunnel might not exist
                }

                // Install and start the tunnel service
                await execAsync(`"${this.wireguardExe}" /installtunnelservice "${configFile}"`);
            } else {
                // macOS/Linux: Use wg-quick
                // Clean up any existing interface before connecting
                try {
                    console.log('Checking for existing VPN interface...');
                    await execAsync(`sudo "${this.wgQuickPath}" down "${configFile}" 2>/dev/null || true`);
                } catch (e) {
                    // Ignore errors - interface might not exist
                }

                // Use direct sudo call (passwordless via sudoers configuration)
                await execAsync(`sudo "${this.wgQuickPath}" up "${configFile}"`);
            }

            this.connected = true;
            return { success: true, message: 'Connected successfully' };
        } catch (error) {
            // Cleanup on failure
            this.stopProxy();
            await this.restoreDNSSettings();
            throw new Error('Connection failed: ' + error.message);
        }
    }

    async disconnect() {
        if (!this.connected) return { success: true, message: 'Not connected' };

        const configFile = path.join(this.configPath, 'sc0.conf');

        try {
            console.log('Disconnecting VPN...');

            if (this.platform === 'win32') {
                // Windows: Uninstall the tunnel service
                await execAsync(`"${this.wireguardExe}" /uninstalltunnelservice sc0`);
                console.log('Windows tunnel service uninstalled');
            } else {
                // macOS/Linux: Use wg-quick (unchanged)
                const { stdout, stderr } = await execAsync(`sudo "${this.wgQuickPath}" down "${configFile}"`);
                console.log('wg-quick down output:', stdout);
                if (stderr) console.log('wg-quick down stderr:', stderr);

                // Verify interface is actually down
                if (this.platform === 'darwin') {
                    try {
                        await execAsync('ifconfig utun9 2>&1');
                        console.warn('Interface still exists after wg-quick down, removing manually');
                        await execAsync('sudo ifconfig utun9 down 2>&1 || true');
                    } catch {
                        console.log('VPN interface removed successfully');
                    }
                }
            }

            // Stop proxy if running
            this.stopProxy();

            await this.apiClient.disconnectVPN();
            await this.restoreDNSSettings();

            this.connected = false;
            return { success: true, message: 'Disconnected successfully' };
        } catch (error) {
            console.error('Disconnect error:', error);
            this.stopProxy();
            await this.restoreDNSSettings();

            // Force cleanup as last resort
            if (this.platform === 'darwin') {
                try {
                    await execAsync('sudo ifconfig utun9 down 2>&1 || true');
                } catch {}
            } else if (this.platform === 'win32') {
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

    generateWireGuardConfig(config, endpoint) {
        const ep = endpoint || config.endpoint;
        return '[Interface]\nPrivateKey = ' + config.privateKey + '\nAddress = ' + config.address + '\nDNS = ' + config.dns + '\n\n[Peer]\nPublicKey = ' + config.publicKey + '\nEndpoint = ' + ep + '\nAllowedIPs = ' + config.allowedIPs + '\nPersistentKeepalive = 25\n';
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
