#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# 1. Environment bootstrap
# =========================================================

export FNM_PATH="$HOME/.local/share/fnm"
export PATH="$FNM_PATH:$PATH"
eval "$("$FNM_PATH/fnm" env --shell bash)"

command -v claude >/dev/null || {
  echo "ERROR: claude not found" >&2
  exit 127
}

# =========================================================
# 2. Config
# =========================================================

WORK_DIR="/opt/zenaflow"
SESSION_DIR="/run/user/$(id -u)/zenaflow"
SESSION_FILE="$SESSION_DIR/claude.session"
TTL_SEC=43200

mkdir -p "$SESSION_DIR"
PROMPT="$*"

# =========================================================
# 3. Helpers
# =========================================================

new_session_id() { uuidgen; }

run_new() {
  claude -p --dangerously-skip-permissions \
    --session-id "$1" "$PROMPT"
}

run_resume() {
  claude -p --dangerously-skip-permissions \
    --resume "$1" "$PROMPT"
}

# =========================================================
# 4. Reset
# =========================================================

if [[ "$PROMPT" == "/reset" ]]; then
  rm -f "$SESSION_FILE"
  echo "Session forgotten!"
  exit 0
fi

# =========================================================
# 5. Session resolution
# =========================================================

MODE=""
SESSION_ID=""

if [[ "$PROMPT" == "/task "* || "$PROMPT" == "/new "* ]]; then
  PROMPT="${PROMPT#"/task "}"
  PROMPT="${PROMPT#"/new "}"
  SESSION_ID="$(new_session_id)"
  MODE="new"
  echo "$SESSION_ID" >"$SESSION_FILE"

else
  if [[ -f "$SESSION_FILE" ]]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE") ))
    if (( AGE < TTL_SEC )); then
      SESSION_ID="$(cat "$SESSION_FILE")"
      MODE="resume"
      touch "$SESSION_FILE"
    fi
  fi

  if [[ -z "${MODE:-}" ]]; then
    SESSION_ID="$(new_session_id)"
    MODE="new"
    echo "$SESSION_ID" >"$SESSION_FILE"
  fi
fi

# =========================================================
# 6. Execute (with busy-session handling)
# =========================================================

cd "$WORK_DIR"

if [[ "$MODE" == "new" ]]; then
  run_new "$SESSION_ID"
else
  if OUTPUT=$(run_resume "$SESSION_ID" 2>&1); then
    echo "$OUTPUT"
    exit 0
  fi

  if echo "$OUTPUT" | grep -qi "already in use"; then
    sleep 2
    run_resume "$SESSION_ID"
    exit 0
  fi

  echo "WARN: Session invalid. Resetting..." >&2
  rm -f "$SESSION_FILE"
  SESSION_ID="$(new_session_id)"
  echo "$SESSION_ID" >"$SESSION_FILE"
  run_new "$SESSION_ID"
fi
