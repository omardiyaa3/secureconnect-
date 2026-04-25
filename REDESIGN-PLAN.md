# SecureConnect Redesign Implementation Plan

## Overview
Redesign the app with a settings panel, cleaner login page, and new features.

---

## File Structure

```
/root/worldposta-vpn-client/
├── login.html          # Redesigned login page (gear icon, auto-fill)
├── settings.html       # NEW - Settings panel with sidebar
├── main.js             # Updated - handle settings window, credentials
├── vpn.js              # Updated - connection statistics
├── preload.js          # Updated - new IPC methods
├── credentials.js      # NEW - secure credential storage
├── styles/
│   └── settings.css    # NEW - settings panel styles
```

---

## Phase 1: Create Settings Window Infrastructure

### 1.1 Update main.js
- Add `settingsWindow` variable
- Add `createSettingsWindow()` function
- Add IPC handlers:
  - `open-settings` - open settings window
  - `close-settings` - close settings window
  - `get-portals` - return saved portals
  - `add-portal` - add new portal
  - `edit-portal` - edit portal
  - `delete-portal` - delete portal
  - `get-credentials` - get saved username/password
  - `save-credentials` - save username/password (encrypted)
  - `clear-credentials` - clear saved credentials (sign out)
  - `get-connection-stats` - get current connection statistics
  - `collect-logs` - collect all logs to file
  - `sign-out` - disconnect + clear credentials

### 1.2 Update preload.js
Add new API methods:
```javascript
openSettings: () => ipcRenderer.send('open-settings'),
closeSettings: () => ipcRenderer.send('close-settings'),
getPortals: () => ipcRenderer.invoke('get-portals'),
addPortal: (portal) => ipcRenderer.invoke('add-portal', portal),
editPortal: (id, portal) => ipcRenderer.invoke('edit-portal', id, portal),
deletePortal: (id) => ipcRenderer.invoke('delete-portal', id),
getCredentials: (portalId) => ipcRenderer.invoke('get-credentials', portalId),
saveCredentials: (portalId, user, pass) => ipcRenderer.invoke('save-credentials', portalId, user, pass),
clearCredentials: () => ipcRenderer.invoke('clear-credentials'),
getConnectionStats: () => ipcRenderer.invoke('get-connection-stats'),
collectLogs: () => ipcRenderer.invoke('collect-logs'),
signOut: () => ipcRenderer.invoke('sign-out')
```

---

## Phase 2: Redesign login.html

### 2.1 Layout Changes
- Remove "Add Portal" and "Remove Portal" buttons
- Add gear icon (⚙️) on top right
- Keep portal dropdown, username, password, connect button
- Add "Remember me" checkbox (optional, or auto-save)

### 2.2 Auto-fill Credentials
- On page load: check for saved credentials
- If found: auto-fill username and password fields
- On successful login: save credentials

### 2.3 Gear Icon Click
- Calls `window.api.openSettings()`
- Opens settings window

---

## Phase 3: Create settings.html

### 3.1 Structure
```html
<div class="settings-container">
  <div class="sidebar">
    <div class="nav-item active" data-view="connections">Connections</div>
    <div class="nav-item" data-view="portals">Manage Portals</div>
    <div class="nav-item" data-view="logs">Logs</div>
    <div class="nav-item" data-view="about">About</div>
    <div class="sign-out">Sign out</div>
  </div>
  <div class="content">
    <!-- Dynamic content based on selected view -->
  </div>
</div>
```

### 3.2 Connections View
```html
<div id="connections-view">
  <h2>Secure Connect</h2>
  <p>Welcome to WorldPosta secure connect</p>

  <div class="status connected">
    <div class="status-icon">✓</div>
    <div class="status-text">Connected</div>
  </div>

  <div class="statistics">
    <div class="stat-row">
      <div class="stat">
        <label>Assigned IP Address(es):</label>
        <span id="assigned-ip">IPv4 10.10.10.14</span>
      </div>
      <div class="stat">
        <label>Session Uptime:</label>
        <span id="uptime">01:05:00</span>
      </div>
      <div class="stat">
        <label>Protocol:</label>
        <span id="protocol">SSL</span>
      </div>
    </div>
    <div class="stat-row">
      <div class="stat">
        <label>Gateway IP Address:</label>
        <span id="gateway-ip">134.119.219.186</span>
      </div>
      <div class="stat">
        <label>Bytes In:</label>
        <span id="bytes-in">105</span>
      </div>
      <div class="stat">
        <label>Bytes Out:</label>
        <span id="bytes-out">58</span>
      </div>
    </div>
  </div>

  <button id="disconnect-btn" class="btn-disconnect">Disconnect</button>
</div>
```

### 3.3 Manage Portals View
```html
<div id="portals-view">
  <div class="portals-header">
    <h2>Manage Portals</h2>
    <button id="add-portal-btn" class="btn-add">+</button>
  </div>

  <table class="portals-table">
    <thead>
      <tr>
        <th>Portal name</th>
        <th>Server IP Address</th>
        <th></th>
      </tr>
    </thead>
    <tbody id="portals-list">
      <!-- Dynamic rows -->
    </tbody>
  </table>
</div>

<!-- Add/Edit Portal Modal -->
<div id="portal-modal" class="modal hidden">
  <div class="modal-content">
    <h3 id="modal-title">Add Portal</h3>
    <div class="form-group">
      <label>Portal name</label>
      <input type="text" id="portal-name" placeholder="Your VPN Server">
    </div>
    <div class="form-group">
      <label>Server IP Address</label>
      <input type="text" id="portal-ip" placeholder="192.168.1.1">
    </div>
    <div class="modal-buttons">
      <button id="modal-cancel" class="btn-cancel">Cancel</button>
      <button id="modal-save" class="btn-save">Add</button>
    </div>
  </div>
</div>
```

