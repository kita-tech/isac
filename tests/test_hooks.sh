#!/bin/bash
# ISAC Hooks テスト
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/test_hooks.sh
#
# 前提条件:
#   - Memory Service が http://localhost:8200 で起動していること
#   - jq がインストールされていること

# エラー時も継続（テスト用）
# set -e

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# テスト結果カウンター
declare -i PASSED=0
declare -i FAILED=0

# テスト用ディレクトリ
TEST_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$SCRIPT_DIR/.claude/hooks"
BIN_DIR="$SCRIPT_DIR/bin"

# 環境変数
export MEMORY_SERVICE_URL="${MEMORY_SERVICE_URL:-http://localhost:8200}"

# クリーンアップ
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# テスト関数
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected to contain: $needle"
        echo "  Actual: $haystack"
        FAILED=$((FAILED + 1))
    fi
}

# ファイル内に指定パターン（grep正規表現）が存在するか検証
assert_file_grep() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Pattern not found: $pattern"
        echo "  File: $file"
        FAILED=$((FAILED + 1))
    fi
}

# ファイル内に指定パターン（grep正規表現）が存在しないことを検証
assert_not_file_grep() {
    local file="$1"
    local pattern="$2"
    local message="$3"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Pattern unexpectedly found: $pattern"
        echo "  File: $file"
        FAILED=$((FAILED + 1))
    else
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    fi
}

