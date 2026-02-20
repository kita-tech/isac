#!/bin/sh
# ISAC statusLine command for Claude Code CLI
# Shows: [project_id] [Memory:ON|OFF] ~/path/to/dir

input=$(cat)

# Current working directory (abbreviated with ~ for home)
cwd=$(echo "$input" | jq -r '.cwd')
home="$HOME"
case "$cwd" in
  "$home"*)
    display_dir="~${cwd#$home}"
    ;;
  *)
    display_dir="$cwd"
    ;;
esac

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
parts="$parts [Memory:$memory_status] $display_dir"

echo "$parts"
