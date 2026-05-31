
#!/usr/bin/env python3
"""
ToT Brain — AI reasoning engine.
Loads device memory, calls AI API, returns action plans.
"""

import os
import json
import re
from datetime import datetime

# Load API key from config
CONFIG_FILE = os.path.expanduser("~/.tot_config")

def load_config():
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    config[k.strip()] = v.strip()
    return config

# ── Action Templates ──────────────────────────────────────
# Maps intent keywords → Termux:API actions
ACTION_MAP = {
    "battery":       {"name": "battery",       "command": "termux-battery-status"},
    "location":      {"name": "location",      "command": "termux-location"},
    "gps":           {"name": "location",      "command": "termux-location"},
    "sms":           {"name": "sms_list",      "command": "termux-sms-list -l 5"},
    "notification":  {"name": "notification",  "command": None},  # dynamic
    "wifi":          {"name": "wifi",          "command": "termux-wifi-connectioninfo"},
    "clipboard":     {"name": "clipboard",     "command": "termux-clipboard-get"},
    "photo":         {"name": "photo",         "command": "termux-camera-photo -c 0 ~/tot/tmp/photo.jpg"},
    "torch":         {"name": "torch_on",      "command": "termux-torch on"},
    "torch off":     {"name": "torch_off",     "command": "termux-torch off"},
    "volume":        {"name": "volume",        "command": None},  # dynamic
    "vibrate":       {"name": "vibrate",       "command": "termux-vibrate -d 500"},
    "speak":         {"name": "speak",         "command": None},  # dynamic
    "contacts":      {"name": "contacts",      "command": "termux-contact-list"},
    "call log":      {"name": "call_log",      "command": "termux-call-log -l 5"},
    "brightness":    {"name": "brightness",    "command": None},  # dynamic
    "download":      {"name": "download",      "command": None},  # dynamic
    "share":         {"name": "share",         "command": None},  # dynamic
}

