#!/bin/bash
# on-session-start.sh
# セッション開始時に軽量ステータスを自動表示
#
# 表示項目（3つに限定）:
#   1. Memory Service ヘルス
#   2. ISACアップデート通知（キャッシュのみ参照、git fetch禁止）
#   3. 現在のプロジェクトID
#
# パフォーマンス制約:
#   - git fetch は絶対に実行しない
#   - 全体で2秒以内に完了
#   - 全コマンドに || true で非ブロッキング

set -e

# 環境変数
ISAC_GLOBAL_DIR="${ISAC_GLOBAL_DIR:-$HOME/.isac}"
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# グローバル設定からMemory URLを取得
if [ -z "${MEMORY_SERVICE_URL:-}" ] && [ -f "${ISAC_GLOBAL_DIR}/config.yaml" ]; then
    CONFIGURED_URL=$(grep -E "^memory_service_url:" "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/memory_service_url:[[:space:]]*//' | tr -d '"' || true)
    if [ -n "${CONFIGURED_URL}" ]; then
        MEMORY_URL="${CONFIGURED_URL}"
    fi
fi

# ========================================
# 1. Memory Service ヘルスチェック
# ========================================
MEMORY_STATUS=""
if curl -s --connect-timeout 1 "${MEMORY_URL}/health" > /dev/null 2>&1; then
    MEMORY_STATUS="ok"
else
    MEMORY_STATUS="down"
fi

# ========================================
# 2. ISACアップデート通知（キャッシュのみ）
# ========================================
UPDATE_STATUS=""
ISAC_SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ISAC_CACHE_FILE="${ISAC_GLOBAL_DIR}/.version_cache"

if [ -d "${ISAC_SOURCE_DIR}/.git" ] && [ -f "${ISAC_CACHE_FILE}" ]; then
    LOCAL_HEAD=$(git -C "${ISAC_SOURCE_DIR}" rev-parse --short HEAD 2>/dev/null || true)
    CACHED_REMOTE=$(cat "${ISAC_CACHE_FILE}" 2>/dev/null || true)

    if [ -n "${LOCAL_HEAD}" ] && [ -n "${CACHED_REMOTE}" ]; then
        if [ "${LOCAL_HEAD}" = "${CACHED_REMOTE}" ]; then
            UPDATE_STATUS="up_to_date"
        else
            UPDATE_STATUS="update_available"
        fi
    else
        UPDATE_STATUS="unknown"
    fi
else
    UPDATE_STATUS="unknown"
fi

# ========================================
# 3. 現在のプロジェクトID
# ========================================
PROJECT_ID=""

# .isac.yaml を親ディレクトリまで探索
find_project_id() {
    local dir="${PWD}"
    while [ "${dir}" != "/" ]; do
        if [ -f "${dir}/.isac.yaml" ]; then
            grep -E '^project_id:' "${dir}/.isac.yaml" 2>/dev/null | sed 's/^project_id:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'" || true
            return 0
        fi
        dir="$(dirname "${dir}")"
    done
    return 1
}

PROJECT_ID=$(find_project_id 2>/dev/null || true)

# ========================================
# 出力
# ========================================

# 異常項目を収集
HAS_WARNING=false

WARN_MEMORY=""
if [ "${MEMORY_STATUS}" = "down" ]; then
    WARN_MEMORY="  Memory Service: Not connected (${MEMORY_URL})"
    HAS_WARNING=true
fi

WARN_UPDATE=""
if [ "${UPDATE_STATUS}" = "update_available" ]; then
    WARN_UPDATE="  ISAC: Update available (run 'isac status' for details)"
    HAS_WARNING=true
fi

WARN_PROJECT=""
if [ -z "${PROJECT_ID}" ]; then
    WARN_PROJECT="  Project: Not configured (run 'isac init')"
    HAS_WARNING=true
fi

# 出力フォーマット
if [ "${HAS_WARNING}" = false ]; then
    # 正常時: 1行サマリー
    PROJECT_DISPLAY="${PROJECT_ID:-default}"
    UPDATE_DISPLAY="up to date"
    if [ "${UPDATE_STATUS}" = "unknown" ]; then
        UPDATE_DISPLAY="unknown"
    fi
    echo "ISAC: Memory connected | project: ${PROJECT_DISPLAY} | ${UPDATE_DISPLAY}"
else
    # 異常時: 問題項目のみ警告表示
    echo "ISAC Status:"
    [ -n "${WARN_MEMORY}" ] && echo "${WARN_MEMORY}" || true
    [ -n "${WARN_UPDATE}" ] && echo "${WARN_UPDATE}" || true
    [ -n "${WARN_PROJECT}" ] && echo "${WARN_PROJECT}" || true
fi

exit 0
