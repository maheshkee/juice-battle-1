import json
import os
from datetime import datetime

QUEUE_FILE = "/app/queue.json"

class QueueEngine:
    def __init__(self, write_cmd_fn, push_evt_fn):
        self.write_cmd = write_cmd_fn
        self.push_evt  = push_evt_fn
        self.queue     = []
        self.date      = ""
        self.status    = "idle"
        self.index     = 0
        self.history   = []
        self._load()

    # ── Persistence ─────────────────────────────────────────────────────────

    def _load(self):
        if os.path.exists(QUEUE_FILE):
            try:
                with open(QUEUE_FILE, "r") as f:
                    data = json.load(f)
                self.queue   = data.get("queue", [])
                self.date    = data.get("date", "")
                self.status  = data.get("state", {}).get("status", "idle")
                self.index   = data.get("state", {}).get("current_index", 0)
                self.history = data.get("history", [])
                print(f"[QUEUE] Loaded {len(self.queue)} videos, status={self.status}", flush=True)
            except Exception as e:
                print(f"[QUEUE] Load failed: {e}", flush=True)

    def _save(self):
        try:
            data = {
                "queue": self.queue,
                "date":  self.date,
                "state": {
                    "status":        self.status,
                    "current_index": self.index
                },
                "history": self.history
            }
            with open(QUEUE_FILE, "w") as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            print(f"[QUEUE] Save failed: {e}", flush=True)

    # ── Commands ─────────────────────────────────────────────────────────────

    def set_queue(self, payload):
        """CMD:QUEUE_SET:<json> — replace entire queue"""
        try:
            data = json.loads(payload)
            self.queue  = data.get("queue", [])
            self.date   = data.get("date", datetime.now().strftime("%Y-%m-%d"))
            self.status = "idle"
            self.index  = 0
            self._save()
            print(f"[QUEUE] Set {len(self.queue)} videos for {self.date}", flush=True)
            self._push_status()
        except Exception as e:
            print(f"[QUEUE] set_queue failed: {e}", flush=True)

    def play(self):
        """CMD:QUEUE_PLAY — start from current index"""
        if not self.queue:
            print("[QUEUE] play: empty queue", flush=True)
            return
        self.status = "playing"
        self._save()
        self._play_current()

    def replay(self):
        """CMD:QUEUE_REPLAY — replay current video"""
        if not self.queue or self.index >= len(self.queue):
            return
        # increment replay count in history
        vid = self.queue[self.index]
        self._update_history(vid["videoId"], replayed=True)
        self.status = "playing"
        self._save()
        self._play_current()

    def skip(self):
        """CMD:QUEUE_SKIP — advance to next video"""
        self._advance()

    def goto(self, n):
        """CMD:QUEUE_GOTO:N — jump to index N"""
        try:
            n = int(n)
            if 0 <= n < len(self.queue):
                self.index  = n
                self.status = "playing"
                self._save()
                self._play_current()
            else:
                print(f"[QUEUE] goto: index {n} out of range", flush=True)
        except ValueError:
            print(f"[QUEUE] goto: invalid index {n}", flush=True)

    def pause(self):
        """CMD:QUEUE_PAUSE"""
        self.status = "paused"
        self._save()
        self._push_status()
        print("[QUEUE] Paused", flush=True)

    def resume(self):
        """CMD:QUEUE_RESUME"""
        if self.status == "paused" and self.queue:
            self.status = "playing"
            self._save()
            self._play_current()

    def stop(self):
        """CMD:QUEUE_STOP"""
        self.status = "idle"
        self._save()
        self.write_cmd("STOP")
        self._push_status()
        print("[QUEUE] Stopped", flush=True)

    def on_video_ended(self, video_id):
        """Called when YouTube IFrame fires ENDED event from splash.html"""
        print(f"[QUEUE] Video ended: {video_id}", flush=True)
        if self.status != "playing":
            return
        # mark as completed in history
        self._update_history(video_id, completed=True)
        self._advance()

    def get_status(self):
        current = self.queue[self.index] if self.queue and self.index < len(self.queue) else {}
        return {
            "event":         "queue_status",
            "status":        self.status,
            "current_index": self.index,
            "total":         len(self.queue),
            "videoId":       current.get("videoId", ""),
            "title":         current.get("title", ""),
            "date":          self.date
        }

    def get_history(self):
        return {
            "event":   "queue_history",
            "history": self.history
        }

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _play_current(self):
        if not self.queue or self.index >= len(self.queue):
            return
        vid = self.queue[self.index]
        video_id = vid.get("videoId", "")
        print(f"[QUEUE] Playing [{self.index+1}/{len(self.queue)}]: {video_id}", flush=True)
        # log play start in history
        self._update_history(video_id, started=True, title=vid.get("title",""))
        self.write_cmd(video_id)
        self._push_status()

    def _advance(self):
        next_index = self.index + 1
        if next_index < len(self.queue):
            self.index = next_index
            self._save()
            self._play_current()
        else:
            print("[QUEUE] Queue complete — returning to splash", flush=True)
            self.status = "idle"
            self.index  = 0
            self._save()
            self.write_cmd("STOP")
            self._push_status()

    def _update_history(self, video_id, started=False, completed=False,
                        replayed=False, title=""):
        # find existing entry for this video in today's session
        entry = next((h for h in self.history
                      if h["videoId"] == video_id
                      and h.get("scheduledDate") == self.date), None)
        if entry is None:
            entry = {
                "videoId":       video_id,
                "title":         title,
                "scheduledDate": self.date,
                "playedAt":      datetime.now().isoformat(timespec="seconds"),
                "completed":     False,
                "replays":       0
            }
            self.history.append(entry)
        if completed:
            entry["completed"] = True
        if replayed:
            entry["replays"] = entry.get("replays", 0) + 1
        self._save()

    def _push_status(self):
        self.push_evt(self.get_status())
