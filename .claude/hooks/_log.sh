#!/bin/bash
# _log.sh - ISAC Hooks 共有ログ関数
#
# ISAC開発プロジェクトでのみログを記録する。
# 他プロジェクトではisac_log()は何もしない。

ISAC_LOG_FILE="${ISAC_GLOBAL_DIR:-$HOME/.isac}/logs/hooks.log"

isac_log() {
    local hook_name="$1"
    local message="$2"

    # ISAC開発プロジェクトでのみログを記録
    if [ ! -f "${CLAUDE_PROJECT_DIR:-}/bin/isac" ]; then
        return 0
    fi

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
    local log_dir
    log_dir=$(dirname "$ISAC_LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true
    echo "[$ts] [$hook_name] $message" >> "$ISAC_LOG_FILE" 2>/dev/null || true
}
