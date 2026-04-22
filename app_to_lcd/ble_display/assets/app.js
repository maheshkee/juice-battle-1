'use strict';

const socket = io(`http://${window.location.host}`);

let isScanning    = false;
let isPlaying     = true;
let isMuted       = false;
let scanData      = {};   // mac -> {name, rssi, path}
let connectedData = {};   // mac -> {name, characteristics}
let trustedData   = {};   // mac -> name
let blePanelOpen  = false;

document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('urlInput').addEventListener('keydown', e => {
        if (e.key === 'Enter') sendUrl();
    });
    socket.emit('get_initial_state', {});
});

// --- socket events ---

socket.on('connect', () => {
    setWsStatus(true);
    addLog('WebSocket connected', 'success');
    socket.emit('get_initial_state', {});
});

socket.on('disconnect', () => {
    setWsStatus(false);
    addLog('WebSocket disconnected', 'error');
});

socket.on('log', d => addLog(d.message, classifyLog(d.message), d.time));

socket.on('initial_state', d => {
    if (d.mode) highlightMode(d.mode);
    if (d.current_url) setNowPlaying(d.current_url);
    if (d.history) renderHistory(d.history);
    if (d.scanning !== undefined) updateScanStatus(d.scanning);
    if (d.scan_results) {
        d.scan_results.forEach(dev => { scanData[dev.mac] = dev; });
        renderBlePanel();
    }
    if (d.connected_devices) {
        d.connected_devices.forEach(dev => { connectedData[dev.mac] = dev; });
        renderBlePanel();
        updateConnectedBadge();
    }
    if (d.trusted) {
        d.trusted.forEach(dev => { trustedData[dev.mac] = dev.name; });
        renderBlePanel();
    }
});

socket.on('scan_status', d => updateScanStatus(d.scanning));

socket.on('scan_results', d => {
    // merge results, filter weak signals
    d.devices.forEach(dev => {
        if (dev.rssi >= -79 || connectedData[dev.mac] || trustedData[dev.mac]) {
            scanData[dev.mac] = dev;
        }
    });
    if (blePanelOpen) renderBlePanel();
});

socket.on('device_connected', d => {
    connectedData[d.mac] = { mac: d.mac, name: d.name, characteristics: [] };
    scanData[d.mac] = { ...(scanData[d.mac] || {}), mac: d.mac, name: d.name };
    updateConnectedBadge();
    if (blePanelOpen) renderBlePanel();
    addLog(`Connected: ${d.name || d.mac}`, 'ble', d.time);
});

socket.on('device_disconnected', d => {
    delete connectedData[d.mac];
    updateConnectedBadge();
    if (blePanelOpen) renderBlePanel();
    addLog(`Disconnected: ${d.mac}`, 'error', d.time);
});

socket.on('device_error', d => {
    addLog(`Connect failed (${d.mac}): ${d.error}`, 'error', d.time);
});

socket.on('connected_devices', d => {
    connectedData = {};
    d.devices.forEach(dev => { connectedData[dev.mac] = dev; });
    updateConnectedBadge();
    if (blePanelOpen) renderBlePanel();
});

socket.on('trusted_devices', d => {
    trustedData = {};
    d.devices.forEach(dev => { trustedData[dev.mac] = dev.name; });
    if (blePanelOpen) renderBlePanel();
});

socket.on('characteristic_update', d => {
    if (connectedData[d.mac]) {
        const chars = connectedData[d.mac].characteristics || [];
        const idx = chars.findIndex(c => c.uuid === d.uuid);
        if (idx >= 0) chars[idx].value = d.value;
        else chars.push({ uuid: d.uuid, name: d.name, value: d.value, flags: [] });
        connectedData[d.mac].characteristics = chars;
        if (blePanelOpen) renderBlePanel();
    }
    addLog(`${d.name} (${d.mac.slice(-5)}): ${d.value}`, 'sensor', d.time);
});

socket.on('url_update', d => {
    setNowPlaying(d.url);
    addLog(`Playing: ${d.url}`, 'url', d.time);
});

socket.on('url_history', d => renderHistory(d.history));

socket.on('url_rejected', d => {
    addLog(`Rejected (${d.reason}): ${d.url}`, 'error', d.time);
});

socket.on('mode_update', d => highlightMode(d.mode));

socket.on('player_state', d => addLog(`Player: ${d.cmd}`, 'cmd', d.time));

// --- BLE panel ---

function openBlePanel() {
    document.getElementById('bleOverlay').classList.add('open');
    blePanelOpen = true;
    renderBlePanel();
    // Auto-scan every time panel opens
    socket.emit('scan_start', {});
}

function closeBlePanel(e) {
    if (e && e.target !== document.getElementById('bleOverlay')) return;
    document.getElementById('bleOverlay').classList.remove('open');
    blePanelOpen = false;
}

function toggleScan() {
    if (isScanning) {
        socket.emit('scan_stop', {});
    } else {
        scanData = {};   // clear old results on manual refresh
        renderBlePanel();
        socket.emit('scan_start', {});
    }
}

