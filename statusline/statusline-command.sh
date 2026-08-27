#!/bin/sh
# ISAC statusLine command for Claude Code CLI
# Shows: [project_id] [Memory:ON|OFF] [model] [5h:NN% ↻remaining] ~/path/to/dir

input=$(cat)

# Current working directory (abbreviated with ~ for home)
cwd=$(printf '%s\n' "$input" | jq -r '.cwd')
home="$HOME"
case "$cwd" in
  "$home"*)
    display_dir="~${cwd#$home}"
    ;;
  *)
    display_dir="$cwd"
    ;;
esac

# Model display name
model_name=$(printf '%s\n' "$input" | jq -r '.model.display_name // empty')

# Rate limit: 5-hour window usage and time until reset.
# Only present for Pro/Max subscriptions, and only after the first API
# response in the session — omit the segment entirely when absent.
usage_pct=$(printf '%s\n' "$input" | jq -r '(.rate_limits.five_hour.used_percentage // empty) | round')
resets_at=$(printf '%s\n' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
usage_part=""
if [ -n "$usage_pct" ]; then
  usage_part="5h:${usage_pct}%"
  if [ -n "$resets_at" ]; then
    now=$(date +%s)
    rem=$((resets_at - now))
    if [ "$rem" -gt 0 ]; then
      h=$((rem / 3600))
      m=$(((rem % 3600) / 60))
      if [ "$h" -gt 0 ]; then
        usage_part="${usage_part} ↻${h}h${m}m"
      else
        usage_part="${usage_part} ↻${m}m"
      fi
    fi
  fi
fi

# Resolve project ID from .isac.yaml (search up from cwd)
project_id=""
dir="$cwd"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/.isac.yaml" ]; then
    project_id=$(grep -E '^project_id:' "$dir/.isac.yaml" 2>/dev/null | sed 's/^project_id:[[:space:]]*//' | tr -d '"' | tr -d "'" || true)
    break
  fi
  dir=$(dirname "$dir")
done

# Memory Service health check (very short timeout to keep statusline fast)
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
if curl -s --connect-timeout 0.3 --max-time 0.5 "$MEMORY_URL/health" > /dev/null 2>&1; then
  memory_status="ON"
else
  memory_status="OFF"
fi

# Build output
parts=""
if [ -n "$project_id" ]; then
  parts="[$project_id]"
fi
parts="$parts [Memory:$memory_status]"
if [ -n "$model_name" ]; then
  parts="$parts [$model_name]"
fi
if [ -n "$usage_part" ]; then
  parts="$parts [$usage_part]"
fi
parts="$parts $display_dir"

echo "$parts"
