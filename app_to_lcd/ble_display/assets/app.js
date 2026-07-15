'use strict';

const socket = io(`http://${window.location.host}`);

// state
let isPlaying    = true;
let isMuted      = false;
let isScanning   = false;
let scanData     = {};
let connData     = {};
let trustedData  = {};
let currentSection = 'dashboard';

// ─────────────────────────────────────────────────────────
// NAV
// ─────────────────────────────────────────────────────────
const sectionTitles = {
    dashboard: 'Dashboard',
    youtube: 'Now Playing',
    gas: 'Gas Cylinder',
    whistle: 'Whistle Counter',
    'youtube-ctrl': 'YouTube',
    ble: 'BLE Devices',
    log: 'Event Log',
};

function showSection(id) {
    document.querySelectorAll('.section').forEach(s => s.classList.add('hidden'));
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    const sec = document.getElementById('sec-' + id);
    if (sec) sec.classList.remove('hidden');
    document.querySelectorAll('.nav-item').forEach(n => {
        if (n.getAttribute('onclick')?.includes(`'${id}'`)) n.classList.add('active');
    });
    document.getElementById('pageTitle').textContent = sectionTitles[id] || id;
    currentSection = id;
}

document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('urlInput')?.addEventListener('keydown', e => { if (e.key === 'Enter') sendUrl(); });
    document.getElementById('urlInputFull')?.addEventListener('keydown', e => { if (e.key === 'Enter') sendUrlFull(); });
    socket.emit('get_initial_state', {});
});

// ─────────────────────────────────────────────────────────
// SOCKET EVENTS
// ─────────────────────────────────────────────────────────
socket.on('connect', () => {
    setWsConnected(true);
    addLog('WebSocket connected', 'success');
    socket.emit('get_initial_state', {});
});

socket.on('disconnect', () => {
    setWsConnected(false);
    addLog('WebSocket disconnected', 'error');
});

socket.on('log', d => {
    addLog(d.message, classifyLog(d.message), d.time);
});

socket.on('initial_state', d => {
    if (d.phone_connected !== undefined) setPhoneStatus(d.phone_connected);
    if (d.ble_status) {
        setGasNodeDot(d.ble_status.gas_node);
        const gasNodeEl = document.getElementById('sysGasNode');
        if (gasNodeEl) gasNodeEl.textContent = d.ble_status.gas_node ? 'Gas Node Online' : 'Gas Node Offline';
        setText('chipGasVal', d.ble_status.gas_node ? 'Online' : 'Offline');
        const _cgd2 = document.getElementById('chipGas'); if (_cgd2) _cgd2.className = 'chip-dot' + (d.ble_status.gas_node ? ' green' : '');
        const wOnline = d.ble_status.wristband;
        const wristEl = document.getElementById('sysWristband');
        if (wristEl) wristEl.textContent = wOnline ? 'Wristband Connected' : 'Wristband Idle';
        setText('chipWrist', wOnline ? 'Connected' : 'Idle');
        const wd = document.getElementById('sysWristDot');
        if (wd) wd.className = 'chip-dot' + (wOnline ? ' green' : '');
    }
    if (d.mode)             setDisplayMode(d.mode);
    if (d.current_url)      setNpUrl(d.current_url);
    if (d.history)          renderHistory(d.history);
    if (d.scan_results)     { d.scan_results.forEach(dev => { scanData[dev.mac] = dev; }); }
    if (d.connected_devices){ d.connected_devices.forEach(dev => { connData[dev.mac] = dev; }); updateConnBadge(); }
    if (d.trusted)          { d.trusted.forEach(dev => { trustedData[dev.mac] = dev.name; }); }
    renderBleSection();
});

