#!/bin/bash
# ISAC 統合テスト
#
# エンドツーエンドのワークフローをテスト
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/test_integration.sh

# エラー時も継続（テスト用）
# set -e

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

# 環境変数
export MEMORY_SERVICE_URL="http://localhost:8100"

# テスト用の一意なプロジェクトID
TEST_PROJECT="integration-test-$(date +%s)"

# テスト用ディレクトリ
TEST_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# テスト関数
test_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    echo "  Detail: $2"
    FAILED=$((FAILED + 1))
}

echo "========================================"
echo "ISAC 統合テスト"
echo "========================================"
echo "テストプロジェクト: $TEST_PROJECT"
echo ""

# ========================================
# シナリオ1: 新規プロジェクトのセットアップ
# ========================================
echo -e "${BLUE}シナリオ1: 新規プロジェクトのセットアップ${NC}"
echo "----------------------------------------"

# 1-1. プロジェクトディレクトリ作成
mkdir -p "$TEST_DIR/my-project"
cd "$TEST_DIR/my-project"

# 1-2. .isac.yaml 作成
cat > .isac.yaml << EOF
project_id: $TEST_PROJECT
EOF

# 1-3. プロジェクト解決の確認
RESOLVE_RESULT=$(bash "$SCRIPT_DIR/.claude/hooks/resolve-project.sh" 2>/dev/null)
RESOLVED_ID=$(echo "$RESOLVE_RESULT" | jq -r '.project_id')

if [ "$RESOLVED_ID" = "$TEST_PROJECT" ]; then
    test_pass "プロジェクトIDが正しく解決される"
else
    test_fail "プロジェクトIDの解決" "Expected: $TEST_PROJECT, Got: $RESOLVED_ID"
fi

echo ""

# ========================================
# シナリオ2: 決定事項の記録
# ========================================
echo -e "${BLUE}シナリオ2: 決定事項の記録${NC}"
echo "----------------------------------------"

# 2-1. 決定を保存
DECISION_RESPONSE=$(curl -s -X POST "$MEMORY_SERVICE_URL/store" \
    -H "Content-Type: application/json" \
    -d '{
        "content": "テストフレームワークにはpytestを採用する。理由: Pythonデファクトスタンダードで、fixtureが強力",
        "type": "decision",
        "importance": 0.8,
        "scope": "project",
        "scope_id": "'"$TEST_PROJECT"'",
        "metadata": {"category": "testing", "decision": "pytest採用"}
    }')

DECISION_ID=$(echo "$DECISION_RESPONSE" | jq -r '.id')

if [ -n "$DECISION_ID" ] && [ "$DECISION_ID" != "null" ]; then
    test_pass "決定事項を保存できる"
else
    test_fail "決定事項の保存" "$DECISION_RESPONSE"
fi

# 2-2. 決定がコンテキストに含まれるか確認
sleep 1
CONTEXT=$(curl -s --get "$MEMORY_SERVICE_URL/context/$TEST_PROJECT" \
    --data-urlencode "query=pytest")

DECISION_COUNT=$(echo "$CONTEXT" | jq '.project_decisions | length')

if [ "$DECISION_COUNT" -gt 0 ]; then
    test_pass "決定事項がコンテキストに含まれる"
else
    test_fail "コンテキストに決定事項がない" "$CONTEXT"
fi

echo ""

# ========================================
# シナリオ3: 作業履歴の記録
# ========================================
echo -e "${BLUE}シナリオ3: 作業履歴の記録${NC}"
echo "----------------------------------------"

# 3-1. 作業を保存
WORK_RESPONSE=$(curl -s -X POST "$MEMORY_SERVICE_URL/store" \
    -H "Content-Type: application/json" \
    -d '{
        "content": "テストファイル test_main.py を作成",
        "type": "work",
        "importance": 0.4,
        "scope": "project",
        "scope_id": "'"$TEST_PROJECT"'",
        "metadata": {"file": "test_main.py", "action": "create"}
    }')

WORK_ID=$(echo "$WORK_RESPONSE" | jq -r '.id')

if [ -n "$WORK_ID" ] && [ "$WORK_ID" != "null" ]; then
    test_pass "作業履歴を保存できる"
else
    test_fail "作業履歴の保存" "$WORK_RESPONSE"
fi

echo ""

# ========================================
# シナリオ4: コンテキスト取得（Hook経由）
# ========================================
echo -e "${BLUE}シナリオ4: コンテキスト取得（Hook経由）${NC}"
echo "----------------------------------------"

# 4-1. on-prompt.sh でコンテキスト取得
cd "$TEST_DIR/my-project"
HOOK_OUTPUT=$(bash "$SCRIPT_DIR/.claude/hooks/on-prompt.sh" "pytestについて" 2>&1)

if [[ "$HOOK_OUTPUT" == *"pytest"* ]] || [[ "$HOOK_OUTPUT" == *"決定"* ]]; then
    test_pass "Hookがコンテキストを出力する"
else
    test_fail "Hookのコンテキスト出力" "pytestまたは決定が含まれていない"
fi

# 4-2. トークン情報が出力されるか
if [[ "$HOOK_OUTPUT" == *"tokens"* ]]; then
    test_pass "トークン情報が出力される"
else
    test_fail "トークン情報の出力" "tokensが含まれていない"
fi

echo ""

# ========================================
# シナリオ5: 検索機能
# ========================================
echo -e "${BLUE}シナリオ5: 検索機能${NC}"
echo "----------------------------------------"

