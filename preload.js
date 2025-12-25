const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('vpnAPI', {
    // Portal management
    getPortals: () => ipcRenderer.invoke('getPortals'),
    getCurrentPortal: () => ipcRenderer.invoke('getCurrentPortal'),
    addPortal: (data) => ipcRenderer.invoke('addPortal', data),
    editPortal: (data) => ipcRenderer.invoke('editPortal', data),
    removePortal: (portalId) => ipcRenderer.invoke('removePortal', portalId),
    selectPortal: (portalId) => ipcRenderer.invoke('selectPortal', portalId),

    // Connection status
    getConnectionStatus: () => ipcRenderer.invoke('getConnectionStatus'),
    getVPNStatus: () => ipcRenderer.invoke('getVPNStatus'),
    getConnectionStats: () => ipcRenderer.invoke('getConnectionStats'),

    // Authentication
    login: (credentials) => ipcRenderer.invoke('login', credentials),

    // VPN control
    connect: () => ipcRenderer.invoke('connect'),
    disconnect: () => ipcRenderer.invoke('disconnect'),

    // Credentials management
    getCredentials: () => ipcRenderer.invoke('getCredentials'),
    saveCredentials: (data) => ipcRenderer.invoke('saveCredentials', data),
    clearCredentials: () => ipcRenderer.invoke('clearCredentials'),

    // Settings window
    openSettings: () => ipcRenderer.invoke('openSettings'),
    closeSettings: () => ipcRenderer.invoke('closeSettings'),

    // Logs
    collectLogs: () => ipcRenderer.invoke('collectLogs'),

    // Sign out
    signOut: () => ipcRenderer.invoke('signOut'),

    // App info
    getAppVersion: () => ipcRenderer.invoke('getAppVersion'),

    // Window control
    close: () => ipcRenderer.invoke('close'),

    // Event listeners for main process notifications
    onConnectionChanged: (callback) => {
        ipcRenderer.on('connection-changed', (event, data) => callback(data));
    },
    onResetLoginForm: (callback) => {
        ipcRenderer.on('reset-login-form', (event) => callback());
    },
    onPortalsChanged: (callback) => {
        ipcRenderer.on('portals-changed', (event) => callback());
    }
});