socket.on('mode_update',   d => setDisplayMode(d.mode));
socket.on('url_update',    d => { setNpUrl(d.url); addLog('Playing: ' + d.url, 'url', d.time); });
socket.on('url_history',   d => renderHistory(d.history));
socket.on('url_rejected',  d => addLog('Rejected (' + d.reason + '): ' + d.url, 'error', d.time));
socket.on('player_state',  d => addLog('Player: ' + d.cmd, 'cmd', d.time));
socket.on('adv_status',    d => setAdvStatus(d.advertising));

socket.on('now_playing', d => {
    const title = d.title || d.video_id || 'Nothing playing';
    setText('npTitle', title);
    setText('fullNpTitle', title);
    setText('miniNpTitle', title);
    if (d.video_id) {
        const thumb = document.getElementById('npThumb');
        if (thumb) thumb.innerHTML = `<img src="https://img.youtube.com/vi/${d.video_id}/mqdefault.jpg" onerror="this.style.display='none'"/>`;
    }
    addLog('Now playing: ' + title, 'url');
});

socket.on('scan_status', d => setScanStatus(d.scanning));

socket.on('scan_results', d => {
    d.devices.forEach(dev => { if ((dev.rssi || -999) >= -80 || connData[dev.mac]) scanData[dev.mac] = dev; });
    if (currentSection === 'ble') renderBleSection();
});

socket.on('connected_devices', d => {
    connData = {};
    d.devices.forEach(dev => { connData[dev.mac] = dev; });
    updateConnBadge();
    if (currentSection === 'ble') renderBleSection();
});

socket.on('device_connected', d => {
    connData[d.mac] = { mac: d.mac, name: d.name };
    updateConnBadge();
    if (currentSection === 'ble') renderBleSection();
    addLog('Connected: ' + (d.name || d.mac), 'ble', d.time);
});

socket.on('device_disconnected', d => {
    delete connData[d.mac];
    updateConnBadge();
    if (currentSection === 'ble') renderBleSection();
    addLog('Disconnected: ' + d.mac, 'error', d.time);
});

socket.on('trusted_devices', d => {
    trustedData = {};
    d.devices.forEach(dev => { trustedData[dev.mac] = dev.name; });
    if (currentSection === 'ble') renderBleSection();
});

// Gas
socket.on('gas_update', d => {
    const pct   = d.gas_pct != null ? Math.min(100, Math.max(0, Math.round(d.gas_pct))) : null;
    const days  = d.days_remaining != null ? parseFloat(d.days_remaining).toFixed(1) : null;
    const grams = d.gas_g != null ? Math.round(d.gas_g) : null;
    const state = d.cylinder_state || 'UNINSTALLED';
    const alert = (d.alert_level || 'none').toLowerCase();

    const colorClass = alert === 'red' ? 'red' : alert === 'amber' ? 'amber' : 'green';
    const pctStr = pct != null ? pct + '%' : '--%';

    // dashboard ring
    setGasRing('dashGasRing', pct, colorClass);
    setText('dashGasPct', pctStr);
    setText('dashGasDays', days != null ? days : '--');
    setText('dashGasGrams', grams != null ? grams + 'g' : '--');

    // full page ring
    setGasRing('fullGasRing', pct, colorClass, 402.1);
    setText('fullGasPct', pctStr);
    setText('fullGasDays', days != null ? days + ' days' : '--');
    setText('fullGasGrams', grams != null ? grams + 'g' : '--');
    setText('fullGasSteel', d.steel_g != null ? Math.round(d.steel_g) + 'g' : '--');
    setText('fullGasGross', d.grams != null ? Math.round(d.grams) + 'g' : '--');
    setText('fullGasAlert', alert.toUpperCase() || '--');
    setText('fullGasState', state);
    setText('fullGasBurn', d.burn_rate_g_per_day != null ? Math.round(d.burn_rate_g_per_day) + 'g/day' : '--');

    const isUninstalled = state === 'UNINSTALLED';
    const isCalibrating = state === 'BOOTSTRAP_ANCHOR';

    // status text
    const statusText = isUninstalled ? 'Place cylinder on scale' :
                       isCalibrating ? 'Calibrating — do not move...' :
                       state + (d.steel_source ? ' · ' + d.steel_source : '');
    setText('dashGasStatus', statusText);

    // install buttons
    showEl('dashInstallBtn', isUninstalled);
    showEl('fullInstallBtn', isUninstalled);

    // sidebar
    const gasNodeEl = document.getElementById('sysGasNode');
    if (gasNodeEl) gasNodeEl.textContent = 'Gas Node Online';
    setGasNodeDot(true);

    // chip
    setText('chipGasVal', 'Online');
    const _cgd = document.getElementById('chipGas'); if (_cgd) _cgd.className = 'chip-dot green';
    setText('sysRowGas', 'Online');
});

