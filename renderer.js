const loginForm = document.getElementById('loginForm');
const loginScreen = document.getElementById('loginScreen');
const connectedScreen = document.getElementById('connectedScreen');
const errorMessage = document.getElementById('errorMessage');
const loginBtn = document.getElementById('loginBtn');
let currentUser = null;
let statusInterval;

loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;
    errorMessage.style.display = 'none';
    loginBtn.disabled = true;
    loginBtn.textContent = 'Authenticating...';

    try {
        const loginResult = await window.vpnAPI.login({ username, password });
        if (!loginResult.success) throw new Error(loginResult.error);
        currentUser = loginResult.data.user;

        loginBtn.textContent = 'Connecting...';
        const connectResult = await window.vpnAPI.connect();
        if (!connectResult.success) throw new Error(connectResult.error);

        showConnectedScreen();
    } catch (error) {
        errorMessage.textContent = error.message;
        errorMessage.style.display = 'block';
        loginBtn.disabled = false;
        loginBtn.textContent = 'Connect';
    }
});

async function disconnect() {
    try {
        const result = await window.vpnAPI.disconnect();
        if (result.success) showLoginScreen();
        else throw new Error(result.error);
    } catch (error) {
        errorMessage.textContent = error.message;
        errorMessage.style.display = 'block';
    }
}

function showConnectedScreen() {
    loginScreen.classList.add('hidden');
    connectedScreen.classList.remove('hidden');
    if (currentUser) {
        document.getElementById('userInfo').textContent = 'Connected as ' + currentUser.username;
    }
    updateStatus();
    statusInterval = setInterval(updateStatus, 5000);
}

function showLoginScreen() {
    connectedScreen.classList.add('hidden');
    loginScreen.classList.remove('hidden');
    document.getElementById('username').value = '';
    document.getElementById('password').value = '';
    loginBtn.disabled = false;
    loginBtn.textContent = 'Connect';
    if (statusInterval) clearInterval(statusInterval);
}

async function updateStatus() {
    try {
        const status = await window.vpnAPI.getStatus();
        if (status.success && status.data) {
            document.getElementById('tunnelIP').textContent = 'IP: ' + (status.data.tunnelIP || 'N/A');
        }
    } catch (error) {
        console.error('Status update failed:', error);
    }
}
