
#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════
# ToT Listener — runs in Termux background
# Polls CREAO-hosted Command Centre via ntfy.sh relay
# No port forwarding. Works on any network. ✅
#
# Setup:
#   1. pkg install termux-api curl jq python3
#   2. pip install openai requests
#   3. Set CHANNEL below (must match the browser UI)
#   4. Set API_KEY below (OpenAI or Gemini)
#   5. bash listener.sh
# ═══════════════════════════════════════════════════════════

# ── CONFIG (edit these) ───────────────────────────────────
CHANNEL="my-android-tot-2024"     # Must match browser UI channel ID
OPENAI_API_KEY=""                  # Your OpenAI key (or leave blank)
GEMINI_API_KEY=""                  # Your Gemini key (or leave blank)
# ─────────────────────────────────────────────────────────

NTFY="https://ntfy.sh"
CMD_TOPIC="${CHANNEL}-cmd"         # Browser → Device
RES_TOPIC="${CHANNEL}-res"         # Device → Browser
MEM_DIR="$HOME/tot/memory"
LOG_DIR="$HOME/tot/logs"
TMP_DIR="$HOME/tot/tmp"

mkdir -p "$MEM_DIR" "$LOG_DIR" "$TMP_DIR"

FACTS_FILE="$MEM_DIR/facts.json"
PREFS_FILE="$MEM_DIR/preferences.json"
HISTORY="$MEM_DIR/history.log"

# Initialize memory files
[ -f "$FACTS_FILE" ] || echo "{}" > "$FACTS_FILE"
[ -f "$PREFS_FILE" ] || echo "{}" > "$PREFS_FILE"

# ── Logging ───────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/$(date +%Y-%m-%d).log"; }

# ── Send to browser ───────────────────────────────────────
send_to_browser() {
  local payload="$1"
  curl -s -X POST "$NTFY/$RES_TOPIC" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null
}

# ── Memory ────────────────────────────────────────────────
mem_count() { jq 'length' "$FACTS_FILE" 2>/dev/null || echo 0; }

save_fact() {
  local key="$1" val="$2"
  local tmp=$(mktemp)
  jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$FACTS_FILE" > "$tmp" && mv "$tmp" "$FACTS_FILE"
  send_to_browser "{\"type\":\"memory_updated\",\"count\":$(mem_count)}"
}

get_facts_summary() {
  jq -r 'to_entries | map("- \(.key): \(.value)") | join("\n")' "$FACTS_FILE" 2>/dev/null | head -30
}

# ── Device Snapshot ───────────────────────────────────────
get_snapshot() {
  local bat wifi
  bat=$(termux-battery-status 2>/dev/null || echo '{"percentage":0,"status":"unknown"}')
  wifi=$(termux-wifi-connectioninfo 2>/dev/null | jq '{ssid:.ssid,rssi:.rssi}' 2>/dev/null || echo '{"ssid":"unknown"}')
  echo "{\"battery\":$bat,\"wifi\":$wifi}"
}

# ── Heartbeat ─────────────────────────────────────────────
send_heartbeat() {
  local snap mem
  snap=$(get_snapshot)
  mem=$(mem_count)
  send_to_browser "{\"type\":\"heartbeat\",\"battery\":$(echo $snap | jq .battery),\"wifi\":$(echo $snap | jq .wifi),\"mem_count\":$mem}"
}