socket.on('gas_node_status', d => {
    const online = d.connected;
    setGasNodeDot(online);
    setText('sysGasNode',  online ? 'Gas Node Online' : 'Gas Node Offline');
    setText('chipGasVal',  online ? 'Online' : 'Offline');
    setText('sysRowGas',   online ? 'Online' : 'Offline');
    setText('fullGasNode', online ? 'Online' : 'Offline');
    const dot = document.getElementById('chipGas');
    if (dot) dot.className = 'chip-dot' + (online ? ' green' : '');
    const rowVal = document.getElementById('sysRowGas');
    if (rowVal) rowVal.className = 'sys-row-val' + (online ? ' green' : '');
});

// Whistle
socket.on('whistle_count',   d => updateWhistle(d));
socket.on('whistle_overlay', d => updateWhistle(d));

function updateWhistle(d) {
    const count   = d.count  ?? 0;
    const target  = d.target ?? null;
    const active  = d.active ?? false;
    const pct     = target ? Math.min(100, Math.round((count / target) * 100)) : 0;

    setText('dashWhistleCount',    count);
    setText('dashWhistleTarget',   target ?? '--');
    setText('dashWhistleProgress', target ? pct + '%' : '--%');
    setText('dashWhistleStatus',   active ? 'Active' : 'Idle');
    setWidth('dashWhistleFill',    pct);

    setText('fullWhistleCount',    count);
    setText('fullWhistleTarget',   target ?? '--');
    setText('fullWhistleProgress', target ? pct + '%' : '--%');
    setText('fullWhistleStatus',   active ? 'Active' : 'Idle');

    // ring
    const ring = document.getElementById('fullWhistleRing');
    if (ring) {
        const circ = 402.1;
        ring.style.strokeDashoffset = circ - (pct / 100) * circ;
    }

    showEl('dashWhistleBadge', active);

    const liveBadge = document.getElementById('dashWhistleBadge');
    if (liveBadge) liveBadge.style.display = active ? 'inline-block' : 'none';
}

// ─────────────────────────────────────────────────────────
// PLAYER CONTROLS
// ─────────────────────────────────────────────────────────
function togglePlayPause() {
    if (isPlaying) { sendCmd('pause');  isPlaying = false; }
    else           { sendCmd('resume'); isPlaying = true;  }
    updatePlayBtns();
}

function updatePlayBtns() {
    const icon    = document.getElementById('npPlayIcon');
    const fullBtn = document.getElementById('fullPlayBtn');
    const miniBtn = document.getElementById('miniPlayBtn');
    if (isPlaying) {
        if (icon)    icon.innerHTML = '<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>';
        if (fullBtn) fullBtn.textContent = '⏸ Pause';
        if (miniBtn) miniBtn.textContent = '⏸';
    } else {
        if (icon)    icon.innerHTML = '<polygon points="5 3 19 12 5 21 5 3"/>';
        if (fullBtn) fullBtn.textContent = '▶ Resume';
        if (miniBtn) miniBtn.textContent = '▶';
    }
}

