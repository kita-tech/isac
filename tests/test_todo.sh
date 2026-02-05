#!/bin/bash
# ISAC Todo機能テスト
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/test_todo.sh
#
# 前提条件:
#   - Memory Service が http://localhost:8100 で起動していること
#   - jq がインストールされていること

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# テスト結果カウンター
declare -i PASSED=0
declare -i FAILED=0

# 環境変数
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
PROJECT_ID="test-todo-$$"
USER_EMAIL="test-user-$$@example.com"

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

assert_greater_than() {
    local threshold="$1"
    local actual="$2"
    local message="$3"

    if [ "$actual" -gt "$threshold" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo "  Expected: > $threshold"
        echo "  Actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

# クリーンアップ関数
cleanup() {
    echo ""
    echo -e "${YELLOW}クリーンアップ中...${NC}"
    # テストで作成したtodoを削除
    TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=all" 2>/dev/null)
    IDS=$(echo "$TODOS" | jq -r '.todos[].id' 2>/dev/null)
    for id in $IDS; do
        curl -s -X DELETE "$MEMORY_URL/memory/$id" > /dev/null 2>&1
    done
    echo -e "${GREEN}クリーンアップ完了${NC}"
}

# ヘッダー
echo "========================================"
echo "ISAC Todo機能テスト"
echo "========================================"
echo ""

# Memory Serviceの起動確認
echo -e "${YELLOW}前提条件チェック...${NC}"
if ! curl -s --connect-timeout 2 "$MEMORY_URL/health" > /dev/null 2>&1; then
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
# Todo API テスト
# ========================================
echo "----------------------------------------"
echo "Todo API テスト"
echo "----------------------------------------"

# テスト1: Todo追加
echo ""
echo -e "${YELLOW}テスト1: Todo追加${NC}"
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "テストタスク1" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      importance: 0.5,
      metadata: {
        owner: $owner,
        status: "pending"
      }
    }')")

TODO_ID1=$(echo "$RESULT" | jq -r '.id')
assert_equals "project/todo" "$(echo "$RESULT" | jq -r '.scope + "/" + .message' | grep -o 'project/todo' | head -1)" "Todoが保存される"

# テスト2: 2つ目のTodo追加
echo ""
echo -e "${YELLOW}テスト2: 2つ目のTodo追加${NC}"
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "テストタスク2" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      importance: 0.5,
      metadata: {
        owner: $owner,
        status: "pending"
      }
    }')")

