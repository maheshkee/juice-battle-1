import os
import json
import shutil
import glob
from datetime import datetime

VIDEOS_DIR  = "/app/assets/videos"
QUEUE_FILE  = "/app/local_queue.json"

def _ensure_dir():
    os.makedirs(VIDEOS_DIR, exist_ok=True)

def list_files():
    """Scan videos dir, return list of file info dicts."""
    _ensure_dir()
    files = []
    for path in sorted(glob.glob(os.path.join(VIDEOS_DIR, "*.mp4"))):
        fname = os.path.basename(path)
        size_mb = round(os.path.getsize(path) / (1024 * 1024), 1)
        files.append({"filename": fname, "title": fname.rsplit(".", 1)[0], "size_mb": size_mb})
    return files

def usb_import(push_evt_fn):
    """Copy all .mp4 files from first detected USB drive to videos dir."""
    _ensure_dir()
    # Find USB mount point
    usb_root = None
    for path in glob.glob("/media/arduino/*/"):
        usb_root = path
        break
    if not usb_root:
        # Also try /media/usb* and /mnt/usb*
        for pattern in ["/media/usb*/", "/mnt/usb*/", "/run/media/arduino/*/"]:
            matches = glob.glob(pattern)
            if matches:
                usb_root = matches[0]
                break

    if not usb_root:
        push_evt_fn({"event": "usb_import_status", "status": "error",
                     "message": "No USB drive detected"})
        return

    mp4_files = glob.glob(os.path.join(usb_root, "**", "*.mp4"), recursive=True)
    mp4_files += glob.glob(os.path.join(usb_root, "**", "*.MP4"), recursive=True)

    if not mp4_files:
        push_evt_fn({"event": "usb_import_status", "status": "error",
                     "message": "No MP4 files found on USB drive"})
        return

    imported = 0
    for src in mp4_files:
        fname = os.path.basename(src)
        dst   = os.path.join(VIDEOS_DIR, fname)
        push_evt_fn({"event": "usb_import_status", "status": "importing",
                     "file": fname, "progress": int((imported / len(mp4_files)) * 100)})
        try:
            shutil.copy2(src, dst)
            imported += 1
            print(f"[LOCAL] Imported: {fname}", flush=True)
        except Exception as e:
            print(f"[LOCAL] Import failed {fname}: {e}", flush=True)

    push_evt_fn({"event": "usb_import_done", "files_imported": imported,
                 "files": list_files()})
    print(f"[LOCAL] USB import complete: {imported} files", flush=True)


class LocalEngine:
    def __init__(self, write_cmd_fn, push_evt_fn):
        self.write_cmd = write_cmd_fn
        self.push_evt  = push_evt_fn
        self.playlist  = []
        self.index     = 0
        self.status    = "idle"
        self._load()

    def _load(self):
        if os.path.exists(QUEUE_FILE):
            try:
                with open(QUEUE_FILE, "r") as f:
                    data = json.load(f)
                self.playlist = data.get("playlist", [])
                self.index    = data.get("index", 0)
                self.status   = data.get("status", "idle")
                print(f"[LOCAL] Loaded playlist: {len(self.playlist)} files", flush=True)
            except Exception as e:
                print(f"[LOCAL] Load failed: {e}", flush=True)

    def _save(self):
        try:
            with open(QUEUE_FILE, "w") as f:
                json.dump({"playlist": self.playlist,
                           "index":    self.index,
                           "status":   self.status}, f, indent=2)
        except Exception as e:
            print(f"[LOCAL] Save failed: {e}", flush=True)

    def list_files(self):
        """CMD:LOCAL_LIST — push file list to phone."""
        files = list_files()
        self.push_evt({"event": "local_files", "files": files})

    def play_file(self, filename):
        """CMD:LOCAL_PLAY:<filename> — play single file."""
        path = os.path.join(VIDEOS_DIR, filename)
        if not os.path.exists(path):
            print(f"[LOCAL] File not found: {filename}", flush=True)
            return
        self.status = "playing"
        self._save()
        print(f"[LOCAL] Playing: {filename}", flush=True)
        self.write_cmd(f"LOCAL:{filename}")
        self.push_evt({"event": "local_status", "status": "playing",
                       "filename": filename})

    def set_playlist(self, payload):
        """CMD:LOCAL_QUEUE_SET:<json> — set local playlist."""
        try:
            data = json.loads(payload)
            self.playlist = data.get("playlist", [])
            self.index    = 0
            self.status   = "idle"
            self._save()
            print(f"[LOCAL] Playlist set: {len(self.playlist)} files", flush=True)
            self.push_evt({"event": "local_status", "status": "idle",
                           "total": len(self.playlist)})
        except Exception as e:
            print(f"[LOCAL] set_playlist failed: {e}", flush=True)

    def play_playlist(self):
        """CMD:LOCAL_QUEUE_PLAY — start local playlist."""
        if not self.playlist:
            print("[LOCAL] Playlist is empty", flush=True)
            return
        self.status = "playing"
        self._save()
        self._play_current()

    def on_video_ended(self, filename):
        """Called when local video ends — advance to next."""
        if self.status != "playing":
            return
        next_index = self.index + 1
        if next_index < len(self.playlist):
            self.index = next_index
            self._save()
            self._play_current()
        else:
            print("[LOCAL] Playlist complete", flush=True)
            self.status = "idle"
            self.index  = 0
            self._save()
            self.write_cmd("STOP")
            self.push_evt({"event": "local_status", "status": "idle"})

    def usb_import(self):
        """CMD:LOCAL_USB_IMPORT — import from USB drive."""
        import threading
        threading.Thread(
            target=usb_import,
            args=(self.push_evt,),
            daemon=True
        ).start()

    def _play_current(self):
        if not self.playlist or self.index >= len(self.playlist):
            return
        item = self.playlist[self.index]
        filename = item.get("filename", "")
        print(f"[LOCAL] Playlist [{self.index+1}/{len(self.playlist)}]: {filename}", flush=True)
        self.write_cmd(f"LOCAL:{filename}")
        self.push_evt({"event": "local_status", "status": "playing",
                       "filename": filename, "current_index": self.index,
                       "total": len(self.playlist)})