function updateScanStatus(scanning) {
    isScanning = scanning;
    const bar    = document.getElementById('bleScanProgress');
    const status = document.getElementById('bleScanStatus');
    const icon   = document.getElementById('refreshIcon');
    const bleDot = document.getElementById('bleDotIndicator');
    if (scanning) {
        bar.classList.add('active');
        if (status) { status.textContent = 'Scanning...'; status.classList.add('active'); }
        if (icon)   icon.style.animation = 'spin 1s linear infinite';
        if (bleDot) bleDot.classList.add('active');
    } else {
        bar.classList.remove('active');
        if (status) { status.textContent = ''; status.classList.remove('active'); }
        if (icon)   icon.style.animation = '';
        if (bleDot) bleDot.classList.remove('active');
    }
}

function renderBlePanel() {
    renderKnownDevices();
    renderAvailableDevices();
}

function renderKnownDevices() {
    const section = document.getElementById('knownSection');
    const list    = document.getElementById('knownList');
    const conn    = Object.keys(connectedData);

    // Only show section when at least one device is connected
    if (conn.length === 0) {
        if (section) section.style.display = 'none';
        return;
    }
    if (section) section.style.display = 'block';

    list.innerHTML = conn.map(mac => {
        const name    = connectedData[mac]?.name || mac;
        const chars   = connectedData[mac]?.characteristics || [];
        const safeId  = mac.replace(/:/g, '_');
        const isTrusted = !!trustedData[mac];

        return `
        <div class="ble-device known connected">
            <div class="ble-device-main" onclick="toggleDeviceExpand('${safeId}')">
                <div class="ble-device-left">
                    <div class="ble-conn-dot on"></div>
                    <div>
                        <div class="ble-device-name">${escHtml(name)}</div>
                        <div class="ble-device-mac">${escHtml(mac)}</div>
                    </div>
                </div>
                <div class="ble-device-right">
                    <span class="ble-status-tag connected">Connected</span>
                    <span class="ble-expand-arrow" id="arrow-${safeId}">&#8250;</span>
                </div>
            </div>
            <div class="ble-char-expand" id="expand-${safeId}">
                <div class="ble-device-actions">
                    <button class="ble-action-btn disconnect full-width" onclick="disconnectDevice('${escHtml(mac)}')">Disconnect</button>
                    <div class="ble-toggle-row">
                        <span class="ble-toggle-label">Auto-connect</span>
                        <label class="ble-toggle-switch">
                            <input type="checkbox" ${isTrusted ? 'checked' : ''} onchange="toggleAutoConnect('${escHtml(mac)}', this.checked)"/>
                            <span class="ble-toggle-slider"></span>
                        </label>
                    </div>
                    <button class="ble-forget-btn-full" onclick="forgetDevice('${escHtml(mac)}')">Forget Device</button>
                </div>
                ${chars.length > 0 ? chars.map(c => `
                    <div class="ble-char-row">
                        <span class="ble-char-name">${escHtml(c.name || c.uuid.slice(0,8))}</span>
                        <span class="ble-char-val">${escHtml(c.value || '-')}</span>
                    </div>
                `).join('') : ''}
            </div>
        </div>`;
    }).join('');
}

function renderAvailableDevices() {
    const list = document.getElementById('availableList');
    // Filter: only named devices, strong signal, not already connected
    const available = Object.values(scanData).filter(d => {
        if (connectedData[d.mac] || trustedData[d.mac]) return false;
        if (!d.name || d.name === d.mac || d.name.trim() === '') return false;
        return (d.rssi || -999) >= -79;
    }).sort((a, b) => (b.rssi || -999) - (a.rssi || -999));

    if (available.length === 0) {
        list.innerHTML = '<div class="ble-empty">' + (isScanning ? 'Scanning for devices...' : 'No devices found. Tap refresh to scan.') + '</div>';
        return;
    }

    list.innerHTML = available.map(d => `
        <div class="ble-device">
            <div class="ble-device-main">
                <div class="ble-device-left">
                    <div class="ble-signal ${rssiClass(d.rssi)}">
                        ${signalBars(d.rssi)}
                    </div>
                    <div>
                        <div class="ble-device-name">${escHtml(d.name || 'Unknown Device')}</div>
                        <div class="ble-device-mac">${escHtml(d.mac)} &nbsp; ${d.rssi || '?'} dBm</div>
                    </div>
                </div>
                <button class="ble-action-btn connect" onclick="connectDevice('${escHtml(d.mac)}')">Connect</button>
            </div>
        </div>
    `).join('');
}

function toggleDeviceExpand(safeId) {
    const el    = document.getElementById('expand-' + safeId);
    const arrow = document.getElementById('arrow-' + safeId);
    if (el) {
        el.classList.toggle('open');
        if (arrow) arrow.classList.toggle('rotated', el.classList.contains('open'));
    }
}

function toggleAutoConnect(mac, enabled) {
    if (enabled) {
        const name = connectedData[mac]?.name || mac;
        trustedData[mac] = name;
        socket.emit('connect_device', { mac }); // re-trust
        addLog('Auto-connect enabled: ' + mac, 'ble');
    } else {
        delete trustedData[mac];
        socket.emit('forget_device', { mac });
        addLog('Auto-connect disabled: ' + mac, 'ble');
    }
}

