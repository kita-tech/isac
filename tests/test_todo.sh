#!/bin/bash
# ISAC Todo機能テスト
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/test_todo.sh
#
# 前提条件:
#   - Memory Service が http://localhost:8200 で起動していること
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
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8200}"
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

# テスト12: 特殊文字を含むタスク（保存・取得・表示）
echo ""
echo -e "${YELLOW}テスト12: 特殊文字を含むタスク${NC}"

# このテスト専用のユーザー
SPECIAL_CHAR_USER="special-char-test-$$@example.com"

# 各種特殊文字をテスト
declare -a SPECIAL_CHARS=(
    'タスク with "double quotes"'
    "タスク with 'single quotes'"
    'タスク with <brackets> & ampersand'
    'タスク with backslash \\ here'
    'タスク with backtick ` here'
    'タスク with dollar $VAR sign'
    $'タスク with tab\there'
)

SPECIAL_PASS=0
SPECIAL_FAIL=0

for SPECIAL_CONTENT in "${SPECIAL_CHARS[@]}"; do
    # 保存
    RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg content "$SPECIAL_CONTENT" \
        --arg scope_id "$PROJECT_ID" \
        --arg owner "$SPECIAL_CHAR_USER" \
        '{
          content: $content,
          type: "todo",
          scope: "project",
          scope_id: $scope_id,
          metadata: { owner: $owner, status: "pending" }
        }')")

    SPECIAL_ID=$(echo "$RESULT" | jq -r '.id')

    if [ "$SPECIAL_ID" != "null" ] && [ -n "$SPECIAL_ID" ]; then
        # 取得確認
        RETRIEVED=$(curl -s "$MEMORY_URL/memory/$SPECIAL_ID" | jq -r '.content')
        if [ "$RETRIEVED" = "$SPECIAL_CONTENT" ]; then
            # 表示確認（1行で表示されるか）
            DISPLAY=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$SPECIAL_CHAR_USER&status=pending" \
              | jq -r --arg id "$SPECIAL_ID" '.todos[] | select(.id == $id) | .content | split("\n")[0] | .[0:60]')
            if [ -n "$DISPLAY" ]; then
                SPECIAL_PASS=$((SPECIAL_PASS + 1))
            else
                echo "  表示失敗: $SPECIAL_CONTENT"
                SPECIAL_FAIL=$((SPECIAL_FAIL + 1))
            fi
        else
            echo "  取得内容不一致: $SPECIAL_CONTENT"
            SPECIAL_FAIL=$((SPECIAL_FAIL + 1))
        fi
        # クリーンアップ
        curl -s -X DELETE "$MEMORY_URL/memory/$SPECIAL_ID" > /dev/null 2>&1
    else
        echo "  保存失敗: $SPECIAL_CONTENT"
        SPECIAL_FAIL=$((SPECIAL_FAIL + 1))
    fi
done

if [ $SPECIAL_FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}: 特殊文字を含むタスクが保存・取得・表示される（${SPECIAL_PASS}件）"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 特殊文字テストに失敗（成功: ${SPECIAL_PASS}, 失敗: ${SPECIAL_FAIL}）"
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
# 追加エッジケーステスト
# ========================================
echo ""
echo "----------------------------------------"
echo "追加エッジケーステスト"
echo "----------------------------------------"

# テスト15: 空文字タスク
echo ""
echo -e "${YELLOW}テスト15: 空文字タスク${NC}"
RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")

