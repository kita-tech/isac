#!/bin/bash
# resolve-project.sh
# 作業ディレクトリからプロジェクトIDを解決し、Typoチェックを行う
#
# 出力形式（JSON）:
# {
#   "project_id": "...",
#   "source": "local|global|env|default",
#   "team_id": "...",
#   "warning": "...",
#   "suggestions": []
# }

set -e

# 環境変数
ISAC_GLOBAL_DIR="${ISAC_GLOBAL_DIR:-$HOME/.isac}"
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# グローバル設定からMemory URLを取得
if [ -z "${MEMORY_SERVICE_URL:-}" ] && [ -f "${ISAC_GLOBAL_DIR}/config.yaml" ]; then
    CONFIGURED_URL=$(grep -E "^memory_service_url:" "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/memory_service_url:[[:space:]]*//' | tr -d '"' || true)
    if [ -n "$CONFIGURED_URL" ]; then
        MEMORY_URL="$CONFIGURED_URL"
    fi
fi

LOCAL_CONFIG=".isac.yaml"
CURRENT_DIR="$(pwd)"

# 結果を格納する変数
PROJECT_ID=""
TEAM_ID=""
SOURCE=""
WARNING=""
SUGGESTIONS="[]"

# JSON出力関数
output_json() {
    echo "{\"project_id\":\"$PROJECT_ID\",\"source\":\"$SOURCE\",\"team_id\":\"$TEAM_ID\",\"warning\":\"$WARNING\",\"suggestions\":$SUGGESTIONS}"
}

# .isac.yaml を親ディレクトリまで探索
find_isac_yaml() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.isac.yaml" ]; then
            echo "$dir/.isac.yaml"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# 1. ローカル設定ファイル (.isac.yaml) をチェック（親ディレクトリも探索）
ISAC_YAML=$(find_isac_yaml 2>/dev/null || true)

if [ -n "$ISAC_YAML" ] && [ -f "$ISAC_YAML" ]; then
    PROJECT_ID=$(grep -E '^project_id:' "$ISAC_YAML" 2>/dev/null | sed 's/^project_id:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'" || echo "")
    TEAM_ID=$(grep -E '^team_id:' "$ISAC_YAML" 2>/dev/null | sed 's/^team_id:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'" || echo "")
    if [ -n "$PROJECT_ID" ]; then
        SOURCE="local"
    fi
fi

# 2. 環境変数 CLAUDE_PROJECT
if [ -z "$PROJECT_ID" ] && [ -n "${CLAUDE_PROJECT:-}" ]; then
    PROJECT_ID="$CLAUDE_PROJECT"
    SOURCE="env"
fi

# 3. グローバル設定ファイル (~/.isac/config.yaml) をチェック
if [ -z "$PROJECT_ID" ] && [ -f "${ISAC_GLOBAL_DIR}/config.yaml" ]; then
    # デフォルトプロジェクト
    DEFAULT_PROJECT=$(grep -E '^default_project:' "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/default_project:[[:space:]]*//' | tr -d '"' || echo "")
    if [ -n "$DEFAULT_PROJECT" ]; then
        PROJECT_ID="$DEFAULT_PROJECT"
        SOURCE="global"
    fi

    # グローバル Team ID
    if [ -z "$TEAM_ID" ]; then
        TEAM_ID=$(grep -E '^team_id:' "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/team_id:[[:space:]]*//' | tr -d '"' || echo "")
    fi
fi

# 4. デフォルト値
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID="default"
    SOURCE="default"
    WARNING="プロジェクトが設定されていません。'isac init' で初期化するか、.isac.yaml を作成してください。"
fi

# 5. Memory Service でTypoチェック
if [ "$SOURCE" != "default" ] && curl -s --connect-timeout 1 "$MEMORY_URL/health" > /dev/null 2>&1; then
    SUGGEST_RESPONSE=$(curl -s --max-time 3 "$MEMORY_URL/projects/suggest?name=$PROJECT_ID" 2>/dev/null || echo "{}")

    EXACT_MATCH=$(echo "$SUGGEST_RESPONSE" | jq -r '.exact_match // false' 2>/dev/null || echo "false")

    if [ "$EXACT_MATCH" = "false" ]; then
        SUGGESTIONS=$(echo "$SUGGEST_RESPONSE" | jq -c '.suggestions // []' 2>/dev/null || echo "[]")
        SUGGESTION_COUNT=$(echo "$SUGGESTIONS" | jq 'length' 2>/dev/null || echo "0")

        if [ "$SUGGESTION_COUNT" -gt 0 ]; then
            FIRST_SUGGESTION=$(echo "$SUGGESTIONS" | jq -r '.[0].project_id' 2>/dev/null || echo "")
            WARNING="プロジェクト '$PROJECT_ID' は登録されていません。もしかして: $FIRST_SUGGESTION ?"
        fi
    fi
fi

# 結果を出力
output_json
