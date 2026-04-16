const socket = io();

const circle     = document.getElementById('status-circle');
const circleText = document.getElementById('circle-text');
const statusText = document.getElementById('status-text');
const lastTime   = document.getElementById('last-time');
const statStatus = document.getElementById('stat-status');
const statTime   = document.getElementById('stat-time');
const log        = document.getElementById('log');
const connBadge  = document.getElementById('conn-status');

socket.on('connect', () => {
  connBadge.textContent = '● Connected';
  connBadge.className   = 'conn-badge connected';
});

socket.on('disconnect', () => {
  connBadge.textContent = '● Disconnected';
  connBadge.className   = 'conn-badge disconnected';
});

socket.on('motion_update', (data) => {

  circle.className   = 'status-circle ' + (data.motion ? 'detected' : 'clear');
  circleText.textContent = data.status;

  statusText.textContent = data.motion ? '⚠ Motion detected' : '✓ Area clear';
  lastTime.textContent   = 'Last event: ' + data.time;

  statStatus.textContent = data.status;
  statStatus.className   = 'stat-value ' + (data.motion ? 'motion' : 'clear');
  statTime.textContent   = data.time;

  const emptyEntry = log.querySelector('.empty-entry');
  if (emptyEntry) emptyEntry.remove();

  const entry = document.createElement('div');
  entry.className = 'log-entry';
  entry.innerHTML = `
    <span class="log-time">${data.time}</span>
    <span class="${data.motion ? 'log-detected' : 'log-clear'}">${data.status}</span>
  `;
  log.insertBefore(entry, log.firstChild);

  while (log.children.length > 50) {
    log.removeChild(log.lastChild);
  }
});