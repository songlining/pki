#!/usr/bin/env bash
set -euo pipefail

# Visual validation for a presenterm demo deck.
#
# Uses a PRIVATE tmux socket/server so validation never attaches to or leaves
# state in the user's normal tmux server. Cleanup kills only this private
# socket/session and presenterm processes launched for THIS EXACT deck path —
# never a broad `pkill -f presenterm`, which would destroy unrelated presenterm
# sessions the user has open.
#
# Vendored from writer-reviewer-harness/scripts/validate-presenterm-visual.sh.
# Local change: the validation viewport defaults to the user's REAL terminal
# size (via tput) instead of a fixed 120x40, so layouts that clip at the user's
# actual launch dimensions are caught. Override with PTERM_VALIDATE_COLS/LINES.
#
# Usage: scripts/validate-deck-visual.sh [path/to/deck.md]
#   default deck path: presenterm/deck.md (relative to the skill root)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECK_PATH="${1:-presenterm/deck.md}"
DECK_ABS="$ROOT_DIR/$DECK_PATH"
SESSION="pterm_validate_$$"
SOCKET="pterm-validate-$$"
OUT_DIR="$ROOT_DIR/output"
OUT="$OUT_DIR/presenterm-visual-capture.txt"
ERR="$OUT_DIR/presenterm-visual-capture.err"

mkdir -p "$OUT_DIR"
: > "$OUT"
: > "$ERR"

cleanup() {
  # Kill the private tmux server/session only; never touch the user's default tmux server.
  tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  # Kill only presenterm processes launched for this exact deck path.
  pkill -f "presenterm.*-x.*${DECK_PATH}" >/dev/null 2>&1 || true
  pkill -f "presenterm.*-x.*${DECK_ABS}" >/dev/null 2>&1 || true
  # kitty --detach can leave a wrapper/window process even after the private tmux
  # server exits. Kill only Kitty processes whose command line contains this
  # private socket name; never touch unrelated Kitty windows.
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    kill "$pid" >/dev/null 2>&1 || true
  done < <(ps -axo pid=,args= | awk -v sock="$SOCKET" '/kitty/ && index($0, sock) {print $1}')
}
trap cleanup EXIT INT TERM HUP

cleanup

[ -f "$DECK_ABS" ] || { echo "deck not found: $DECK_ABS" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "tmux not installed" >&2; exit 1; }
command -v kitty >/dev/null 2>&1 || { echo "kitty not installed" >&2; exit 1; }
command -v presenterm >/dev/null 2>&1 || { echo "presenterm not installed: brew install presenterm" >&2; exit 1; }

# Validation viewport. Prefer an explicit override, then the user's real terminal
# size, then a conservative fallback. Matching the real size catches clipping that
# a fixed 120x40 would hide.
W="${PTERM_VALIDATE_COLS:-$(tput cols 2>/dev/null || echo 120)}"
H="${PTERM_VALIDATE_LINES:-$(tput lines 2>/dev/null || echo 40)}"
echo "validation_viewport=${W}x${H}" | tee -a "$OUT"

# Start a private tmux session. If launched outside Kitty, put that private tmux
# session in a detached Kitty window. Because the session exits via cleanup, the
# Kitty window closes as well.
if [ "${TERM:-}" = "xterm-kitty" ] || [ -n "${KITTY_PID:-}" ]; then
  tmux -L "$SOCKET" new-session -d -s "$SESSION" -x "$W" -y "$H" -c "$ROOT_DIR"
else
  kitty --detach tmux -L "$SOCKET" new-session -s "$SESSION" -x "$W" -y "$H" -c "$ROOT_DIR"
  sleep 2
fi

tmux -L "$SOCKET" has-session -t "$SESSION" >/dev/null 2>&1 || {
  echo "ERROR: private tmux session did not start" | tee -a "$ERR" >&2
  exit 1
}

tmux -L "$SOCKET" send-keys -t "$SESSION" "cd '$ROOT_DIR' && presenterm -x '$DECK_PATH'" Enter
sleep 3

TOTAL_SLIDES="$(grep -c '<!-- end_slide -->' "$DECK_ABS")"
echo "deck_end_slide_markers=$TOTAL_SLIDES" | tee -a "$OUT"

capture_current() {
  local label="$1"
  echo "=== $label ===" | tee -a "$OUT"
  tmux -L "$SOCKET" capture-pane -t "$SESSION" -p | cat -s | tee -a "$OUT"
  echo "" | tee -a "$OUT"
}

capture_current "SLIDE 1"

# Right/Space can be consumed by incremental list reveals. Walk until the footer
# slide number changes or until a generous upper bound; capture each distinct
# footer slide number exactly once. A fixed N+1 loop would under-count whenever a
# reveal eats a keypress — this footer-tracking walk does not.
seen=" 1 "
keypresses=0
while [ "$keypresses" -lt 120 ]; do
  tmux -L "$SOCKET" send-keys -t "$SESSION" Right
  sleep 0.25
  keypresses=$((keypresses + 1))
  CAP="$(tmux -L "$SOCKET" capture-pane -t "$SESSION" -p | cat -s)"
  FOOTER="$(printf '%s\n' "$CAP" | grep -Eo '[0-9]+ / [0-9]+' | tail -1 | awk '{print $1}' || true)"
  [ -n "$FOOTER" ] || continue
  case "$seen" in
    *" $FOOTER "*) ;;
    *)
      seen="$seen$FOOTER "
      echo "=== SLIDE $FOOTER ===" | tee -a "$OUT"
      printf '%s\n' "$CAP" | tee -a "$OUT"
      echo "" | tee -a "$OUT"
      ;;
  esac
  # Stop after seeing the final slide number.
  if printf '%s\n' "$CAP" | grep -q "${TOTAL_SLIDES} / ${TOTAL_SLIDES}"; then
    break
  fi
done

# Hard cleanup before reporting success.
cleanup
sleep 0.5

LEFTOVERS="$(ps -axo pid=,ppid=,comm=,args= | grep -E "presenterm.*-x.*${DECK_PATH}|tmux.*${SOCKET}|kitty.*${SOCKET}" | grep -v grep || true)"
if [ -n "$LEFTOVERS" ]; then
  echo "ERROR: validation leftovers remain:" | tee -a "$ERR" >&2
  echo "$LEFTOVERS" | tee -a "$ERR" >&2
  exit 1
fi

echo "Visual capture written to $OUT"
echo "Cleanup verified: no private tmux/kitty/presenterm validation processes remain."