# 空文字でも保存される（APIレベルでは制限なし）
if [ "$(echo "$RESULT" | jq -r '.id')" != "null" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 空文字タスクが保存される（API許容）"
    PASSED=$((PASSED + 1))
    # クリーンアップ
    EMPTY_TODO_ID=$(echo "$RESULT" | jq -r '.id')
    curl -s -X DELETE "$MEMORY_URL/memory/$EMPTY_TODO_ID" > /dev/null 2>&1
else
    echo -e "${RED}✗ FAIL${NC}: 空文字タスクの保存に失敗"
    FAILED=$((FAILED + 1))
fi

# テスト16: 同一内容の重複登録
echo ""
echo -e "${YELLOW}テスト16: 同一内容の重複登録${NC}"
DUPLICATE_CONTENT="重複テストタスク"

# 1回目
RESULT1=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "$DUPLICATE_CONTENT" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")
DUP_ID1=$(echo "$RESULT1" | jq -r '.id')

# 2回目（同じ内容）
RESULT2=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "$DUPLICATE_CONTENT" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")
DUP_ID2=$(echo "$RESULT2" | jq -r '.id')

# 両方保存される（重複は許容）
if [ "$DUP_ID1" != "null" ] && [ "$DUP_ID2" != "null" ] && [ "$DUP_ID1" != "$DUP_ID2" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 重複タスクは別々のIDで保存される"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 重複タスクの保存に問題"
    FAILED=$((FAILED + 1))
fi

# クリーンアップ
curl -s -X DELETE "$MEMORY_URL/memory/$DUP_ID1" > /dev/null 2>&1
curl -s -X DELETE "$MEMORY_URL/memory/$DUP_ID2" > /dev/null 2>&1

# テスト17: 存在しないIDでの完了操作
echo ""
echo -e "${YELLOW}テスト17: 存在しないIDでの完了操作${NC}"
FAKE_ID="nonexistent-id-12345"
RESULT=$(curl -s -X PATCH "$MEMORY_URL/memory/$FAKE_ID" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"status": "done"}}')

if [ "$(echo "$RESULT" | jq -r '.detail')" = "Memory not found" ]; then
    echo -e "${GREEN}✓ PASS${NC}: 存在しないIDでは404エラー"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: 存在しないIDのエラー処理が不正"
    echo "  Response: $RESULT"
    FAILED=$((FAILED + 1))
fi

# テスト18: done状態のタスク一括削除（clearコマンド相当）
echo ""
echo -e "${YELLOW}テスト18: done状態のタスク一括削除${NC}"

# このテスト用の専用ユーザーを使用（他テストの影響を排除）
CLEAR_TEST_USER="clear-test-$$@example.com"

# doneタスクを2つ作成
DONE1=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "完了済みタスク1" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$CLEAR_TEST_USER" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "done" }
    }')" | jq -r '.id')

DONE2=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "完了済みタスク2" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$CLEAR_TEST_USER" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "done" }
    }')" | jq -r '.id')

# pendingタスクを1つ作成
PENDING1=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "未完了タスク" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$CLEAR_TEST_USER" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')" | jq -r '.id')

# doneタスクを取得して削除（clearコマンドのシミュレーション）
DONE_TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$CLEAR_TEST_USER&status=done")
DONE_IDS=$(echo "$DONE_TODOS" | jq -r '.todos[].id')
DONE_COUNT=$(echo "$DONE_TODOS" | jq -r '.count')

for id in $DONE_IDS; do
    curl -s -X DELETE "$MEMORY_URL/memory/$id" > /dev/null 2>&1
done

# 削除後、pendingのみ残っているか確認
REMAINING=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$CLEAR_TEST_USER&status=all")
REMAINING_COUNT=$(echo "$REMAINING" | jq -r '.count')

if [ "$DONE_COUNT" = "2" ] && [ "$REMAINING_COUNT" = "1" ]; then
    echo -e "${GREEN}✓ PASS${NC}: done状態のタスクのみ削除された"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: clear処理に問題（done: $DONE_COUNT, remaining: $REMAINING_COUNT）"
    FAILED=$((FAILED + 1))
fi

# 残ったpendingタスクを削除
curl -s -X DELETE "$MEMORY_URL/memory/$PENDING1" > /dev/null 2>&1

# テスト19: 改行を含むタスク
echo ""
echo -e "${YELLOW}テスト19: 改行を含むタスク${NC}"
MULTILINE_CONTENT="改行を含むタスク
2行目の内容
3行目の内容"