# ── AI Reasoning ──────────────────────────────────────────
call_ai() {
  local user_msg="$1"
  local facts_ctx
  facts_ctx=$(get_facts_summary)

  local system_prompt="You are ToT, an AI that controls an Android device via Termux:API.
You remember everything about this device and never re-learn the same thing twice.

Known device facts:
$facts_ctx

Available actions (respond with ACTIONS:{...} at the end if needed):
- battery: termux-battery-status
- location: termux-location
- wifi: termux-wifi-connectioninfo
- photo: termux-camera-photo -c 0 ~/tot/tmp/photo.jpg
- torch_on: termux-torch on
- torch_off: termux-torch off
- sms_list: termux-sms-list -l 5
- call_log: termux-call-log -l 5
- contacts: termux-contact-list
- clipboard: termux-clipboard-get
- vibrate: termux-vibrate -d 300
- storage: df -h /storage/emulated/0
- speak [text]: termux-tts-speak '[text]'
- notify [title] [body]: termux-notification --title '[title]' --content '[body]'
- volume [level]: termux-volume music [0-15]
- brightness [level]: termux-brightness [0-255]
- sms_send [number] [msg]: termux-sms-send -n '[number]' '[msg]'

Respond in markdown. End with ACTIONS:{\"actions\":[{\"name\":\"...\",\"command\":\"...\"}]} if device action needed."

  if [ -n "$OPENAI_API_KEY" ]; then
    local payload
    payload=$(jq -n \
      --arg sys "$system_prompt" \
      --arg usr "$user_msg" \
      '{model:"gpt-4o-mini",messages:[{role:"system",content:$sys},{role:"user",content:$usr}],max_tokens:800}')
    curl -s https://api.openai.com/v1/chat/completions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" | jq -r '.choices[0].message.content // "Error calling AI"'

  elif [ -n "$GEMINI_API_KEY" ]; then
    local full_prompt="$system_prompt\n\nUser: $user_msg"
    local payload
    payload=$(jq -n --arg p "$full_prompt" '{contents:[{parts:[{text:$p}]}]}')
    curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" | jq -r '.candidates[0].content.parts[0].text // "Error calling Gemini"'

  else
    # Rule-based fallback
    echo "🤖 **ToT** (rule-based mode — set API key for full AI)\n\nI received: *$user_msg*"
    # Simple keyword detection
    case "${user_msg,,}" in
      *battery*) echo 'ACTIONS:{"actions":[{"name":"battery","command":"termux-battery-status"}]}' ;;
      *location*|*gps*) echo 'ACTIONS:{"actions":[{"name":"location","command":"termux-location"}]}' ;;
      *photo*|*camera*) echo 'ACTIONS:{"actions":[{"name":"photo","command":"termux-camera-photo -c 0 ~/tot/tmp/photo.jpg"}]}' ;;
      *torch on*|*flashlight on*) echo 'ACTIONS:{"actions":[{"name":"torch_on","command":"termux-torch on"}]}' ;;
      *torch off*|*flashlight off*) echo 'ACTIONS:{"actions":[{"name":"torch_off","command":"termux-torch off"}]}' ;;
      *sms*) echo 'ACTIONS:{"actions":[{"name":"sms_list","command":"termux-sms-list -l 5"}]}' ;;
      *vibrate*) echo 'ACTIONS:{"actions":[{"name":"vibrate","command":"termux-vibrate -d 500"}]}' ;;
      *wifi*) echo 'ACTIONS:{"actions":[{"name":"wifi","command":"termux-wifi-connectioninfo"}]}' ;;
    esac
  fi
}

# ── Execute Device Action ─────────────────────────────────
run_action() {
  local name="$1" cmd="$2"
  log "▶ Action: $name  →  $cmd"

  send_to_browser "{\"type\":\"action_start\",\"action\":\"$name\",\"command\":$(echo "$cmd" | jq -Rs .)}"

  local output exit_code
  output=$(eval "$cmd" 2>&1)
  exit_code=$?

  local success="true"
  [ $exit_code -ne 0 ] && success="false"

  # Try to parse as JSON
  local out_json
  if echo "$output" | jq . > /dev/null 2>&1; then
    out_json=$(echo "$output" | jq .)
  else
    out_json=$(echo "$output" | jq -Rs .)
  fi

  local snap
  snap=$(get_snapshot)

  send_to_browser "{\"type\":\"action_result\",\"action\":\"$name\",\"success\":$success,\"output\":$out_json,\"device\":$snap}"

  # Save successful action to memory
  if [ "$success" = "true" ]; then
    save_fact "action_${name}" "$cmd"
    log "✅ $name succeeded"
  else
    save_fact "error_${name}" "Failed: $output — cmd: $cmd"
    log "❌ $name failed: $output"
  fi
}