class ToTBrain:
    def __init__(self, memory_dir: str):
        self.memory_dir  = memory_dir
        self.facts_file  = os.path.join(memory_dir, "facts.json")
        self.prefs_file  = os.path.join(memory_dir, "preferences.json")
        self.history_file = os.path.join(memory_dir, "history.log")
        self.config      = load_config()
        self._load_memory()

    def _load_memory(self):
        self.facts = {}
        self.prefs = {}
        if os.path.exists(self.facts_file):
            with open(self.facts_file) as f:
                self.facts = json.load(f)
        if os.path.exists(self.prefs_file):
            with open(self.prefs_file) as f:
                self.prefs = json.load(f)

    def memory_count(self):
        return len(self.facts) + len(self.prefs)

    def _save_memory(self):
        with open(self.facts_file, "w") as f:
            json.dump(self.facts, f, indent=2)
        with open(self.prefs_file, "w") as f:
            json.dump(self.prefs, f, indent=2)

    def _log(self, role: str, content: str):
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(self.history_file, "a") as f:
            f.write(f"[{ts}] {role}: {content}\n")

    def _build_system_prompt(self) -> str:
        memory_summary = ""
        if self.facts:
            memory_summary += "\n\n### Known Device Facts:\n"
            for k, v in list(self.facts.items())[-20:]:
                memory_summary += f"- {k}: {v}\n"
        if self.prefs:
            memory_summary += "\n### User Preferences:\n"
            for k, v in self.prefs.items():
                memory_summary += f"- {k}: {v}\n"

        return f"""You are ToT, an adaptive AI that controls an Android device via Termux.
You have FULL device control through Termux:API commands.
You remember everything you've done on this device and never re-learn the same thing twice.

{memory_summary}

Available device actions you can trigger:
- battery: Check battery level and charging status
- location/gps: Get current GPS coordinates
- notification: Show a notification (specify title and content)
- wifi: Get WiFi connection info  
- clipboard: Read clipboard content
- photo: Take a photo with the camera
- torch: Turn flashlight on/off
- speak: Text-to-speech output
- vibrate: Vibrate the device
- sms: Read recent SMS messages
- contacts: List contacts
- volume: Set media/call volume (0-15)
- brightness: Set screen brightness (0-255)

When the user gives a command:
1. Respond conversationally in markdown
2. List any device actions to execute as JSON at the END of your response in this exact format:
ACTIONS:{{\"actions\":[{{\"name\":\"action_name\",\"command\":\"termux command here\",\"params\":{{}}}}]}}

If no device action is needed, just respond conversationally.
Always confirm what you did and what you learned/remembered.
"""

    def reason(self, user_message: str) -> dict:
        """Main reasoning function. Returns response + action plan."""
        self._log("user", user_message)

        # Try AI API first, fall back to rule-based
        api_key = self.config.get("OPENAI_API_KEY") or self.config.get("GEMINI_API_KEY")

        if api_key and self.config.get("OPENAI_API_KEY"):
            return self._reason_openai(user_message)
        elif api_key and self.config.get("GEMINI_API_KEY"):
            return self._reason_gemini(user_message)
        else:
            return self._reason_local(user_message)

    def _reason_openai(self, user_message: str) -> dict:
        try:
            from openai import OpenAI
            client = OpenAI(api_key=self.config["OPENAI_API_KEY"])
            resp = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": self._build_system_prompt()},
                    {"role": "user",   "content": user_message}
                ],
                max_tokens=1000
            )
            full_text = resp.choices[0].message.content
            return self._parse_response(full_text)
        except Exception as e:
            return {"response": f"❌ AI API error: {e}", "actions": []}

    def _reason_gemini(self, user_message: str) -> dict:
        try:
            import requests
            url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={self.config['GEMINI_API_KEY']}"
            prompt = self._build_system_prompt() + f"\n\nUser: {user_message}"
            resp = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]})
            full_text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
            return self._parse_response(full_text)
        except Exception as e:
            return {"response": f"❌ Gemini API error: {e}", "actions": []}

    def _reason_local(self, user_message: str) -> dict:
        """Rule-based fallback when no API key is set."""
        msg_lower = user_message.lower()
        actions = []
        response_parts = ["🤖 **ToT responding** (no API key set — using rule-based mode):\n"]

        for keyword, action in ACTION_MAP.items():
            if keyword in msg_lower and action["command"]:
                actions.append(action)
                response_parts.append(f"▶ Executing: **{action['name']}**")

        if not actions:
            response_parts.append(f"I heard: *{user_message}*\n\nSet your API key in `~/.tot_config` for full AI reasoning.")

        return {"response": "\n".join(response_parts), "actions": actions}

    def _parse_response(self, full_text: str) -> dict:
        """Parse AI response to extract text + action plan."""
        actions = []
        response_text = full_text

        if "ACTIONS:" in full_text:
            parts = full_text.split("ACTIONS:", 1)
            response_text = parts[0].strip()
            try:
                action_json = json.loads(parts[1].strip())
                actions = action_json.get("actions", [])
            except Exception:
                pass

        self._log("tot", response_text)
        return {"response": response_text, "actions": actions}

    def save_device_actions(self, actions: list, results: list):
        """Permanently save learned device actions to memory."""
        for action, result in zip(actions, results):
            if result.get("success"):
                key = f"device_action_{action['name']}"
                self.facts[key] = {
                    "command": action.get("command", ""),
                    "last_used": datetime.now().isoformat(),
                    "success_count": self.facts.get(key, {}).get("success_count", 0) + 1
                }
            else:
                key = f"device_error_{action['name']}"
                self.facts[key] = {
                    "error": result.get("error", ""),
                    "command_attempted": action.get("command", ""),
                    "logged_at": datetime.now().isoformat()
                }
        self._save_memory()

    def transcribe(self, audio_path: str) -> str:
        """Transcribe audio using Whisper API or local tool."""
        api_key = self.config.get("OPENAI_API_KEY")
        if api_key:
            try:
                from openai import OpenAI
                client = OpenAI(api_key=api_key)
                with open(audio_path, "rb") as f:
                    result = client.audio.transcriptions.create(model="whisper-1", file=f)
                return result.text
            except Exception as e:
                return f"[transcription error: {e}]"
        return "[No API key — voice transcription unavailable]"