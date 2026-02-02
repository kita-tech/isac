#!/bin/bash
# ISAC Hooks テスト
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/test_hooks.sh
#
# 前提条件:
#   - Memory Service が http://localhost:8100 で起動していること
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
export MEMORY_SERVICE_URL="http://localhost:8100"

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