TODO_ID2=$(echo "$RESULT" | jq -r '.id')
if [ -n "$TODO_ID2" ] && [ "$TODO_ID2" != "null" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 2つ目のTodoが保存される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 2つ目のTodoが保存されない"
    FAILED=$((FAILED + 1))
fi

# テスト3: Todo一覧取得（pending）
echo ""
echo -e "${YELLOW}テスト3: Todo一覧取得（pending）${NC}"
TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending")
COUNT=$(echo "$TODOS" | jq -r '.count')
assert_equals "2" "$COUNT" "pending Todoが2件取得される"

# テスト4: Todoの内容確認
echo ""
echo -e "${YELLOW}テスト4: Todoの内容確認${NC}"
FIRST_CONTENT=$(echo "$TODOS" | jq -r '.todos[0].content')
if [ "$FIRST_CONTENT" = "テストタスク2" ] || [ "$FIRST_CONTENT" = "テストタスク1" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Todoの内容が正しい"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: Todoの内容が不正 ($FIRST_CONTENT)"
    FAILED=$((FAILED + 1))
fi

# テスト5: Todo完了（metadata更新）
echo ""
echo -e "${YELLOW}テスト5: Todo完了（metadata更新）${NC}"
RESULT=$(curl -s -X PATCH "$MEMORY_URL/memory/$TODO_ID1" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"status": "done"}}')
assert_equals "Memory updated" "$(echo "$RESULT" | jq -r '.message')" "Todoを完了にできる"

# テスト6: pending Todoが1件になる
echo ""
echo -e "${YELLOW}テスト6: pending Todoが1件になる${NC}"
TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending")
COUNT=$(echo "$TODOS" | jq -r '.count')
assert_equals "1" "$COUNT" "pending Todoが1件になる"

# テスト7: all Todoは2件
echo ""
echo -e "${YELLOW}テスト7: all Todoは2件${NC}"
TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=all")
COUNT=$(echo "$TODOS" | jq -r '.count')
assert_equals "2" "$COUNT" "all Todoは2件"

# テスト8: done Todoは1件
echo ""
echo -e "${YELLOW}テスト8: done Todoは1件${NC}"
TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=done")
COUNT=$(echo "$TODOS" | jq -r '.count')
assert_equals "1" "$COUNT" "done Todoは1件"

# テスト9: Todo削除
echo ""
echo -e "${YELLOW}テスト9: Todo削除${NC}"
RESULT=$(curl -s -X DELETE "$MEMORY_URL/memory/$TODO_ID1")
assert_equals "Memory deleted" "$(echo "$RESULT" | jq -r '.message')" "Todoを削除できる"

# テスト10: 削除後のカウント
echo ""
echo -e "${YELLOW}テスト10: 削除後のカウント${NC}"
TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=all")
COUNT=$(echo "$TODOS" | jq -r '.count')
assert_equals "1" "$COUNT" "削除後は1件"

# ========================================
# エッジケーステスト
# ========================================
echo ""
echo "----------------------------------------"
echo "エッジケーステスト"
echo "----------------------------------------"

# テスト11: 日本語タスク
echo ""
echo -e "${YELLOW}テスト11: 日本語タスク${NC}"
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "日本語のタスク：テスト実装" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")

if [ "$(echo "$RESULT" | jq -r '.id')" != "null" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 日本語タスクが保存される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 日本語タスクが保存されない"
    FAILED=$((FAILED + 1))
fi

# テスト12: 特殊文字を含むタスク
echo ""
echo -e "${YELLOW}テスト12: 特殊文字を含むタスク${NC}"
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content 'タスク with "quotes" and <brackets>' \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")

if [ "$(echo "$RESULT" | jq -r '.id')" != "null" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 特殊文字を含むタスクが保存される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 特殊文字を含むタスクが保存されない"
    FAILED=$((FAILED + 1))
fi

# テスト13: 長いタスク（256文字以上）
echo ""
echo -e "${YELLOW}テスト13: 長いタスク${NC}"
LONG_CONTENT=$(printf 'A%.0s' {1..300})
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "$LONG_CONTENT" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")

if [ "$(echo "$RESULT" | jq -r '.id')" != "null" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 長いタスクが保存される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 長いタスクが保存されない"
    FAILED=$((FAILED + 1))
fi

# テスト14: 別ユーザーのTodoは取得されない
echo ""
echo -e "${YELLOW}テスト14: 別ユーザーのTodoは取得されない${NC}"
OTHER_USER="other-user@example.com"
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "他のユーザーのタスク" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$OTHER_USER" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")

# 元のユーザーで取得
TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=all")
CONTENTS=$(echo "$TODOS" | jq -r '.todos[].content')

if [[ "$CONTENTS" != *"他のユーザーのタスク"* ]]; then
    echo -e "${GREEN}✓ PASS${NC}: 別ユーザーのTodoは取得されない"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 別ユーザーのTodoが取得された"
    FAILED=$((FAILED + 1))
fi

# 他のユーザーのTodoを削除
OTHER_TODO_ID=$(echo "$RESULT" | jq -r '.id')
curl -s -X DELETE "$MEMORY_URL/memory/$OTHER_TODO_ID" > /dev/null 2>&1

# ========================================
# クリーンアップ
# ========================================
cleanup

# ========================================
# 結果サマリー
# ========================================
echo ""
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
