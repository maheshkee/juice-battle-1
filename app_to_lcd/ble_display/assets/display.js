let ytPlayer = null;
let playerReady = false;

function onYouTubeIframeAPIReady() {
    ytPlayer = new YT.Player('yt-player', {
        width: '100%',
        height: '100%',
        playerVars: {
            autoplay: 1,
            controls: 0,
            modestbranding: 1,
            rel: 0,
            iv_load_policy: 3,
            fs: 0,
        },
        events: {
            onReady: (e) => {
                playerReady = true;
                console.log('[YT] Player ready');
            },
            onStateChange: (e) => {
                console.log('[YT] State:', e.data);
            },
            onError: (e) => {
                console.log('[YT] Error:', e.data);
            }
        }
    });
}

function playVideo(videoId) {
    if (!ytPlayer || !playerReady) {
        console.log('[YT] Player not ready, retrying...');
        setTimeout(() => playVideo(videoId), 500);
        return;
    }
    console.log('[YT] Playing:', videoId);
    ytPlayer.loadVideoById(videoId);
}

function handleCmd(cmd, data) {
    if (!ytPlayer || !playerReady) return;
    switch (cmd) {
        case 'play':
            playVideo(data.video_id);
            break;
        case 'pause':
            ytPlayer.pauseVideo();
            break;
        case 'resume':
            ytPlayer.playVideo();
            break;
        case 'stop':
            ytPlayer.stopVideo();
            break;
        case 'mute':
            ytPlayer.mute();
            break;
        case 'unmute':
            ytPlayer.unMute();
            break;
        case 'vol_up':
            ytPlayer.setVolume(Math.min(100, ytPlayer.getVolume() + 10));
            break;
        case 'vol_down':
            ytPlayer.setVolume(Math.max(0, ytPlayer.getVolume() - 10));
            break;
        case 'set_mode':
            if (data.mode !== 'youtube') ytPlayer.stopVideo();
            break;
    }
}

window.addEventListener('message', (e) => {
    try {
        const msg = JSON.parse(e.data);
        if (msg.cmd) handleCmd(msg.cmd, msg);
    } catch (_) {}
});