function toggleMute() {
    if (isMuted) { sendCmd('unmute'); isMuted = false; }
    else         { sendCmd('mute');   isMuted = true;  }
    const muteBtn = document.getElementById('fullMuteBtn');
    const miniMute = document.getElementById('miniMuteBtn');
    if (muteBtn)  muteBtn.textContent  = isMuted ? '🔇 Unmute' : '🔊 Mute';
    if (miniMute) miniMute.textContent = isMuted ? '🔇' : '🔊';
}

function sendCmd(cmd) {
    socket.emit('player_cmd', { cmd });
    addLog('Player: ' + cmd, 'cmd');
}

function setMode(mode) {
    socket.emit('set_mode', { mode });
    setDisplayMode(mode);
}

function sendUrl() {
    const el = document.getElementById('urlInput');
    if (!el || !el.value.trim()) return;
    socket.emit('send_url', { url: el.value.trim() });
    addLog('Sent: ' + el.value.trim(), 'url');
    el.value = '';
}

function sendUrlFull() {
    const el = document.getElementById('urlInputFull');
    if (!el || !el.value.trim()) return;
    socket.emit('send_url', { url: el.value.trim() });
    addLog('Sent: ' + el.value.trim(), 'url');
    el.value = '';
}

function playFromHistory(url) {
    socket.emit('send_url', { url });
    addLog('Replaying: ' + url, 'url');
}

// ─────────────────────────────────────────────────────────
// GAS
// ─────────────────────────────────────────────────────────
function gasSetup() {
    socket.emit('gas_setup', { mode: 'FRESH', brand: null });
    showEl('dashInstallBtn', false);
    showEl('fullInstallBtn', false);
    addLog('Gas: install cylinder mode started', 'cmd');
}

function setGasRing(id, pct, colorClass, circ = 301.6) {
    const ring = document.getElementById(id);
    if (!ring) return;
    ring.style.strokeDashoffset = pct != null ? circ - (pct / 100) * circ : circ;
    ring.className = 'ring-fill ' + (colorClass || '');
}

function setGasNodeDot(online) {
    ['dashGasNode'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.className = 'node-dot' + (online ? ' online' : '');
    });
}

// ─────────────────────────────────────────────────────────
// WHISTLE
// ─────────────────────────────────────────────────────────
function sendWhistleCmd(cmd) {
    socket.emit('player_cmd', { cmd });
    addLog('Whistle: ' + cmd, 'cmd');
}

// ─────────────────────────────────────────────────────────
// BLE
// ─────────────────────────────────────────────────────────
function toggleScan() {
    if (isScanning) { socket.emit('scan_stop', {}); }
    else            { scanData = {}; socket.emit('scan_start', {}); }
}

function setScanStatus(scanning) {
    isScanning = scanning;
    const bar    = document.getElementById('bleScanProgress');
    const badge  = document.getElementById('bleScanBadge');
    const btn    = document.getElementById('bleScanBtn');
    if (bar)   bar.className   = 'ble-scan-progress' + (scanning ? ' active' : '');
    if (badge) badge.style.display = scanning ? 'inline-block' : 'none';
    if (btn)   btn.textContent = scanning ? '⏹ Stop' : '⟳ Scan';
}

function renderBleSection() {
    renderConnectedDevices();
    renderAvailableDevices();
}

function renderConnectedDevices() {
    const el = document.getElementById('bleConnectedList');
    if (!el) return;
    const list = Object.values(connData);
    if (list.length === 0) { el.innerHTML = '<div class="ble-empty">No devices connected</div>'; return; }
    el.innerHTML = list.map(d => `
        <div class="ble-device-row">
            <div class="ble-dev-left">
                <div class="ble-conn-dot on"></div>
                <div>
                    <div class="ble-dev-name">${esc(d.name || d.mac)}</div>
                    <div class="ble-dev-mac">${esc(d.mac)}</div>
                </div>
            </div>
            <div class="ble-dev-actions">
                <button class="ble-btn disconnect" onclick="bleDisconnect('${esc(d.mac)}')">Disconnect</button>
                <button class="ble-btn forget"     onclick="bleForget('${esc(d.mac)}')">Forget</button>
            </div>
        </div>`).join('');
}

