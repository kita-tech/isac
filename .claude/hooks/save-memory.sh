#!/bin/bash
# save-memory.sh
# Claudeが出力した分類JSONをMemory Serviceに保存
#
# 使用方法: on-stop.sh (prompt type) の後に実行
# 標準入力からJSONを受け取り、Memory Serviceに送信

set -e

# 環境変数
ISAC_GLOBAL_DIR="${ISAC_GLOBAL_DIR:-$HOME/.isac}"
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# グローバル設定からMemory URLを取得
if [ -z "${MEMORY_SERVICE_URL:-}" ] && [ -f "${ISAC_GLOBAL_DIR}/config.yaml" ]; then
    CONFIGURED_URL=$(grep -E "^memory_service_url:" "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/memory_service_url:[[:space:]]*//' | tr -d '"' || true)
    if [ -n "$CONFIGURED_URL" ]; then
        MEMORY_URL="$CONFIGURED_URL"
    fi
fi

# Memory Serviceが起動していない場合はスキップ
if ! curl -s --connect-timeout 1 "$MEMORY_URL/health" > /dev/null 2>&1; then
    exit 0
fi

# プロジェクトIDを解決
PROJECT_ID="default"
TEAM_ID=""
if [ -f "$SCRIPT_DIR/resolve-project.sh" ]; then
    RESOLVE_RESULT=$(bash "$SCRIPT_DIR/resolve-project.sh" 2>/dev/null || echo '{"project_id":"default","team_id":""}')
    PROJECT_ID=$(echo "$RESOLVE_RESULT" | jq -r '.project_id // "default"' 2>/dev/null || echo "default")
    TEAM_ID=$(echo "$RESOLVE_RESULT" | jq -r '.team_id // ""' 2>/dev/null || echo "")
fi

# ユーザー情報取得
USER_ID=$(git config user.email 2>/dev/null || echo "${USER:-unknown}")

# 標準入力からJSONを読み取り
INPUT=$(cat)

# JSON部分を抽出（```json ... ``` の中身）
JSON_CONTENT=$(echo "$INPUT" | sed -n '/```json/,/```/p' | sed '1d;$d')

# JSONが見つからない場合は終了
if [ -z "$JSON_CONTENT" ]; then
    # フォールバック: 生のJSONを試す
    JSON_CONTENT=$(echo "$INPUT" | jq -c '.' 2>/dev/null || echo "")
    if [ -z "$JSON_CONTENT" ]; then
        exit 0
    fi
fi

# skipフラグをチェック
SKIP=$(echo "$JSON_CONTENT" | jq -r '.skip // false' 2>/dev/null || echo "false")
if [ "$SKIP" = "true" ]; then
    exit 0
fi

# 各フィールドを抽出
TYPE=$(echo "$JSON_CONTENT" | jq -r '.type // "work"' 2>/dev/null || echo "work")
CATEGORY=$(echo "$JSON_CONTENT" | jq -r '.category // "other"' 2>/dev/null || echo "other")
TAGS=$(echo "$JSON_CONTENT" | jq -c '.tags // []' 2>/dev/null || echo "[]")
SUMMARY=$(echo "$JSON_CONTENT" | jq -r '.summary // ""' 2>/dev/null || echo "")
IMPORTANCE=$(echo "$JSON_CONTENT" | jq -r '.importance // 0.5' 2>/dev/null || echo "0.5")

# サマリが空の場合はスキップ
if [ -z "$SUMMARY" ]; then
    exit 0
fi

# importanceの範囲チェック
if ! echo "$IMPORTANCE" | grep -qE '^[0-9]*\.?[0-9]+$'; then
    IMPORTANCE="0.5"
fi

# Memory Serviceに保存
curl -s --max-time 5 -X POST "$MEMORY_URL/store" \
    -H "Content-Type: application/json" \
    -d "{
        \"content\": \"$SUMMARY\",
        \"type\": \"$TYPE\",
        \"importance\": $IMPORTANCE,
        \"scope\": \"project\",
        \"scope_id\": \"$PROJECT_ID\",
        \"category\": \"$CATEGORY\",
        \"tags\": $TAGS,
        \"metadata\": {
            \"source\": \"ai-classification\",
            \"user\": \"$USER_ID\",
            \"team_id\": \"$TEAM_ID\"
        }
    }" > /dev/null 2>&1 || true

echo "[ISAC] Memory saved: $SUMMARY (category: $CATEGORY)"
