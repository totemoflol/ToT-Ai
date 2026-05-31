
#!/usr/bin/env python3
"""
ToT Device Controller — executes Termux:API commands
and returns structured results.
"""

import subprocess
import json
import os
import shlex
from datetime import datetime

class DeviceController:
    def __init__(self, memory_dir: str):
        self.memory_dir = memory_dir
        self.tmp_dir    = os.path.expanduser("~/tot/tmp")
        os.makedirs(self.tmp_dir, exist_ok=True)

    def _run(self, command: str, timeout: int = 15) -> dict:
        """Run a shell command and return structured result."""
        try:
            result = subprocess.run(
                command, shell=True,
                capture_output=True, text=True, timeout=timeout
            )
            output = result.stdout.strip()
            error  = result.stderr.strip()
            success = result.returncode == 0
            try:
                parsed = json.loads(output)
            except Exception:
                parsed = output
            return {"success": success, "output": parsed, "error": error, "raw": output}
        except subprocess.TimeoutExpired:
            return {"success": False, "output": "", "error": "Command timed out", "raw": ""}
        except Exception as e:
            return {"success": False, "output": "", "error": str(e), "raw": ""}

    def execute(self, action: dict) -> dict:
        """Execute a device action from the AI plan."""
        name    = action.get("name", "")
        command = action.get("command", "")
        params  = action.get("params", {})

        # Dynamic command builders
        if name == "notification":
            title   = params.get("title", "ToT")
            content = params.get("content", "Hello from ToT!")
            command = f'termux-notification --title "{title}" --content "{content}" --id 42'

        elif name == "speak":
            text    = params.get("text", "")
            command = f'termux-tts-speak "{text}"'

        elif name == "volume":
            level   = params.get("level", 8)
            stream  = params.get("stream", "music")
            command = f"termux-volume {stream} {level}"

        elif name == "brightness":
            level   = params.get("level", 128)
            command = f"termux-brightness {level}"

        elif name == "sms_send":
            number  = params.get("number", "")
            msg     = params.get("message", "")
            command = f'termux-sms-send -n "{number}" "{msg}"'

        elif name == "download":
            url     = params.get("url", "")
            dest    = params.get("dest", f"{self.tmp_dir}/download")
            command = f'termux-download -d "{dest}" "{url}"'

        elif name == "share":
            text    = params.get("text", "")
            command = f'termux-share -a send -t text/plain "{text}"'

        if not command:
            return {"success": False, "output": "", "error": f"No command for action: {name}"}

        return self._run(command)

    def get_snapshot(self) -> dict:
        """Get current device state snapshot for the UI dashboard."""
        snapshot = {}

        # Battery
        bat = self._run("termux-battery-status", timeout=5)
        if bat["success"] and isinstance(bat["output"], dict):
            snapshot["battery"] = bat["output"]

        # WiFi
        wifi = self._run("termux-wifi-connectioninfo", timeout=5)
        if wifi["success"] and isinstance(wifi["output"], dict):
            snapshot["wifi"] = {
                "ssid":   wifi["output"].get("ssid", "Unknown"),
                "signal": wifi["output"].get("rssi", "N/A")
            }

        # Timestamp
        snapshot["timestamp"] = datetime.now().strftime("%H:%M:%S")

        return snapshot