function renderAvailableDevices() {
    const el = document.getElementById('bleAvailableList');
    if (!el) return;
    const available = Object.values(scanData)
        .filter(d => !connData[d.mac] && d.name && d.name !== d.mac)
        .sort((a,b) => (b.rssi||0) - (a.rssi||0));
    if (available.length === 0) {
        el.innerHTML = `<div class="ble-empty">${isScanning ? 'Scanning...' : 'No devices found. Tap Scan.'}</div>`;
        return;
    }
    el.innerHTML = available.map(d => `
        <div class="ble-device-row">
            <div class="ble-dev-left">
                <div class="ble-conn-dot"></div>
                <div>
                    <div class="ble-dev-name">${esc(d.name)}</div>
                    <div class="ble-dev-mac">${esc(d.mac)} &nbsp; ${d.rssi || '?'} dBm</div>
                </div>
            </div>
            <button class="ble-btn connect" onclick="bleConnect('${esc(d.mac)}')">Connect</button>
        </div>`).join('');
}

function bleConnect(mac)    { socket.emit('connect_device',    { mac }); addLog('Connecting: ' + mac, 'ble'); }
function bleDisconnect(mac) { socket.emit('disconnect_device', { mac }); addLog('Disconnecting: ' + mac, 'ble'); }
function bleForget(mac)     { socket.emit('forget_device',     { mac }); delete trustedData[mac]; addLog('Forgot: ' + mac); renderBleSection(); }

function updateConnBadge() {
    const count = Object.keys(connData).length;
    const badge = document.getElementById('navBadge');
    const sysEl = document.getElementById('sysDevices');
    if (badge) { badge.textContent = count; badge.style.display = count > 0 ? 'inline-block' : 'none'; }
    if (sysEl) sysEl.textContent = count + ' BLE Connected';
    setText('chipDevVal',  count + ' Connected');
    setText('sysRowDev',   count + ' Connected');
    const dot = document.getElementById('chipDev');
    if (dot) dot.className = 'chip-dot' + (count > 0 ? ' green' : '');
}

// ─────────────────────────────────────────────────────────
// UI HELPERS
// ─────────────────────────────────────────────────────────
function setWsConnected(ok) {
    const dot = document.getElementById('wsDot');
    if (dot) dot.className = 'ws-dot' + (ok ? ' connected' : '');
    const sysLabel = document.getElementById('sysLabel');
    if (sysLabel) sysLabel.textContent = ok ? 'System Healthy' : 'Disconnected';
    const sysDot = document.getElementById('sysDot');
    if (sysDot) sysDot.className = 'sys-dot' + (ok ? ' green' : '');
    setText('chipBoardVal', ok ? 'Connected' : 'Disconnected');
    setText('sysRowBoard',  ok ? 'Connected' : 'Disconnected');
    const chipB = document.getElementById('chipBoard');
    if (chipB) chipB.className = 'chip-dot' + (ok ? ' green' : '');
}

function setAdvStatus(adv) {
    const pill = document.getElementById('advPill');
    const dot  = document.getElementById('advDot');
    const text = document.getElementById('advText');
    if (adv) {
        if (pill) pill.style.background = 'rgba(63,185,80,0.1)';
        if (dot)  dot.style.background = 'var(--green)';
        if (text) text.textContent = 'Advertising';
    } else {
        if (pill) pill.style.background = 'rgba(125,133,144,0.1)';
        if (dot)  dot.style.background = 'var(--muted)';
        if (text) text.textContent = 'Not Advertising';
    }
    const chipAdv = document.getElementById('chipAdv');
    if (chipAdv) chipAdv.className = 'chip-dot' + (adv ? ' green' : '');
    setText('chipAdvVal', adv ? 'Active' : 'Stopped');
    setText('sysRowAdv',  adv ? 'Active' : 'Stopped');
}

