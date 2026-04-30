'use strict';

(function requestFS() {
    const el = document.documentElement;
    const fn = el.requestFullscreen || el.webkitRequestFullscreen || el.mozRequestFullScreen;
    if (fn) fn.call(el).catch(() => {});
})();

(function spawnParticles() {
    const container = document.getElementById('particles');
    if (!container) return;
    for (let i = 0; i < 40; i++) {
        const p = document.createElement('div');
        p.className = 'particle';
        p.style.left     = Math.random() * 100 + 'vw';
        p.style.animationDuration  = (8 + Math.random() * 14) + 's';
        p.style.animationDelay     = (-Math.random() * 20) + 's';
        p.style.opacity  = (0.2 + Math.random() * 0.5).toString();
        container.appendChild(p);
    }
})();

let currentMode  = 'idle';
let queueActive  = false;

function showScreen(mode) {
    document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
    const target = document.getElementById(mode + '-screen');
    if (target) target.classList.add('active');
    currentMode = mode;
}

let toastTimer = null;
function showToast(msg) {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 2000);
}

const DAYS   = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
const MONTHS = ['January','February','March','April','May','June',
                'July','August','September','October','November','December'];

function pad2(n) { return String(n).padStart(2, '0'); }

function tickClock() {
    const now = new Date();
    document.getElementById('clock-h').textContent    = pad2(now.getHours());
    document.getElementById('clock-m').textContent    = pad2(now.getMinutes());
    document.getElementById('clock-s').textContent    = pad2(now.getSeconds());
    document.getElementById('clock-date').textContent =
        `${DAYS[now.getDay()]}  |  ${MONTHS[now.getMonth()]} ${now.getDate()}, ${now.getFullYear()}`;
    document.getElementById('sec-bar').style.width =
        ((now.getSeconds() / 59) * 100) + '%';
}
setInterval(tickClock, 1000);
tickClock();

let ytPlayer     = null;
let ytReady      = false;
let pendingVideo = null;

window.onYouTubeIframeAPIReady = function () {
    ytReady = true;
    ytPlayer = new YT.Player('player', {
        width:  '100%',
        height: '100%',
        playerVars: {
            autoplay:       1,
            controls:       1,
            rel:            0,
            modestbranding: 1,
            iv_load_policy: 3,
            fs:             1,
        },
        events: {
            onReady:       onPlayerReady,
            onStateChange: onPlayerStateChange,
        }
    });
};

function onPlayerReady() {
    if (pendingVideo) {
        loadAndPlay(pendingVideo);
        pendingVideo = null;
    }
}

function onPlayerStateChange(event) {
    const states = {
        [-1]: 'unstarted',
        [YT.PlayerState.ENDED]:     'ended',
        [YT.PlayerState.PLAYING]:   'playing',
        [YT.PlayerState.PAUSED]:    'paused',
        [YT.PlayerState.BUFFERING]: 'buffering',
        [YT.PlayerState.CUED]:      'cued',
    };
    const state = states[event.data] || 'unknown';
    socket.emit('player_event', { state });
    if (event.data === YT.PlayerState.ENDED && !queueActive) {
        setTimeout(() => showScreen('idle'), 2000);
    }
}

function loadAndPlay(videoId) {
    if (!ytPlayer || !ytReady) {
        pendingVideo = videoId;
        return;
    }
    showScreen('youtube');
    ytPlayer.loadVideoById({ videoId, suggestedQuality: 'hd720' });
    setTimeout(() => {
        try { ytPlayer.playVideo(); } catch(e) {}
    }, 1500);
}

const qualityMap = {
    '1080p': 'hd1080', '720p': 'hd720', '480p': 'large',
    '360p': 'medium',  '240p': 'small', '144p': 'tiny', 'Auto': 'default'
};

function execCmd(cmd) {
    switch (true) {
        case cmd === 'pause':
            if (ytPlayer) ytPlayer.pauseVideo();
            showToast('⏸ Paused');
            break;
        case cmd === 'resume':
        case cmd === 'play':
            if (ytPlayer) ytPlayer.playVideo();
            showToast('▶ Playing');
            break;
        case cmd === 'mute':
            if (ytPlayer) ytPlayer.mute();
            showToast('🔇 Muted');
            break;
        case cmd === 'unmute':
            if (ytPlayer) ytPlayer.unMute();
            showToast('🔊 Unmuted');
            break;
        case cmd === 'vol_up':
            if (ytPlayer) ytPlayer.setVolume(Math.min(100, ytPlayer.getVolume() + 10));
            showToast('🔊 Vol +');
            break;
        case cmd === 'vol_down':
            if (ytPlayer) ytPlayer.setVolume(Math.max(0, ytPlayer.getVolume() - 10));
            showToast('🔉 Vol -');
            break;
        case cmd === 'seek_fwd':
            if (ytPlayer) ytPlayer.seekTo(ytPlayer.getCurrentTime() + 10, true);
            showToast('⏩ +10s');
            break;
        case cmd === 'seek_back':
            if (ytPlayer) ytPlayer.seekTo(Math.max(0, ytPlayer.getCurrentTime() - 10), true);
            showToast('⏪ -10s');
            break;
        case cmd === 'replay':
            if (ytPlayer) ytPlayer.seekTo(0, true);
            showToast('⏮ Replay');
            break;
        case cmd.startsWith('quality:'):
            const q = cmd.split(':')[1];
            if (ytPlayer) ytPlayer.setPlaybackQuality(qualityMap[q] || 'default');
            showToast(`⚙️ ${q}`);
            break;
        default:
            break;
    }
}

const WEBUI_HOST = window.location.hostname + ':7000';
const socket = io(`http://${WEBUI_HOST}`, {
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 3000,
    reconnectionDelayMax: 5000,
});

socket.on('connect', () => {
    console.log('[Socket] connected');
    if (!ytPlayer && !ytReady) {
        const tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
    }
});

socket.on('disconnect', () => {
    if (ytPlayer) { try { ytPlayer.stopVideo(); } catch(e) {} }
    showScreen('idle');
});

socket.on('display_cmd', (data) => {
    const { cmd, video_id, mode } = data;
    if (cmd === 'play' && video_id) {
        showToast('▶ Loading...');
        loadAndPlay(video_id);
        return;
    }
    if (cmd === 'stop') {
        if (ytPlayer) { try { ytPlayer.stopVideo(); } catch(e) {} }
        queueActive = false;
        showScreen('idle');
        showToast('⏹ Stopped');
        return;
    }
    if (cmd === 'set_mode' && mode) {
        showScreen(mode);
        return;
    }
    execCmd(cmd);
});

socket.on('queue_status', (data) => {
    queueActive = data.active === true;
});

const tag = document.createElement('script');
tag.src = 'https://www.youtube.com/iframe_api';
document.head.appendChild(tag);