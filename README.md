# 🧠 ToT-Ai — Android Device Control System

> Adaptive AI that controls your Android device from any browser via CREAO-hosted UI + Termux bridge.

## 📁 Files
| File | Purpose |
|------|---------|
| `brain.py` | AI reasoning engine (OpenAI / Gemini / rule-based fallback) |
| `device.py` | Termux:API device controller — executes all hardware commands |
| `listener.sh` | Background bridge — connects Termux to the CREAO browser UI |
| `requirements.txt` | Python dependencies |

---

## ⚡ Setup — 2 Commands

### 1️⃣ Install Dependencies
```bash
pkg install -y termux-api curl jq && pip install -r <(curl -fsSL https://raw.githubusercontent.com/totemoflol/ToT-Ai/main/requirements.txt)
```

### 2️⃣ Run ToT
```bash
curl -fsSL https://raw.githubusercontent.com/totemoflol/ToT-Ai/main/listener.sh | bash
```

---

## ⚙️ Config (before running)
Edit `listener.sh` and set:
```bash
CHANNEL="your-unique-channel-id"   # Must match browser UI
OPENAI_API_KEY="sk-..."            # Or use GEMINI_API_KEY
```

---

## 🌐 Browser UI
Open the ToT Command Centre hosted on CREAO — enter the same Channel ID and start controlling your device from anywhere.

---

## 🔒 Security
- Your channel ID is your private key — use a long, random string
- All communication goes through ntfy.sh relay (free, open source)
- No ports open on your device, no root required