RESULT=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "$MULTILINE_CONTENT" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending" }
    }')")

MULTILINE_TODO_ID=$(echo "$RESULT" | jq -r '.id')

if [ "$MULTILINE_TODO_ID" != "null" ] && [ -n "$MULTILINE_TODO_ID" ]; then
    # /my/todos で取得できるか確認
    TODOS=$(curl -s "$MEMORY_URL/my/todos?project_id=$PROJECT_ID&owner=$USER_EMAIL&status=pending")
    # jqでパースできるか確認（改行を含むJSONが正しく処理されるか）
    PARSE_CHECK=$(echo "$TODOS" | jq -r '.count' 2>&1)
    if [[ "$PARSE_CHECK" =~ ^[0-9]+$ ]]; then
        echo -e "${GREEN}✓ PASS${NC}: 改行を含むタスクが保存・取得できる"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: 改行を含むタスクの取得でパースエラー"
        echo "  Error: $PARSE_CHECK"
        FAILED=$((FAILED + 1))
    fi
    # 表示テスト: 改行を含むcontentが1行で表示されるか（該当タスクのみチェック）
    DISPLAY_LINE=$(echo "$TODOS" | jq -r --arg id "$MULTILINE_TODO_ID" '.todos[] | select(.id == $id) | .content | split("\n")[0] | .[0:60]' 2>&1)
    # 表示結果に改行が含まれていないことを確認
    if [[ "$DISPLAY_LINE" == "改行を含むタスク" ]] && [[ ! "$DISPLAY_LINE" =~ $'\n' ]]; then
        echo -e "${GREEN}✓ PASS${NC}: 改行を含むタスクが1行で表示される"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: 改行を含むタスクの表示に問題"
        echo "  Display: $DISPLAY_LINE"
        FAILED=$((FAILED + 1))
    fi
    # クリーンアップ
    curl -s -X DELETE "$MEMORY_URL/memory/$MULTILINE_TODO_ID" > /dev/null 2>&1
else
    echo -e "${RED}✗ FAIL${NC}: 改行を含むタスクが保存されない"
    FAILED=$((FAILED + 1))
fi

# テスト20: metadata更新のマージ動作
echo ""
echo -e "${YELLOW}テスト20: metadata更新のマージ動作${NC}"

# タスク作成（複数のmetadataフィールド）
MERGE_TODO=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "マージテストタスク" \
    --arg scope_id "$PROJECT_ID" \
    --arg owner "$USER_EMAIL" \
    '{
      content: $content,
      type: "todo",
      scope: "project",
      scope_id: $scope_id,
      metadata: { owner: $owner, status: "pending", priority: "high" }
    }')" | jq -r '.id')

# statusのみ更新（ownerとpriorityは保持されるべき）
curl -s -X PATCH "$MEMORY_URL/memory/$MERGE_TODO" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"status": "done"}}' > /dev/null

# 更新後のmetadataを確認
UPDATED=$(curl -s "$MEMORY_URL/memory/$MERGE_TODO")
UPDATED_OWNER=$(echo "$UPDATED" | jq -r '.metadata.owner')
UPDATED_STATUS=$(echo "$UPDATED" | jq -r '.metadata.status')
UPDATED_PRIORITY=$(echo "$UPDATED" | jq -r '.metadata.priority')

if [ "$UPDATED_OWNER" = "$USER_EMAIL" ] && [ "$UPDATED_STATUS" = "done" ] && [ "$UPDATED_PRIORITY" = "high" ]; then
    echo -e "${GREEN}✓ PASS${NC}: metadata更新がマージされた（既存値保持）"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}: metadata更新でマージが機能していない"
    echo "  owner: $UPDATED_OWNER, status: $UPDATED_STATUS, priority: $UPDATED_PRIORITY"
    FAILED=$((FAILED + 1))
fi

# クリーンアップ
curl -s -X DELETE "$MEMORY_URL/memory/$MERGE_TODO" > /dev/null 2>&1

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