# 5-1. キーワード検索
SEARCH_RESULT=$(curl -s --get "$MEMORY_SERVICE_URL/search" \
    --data-urlencode "query=pytest" \
    --data-urlencode "scope_id=$TEST_PROJECT")

SEARCH_COUNT=$(echo "$SEARCH_RESULT" | jq '.memories | length')

if [ "$SEARCH_COUNT" -gt 0 ]; then
    test_pass "キーワードで検索できる"
else
    test_fail "キーワード検索" "結果が0件"
fi

# 5-2. タイプでフィルタ
FILTERED_RESULT=$(curl -s --get "$MEMORY_SERVICE_URL/search" \
    --data-urlencode "query=pytest" \
    --data-urlencode "type=decision" \
    --data-urlencode "scope_id=$TEST_PROJECT")

FILTERED_COUNT=$(echo "$FILTERED_RESULT" | jq '.memories | length')

if [ "$FILTERED_COUNT" -gt 0 ]; then
    test_pass "タイプでフィルタできる"
else
    test_fail "タイプフィルタ" "decision が見つからない"
fi

echo ""

# ========================================
# シナリオ6: プロジェクト一覧とTypo検出
# ========================================
echo -e "${BLUE}シナリオ6: プロジェクト一覧とTypo検出${NC}"
echo "----------------------------------------"

# 6-1. プロジェクト一覧に表示される
PROJECTS=$(curl -s "$MEMORY_SERVICE_URL/projects")
PROJECT_EXISTS=$(echo "$PROJECTS" | jq -r '.[] | select(.project_id == "'"$TEST_PROJECT"'") | .project_id')

if [ "$PROJECT_EXISTS" = "$TEST_PROJECT" ]; then
    test_pass "プロジェクト一覧に表示される"
else
    test_fail "プロジェクト一覧" "$TEST_PROJECT が見つからない"
fi

# 6-2. Typo検出
TYPO_NAME="${TEST_PROJECT}x"  # 末尾にxを追加
SUGGEST_RESULT=$(curl -s --get "$MEMORY_SERVICE_URL/projects/suggest" \
    --data-urlencode "name=$TYPO_NAME")

EXACT_MATCH=$(echo "$SUGGEST_RESULT" | jq -r '.exact_match')
SUGGESTION_COUNT=$(echo "$SUGGEST_RESULT" | jq -r '.suggestions | length')

# exact_matchがfalseで、何らかの提案があればOK
if [ "$EXACT_MATCH" = "false" ] && [ "$SUGGESTION_COUNT" -gt 0 ]; then
    test_pass "Typoを検出して候補を提案"
else
    test_fail "Typo検出" "exact_match=$EXACT_MATCH, suggestion_count=$SUGGESTION_COUNT"
fi

echo ""

# ========================================
# シナリオ7: エクスポート・インポート
# ========================================
echo -e "${BLUE}シナリオ7: エクスポート・インポート${NC}"
echo "----------------------------------------"

# 7-1. エクスポート
EXPORT_RESULT=$(curl -s "$MEMORY_SERVICE_URL/export/$TEST_PROJECT")
EXPORT_COUNT=$(echo "$EXPORT_RESULT" | jq '.count')

if [ "$EXPORT_COUNT" -gt 0 ]; then
    test_pass "プロジェクトをエクスポートできる"
else
    test_fail "エクスポート" "count=$EXPORT_COUNT"
fi

# 7-2. 別プロジェクトにインポート
IMPORT_PROJECT="${TEST_PROJECT}-imported"
MEMORIES_TO_IMPORT=$(echo "$EXPORT_RESULT" | jq '.memories | map(.scope_id = "'"$IMPORT_PROJECT"'")')

IMPORT_RESULT=$(curl -s -X POST "$MEMORY_SERVICE_URL/import" \
    -H "Content-Type: application/json" \
    -d "{\"memories\": $MEMORIES_TO_IMPORT}")

IMPORTED_COUNT=$(echo "$IMPORT_RESULT" | jq '.imported')

if [ "$IMPORTED_COUNT" -gt 0 ]; then
    test_pass "メモリをインポートできる"
else
    test_fail "インポート" "$IMPORT_RESULT"
fi

echo ""

# ========================================
# シナリオ8: 統計情報
# ========================================
echo -e "${BLUE}シナリオ8: 統計情報${NC}"
echo "----------------------------------------"

STATS=$(curl -s "$MEMORY_SERVICE_URL/stats/$TEST_PROJECT")
STATS_PROJECT=$(echo "$STATS" | jq -r '.project_id')

if [ "$STATS_PROJECT" = "$TEST_PROJECT" ]; then
    test_pass "統計情報を取得できる"
else
    test_fail "統計情報" "$STATS"
fi

echo ""

# ========================================
# クリーンアップ（テストデータ削除）
# ========================================
echo -e "${BLUE}クリーンアップ${NC}"
echo "----------------------------------------"

# テスト用メモリを削除（オプション）
# 本番環境では削除しない方がいいかもしれない
echo -e "${YELLOW}テストデータは削除していません${NC}"
echo "プロジェクト: $TEST_PROJECT"
echo "インポート先: $IMPORT_PROJECT"

echo ""

# ========================================
# 結果サマリー
# ========================================
echo "========================================"
echo "統合テスト結果"
echo "========================================"
echo -e "${GREEN}PASSED${NC}: $PASSED"
echo -e "${RED}FAILED${NC}: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}テストが失敗しました${NC}"
    exit 1
else
    echo -e "${GREEN}すべての統合テストが成功しました${NC}"
    exit 0
fi