# ── Process Incoming Message ──────────────────────────────
process_message() {
  local raw="$1"
  local msg_type user_msg

  msg_type=$(echo "$raw" | jq -r '.type // "chat"')
  log "Received: type=$msg_type"

  case "$msg_type" in
    ping)
      send_heartbeat
      ;;

    chat)
      user_msg=$(echo "$raw" | jq -r '.message // ""')
      [ -z "$user_msg" ] && return

      log "User: $user_msg"
      echo "[$(date '+%H:%M:%S')] USER: $user_msg" >> "$HISTORY"

      # Call AI
      local ai_full
      ai_full=$(call_ai "$user_msg")

      # Split response from actions
      local ai_response actions_json
      if echo "$ai_full" | grep -q "ACTIONS:{"; then
        ai_response=$(echo "$ai_full" | sed 's/ACTIONS:{.*//')
        actions_json=$(echo "$ai_full" | grep -o 'ACTIONS:{.*' | sed 's/ACTIONS://')
      else
        ai_response="$ai_full"
        actions_json=""
      fi

      # Send text response to browser
      local resp_escaped
      resp_escaped=$(echo "$ai_response" | jq -Rs .)
      send_to_browser "{\"type\":\"response\",\"text\":$resp_escaped}"
      echo "[$(date '+%H:%M:%S')] TOT: $ai_response" >> "$HISTORY"

      # Execute actions
      if [ -n "$actions_json" ]; then
        local action_count
        action_count=$(echo "$actions_json" | jq '.actions | length' 2>/dev/null || echo 0)
        for i in $(seq 0 $((action_count - 1))); do
          local a_name a_cmd
          a_name=$(echo "$actions_json" | jq -r ".actions[$i].name")
          a_cmd=$(echo "$actions_json"  | jq -r ".actions[$i].command")
          run_action "$a_name" "$a_cmd"
        done
      fi

      # Send updated snapshot
      send_to_browser "{\"type\":\"device_update\",\"device\":$(get_snapshot)}"
      ;;

    voice_b64)
      # Decode audio and transcribe
      local audio_b64 audio_path
      audio_b64=$(echo "$raw" | jq -r '.audio // ""')
      audio_path="$TMP_DIR/voice_input.webm"
      echo "$audio_b64" | base64 -d > "$audio_path" 2>/dev/null

      if [ -n "$OPENAI_API_KEY" ]; then
        local transcript
        transcript=$(curl -s https://api.openai.com/v1/audio/transcriptions \
          -H "Authorization: Bearer $OPENAI_API_KEY" \
          -F file="@$audio_path" -F model="whisper-1" | jq -r '.text // ""')
        # Process transcription as chat
        local fake_msg
        fake_msg=$(jq -n --arg t "$transcript" '{type:"chat",message:$t}')
        process_message "$fake_msg"
      else
        send_to_browser "{\"type\":\"response\",\"text\":\"🎤 Voice received. Set OPENAI_API_KEY in listener.sh for transcription.\"}"
      fi
      ;;
  esac
}

# ── Main Loop ─────────────────────────────────────────────
log "🤖 ToT Listener starting..."
log "📡 Channel: $CHANNEL"
log "🧠 Memory: $(mem_count) facts loaded"
log "🌐 Listening on: $NTFY/$CMD_TOPIC"

# Announce online
send_to_browser "{\"type\":\"heartbeat\",\"status\":\"online\",\"mem_count\":$(mem_count)}"
send_heartbeat

# Heartbeat every 30s in background
(while true; do sleep 30; send_heartbeat; done) &

log "✅ Ready. Waiting for commands from browser..."

# ── SSE Listener (real-time, no polling) ──────────────────
curl -s "${NTFY}/${CMD_TOPIC}/sse" | while IFS= read -r line; do
  if [[ "$line" == data:* ]]; then
    raw_data="${line#data: }"
    # Extract the message field from ntfy SSE envelope
    inner=$(echo "$raw_data" | jq -r '.message // empty' 2>/dev/null)
    if [ -n "$inner" ]; then
      process_message "$inner"
    fi
  fi
done

log "⚠️ SSE stream ended. Restarting in 5s..."
sleep 5
exec "$0"  # Restart