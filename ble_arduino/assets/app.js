
const MAX_COMMAND_HISTORY = 5;
let commandHistory = [];
let isAdvertising = true;
let ledState = false;

const socket = io(`http://${window.location.host}`);

document.addEventListener('DOMContentLoaded', () => {
    clearLog();
    initSocketIO();
    updateAdvUI(true);
    socket.emit('get_initial_state', {});
});

function initSocketIO() {
    socket.on('connect', () => {
        setStatus(true);
        clearLog();
        addLog('WebSocket connected', 'success');
        socket.emit('get_initial_state', {});
    });

    socket.on('disconnect', () => {
        setStatus(false);
        addLog('WebSocket disconnected', 'error');
    });

    socket.on('log', (data) => {
        const msgLower = data.message.toLowerCase();
        let type = 'default';
        if (msgLower.includes('sensor') || msgLower.includes('read')) type = 'sensor';
        else if (msgLower.includes('command') || msgLower.includes('write')) type = 'command';
        else if (msgLower.includes('notify') || msgLower.includes('timestamp')) type = 'notify';
        else if (msgLower.includes('✓') || msgLower.includes('registered')) type = 'success';
        else if (msgLower.includes('error') || msgLower.includes('✗')) type = 'error';
        else if (msgLower.includes('led')) type = 'led';
        addLog(data.message, type, data.time);
    });

    socket.on('sensor_update', (data) => {
        document.getElementById('sensorValue').textContent = data.value;
        document.getElementById('sensorTime').textContent = `Last read: ${data.time}`;
        document.getElementById('sensorProgress').style.width = `${data.value}%`;
    });

    socket.on('command_update', (data) => {
        document.getElementById('commandValue').textContent = `"${data.text}"`;
        document.getElementById('commandTime').textContent = `Last received: ${data.time}`;
        addCommandHistory(data.text, data.time);
    });

    socket.on('timestamp_update', (data) => {
        document.getElementById('timestampValue').textContent = data.timestamp;
        document.getElementById('timestampTime').textContent = `Last notify: ${data.time}`;
        const indicator = document.getElementById('notifyIndicator');
        indicator.classList.add('active');
        indicator.innerHTML = `<span class="pulse active"></span> Notifying actively`;
    });

    socket.on('adv_status', (data) => {
        isAdvertising = data.advertising;
        updateAdvUI(data.advertising);
        
    });

    socket.on('device_status', (data) => {
        updateDeviceStatus(data);
        
    });

    socket.on('led_status', (data) => {
        ledState = data.state;
        updateLedUI(data.state);
    });
}

function updateAdvUI(advertising) {
    const dot = document.getElementById('advDot');
    const text = document.getElementById('advStatusText');
    const startBtn = document.getElementById('startAdvBtn');
    const stopBtn = document.getElementById('stopAdvBtn');

    if (advertising) {
        dot.classList.add('active');
        text.textContent = 'Advertising...';
        startBtn.disabled = true;
        stopBtn.disabled = false;
    } else {
        dot.classList.remove('active');
        text.textContent = 'Not advertising';
        startBtn.disabled = false;
        stopBtn.disabled = true;
    }
}

function updateDeviceStatus(data) {
    const dot = document.getElementById('bleDot');
    const text = document.getElementById('bleStatusText');
    const info = document.getElementById('deviceInfo');

    if (data.connected) {
        dot.classList.add('connected');
        text.textContent = 'Device connected';
        const display = data.name || data.mac || 'Unknown device';
        info.textContent = display;
    } else {
        dot.classList.remove('connected');
        text.textContent = 'No device connected';
        info.textContent = '';
    }
}

function updateLedUI(state) {
    const bulb = document.getElementById('ledBulb');
    const text = document.getElementById('ledStateText');
    const time = document.getElementById('ledTime');

    if (state) {
        bulb.classList.add('on');
        text.classList.add('on');
        text.textContent = 'ON';
    } else {
        bulb.classList.remove('on');
        text.classList.remove('on');
        text.textContent = 'OFF';
    }
    time.textContent = `Last toggled: ${new Date().toLocaleTimeString('en-US', { hour12: false })}`;
}

function toggleLed() {
    socket.emit('toggle_led', {});
}

function startAdv() {
    socket.emit('start_adv', {});
}

function stopAdv() {
    socket.emit('stop_adv', {});
}

function setStatus(connected) {
    const dot = document.getElementById('statusDot');
    const text = document.getElementById('statusText');
    if (connected) {
        dot.classList.add('connected');
        text.textContent = 'Connected';
    } else {
        dot.classList.remove('connected');
        text.textContent = 'Disconnected';
    }
}

function addLog(message, type = 'default', time = null) {
    const console_ = document.getElementById('console');
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    const now = time || new Date().toLocaleTimeString('en-US', { hour12: false });
    entry.innerHTML = `
        <span class="log-time">${now}</span>
        <span class="log-message ${type}">${message}</span>
    `;
    console_.appendChild(entry);
    console_.scrollTop = console_.scrollHeight;
}

function addCommandHistory(text, time) {
    commandHistory.unshift({ text, time });
    if (commandHistory.length > MAX_COMMAND_HISTORY) {
        commandHistory = commandHistory.slice(0, MAX_COMMAND_HISTORY);
    }
    const historyEl = document.getElementById('commandHistory');
    historyEl.innerHTML = commandHistory.map(item =>
        `<div class="command-history-item"><span>${item.time}</span>${item.text}</div>`
    ).join('');
}

function clearLog() {
    document.getElementById('console').innerHTML = '';
}