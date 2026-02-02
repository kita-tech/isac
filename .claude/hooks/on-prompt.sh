#!/bin/bash
# on-prompt.sh
# プロンプト送信時にMemory Serviceから関連記憶を取得
#
# 使用方法: prompt_submit hookとして設定
# トークン予算: 2000 tokens (設定可能)

set -e

# 引数からクエリを取得
QUERY="${1:-}"

# 環境変数
ISAC_GLOBAL_DIR="${ISAC_GLOBAL_DIR:-$HOME/.isac}"
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
MAX_TOKENS="${MEMORY_MAX_TOKENS:-2000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# グローバル設定からMemory URLを取得
if [ -z "${MEMORY_SERVICE_URL:-}" ] && [ -f "${ISAC_GLOBAL_DIR}/config.yaml" ]; then
    CONFIGURED_URL=$(grep -E "^memory_service_url:" "${ISAC_GLOBAL_DIR}/config.yaml" 2>/dev/null | sed 's/memory_service_url:[[:space:]]*//' | tr -d '"' || true)
    if [ -n "$CONFIGURED_URL" ]; then
        MEMORY_URL="$CONFIGURED_URL"
    fi
fi

# クエリが空の場合はスキップ
if [ -z "$QUERY" ]; then
    exit 0
fi

# Memory Serviceが起動していない場合はスキップ
if ! curl -s --connect-timeout 1 "$MEMORY_URL/health" > /dev/null 2>&1; then
    exit 0
fi

# プロジェクトIDとTeam IDを解決
if [ -f "$SCRIPT_DIR/resolve-project.sh" ]; then
    RESOLVE_RESULT=$(bash "$SCRIPT_DIR/resolve-project.sh" 2>/dev/null || echo '{"project_id":"default","source":"default","team_id":""}')
    PROJECT_ID=$(echo "$RESOLVE_RESULT" | jq -r '.project_id // "default"' 2>/dev/null || echo "default")
    PROJECT_SOURCE=$(echo "$RESOLVE_RESULT" | jq -r '.source // "default"' 2>/dev/null || echo "default")
    PROJECT_WARNING=$(echo "$RESOLVE_RESULT" | jq -r '.warning // empty' 2>/dev/null || echo "")
    SUGGESTIONS=$(echo "$RESOLVE_RESULT" | jq -r '.suggestions // []' 2>/dev/null || echo "[]")
    TEAM_ID=$(echo "$RESOLVE_RESULT" | jq -r '.team_id // ""' 2>/dev/null || echo "")
else
    PROJECT_ID="default"
    PROJECT_SOURCE="default"
    PROJECT_WARNING="プロジェクトが設定されていません"
    SUGGESTIONS="[]"
    TEAM_ID=""
fi

# 警告がある場合は出力
if [ -n "$PROJECT_WARNING" ]; then
    echo ""
    echo "## ⚠️ プロジェクト設定の警告"
    echo "$PROJECT_WARNING"
    echo ""

    # 登録済みプロジェクトリストを表示
    PROJECTS=$(curl -s --max-time 3 "$MEMORY_URL/projects" 2>/dev/null || echo "[]")
    PROJECT_COUNT=$(echo "$PROJECTS" | jq 'length' 2>/dev/null || echo "0")

    if [ "$PROJECT_COUNT" -gt 0 ]; then
        echo "### 登録済みプロジェクト:"
        echo "$PROJECTS" | jq -r '.[] | "- \(.project_id) (memories: \(.memory_count), decisions: \(.decision_count))"' 2>/dev/null
        echo ""
        echo "設定方法: \`isac init <project-name>\` を実行"
    fi
    echo ""
fi

# コンテキスト取得（Team IDがあればヘッダーに追加）
CONTEXT=""
if [ -n "$TEAM_ID" ]; then
    CONTEXT=$(curl -s --max-time 5 "$MEMORY_URL/context/$PROJECT_ID" \
        --get \
        --data-urlencode "query=$QUERY" \
        --data-urlencode "max_tokens=$MAX_TOKENS" \
        -H "X-Team-Id: $TEAM_ID" \
        2>/dev/null || echo "")
else
    CONTEXT=$(curl -s --max-time 5 "$MEMORY_URL/context/$PROJECT_ID" \
        --get \
        --data-urlencode "query=$QUERY" \
        --data-urlencode "max_tokens=$MAX_TOKENS" \
        2>/dev/null || echo "")
fi

# レスポンスが空または無効な場合はスキップ
if [ -z "$CONTEXT" ] || [ "$CONTEXT" = "null" ] || [ "$CONTEXT" = "{}" ]; then
    exit 0
fi

# JSONパースエラーチェック
if ! echo "$CONTEXT" | jq empty 2>/dev/null; then
    exit 0
fi

# ヘッダー出力（コンテキストがある場合のみ）
HAS_CONTENT="false"

# グローバルナレッジを出力
GLOBAL=$(echo "$CONTEXT" | jq -r '.global_knowledge[]? | "- [\(.importance | tostring | .[0:3])] \(.summary // .content[0:100])"' 2>/dev/null)
if [ -n "$GLOBAL" ] && [ "$GLOBAL" != "null" ]; then
    echo ""
    echo "## 🌍 グローバルナレッジ"
    echo "$GLOBAL"
    HAS_CONTENT="true"
fi

# チームナレッジを出力
TEAM=$(echo "$CONTEXT" | jq -r '.team_knowledge[]? | "- [\(.importance | tostring | .[0:3])] \(.summary // .content[0:100])"' 2>/dev/null)
if [ -n "$TEAM" ] && [ "$TEAM" != "null" ]; then
    echo ""
    echo "## 👥 チームナレッジ"
    echo "$TEAM"
    HAS_CONTENT="true"
fi

# プロジェクト決定事項を出力
DECISIONS=$(echo "$CONTEXT" | jq -r '.project_decisions[]? | "- [\(.importance | tostring | .[0:3])] \(.summary // .content[0:100])"' 2>/dev/null)
if [ -n "$DECISIONS" ] && [ "$DECISIONS" != "null" ]; then
    echo ""
    echo "## 📋 プロジェクト決定事項"
    echo "$DECISIONS"
    HAS_CONTENT="true"
fi

# 最近の作業を出力
RECENT=$(echo "$CONTEXT" | jq -r '.project_recent[]? | "- \(.summary // .content[0:80]) (\(.created_by // "unknown"))"' 2>/dev/null)
if [ -n "$RECENT" ] && [ "$RECENT" != "null" ]; then
    echo ""
    echo "## 📝 最近の関連作業"
    echo "$RECENT"
    HAS_CONTENT="true"
fi

# トークン使用量とプロジェクト情報をログ（stderr）
TOKENS=$(echo "$CONTEXT" | jq -r '.total_tokens // 0' 2>/dev/null)
if [ "$TOKENS" != "0" ] && [ "$TOKENS" != "null" ]; then
    TEAM_INFO=""
    if [ -n "$TEAM_ID" ]; then
        TEAM_INFO=", team=$TEAM_ID"
    fi
    echo "" >&2
    echo "[ISAC Memory: project=$PROJECT_ID ($PROJECT_SOURCE)$TEAM_INFO, ${TOKENS} tokens]" >&2
fi
