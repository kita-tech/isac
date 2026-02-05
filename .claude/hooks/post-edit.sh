#!/bin/bash
# post-edit.sh
# ファイル編集後に作業履歴をMemory Serviceに保存
#
# 使用方法: post_tool_execution hookとして設定（Edit/Write matcher）

set -e

# 引数からファイルパスを取得
FILE_PATH="${1:-}"

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

# ファイルパスが空の場合はスキップ
if [ -z "$FILE_PATH" ]; then
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
    TEAM_ID=$(echo "$RESOLVE_RESULT" | jq -r '.team_id // ""' 2>/dev/null || echo "")
else
    PROJECT_ID="default"
    TEAM_ID=""
fi

# ファイル名と拡張子を取得
FILENAME=$(basename "$FILE_PATH")
EXTENSION="${FILENAME##*.}"
DIRNAME=$(dirname "$FILE_PATH")

# 機密ファイルのスキップ（.env, credentials, secrets等）
case "$FILENAME" in
    .env|.env.*|*.pem|*.key|credentials.*|secrets.*|*secret*|*credential*)
        # 機密ファイルは記録しない
        exit 0
        ;;
esac

# 要約を生成
SUMMARY="ファイル編集: $FILENAME"

# ファイルタイプに応じた追加情報
case "$EXTENSION" in
    py)
        SUMMARY="Python: $FILENAME を編集"
        ;;
    js|ts|tsx|jsx)
        SUMMARY="JavaScript/TypeScript: $FILENAME を編集"
        ;;
    php)
        SUMMARY="PHP: $FILENAME を編集"
        ;;
    md)
        SUMMARY="ドキュメント: $FILENAME を編集"
        ;;
    yaml|yml)
        SUMMARY="設定: $FILENAME を編集"
        ;;
    json)
        SUMMARY="JSON: $FILENAME を編集"
        ;;
    sh)
        SUMMARY="シェルスクリプト: $FILENAME を編集"
        ;;
    go)
        SUMMARY="Go: $FILENAME を編集"
        ;;
    rs)
        SUMMARY="Rust: $FILENAME を編集"
        ;;
    rb)
        SUMMARY="Ruby: $FILENAME を編集"
        ;;
    java)
        SUMMARY="Java: $FILENAME を編集"
        ;;
    swift)
        SUMMARY="Swift: $FILENAME を編集"
        ;;
    kt|kts)
        SUMMARY="Kotlin: $FILENAME を編集"
        ;;
    c|h)
        SUMMARY="C: $FILENAME を編集"
        ;;
    cpp|hpp|cc|cxx)
        SUMMARY="C++: $FILENAME を編集"
        ;;
    css|scss|sass|less)
        SUMMARY="スタイル: $FILENAME を編集"
        ;;
    html|htm)
        SUMMARY="HTML: $FILENAME を編集"
        ;;
    sql)
        SUMMARY="SQL: $FILENAME を編集"
        ;;
    dockerfile|Dockerfile)
        SUMMARY="Docker: $FILENAME を編集"
        ;;
esac

# 機密情報フィルター（ファイルパスに機密情報が含まれていないかチェック）
if [ -f "$SCRIPT_DIR/sensitive-filter.sh" ]; then
    FILTER_RESULT=$(echo "$FILE_PATH" | bash "$SCRIPT_DIR/sensitive-filter.sh" 2>/dev/null || echo '{"is_sensitive":false}')
    IS_SENSITIVE=$(echo "$FILTER_RESULT" | jq -r '.is_sensitive // false' 2>/dev/null || echo "false")

    if [ "$IS_SENSITIVE" = "true" ]; then
        # 機密情報が含まれる場合はマスキング
        FILE_PATH=$(echo "$FILTER_RESULT" | jq -r '.filtered // ""' 2>/dev/null || echo "$FILE_PATH")
    fi
fi

# ユーザー情報取得（git configから）
USER_ID=$(git config user.email 2>/dev/null || echo "${USER:-unknown}")

# カテゴリとタグを自動推定
AUTO_CATEGORY="other"
AUTO_TAGS="[]"

# ファイルパスとディレクトリからカテゴリを推定
case "$DIRNAME" in
    *test*|*tests*|*spec*|*__tests__*)
        AUTO_CATEGORY="test"
        ;;
    *doc*|*docs*|*documentation*)
        AUTO_CATEGORY="docs"
        ;;
    *component*|*components*|*ui*|*view*|*views*|*pages*)
        AUTO_CATEGORY="ui"
        ;;
    *api*|*routes*|*endpoint*|*handlers*)
        AUTO_CATEGORY="api"
        ;;
    *infra*|*deploy*|*ci*|*cd*|*.github*)
        AUTO_CATEGORY="infra"
        ;;
    *db*|*database*|*migration*|*models*|*schema*)
        AUTO_CATEGORY="database"
        ;;
    *auth*|*security*|*permission*)
        AUTO_CATEGORY="security"
        ;;
esac

# 拡張子からタグを推定
case "$EXTENSION" in
    py)
        AUTO_TAGS='["python"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="backend"
        ;;
    js|ts)
        AUTO_TAGS='["javascript"]'
        ;;
    tsx|jsx)
        AUTO_TAGS='["react"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="frontend"
        ;;
    vue)
        AUTO_TAGS='["vue"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="frontend"
        ;;
    go)
        AUTO_TAGS='["golang"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="backend"
        ;;
    rs)
        AUTO_TAGS='["rust"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="backend"
        ;;
    rb)
        AUTO_TAGS='["ruby"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="backend"
        ;;
    java|kt|kts)
        AUTO_TAGS='["java"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="backend"
        ;;
    swift)
        AUTO_TAGS='["swift"]'
        ;;
    php)
        AUTO_TAGS='["php"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="backend"
        ;;
    sql)
        AUTO_TAGS='["sql"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="database"
        ;;
    css|scss|sass|less)
        AUTO_TAGS='["css"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="ui"
        ;;
    html|htm)
        AUTO_TAGS='["html"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="frontend"
        ;;
    md)
        AUTO_TAGS='["markdown"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="docs"
        ;;
    yaml|yml)
        AUTO_TAGS='["yaml", "config"]'
        ;;
    json)
        AUTO_TAGS='["json", "config"]'
        ;;
    sh)
        AUTO_TAGS='["bash", "shell"]'
        ;;
    dockerfile|Dockerfile)
        AUTO_TAGS='["docker"]'
        [ "$AUTO_CATEGORY" = "other" ] && AUTO_CATEGORY="infra"
        ;;
esac

# Memory Serviceに保存（jqで安全にJSONを構築）
PAYLOAD=$(jq -n \
    --arg content "$SUMMARY" \
    --arg scope_id "$PROJECT_ID" \
    --arg category "$AUTO_CATEGORY" \
    --argjson tags "$AUTO_TAGS" \
    --arg file "$FILE_PATH" \
    --arg filename "$FILENAME" \
    --arg extension "$EXTENSION" \
    --arg directory "$DIRNAME" \
    --arg user "$USER_ID" \
    --arg team_id "$TEAM_ID" \
    '{
        content: $content,
        type: "work",
        importance: 0.3,
        scope: "project",
        scope_id: $scope_id,
        category: $category,
        tags: $tags,
        metadata: {
            file: $file,
            filename: $filename,
            extension: $extension,
            directory: $directory,
            action: "edit",
            user: $user,
            team_id: $team_id
        }
    }')

curl -s --max-time 3 -X POST "$MEMORY_URL/store" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null 2>&1 || true
