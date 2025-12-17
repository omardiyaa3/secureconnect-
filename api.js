class APIClient {
    constructor(baseUrl = 'https://37.61.216.230:3000') {
        this.baseUrl = baseUrl;
        this.token = null;
        this.user = null;
    }

    setBaseUrl(baseUrl) {
        this.baseUrl = baseUrl;
    }

    async login(username, password) {
        const response = await fetch(this.baseUrl + '/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });
        const data = await response.json();
        if (!data.success) throw new Error(data.error || 'Login failed');
        this.token = data.token;
        this.user = data.user;
        return data;
    }

    async connectVPN() {
        if (!this.token) throw new Error('Not authenticated');
        const response = await fetch(this.baseUrl + '/api/vpn/connect', {
            method: 'POST',
            headers: { 'Authorization': 'Bearer ' + this.token }
        });
        const data = await response.json();
        if (!data.success) throw new Error(data.error || 'VPN connection failed');
        return data.config;
    }

    async disconnectVPN() {
        if (!this.token) throw new Error('Not authenticated');
        const response = await fetch(this.baseUrl + '/api/vpn/disconnect', {
            method: 'POST',
            headers: { 'Authorization': 'Bearer ' + this.token }
        });
        const data = await response.json();
        if (!data.success) throw new Error(data.error || 'VPN disconnect failed');
        return data;
    }

    async getStatus() {
        if (!this.token) throw new Error('Not authenticated');
        const response = await fetch(this.baseUrl + '/api/vpn/status', {
            headers: { 'Authorization': 'Bearer ' + this.token }
        });
        const data = await response.json();
        if (!data.success) throw new Error(data.error);
        return data;
    }
}
module.exports = APIClient;
