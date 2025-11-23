const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('vpnAPI', {
    getPortals: () => ipcRenderer.invoke('getPortals'),
    getCurrentPortal: () => ipcRenderer.invoke('getCurrentPortal'),
    getConnectionStatus: () => ipcRenderer.invoke('getConnectionStatus'),
    addPortal: () => ipcRenderer.invoke('addPortal'),
    removePortal: (portalId) => ipcRenderer.invoke('removePortal', portalId),
    selectPortal: (portalId) => ipcRenderer.invoke('selectPortal', portalId),
    login: (credentials) => ipcRenderer.invoke('login', credentials),
    connect: () => ipcRenderer.invoke('connect'),
    disconnect: () => ipcRenderer.invoke('disconnect'),
    close: () => ipcRenderer.invoke('close')
});