function setDisplayMode(mode) {
    setText('npMode',   mode);
    setText('fullNpMode', mode);
    document.querySelectorAll('.mode-pill').forEach(p => p.classList.remove('active'));
}

function setNpUrl(url) {
    setText('npUrl', url);
}

function renderHistory(history) {
    if (!history || history.length === 0) return;
    const html = history.map(item => `
        <div class="yt-hist-item" onclick="playFromHistory('${esc(item.url)}')">
            <span class="yt-hist-time">${item.time || ''}</span>
            <span class="yt-hist-title">${esc(item.title || item.url)}</span>
            <span class="yt-hist-play">▶</span>
        </div>`).join('');
    setText_html('dashHistory', html);
    setText_html('fullHistory', html);
}

function setChip(id, val, colorClass) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = val;
    el.className = 'sys-row-val' + (colorClass ? ' ' + colorClass : '');
}

function setText(id, val)      { const e = document.getElementById(id); if (e) e.textContent = val; }
function setText_html(id, val) { const e = document.getElementById(id); if (e) e.innerHTML   = val; }
function setWidth(id, pct)     { const e = document.getElementById(id); if (e) e.style.width = pct + '%'; }
function showEl(id, show)      { const e = document.getElementById(id); if (e) e.style.display = show ? '' : 'none'; }
function esc(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function setPhoneStatus(connected) {
    const el = document.getElementById('sysPhoneStatus');
    if (el) el.textContent = connected ? 'Phone Connected' : 'Phone Disconnected';
    const dot = document.getElementById('sysPhoneDot');
    if (dot) dot.className = 'chip-dot' + (connected ? ' green' : '');
    // update chip
    const chip = document.getElementById('chipPhone');
    if (chip) { chip.textContent = connected ? 'Connected' : 'Idle'; chip.className = 'chip-val' + (connected ? '' : ''); }
}

function addLog(message, type = 'default', time = null) {
    const c = document.getElementById('console');
    if (!c) return;
    const div = document.createElement('div');
    div.className = 'log-entry';
    const t = time || new Date().toLocaleTimeString('en-US', { hour12: false });
    div.innerHTML = `<span class="log-time">${t}</span><span class="log-msg ${type}">${esc(message)}</span>`;
    c.appendChild(div);
    c.scrollTop = c.scrollHeight;
    while (c.children.length > 300) c.removeChild(c.firstChild);
}

function clearLog() { const c = document.getElementById('console'); if (c) c.innerHTML = ''; }

function classifyLog(msg) {
    const m = msg.toLowerCase();
    if (m.includes('error') || m.includes('failed') || m.includes('disconnect')) return 'error';
    if (m.includes('connected') || m.includes('started') || m.includes('ok')) return 'success';
    if (m.includes('url') || m.includes('playing') || m.includes('video')) return 'url';
    if (m.includes('command') || m.includes('player') || m.includes('whistle')) return 'cmd';
    if (m.includes('ble') || m.includes('scan') || m.includes('trust')) return 'ble';
    return 'default';
}
// phone status
socket.on('phone_status', d => {
    setPhoneStatus(d.connected);
});

// wristband status
socket.on('wristband_status', d => {
    const connected = d.connected;
    const dot  = document.getElementById('sysWristDot');
    const chip = document.getElementById('chipWrist');
    const side = document.getElementById('sysWristband');
    if (dot)  dot.className  = 'chip-dot' + (connected ? ' green' : '');
    if (chip) chip.textContent = connected ? 'Connected' : 'Idle';
    if (side) side.textContent = connected ? 'Wristband Connected' : 'Wristband Idle';
});

// phone status from log events
socket.on('log', d => {

});
