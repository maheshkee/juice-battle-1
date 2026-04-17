// app.js — socket logic and DOM updates
const socket     = io();
const circle     = document.getElementById('status-circle');
const statusText = document.getElementById('status-text');
const lastTime   = document.getElementById('last-time');
const log        = document.getElementById('log');
const connStatus = document.getElementById('conn-status');

socket.on('connect', () => {
  connStatus.textContent = '\u25CF Connected';
  connStatus.className = 'connected';
});
socket.on('disconnect', () => {
  connStatus.textContent = '\u25CF Disconnected';
  connStatus.className = 'disconnected';
});
socket.on('motion_update', (data) => {
  circle.className = data.motion ? 'detected' : 'clear';
  circle.textContent = data.status;
  statusText.textContent = data.motion ? '\u26A0 Motion Detected' : '\u2713 Area Clear';
  lastTime.textContent = 'Last event: ' + data.time;
  const waiting = log.querySelector('.log-waiting');
  if (waiting) waiting.remove();
  const entry = document.createElement('div');
  entry.className = 'log-entry ' + (data.motion ? 'log-detected' : 'log-clear');
  entry.textContent = data.time + '  \u2192  ' + data.status;
  log.insertBefore(entry, log.firstChild);
  while (log.children.length > 50) log.removeChild(log.lastChild);
});