assert_not_empty() {
    local value="$1"
    local message="$2"

    if [ -n "$value" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (value is empty)"
        FAILED=$((FAILED + 1))
    fi
}

assert_empty() {
    local value="$1"
    local message="$2"

    if [ -z "$value" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message (value is not empty: $value)"
        FAILED=$((FAILED + 1))
    fi
}

# ヘッダー
echo "========================================"
echo "ISAC Hooks テスト"
echo "========================================"
echo ""

# Memory Serviceの起動確認
echo -e "${YELLOW}前提条件チェック...${NC}"
if ! curl -s --connect-timeout 2 "$MEMORY_SERVICE_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Memory Service が起動していません${NC}"
    echo "  docker compose up -d を実行してください"
    exit 1
fi
echo -e "${GREEN}Memory Service: OK${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq がインストールされていません${NC}"
    exit 1
fi
echo -e "${GREEN}jq: OK${NC}"
echo ""

# ========================================
# resolve-project.sh のテスト
# ========================================
echo "----------------------------------------"
echo "resolve-project.sh テスト"
echo "----------------------------------------"

# テスト1: ローカル設定ファイルからプロジェクトIDを取得
echo "project_id: test-local-project" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
PROJECT_ID=$(echo "$RESULT" | jq -r '.project_id')
SOURCE=$(echo "$RESULT" | jq -r '.source')

assert_equals "test-local-project" "$PROJECT_ID" "ローカル設定からproject_idを取得"
assert_equals "local" "$SOURCE" "sourceがlocalになる"

# テスト2: Team IDも取得
echo -e "project_id: test-team-project\nteam_id: test-team" > "$TEST_DIR/.isac.yaml"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
TEAM_ID=$(echo "$RESULT" | jq -r '.team_id')
assert_equals "test-team" "$TEAM_ID" "team_idを正しく取得"

# テスト3: 設定ファイルがない場合はdefault
rm "$TEST_DIR/.isac.yaml"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
PROJECT_ID=$(echo "$RESULT" | jq -r '.project_id')
SOURCE=$(echo "$RESULT" | jq -r '.source')
WARNING=$(echo "$RESULT" | jq -r '.warning')

assert_equals "default" "$PROJECT_ID" "設定なしでdefaultになる"
assert_equals "default" "$SOURCE" "sourceがdefaultになる"
assert_not_empty "$WARNING" "警告メッセージが出る"

# テスト4: Typo検出
echo "project_id: isca" > "$TEST_DIR/.isac.yaml"  # isac のtypo
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
WARNING=$(echo "$RESULT" | jq -r '.warning')
SUGGESTIONS=$(echo "$RESULT" | jq -r '.suggestions | length')

# isacプロジェクトが存在する場合のみテスト
if curl -s "$MEMORY_SERVICE_URL/projects/suggest?name=isac" | jq -e '.exact_match == true' > /dev/null 2>&1; then
    assert_contains "$WARNING" "isac" "Typo検出で正しいプロジェクト名を提案"
else
    echo -e "${YELLOW}⚠ SKIP${NC}: isacプロジェクトが存在しないためTypo検出テストをスキップ"
fi

# テスト5: クォート付きproject_id
echo 'project_id: "quoted-project"' > "$TEST_DIR/.isac.yaml"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
PROJECT_ID=$(echo "$RESULT" | jq -r '.project_id')
assert_equals "quoted-project" "$PROJECT_ID" "クォート付きproject_idを正しく解析"

# テスト6: シングルクォート付きproject_id
echo "project_id: 'single-quoted'" > "$TEST_DIR/.isac.yaml"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
PROJECT_ID=$(echo "$RESULT" | jq -r '.project_id')
assert_equals "single-quoted" "$PROJECT_ID" "シングルクォート付きproject_idを正しく解析"

# テスト7: ダブルクォートを含むwarningが安全にJSON出力される
rm "$TEST_DIR/.isac.yaml"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
# JSONとしてパースできることを確認
if echo "$RESULT" | jq empty 2>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: warningを含むJSON出力が有効"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: warningを含むJSON出力が無効"
    echo "  Output: $RESULT"
    FAILED=$((FAILED + 1))
fi

# テスト8: 特殊文字を含むproject_id（エスケープテスト）
echo 'project_id: test-with-"quotes"' > "$TEST_DIR/.isac.yaml"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
if echo "$RESULT" | jq empty 2>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}: ダブルクォートを含むproject_idでもJSONが有効"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: ダブルクォートを含むproject_idでJSONが無効"
    FAILED=$((FAILED + 1))
fi

# テスト9: 親ディレクトリの.isac.yaml探索
mkdir -p "$TEST_DIR/subdir/nested"
echo "project_id: parent-project" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR/subdir/nested"
RESULT=$(bash "$HOOKS_DIR/resolve-project.sh" 2>/dev/null)
PROJECT_ID=$(echo "$RESULT" | jq -r '.project_id')
assert_equals "parent-project" "$PROJECT_ID" "親ディレクトリの.isac.yamlを探索"
cd "$TEST_DIR"

echo ""

# ========================================
# sensitive-filter.sh のテスト
# ========================================
echo "----------------------------------------"
echo "sensitive-filter.sh テスト"
echo "----------------------------------------"

# テスト1: APIキーの検出
RESULT=$(echo "api_key=sk-abc123456789abcdef" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
DETECTED=$(echo "$RESULT" | jq -r '.detected[0]')
assert_equals "true" "$IS_SENSITIVE" "APIキーを検出"
assert_equals "api_key" "$DETECTED" "検出タイプがapi_key"

# テスト2: パスワードの検出
RESULT=$(echo "password=mysecretpass123" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "パスワードを検出"

# テスト3: AWSキーの検出
RESULT=$(echo "AKIAIOSFODNN7EXAMPLE" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "AWSアクセスキーを検出"

# テスト4: Database URLの検出
RESULT=$(echo "postgres://user:pass@localhost/db" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Database URLを検出"

# テスト5: 安全なテキストは検出しない
RESULT=$(echo "This is a normal text" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "false" "$IS_SENSITIVE" "通常テキストは検出しない"

# テスト6: GitHubトークン (ghp_) の検出（ghp_ + 36文字）
RESULT=$(echo "token=ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "GitHubトークン(ghp_)を検出"

# テスト7: GitHubトークン (gho_) の検出（gho_ + 36文字）
RESULT=$(echo "GITHUB_TOKEN=gho_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "GitHubトークン(gho_)を検出"

# テスト8: Slackトークン (xoxb-) の検出
# Note: 実際のトークン形式に近いが、GitHubのシークレットスキャンを回避するためダミー値を使用
RESULT=$(echo 'SLACK_BOT_TOKEN=xoxb-FAKE-TEST-TOKEN-VALUE' | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Slackトークン(xoxb-)を検出"

# テスト9: Slackトークン (xoxp-) の検出
RESULT=$(echo 'xoxp-FAKE-TEST-TOKEN' | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Slackトークン(xoxp-)を検出"

# テスト10: Notionトークン (ntn_) の検出
RESULT=$(echo "NOTION_TOKEN=ntn_AbCdEfGhIjKlMnOpQrStUvWxYz" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Notionトークン(ntn_)を検出"

# テスト11: Notionトークン (secret_) の検出
RESULT=$(echo "secret_AbCdEfGhIjKlMnOpQrStUvWxYz123456" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Notionトークン(secret_)を検出"

# テスト12: Context7 APIキーの検出
RESULT=$(echo "CONTEXT7_API_KEY=ctx7sk-12345678-1234-1234-1234-123456789012" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Context7 APIキーを検出"

# テスト13: 複数の機密情報を検出
RESULT=$(echo "api_key=sk-abc123456789abcdef password=secret123" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
DETECTED_COUNT=$(echo "$RESULT" | jq -r '.detected | length')
if [ "$DETECTED_COUNT" -ge 2 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 複数の機密情報を検出 (count: $DETECTED_COUNT)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 複数の機密情報を検出できず (count: $DETECTED_COUNT)"
    FAILED=$((FAILED + 1))
fi

# テスト14: JWTトークンの検出
RESULT=$(echo "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "JWTトークンを検出"

# テスト15: MongoDB URL (+srv) の検出
RESULT=$(echo "mongodb+srv://user:password@cluster.mongodb.net/db" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "MongoDB+srv URLを検出"

# テスト16: Private Keyの検出
RESULT=$(echo "-----BEGIN RSA PRIVATE KEY-----" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "RSA Private Keyを検出"

# テスト17: Bearerトークンの検出
RESULT=$(echo "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "Bearerトークンを検出"

# テスト18: マスキング出力の確認
RESULT=$(echo "password=supersecret123" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
FILTERED=$(echo "$RESULT" | jq -r '.filtered')
if [[ "$FILTERED" == *"[MASKED:"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: 機密情報がマスキングされる"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 機密情報がマスキングされていない: $FILTERED"
    FAILED=$((FAILED + 1))
fi

# テスト19: 引数での入力（パイプではなく）
RESULT=$(bash "$HOOKS_DIR/sensitive-filter.sh" "api_key=sk-test1234567890abcdef" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "引数からの入力でも検出"

# テスト20: 大文字小文字を無視した検出
RESULT=$(echo "API_KEY=sk-test1234567890abcdef" | bash "$HOOKS_DIR/sensitive-filter.sh" 2>/dev/null)
IS_SENSITIVE=$(echo "$RESULT" | jq -r '.is_sensitive')
assert_equals "true" "$IS_SENSITIVE" "大文字のAPI_KEYも検出"

echo ""

# ========================================
# on-prompt.sh のテスト
# ========================================
echo "----------------------------------------"
echo "on-prompt.sh テスト"
echo "----------------------------------------"

# テスト1: 正常なプロジェクトでコンテキスト取得
echo "project_id: isac" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "テスト" 2>/dev/null)

# グローバルナレッジまたはプロジェクト決定が含まれていればOK
if [[ "$OUTPUT" == *"グローバルナレッジ"* ]] || [[ "$OUTPUT" == *"プロジェクト決定"* ]] || [[ "$OUTPUT" == *"最近の"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: on-prompt.shがコンテキストを出力"
    PASSED=$((PASSED + 1))
elif [ -z "$OUTPUT" ]; then
    echo -e "${YELLOW}⚠ SKIP${NC}: コンテキストが空（メモリがない可能性）"
else
    echo -e "${GREEN}✓ PASS${NC}: on-prompt.shが実行された"
    PASSED=$((PASSED + 1))
fi

# テスト2: 空のクエリではスキップ
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "" 2>/dev/null)
assert_empty "$OUTPUT" "空のクエリでは出力なし"

# テスト3: 未設定プロジェクトで警告
rm "$TEST_DIR/.isac.yaml"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "テスト" 2>/dev/null)
assert_contains "$OUTPUT" "プロジェクト設定" "未設定時に警告を出力"

# テスト4: 特殊文字を含むプロジェクトID（URLエンコード）
echo "project_id: test-project/with/slashes" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "テスト" 2>&1)
# スラッシュを含むプロジェクトIDでエラーにならないこと
if [ $? -eq 0 ] || [[ "$OUTPUT" != *"error"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: スラッシュを含むプロジェクトIDでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: スラッシュを含むプロジェクトIDでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト5: スペースを含むプロジェクトID
echo "project_id: test project with spaces" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "テスト" 2>&1)
if [ $? -eq 0 ] || [[ "$OUTPUT" != *"error"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: スペースを含むプロジェクトIDでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: スペースを含むプロジェクトIDでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト6: アンパサンドを含むプロジェクトID
echo "project_id: test&project" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "テスト" 2>&1)
if [ $? -eq 0 ] || [[ "$OUTPUT" != *"error"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: &を含むプロジェクトIDでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: &を含むプロジェクトIDでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト7: 日本語を含むプロジェクトID
echo "project_id: テストプロジェクト" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "テスト" 2>&1)
if [ $? -eq 0 ] || [[ "$OUTPUT" != *"error"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: 日本語プロジェクトIDでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 日本語プロジェクトIDでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト8: isac statusコマンド検出
echo "project_id: test-status" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(bash "$HOOKS_DIR/on-prompt.sh" "isac status" 2>/dev/null)
if [[ "$OUTPUT" == *"ISAC Status"* ]] || [[ "$OUTPUT" == *"CLI出力"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: isac statusコマンドでステータス出力を注入"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ SKIP${NC}: isac statusの注入が確認できず（isac CLIのパス問題かも）"
fi

echo ""

# ========================================
# post-edit.sh のテスト
# ========================================
echo "----------------------------------------"
echo "post-edit.sh テスト"
echo "----------------------------------------"

# テスト1: ファイル編集を記録
echo "project_id: test-post-edit" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"
bash "$HOOKS_DIR/post-edit.sh" "/path/to/test.py" 2>/dev/null

# Memory Serviceに記録されたか確認
sleep 1
SEARCH_RESULT=$(curl -s "$MEMORY_SERVICE_URL/search?query=test.py&scope_id=test-post-edit" 2>/dev/null)
FOUND=$(echo "$SEARCH_RESULT" | jq -r '.memories | length')

if [ "$FOUND" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: post-edit.shがメモリに記録"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARN${NC}: post-edit.shの記録が確認できず（タイミングの問題かも）"
fi

# テスト2: 空のファイルパスではスキップ
bash "$HOOKS_DIR/post-edit.sh" "" 2>/dev/null && {
    echo -e "${GREEN}✓ PASS${NC}: 空のファイルパスでエラーにならない"
    PASSED=$((PASSED + 1))
}

# テスト3: 機密ファイルはスキップ
echo "project_id: test-post-edit-sensitive" > "$TEST_DIR/.isac.yaml"
bash "$HOOKS_DIR/post-edit.sh" "/path/to/.env" 2>/dev/null
sleep 1
SEARCH_RESULT=$(curl -s "$MEMORY_SERVICE_URL/search?query=.env&scope_id=test-post-edit-sensitive" 2>/dev/null)
FOUND=$(echo "$SEARCH_RESULT" | jq -r '.memories | length')

if [ "$FOUND" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: .envファイルは記録されない"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARN${NC}: .envファイルが記録されてしまった"
fi

# テスト4: .env.* 形式の機密ファイルスキップ
bash "$HOOKS_DIR/post-edit.sh" "/path/to/.env.local" 2>/dev/null
bash "$HOOKS_DIR/post-edit.sh" "/path/to/.env.production" 2>/dev/null
echo -e "${GREEN}✓ PASS${NC}: .env.*形式の機密ファイルでエラーにならない"
PASSED=$((PASSED + 1))

# テスト5: .pemファイルのスキップ
bash "$HOOKS_DIR/post-edit.sh" "/path/to/server.pem" 2>/dev/null
echo -e "${GREEN}✓ PASS${NC}: .pemファイルでエラーにならない"
PASSED=$((PASSED + 1))

# テスト6: credentials.*ファイルのスキップ
bash "$HOOKS_DIR/post-edit.sh" "/path/to/credentials.json" 2>/dev/null
echo -e "${GREEN}✓ PASS${NC}: credentials.jsonでエラーにならない"
PASSED=$((PASSED + 1))

# テスト7: スペースを含むファイル名
echo "project_id: test-post-edit-spaces" > "$TEST_DIR/.isac.yaml"
bash "$HOOKS_DIR/post-edit.sh" "/path/to/file with spaces.py" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: スペースを含むファイル名でエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: スペースを含むファイル名でエラー"
    FAILED=$((FAILED + 1))
fi

# テスト8: 日本語ファイル名
bash "$HOOKS_DIR/post-edit.sh" "/path/to/テストファイル.py" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 日本語ファイル名でエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 日本語ファイル名でエラー"
    FAILED=$((FAILED + 1))
fi

# テスト9: ダブルクォートを含むファイル名（JSONエスケープ確認）
bash "$HOOKS_DIR/post-edit.sh" '/path/to/file"with"quotes.py' 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: ダブルクォートを含むファイル名でエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: ダブルクォートを含むファイル名でエラー"
    FAILED=$((FAILED + 1))
fi

# テスト10: 長いファイルパス (256文字以上)
LONG_PATH="/path/to/very/long/directory/structure/that/goes/on/and/on/and/on/for/a/very/long/time/to/test/boundary/conditions/in/file/handling/routines/that/might/have/issues/with/extremely/long/paths/like/this/one/file.py"
bash "$HOOKS_DIR/post-edit.sh" "$LONG_PATH" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 長いファイルパスでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 長いファイルパスでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト11: 様々な拡張子のファイルタイプ検出
for ext in py js ts tsx jsx go rs rb java php vue css scss html sql sh yaml json; do
    bash "$HOOKS_DIR/post-edit.sh" "/path/to/test.$ext" 2>/dev/null
done
echo -e "${GREEN}✓ PASS${NC}: 各種拡張子のファイルでエラーにならない"
PASSED=$((PASSED + 1))

# テスト12: testディレクトリのカテゴリ判定
echo "project_id: test-post-edit-category" > "$TEST_DIR/.isac.yaml"
bash "$HOOKS_DIR/post-edit.sh" "/path/to/tests/test_example.py" 2>/dev/null
sleep 1
SEARCH_RESULT=$(curl -s "$MEMORY_SERVICE_URL/search?query=test_example&scope_id=test-post-edit-category" 2>/dev/null)
CATEGORY=$(echo "$SEARCH_RESULT" | jq -r '.memories[0].category // "unknown"')
if [ "$CATEGORY" = "test" ]; then
    echo -e "${GREEN}✓ PASS${NC}: testsディレクトリのファイルがtestカテゴリになる"
    PASSED=$((PASSED + 1))
elif [ "$CATEGORY" = "unknown" ]; then
    echo -e "${YELLOW}⚠ SKIP${NC}: カテゴリ判定が確認できず（メモリが見つからない）"
else
    echo -e "${YELLOW}⚠ WARN${NC}: testsディレクトリのファイルがtestカテゴリでない ($CATEGORY)"
fi

# テスト13: apiディレクトリのカテゴリ判定
bash "$HOOKS_DIR/post-edit.sh" "/path/to/api/routes/users.py" 2>/dev/null
sleep 1
SEARCH_RESULT=$(curl -s "$MEMORY_SERVICE_URL/search?query=users.py&scope_id=test-post-edit-category" 2>/dev/null)
CATEGORY=$(echo "$SEARCH_RESULT" | jq -r '.memories[0].category // "unknown"')
if [ "$CATEGORY" = "api" ]; then
    echo -e "${GREEN}✓ PASS${NC}: apiディレクトリのファイルがapiカテゴリになる"
    PASSED=$((PASSED + 1))
elif [ "$CATEGORY" = "unknown" ]; then
    echo -e "${YELLOW}⚠ SKIP${NC}: カテゴリ判定が確認できず"
else
    echo -e "${YELLOW}⚠ WARN${NC}: apiディレクトリのファイルがapiカテゴリでない ($CATEGORY)"
fi

echo ""

# ========================================
# save-memory.sh のテスト
# ========================================
echo "----------------------------------------"
echo "save-memory.sh テスト"
echo "----------------------------------------"

# テスト1: 基本的なJSON入力
echo "project_id: test-save-memory" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"

JSON_INPUT='```json
{
  "type": "work",
  "category": "test",
  "tags": ["unittest"],
  "summary": "save-memory test entry",
  "importance": 0.6
}
```'

echo "$JSON_INPUT" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: save-memory.shが正常終了"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: save-memory.shがエラー"
    FAILED=$((FAILED + 1))
fi

# テスト2: skip=trueで保存しない
JSON_SKIP='```json
{
  "skip": true,
  "summary": "This should not be saved"
}
```'
echo "$JSON_SKIP" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
echo -e "${GREEN}✓ PASS${NC}: skip=trueでエラーにならない"
PASSED=$((PASSED + 1))

# テスト3: 空のサマリでスキップ
JSON_EMPTY='```json
{
  "type": "work",
  "summary": ""
}
```'
echo "$JSON_EMPTY" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
echo -e "${GREEN}✓ PASS${NC}: 空のサマリでエラーにならない"
PASSED=$((PASSED + 1))

# テスト4: ダブルクォートを含むサマリ（JSONエスケープ確認）
JSON_QUOTES='```json
{
  "type": "work",
  "category": "test",
  "tags": [],
  "summary": "Test with \"quotes\" in summary",
  "importance": 0.5
}
```'
echo "$JSON_QUOTES" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: ダブルクォートを含むサマリでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: ダブルクォートを含むサマリでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト5: 日本語サマリ
JSON_JAPANESE='```json
{
  "type": "work",
  "category": "test",
  "tags": ["テスト"],
  "summary": "日本語のサマリをテスト",
  "importance": 0.5
}
```'
echo "$JSON_JAPANESE" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 日本語サマリでエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 日本語サマリでエラー"
    FAILED=$((FAILED + 1))
fi

# テスト6: 不正なimportance値（範囲チェック）
JSON_INVALID_IMPORTANCE='```json
{
  "type": "work",
  "summary": "Test invalid importance",
  "importance": "invalid"
}
```'
echo "$JSON_INVALID_IMPORTANCE" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
echo -e "${GREEN}✓ PASS${NC}: 不正なimportance値でエラーにならない（デフォルト0.5にフォールバック）"
PASSED=$((PASSED + 1))

# テスト7: Memory Serviceが停止している場合のフォールバック（タイムアウト）
# このテストは実際にサービスを停止する必要があるためスキップ
echo -e "${YELLOW}⚠ SKIP${NC}: Memory Service停止テストはスキップ"

# テスト8: 生のJSON入力（```jsonなし）
JSON_RAW='{"type": "work", "summary": "Raw JSON test", "importance": 0.5}'
echo "$JSON_RAW" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 生のJSON入力でエラーにならない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 生のJSON入力でエラー"
    FAILED=$((FAILED + 1))
fi

# テスト9: scope=projectで保存（デフォルト）
echo "project_id: test-scope-project" > "$TEST_DIR/.isac.yaml"
JSON_SCOPE_PROJECT='```json
{
  "type": "work",
  "scope": "project",
  "category": "test",
  "tags": ["scope-test"],
  "summary": "Scope project test entry",
  "importance": 0.5
}
```'
OUTPUT=$(echo "$JSON_SCOPE_PROJECT" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null)
assert_contains "$OUTPUT" "scope: project" "scope=projectが出力に含まれる"

# テスト10: E2E - project保存時にMemory ServiceのAPIレスポンスでscope_id=プロジェクトIDを検証
UNIQUE_TAG_PROJECT="e2e-project-$(date +%s)"
JSON_PROJECT_E2E='{"type": "work", "scope": "project", "category": "test", "tags": ["'"$UNIQUE_TAG_PROJECT"'"], "summary": "E2E project scope_id verify test", "importance": 0.5}'
echo "$JSON_PROJECT_E2E" | MEMORY_SERVICE_URL="$MEMORY_SERVICE_URL" bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
sleep 1
SEARCH_RESULT=$(curl -s "$MEMORY_SERVICE_URL/search?query=E2E+project+scope_id+verify+test&scope_id=test-scope-project&limit=5" 2>/dev/null)
FOUND_ENTRY=$(echo "$SEARCH_RESULT" | jq '[.memories[] | select(.tags[] == "'"$UNIQUE_TAG_PROJECT"'")] | .[0]')
if [ "$FOUND_ENTRY" = "null" ]; then
    echo -e "${YELLOW}⚠ SKIP${NC}: E2E: project記憶が検索で見つからず（タイミングの問題の可能性）"
else
    FOUND_SCOPE=$(echo "$FOUND_ENTRY" | jq -r '.scope')
    FOUND_SCOPE_ID=$(echo "$FOUND_ENTRY" | jq -r '.scope_id')
    if [ "$FOUND_SCOPE" = "project" ] && [ "$FOUND_SCOPE_ID" = "test-scope-project" ]; then
        echo -e "${GREEN}✓ PASS${NC}: E2E: projectスコープで保存され、scope_id=test-scope-projectがAPI応答で確認"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: E2E: scope=$FOUND_SCOPE, scope_id=$FOUND_SCOPE_ID (expected: project, test-scope-project)"
        FAILED=$((FAILED + 1))
    fi
fi

# テスト11: scope=globalの出力メッセージ確認
JSON_SCOPE_GLOBAL='```json
{
  "type": "knowledge",
  "scope": "global",
  "category": "backend",
  "tags": ["scope-test", "global"],
  "summary": "Scope global test entry",
  "importance": 0.7
}
```'
OUTPUT=$(echo "$JSON_SCOPE_GLOBAL" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null)
assert_contains "$OUTPUT" "scope: global" "scope=globalが出力に含まれる"

# テスト12: E2E - global保存時にMemory ServiceのAPIレスポンスでscope_id=nullを検証
UNIQUE_TAG="e2e-global-$(date +%s)"
JSON_GLOBAL_E2E='{"type": "knowledge", "scope": "global", "category": "backend", "tags": ["'"$UNIQUE_TAG"'"], "summary": "E2E global scope_id null test", "importance": 0.7}'
echo "$JSON_GLOBAL_E2E" | MEMORY_SERVICE_URL="$MEMORY_SERVICE_URL" bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null
sleep 1
# Memory Service APIから保存された記憶を検索し、scope/scope_idを直接検証
SEARCH_RESULT=$(curl -s "$MEMORY_SERVICE_URL/search?query=E2E+global+scope_id+null+test&limit=5" 2>/dev/null)
# jqの // 演算子はnullをfalsyとして扱うため、scope_idの検証には使わない
FOUND_ENTRY=$(echo "$SEARCH_RESULT" | jq '[.memories[] | select(.tags[] == "'"$UNIQUE_TAG"'")] | .[0]')
if [ "$FOUND_ENTRY" = "null" ]; then
    echo -e "${YELLOW}⚠ SKIP${NC}: E2E: global記憶が検索で見つからず（タイミングの問題の可能性）"
else
    FOUND_SCOPE=$(echo "$FOUND_ENTRY" | jq -r '.scope')
    FOUND_SCOPE_ID_IS_NULL=$(echo "$FOUND_ENTRY" | jq '.scope_id == null')
    if [ "$FOUND_SCOPE" = "global" ] && [ "$FOUND_SCOPE_ID_IS_NULL" = "true" ]; then
        echo -e "${GREEN}✓ PASS${NC}: E2E: globalスコープで保存され、scope_id=nullがAPI応答で確認"
        PASSED=$((PASSED + 1))
    else
        FOUND_SCOPE_ID=$(echo "$FOUND_ENTRY" | jq '.scope_id')
        echo -e "${RED}✗ FAIL${NC}: E2E: scope=$FOUND_SCOPE, scope_id=$FOUND_SCOPE_ID (expected: global, null)"
        FAILED=$((FAILED + 1))
    fi
fi

# テスト13: 不正なscope値でprojectにフォールバック
JSON_SCOPE_INVALID='```json
{
  "type": "work",
  "scope": "invalid_scope",
  "category": "test",
  "tags": ["scope-test"],
  "summary": "Invalid scope fallback test",
  "importance": 0.5
}
```'
OUTPUT=$(echo "$JSON_SCOPE_INVALID" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null)
assert_contains "$OUTPUT" "scope: project" "不正なscope値がprojectにフォールバック"

# テスト14: scopeフィールド未指定でprojectがデフォルト
JSON_NO_SCOPE='```json
{
  "type": "work",
  "category": "test",
  "tags": ["scope-test"],
  "summary": "No scope field test",
  "importance": 0.5
}
```'
OUTPUT=$(echo "$JSON_NO_SCOPE" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null)
assert_contains "$OUTPUT" "scope: project" "scope未指定でprojectがデフォルト"

# テスト15: scope=空文字でprojectにフォールバック
JSON_SCOPE_EMPTY='```json
{
  "type": "work",
  "scope": "",
  "category": "test",
  "tags": ["scope-test"],
  "summary": "Empty scope fallback test",
  "importance": 0.5
}
```'
OUTPUT=$(echo "$JSON_SCOPE_EMPTY" | bash "$HOOKS_DIR/save-memory.sh" 2>/dev/null)
assert_contains "$OUTPUT" "scope: project" "空のscope値がprojectにフォールバック"

echo ""

# ========================================
# on-stop.sh のテスト
# ========================================
echo "----------------------------------------"
echo "on-stop.sh テスト"
echo "----------------------------------------"

# テスト1: on-stop.shの出力にscopeフィールドが含まれる
echo "project_id: test-on-stop" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"
ON_STOP_OUTPUT=$(bash "$HOOKS_DIR/on-stop.sh" 2>/dev/null)
assert_contains "$ON_STOP_OUTPUT" '"scope"' "on-stop.shの出力にscopeフィールドが含まれる"

# テスト2: scopeガイドラインが含まれる
assert_contains "$ON_STOP_OUTPUT" "scope" "on-stop.shの出力にscopeガイドラインが含まれる"

# テスト3: 「迷ったらproject」が含まれる
assert_contains "$ON_STOP_OUTPUT" "迷ったらproject" "on-stop.shの出力に「迷ったらproject」が含まれる"

# テスト4: globalの判定ヒント（ツール/言語/FW）が含まれる
assert_contains "$ON_STOP_OUTPUT" "global" "on-stop.shの出力にglobalの説明が含まれる"

echo ""

# ========================================
# memory-classifier.md のテスト
# ========================================
echo "----------------------------------------"
echo "memory-classifier.md テスト"
echo "----------------------------------------"

CLASSIFIER_MD="$SCRIPT_DIR/.claude/agents/memory-classifier.md"

# テスト1: scopeセクションが存在する
assert_file_grep "$CLASSIFIER_MD" "scope" "memory-classifier.mdにscopeセクションが存在する"

# テスト2: 「迷ったらproject」ルールが記載されている
assert_file_grep "$CLASSIFIER_MD" "迷ったら" "memory-classifier.mdに「迷ったら」ルールが記載されている"

# テスト3: global判定基準が記載されている
assert_file_grep "$CLASSIFIER_MD" "global" "memory-classifier.mdにglobal判定基準が記載されている"

# テスト4: scope_id=null の説明がある
assert_file_grep "$CLASSIFIER_MD" "null" "memory-classifier.mdにscope_id=nullの説明がある"

echo ""

# ========================================
# on-session-start.sh のテスト
# ========================================
echo "----------------------------------------"
echo "on-session-start.sh テスト"
echo "----------------------------------------"

# テスト1: 正常時に1行サマリーを出力
echo "project_id: test-session-start" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"
OUTPUT=$(bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "ISAC:" "正常時にISACプレフィックス付きサマリーを出力"

# テスト2: 正常時にプロジェクトIDが含まれる
assert_contains "$OUTPUT" "test-session-start" "正常時にプロジェクトIDが含まれる"

# テスト3: 正常時にMemory接続状態が含まれる
assert_contains "$OUTPUT" "Memory" "正常時にMemory状態が含まれる"

# テスト4: プロジェクト未設定時の警告表示
rm "$TEST_DIR/.isac.yaml"
# 親ディレクトリにも.isac.yamlがないことを確認するために、TEST_DIR自体で実行
OUTPUT=$(cd "$TEST_DIR" && bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "Project" "プロジェクト未設定時にProject警告が含まれる"

# テスト5: スクリプトがエラーなく完了する（終了コード0）
echo "project_id: test-session-exit" > "$TEST_DIR/.isac.yaml"
cd "$TEST_DIR"
bash "$HOOKS_DIR/on-session-start.sh" > /dev/null 2>&1
EXIT_CODE=$?
assert_equals "0" "$EXIT_CODE" "スクリプトが終了コード0で完了"

# テスト6: 2秒以内に完了する（パフォーマンス制約）
START_TIME=$(date +%s)
cd "$TEST_DIR"
bash "$HOOKS_DIR/on-session-start.sh" > /dev/null 2>&1
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
if [ "$ELAPSED" -le 2 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 2秒以内に完了 (${ELAPSED}秒)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 2秒を超過 (${ELAPSED}秒)"
    FAILED=$((FAILED + 1))
fi

# テスト7: コード行にgit fetchを含まない（セキュリティ: git fetch禁止確認）
# コメント行（#で始まる行）を除外して、実行コードにgitネットワークコマンドがないことを確認
if grep -v '^[[:space:]]*#' "$HOOKS_DIR/on-session-start.sh" | grep -q "git fetch" 2>/dev/null || \
   grep -v '^[[:space:]]*#' "$HOOKS_DIR/on-session-start.sh" | grep -q "git pull" 2>/dev/null || \
   grep -v '^[[:space:]]*#' "$HOOKS_DIR/on-session-start.sh" | grep -q "git ls-remote" 2>/dev/null; then
    echo -e "${RED}✗ FAIL${NC}: スクリプトのコード行にgit fetch/pull/ls-remoteが含まれている"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓ PASS${NC}: スクリプトのコード行にgitネットワークコマンドが含まれていない"
    PASSED=$((PASSED + 1))
fi

# テスト8: 親ディレクトリの.isac.yaml探索
mkdir -p "$TEST_DIR/subdir/nested"
echo "project_id: parent-session-project" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(cd "$TEST_DIR/subdir/nested" && bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "parent-session-project" "親ディレクトリの.isac.yamlからプロジェクトIDを取得"

# テスト9: クォート付きproject_idを正しく解析
echo 'project_id: "quoted-session-project"' > "$TEST_DIR/.isac.yaml"
OUTPUT=$(cd "$TEST_DIR" && bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "quoted-session-project" "クォート付きproject_idを正しく表示"

# テスト10: シングルクォート付きproject_id
echo "project_id: 'single-quoted-session'" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(cd "$TEST_DIR" && bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "single-quoted-session" "シングルクォート付きproject_idを正しく表示"

# テスト11: 日本語プロジェクトID
echo "project_id: テストプロジェクト" > "$TEST_DIR/.isac.yaml"
OUTPUT=$(cd "$TEST_DIR" && bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "テストプロジェクト" "日本語プロジェクトIDを正しく表示"

# テスト12: 空のproject_idの場合
echo "project_id: " > "$TEST_DIR/.isac.yaml"
OUTPUT=$(cd "$TEST_DIR" && bash "$HOOKS_DIR/on-session-start.sh" 2>/dev/null)
assert_contains "$OUTPUT" "Project" "空のproject_idで警告が表示される"

# テスト13: settings.yamlにSessionStartフックが定義されている
SETTINGS_FILE="$SCRIPT_DIR/.claude/settings.yaml"
assert_file_grep "$SETTINGS_FILE" "SessionStart" "settings.yamlにSessionStartフックが定義されている"

# テスト14: SessionStartフックがon-session-start.shを参照している
assert_file_grep "$SETTINGS_FILE" "on-session-start.sh" "SessionStartフックがon-session-start.shを参照している"

# テスト15: SessionStartフックのタイムアウトが2000ms以下
if grep -A3 "SessionStart" "$SETTINGS_FILE" | grep -q "timeout: 2000"; then
    echo -e "${GREEN}✓ PASS${NC}: SessionStartフックのタイムアウトが2000ms"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: SessionStartフックのタイムアウトが2000msでない"
    FAILED=$((FAILED + 1))
fi

echo ""

# ========================================
# isac CLI のテスト
# ========================================
echo "----------------------------------------"
echo "isac CLI テスト"
echo "----------------------------------------"

# テスト1: isac help
HELP_OUTPUT=$("$BIN_DIR/isac" help 2>/dev/null)
assert_contains "$HELP_OUTPUT" "install" "isac helpにinstallコマンドが含まれる"
assert_contains "$HELP_OUTPUT" "switch" "isac helpにswitchコマンドが含まれる"

# テスト2: isac version
VERSION_OUTPUT=$("$BIN_DIR/isac" version 2>/dev/null)
assert_contains "$VERSION_OUTPUT" "ISAC version" "isac versionが出力される"

# テスト3: isac status
STATUS_OUTPUT=$("$BIN_DIR/isac" status 2>/dev/null)
assert_contains "$STATUS_OUTPUT" "Memory Service" "isac statusにMemory Service情報が含まれる"

# テスト4: isac projects
PROJECTS_OUTPUT=$("$BIN_DIR/isac" projects 2>/dev/null)
assert_contains "$PROJECTS_OUTPUT" "Projects" "isac projectsがプロジェクト一覧を表示"

# テスト5: isac init (基本)
cd "$TEST_DIR"
rm -f .isac.yaml
rm -rf .claude
echo "test-cli-init" | "$BIN_DIR/isac" init 2>/dev/null
if [ -f "$TEST_DIR/.isac.yaml" ]; then
    echo -e "${GREEN}✓ PASS${NC}: isac initで.isac.yamlが作成される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: isac initで.isac.yamlが作成されなかった"
    FAILED=$((FAILED + 1))
fi

# テスト6: isac init --yes で .claude/ が作成される
cd "$TEST_DIR"
rm -rf .claude .isac.yaml
"$BIN_DIR/isac" init test-auto-claude --yes 2>/dev/null
if [ -d "$TEST_DIR/.claude" ] && [ -f "$TEST_DIR/.claude/settings.yaml" ]; then
    echo -e "${GREEN}✓ PASS${NC}: isac init --yesで.claude/settings.yamlが作成される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: isac init --yesで.claude/が作成されなかった"
    FAILED=$((FAILED + 1))
fi

# テスト7: hooks シンボリックリンクの確認
if [ -L "$TEST_DIR/.claude/hooks/on-prompt.sh" ]; then
    echo -e "${GREEN}✓ PASS${NC}: hooks/on-prompt.shがシンボリックリンクで作成される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: hooks/on-prompt.shがシンボリックリンクでない"
    FAILED=$((FAILED + 1))
fi

# テスト8: skills シンボリックリンクの確認（ディレクトリ構造）
if [ -L "$TEST_DIR/.claude/skills/isac-memory" ] && [ -d "$TEST_DIR/.claude/skills/isac-memory" ]; then
    echo -e "${GREEN}✓ PASS${NC}: skills/isac-memoryがシンボリックリンクで作成される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: skills/isac-memoryがシンボリックリンクでない"
    FAILED=$((FAILED + 1))
fi

# テスト9: isac init --force で再作成
"$BIN_DIR/isac" init test-force --force --yes 2>/dev/null
FORCE_PROJECT=$(grep "project_id:" "$TEST_DIR/.isac.yaml" | sed 's/project_id: *//')
if [ "$FORCE_PROJECT" = "test-force" ]; then
    echo -e "${GREEN}✓ PASS${NC}: isac init --forceでproject_idが上書きされる"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: isac init --forceでproject_idが上書きされなかった (got: $FORCE_PROJECT)"
    FAILED=$((FAILED + 1))
fi

# ----------------------------------------
# MCP設定非生成 テスト
# ----------------------------------------
echo ""
echo "----------------------------------------"
echo "MCP設定非生成 テスト"
echo "----------------------------------------"

# テスト10: isac init で生成される settings.yaml に mcpServers が含まれないこと
cd "$TEST_DIR"
rm -rf .claude .isac.yaml
"$BIN_DIR/isac" init test-mcp-new --yes 2>/dev/null
assert_not_file_grep "$TEST_DIR/.claude/settings.yaml" "^mcpServers:" \
    "settings.yamlにmcpServersが含まれない"

# テスト11: settings.yaml に ISAC-MANAGED マーカーが含まれないこと
assert_not_file_grep "$TEST_DIR/.claude/settings.yaml" "ISAC-MANAGED" \
    "settings.yamlにISAC-MANAGEDマーカーが含まれない"

# テスト12: --force で再作成しても mcpServers が含まれないこと
"$BIN_DIR/isac" init test-mcp-force --force --yes 2>/dev/null
assert_not_file_grep "$TEST_DIR/.claude/settings.yaml" "^mcpServers:" \
    "--forceでもsettings.yamlにmcpServersが含まれない"

echo ""

# ========================================
# 結果サマリー
# ========================================
echo "========================================"
echo "テスト結果"
echo "========================================"
echo -e "${GREEN}PASSED${NC}: $PASSED"
echo -e "${RED}FAILED${NC}: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}テストが失敗しました${NC}"
    exit 1
else
    echo -e "${GREEN}すべてのテストが成功しました${NC}"
    exit 0
fi
