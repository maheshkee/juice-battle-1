// app.js — socket logic and DOM updates for multi-room dashboard
const socket     = io();
const circle     = document.getElementById('status-circle');
const statusText = document.getElementById('status-text');
const lastTime   = document.getElementById('last-time');
const log        = document.getElementById('log');
const connStatus = document.getElementById('conn-status');
const remoteDiv  = document.getElementById('remote-sensors');

socket.on('connect', () => {
  connStatus.textContent = '\u25CF Connected';
  connStatus.className = 'connected';
});
socket.on('disconnect', () => {
  connStatus.textContent = '\u25CF Disconnected';
  connStatus.className = 'disconnected';
});

// Local PIR update
socket.on('motion_update', (data) => {
  circle.className = data.motion ? 'detected' : 'clear';
  circle.textContent = data.status;
  statusText.textContent = data.motion ? '\u26A0 Motion Detected' : '\u2713 Area Clear';
  lastTime.textContent = 'Last event: ' + (data.time || '');
  addLog('Local', data.motion, data.status, data.time);
});

// Remote PIR update
socket.on('remote_update', (data) => {
  updateRemoteCard(data.name, data.motion, data.status);
  addLog(data.name, data.motion, data.status, '');
});

function updateRemoteCard(name, motion, status) {
  // Remove placeholder on first remote sensor
  const placeholder = remoteDiv.querySelector('.remote-placeholder');
  if (placeholder) placeholder.remove();

  let card = document.getElementById('sensor-' + name);
  if (!card) {
    card = document.createElement('div');
    card.id = 'sensor-' + name;
    remoteDiv.appendChild(card);
  }
  card.className = 'remote-card ' + (motion ? 'detected' : 'clear');
  card.innerHTML =
    '<span class="remote-name">' + name + '</span>' +
    '<span class="remote-status">' + status + '</span>';
}

function addLog(source, motion, status, time) {
  const waiting = log.querySelector('.log-waiting');
  if (waiting) waiting.remove();
  const entry = document.createElement('div');
  entry.className = 'log-entry ' + (motion ? 'log-detected' : 'log-clear');
  const t = time || new Date().toLocaleTimeString();
  entry.textContent = t + '  [' + source + ']  \u2192  ' + status;
  log.insertBefore(entry, log.firstChild);
  while (log.children.length > 50) log.removeChild(log.lastChild);
}
