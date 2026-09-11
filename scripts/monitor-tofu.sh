#!/usr/bin/env bash
# Monitor OpenTofu operations in real-time
# Usage: ./monitor-tofu.sh [log-file]
#        Default: /tmp/tofu.log
set -euo pipefail

LOG_FILE="${1:-/tmp/tofu.log}"

echo "=== OpenTofu Real-Time Monitor ==="
echo "Monitoring: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""
echo "Legend:"
echo "  [STATE]  - State refresh operations"
echo "  [CHANGE] - Creating/Modifying/Destroying resources"
echo "  [ERROR]  - Timeout or failure detected"
echo "  [API]    - HTTP API calls"
echo ""
echo "---"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Waiting for log file to be created..."
  while [[ ! -f "$LOG_FILE" ]]; do
    sleep 1
  done
fi

tail -f "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
  if [[ "$line" =~ "Refreshing state" ]]; then
    echo "[STATE]  $line"
  elif [[ "$line" =~ "context deadline" || "$line" =~ "deadline exceeded" ]]; then
    echo "[ERROR]  $line"
  elif [[ "$line" =~ "timeout" ]] && [[ "$line" =~ [Ee]rror ]]; then
    echo "[ERROR]  $line"
  elif [[ "$line" =~ "Creating..." || "$line" =~ "Modifying..." || "$line" =~ "Destroying..." ]]; then
    echo "[CHANGE] $line"
  elif [[ "$line" =~ "Creation complete" || "$line" =~ "Modifications complete" || "$line" =~ "Destruction complete" ]]; then
    echo "[CHANGE] $line"
  elif [[ "$line" =~ "GET " || "$line" =~ "POST " || "$line" =~ "PUT " || "$line" =~ "DELETE " ]]; then
    echo "[API]    $line"
  elif [[ "$line" =~ "Error:" || "$line" =~ "error:" ]]; then
    echo "[ERROR]  $line"
  fi
done