function signalBars(rssi) {
    const strength = rssi >= -65 ? 4 : rssi >= -72 ? 3 : rssi >= -79 ? 2 : 1;
    return [1,2,3,4].map(i =>
        `<div class="bar ${i <= strength ? 'filled' : ''}"></div>`
    ).join('');
}

function rssiClass(rssi) {
    if (rssi >= -65) return 'strong';
    if (rssi >= -72) return 'medium';
    return 'weak';
}

function updateConnectedBadge() {
    const count = Object.keys(connectedData).length;
    const badge = document.getElementById('deviceBadge');
    const dot   = document.getElementById('bleDotIndicator');
    if (badge) badge.textContent = `${count} connected`;
    if (dot)   dot.classList.toggle('has-devices', count > 0);
}

// --- BLE actions ---

function connectDevice(mac) {
    addLog(`Connecting to ${mac}...`, 'ble');
    socket.emit('connect_device', { mac });
}

function disconnectDevice(mac) {
    addLog(`Disconnecting ${mac}...`, 'ble');
    socket.emit('disconnect_device', { mac });
}

function forgetDevice(mac) {
    delete trustedData[mac];
    socket.emit('forget_device', { mac });
    addLog(`Forgot ${mac}`, 'default');
    renderBlePanel();
}

// --- YouTube actions ---

function sendUrl() {
    const input = document.getElementById('urlInput');
    const url = input.value.trim();
    if (!url) return;
    socket.emit('send_url', { url });
    addLog(`Sent URL: ${url}`, 'url');
    input.value = '';
}

function togglePlayPause() {
    const btn = document.getElementById('playPauseBtn');
    if (isPlaying) {
        sendCmd('pause');
        isPlaying = false;
        if (btn) btn.textContent = '> Resume';
    } else {
        sendCmd('resume');
        isPlaying = true;
        if (btn) btn.textContent = '|| Pause';
    }
}

function toggleMute() {
    const btn = document.getElementById('muteBtn');
    if (isMuted) {
        sendCmd('unmute');
        isMuted = false;
        if (btn) btn.textContent = 'Mute';
    } else {
        sendCmd('mute');
        isMuted = true;
        if (btn) btn.textContent = 'Unmute';
    }
}

function sendCmd(cmd) {
    socket.emit('player_cmd', { cmd });
    addLog(`Command: ${cmd}`, 'cmd');
}

function setMode(mode) {
    socket.emit('set_mode', { mode });
    highlightMode(mode);
}

function playFromHistory(url) {
    socket.emit('send_url', { url });
    addLog(`Replaying: ${url}`, 'url');
}

// --- UI helpers ---

function setWsStatus(connected) {
    document.getElementById('statusDot').classList.toggle('connected', connected);
    document.getElementById('statusText').textContent = connected ? 'Connected' : 'Disconnected';
}

function setNowPlaying(url) {
    document.getElementById('npUrl').textContent = url;
}

function highlightMode(mode) {
    ['idle', 'youtube-mode', 'clock'].forEach(m => {
        const el = document.getElementById('btn-' + m);
        if (el) el.classList.toggle('active', m === mode || (mode === 'youtube' && m === 'youtube-mode'));
    });
}

function renderHistory(history) {
    const el = document.getElementById('historyList');
    if (!history || history.length === 0) {
        el.innerHTML = '<div class="history-empty">No links sent yet</div>';
        return;
    }
    el.innerHTML = history.map(item => `
        <div class="history-item" onclick="playFromHistory('${escHtml(item.url)}')">
            <span class="history-time">${item.time}</span>
            <span class="history-url">${escHtml(item.url)}</span>
            <span class="history-play">&#9654;</span>
        </div>
    `).join('');
}

function addLog(message, type = 'default', time = null) {
    const c   = document.getElementById('console');
    const div = document.createElement('div');
    div.className = 'log-entry';
    const t = time || new Date().toLocaleTimeString('en-US', { hour12: false });
    div.innerHTML = `<span class="log-time">${t}</span><span class="log-msg ${type}">${escHtml(message)}</span>`;
    c.appendChild(div);
    c.scrollTop = c.scrollHeight;
    while (c.children.length > 200) c.removeChild(c.firstChild);
}

function clearLog() { document.getElementById('console').innerHTML = ''; }

function classifyLog(msg) {
    const m = msg.toLowerCase();
    if (m.includes('error') || m.includes('failed') || m.includes('disconnect')) return 'error';
    if (m.includes('connected') || m.includes('ok') || m.includes('started')) return 'success';
    if (m.includes('url') || m.includes('playing') || m.includes('video')) return 'url';
    if (m.includes('command') || m.includes('player')) return 'cmd';
    if (m.includes('ble') || m.includes('scan') || m.includes('trust') || m.includes('notify')) return 'ble';
    if (m.includes('battery') || m.includes('temperature') || m.includes('sensor')) return 'sensor';
    return 'default';
}

function escHtml(str) {
    return String(str)
        .replace(/&/g,'&amp;').replace(/</g,'&lt;')
        .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}