### 3.4 Logs View
```html
<div id="logs-view">
  <h2>Logs</h2>
  <p>If you're having trouble with Secure Connect, please contact your system administrator.</p>
  <p>They might need to see the Secure Connect logs in order to troubleshoot the problem.</p>
  <button id="collect-logs-btn" class="btn-collect">Collect Logs</button>
</div>
```

### 3.5 About View
```html
<div id="about-view">
  <h2>About</h2>
  <div class="app-info">
    <img src="logo.jpeg" alt="Logo" class="about-logo">
    <h3>SecureConnect</h3>
    <p>Version 2.0.0</p>
    <p>© 2024 WorldPosta</p>
  </div>
</div>
```

---

## Phase 4: Credential Storage (credentials.js)

### 4.1 Using Electron safeStorage
```javascript
const { safeStorage } = require('electron');
const fs = require('fs');
const path = require('path');

const CREDS_FILE = path.join(app.getPath('userData'), 'credentials.enc');

function saveCredentials(portalId, username, password) {
  const data = { portalId, username, password };
  const encrypted = safeStorage.encryptString(JSON.stringify(data));
  fs.writeFileSync(CREDS_FILE, encrypted);
}

function getCredentials() {
  if (!fs.existsSync(CREDS_FILE)) return null;
  const encrypted = fs.readFileSync(CREDS_FILE);
  const decrypted = safeStorage.decryptString(encrypted);
  return JSON.parse(decrypted);
}

function clearCredentials() {
  if (fs.existsSync(CREDS_FILE)) {
    fs.unlinkSync(CREDS_FILE);
  }
}
```

---

## Phase 5: Connection Statistics

### 5.1 Data to Track
- Assigned IP (from VPN config response)
- Gateway IP (server IP)
- Session start time (calculate uptime)
- Bytes In/Out (from interface stats)
- Protocol (always "AmneziaWG" or "WireGuard")

### 5.2 Update vpn.js
Add method to get interface statistics:
```javascript
async getConnectionStats() {
  if (!this.isConnected) return null;

  // Get interface stats (platform specific)
  // Linux: cat /sys/class/net/sc0/statistics/rx_bytes
  // macOS: netstat -I utun* -b
  // Windows: netsh interface show interface

  return {
    assignedIP: this.tunnelIP,
    gatewayIP: this.serverIP,
    uptime: this.getUptime(),
    bytesIn: await this.getBytesIn(),
    bytesOut: await this.getBytesOut(),
    protocol: 'AmneziaWG'
  };
}
```

---

## Phase 6: Log Collection

### 6.1 What to Collect
- Application logs (from console)
- VPN connection logs
- System info (OS, version)
- Config (sanitized - no keys)

### 6.2 Implementation
```javascript
async collectLogs() {
  const logData = {
    timestamp: new Date().toISOString(),
    appVersion: app.getVersion(),
    platform: process.platform,
    osVersion: os.release(),
    logs: this.appLogs, // collected during runtime
    vpnLogs: this.vpnLogs
  };

  const { filePath } = await dialog.showSaveDialog({
    defaultPath: `secureconnect-logs-${Date.now()}.txt`,
    filters: [{ name: 'Text Files', extensions: ['txt'] }]
  });

  if (filePath) {
    fs.writeFileSync(filePath, JSON.stringify(logData, null, 2));
  }
}
```

---

## Phase 7: Sign Out

### 7.1 Implementation
```javascript
async signOut() {
  // 1. Disconnect VPN if connected
  if (vpnManager.isConnected) {
    await vpnManager.disconnect();
  }

  // 2. Clear saved credentials
  clearCredentials();

  // 3. Close settings window
  if (settingsWindow) {
    settingsWindow.close();
  }

  // 4. Reset login form in main window
  mainWindow.webContents.send('reset-login-form');
}
```

---

## Implementation Order

1. **main.js** - Add settings window, IPC handlers
2. **preload.js** - Add new API methods
3. **settings.html** - Create complete settings panel
4. **login.html** - Add gear icon, auto-fill, remove portal buttons
5. **credentials.js** - Implement secure storage
6. **vpn.js** - Add connection statistics
7. **Log collection** - Implement in main.js
8. **Testing** - Test all features on macOS, Windows, Linux

---

## Testing Checklist

- [ ] Gear icon opens settings window
- [ ] Settings window shows correct view on nav click
- [ ] Connections view shows status and stats when connected
- [ ] Manage Portals: Add portal works
- [ ] Manage Portals: Edit portal works
- [ ] Manage Portals: Delete portal works
- [ ] Logs: Collect logs saves file
- [ ] About: Shows correct info
- [ ] Sign Out: Disconnects VPN
- [ ] Sign Out: Clears credentials
- [ ] Sign Out: Resets login form
- [ ] Auto-fill: Credentials saved after login
- [ ] Auto-fill: Credentials loaded on app start
- [ ] Portal dropdown: Shows saved portals
- [ ] Works on macOS
- [ ] Works on Windows
- [ ] Works on Linux
