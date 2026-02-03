#!/bin/bash
# ISAC CLI テスト
#
# isac コマンドの動作をテスト
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/test_cli.sh

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISAC_CMD="$SCRIPT_DIR/bin/isac"

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
echo "ISAC CLI テスト"
echo "========================================"
echo ""

# ========================================
# テスト1: isac status の基本動作
# ========================================
echo -e "${BLUE}テスト1: isac status の基本動作${NC}"
echo "----------------------------------------"

cd "$SCRIPT_DIR"

# 1-1. status コマンドが実行できる
STATUS_OUTPUT=$("$ISAC_CMD" status 2>&1)
if [ $? -eq 0 ]; then
    test_pass "isac status が正常終了する"
else
    test_fail "isac status の実行" "Exit code: $?"
fi

# 1-2. バージョン情報が表示される
if echo "$STATUS_OUTPUT" | grep -q "Version:"; then
    test_pass "バージョン情報が表示される"
else
    test_fail "バージョン情報の表示" "Version: が見つからない"
fi

# 1-3. Local バージョンが表示される
if echo "$STATUS_OUTPUT" | grep -q "Local:"; then
    test_pass "ローカルバージョンが表示される"
else
    test_fail "ローカルバージョンの表示" "Local: が見つからない"
fi

# 1-4. Status が表示される
if echo "$STATUS_OUTPUT" | grep -q "Status:"; then
    test_pass "ステータスが表示される"
else
    test_fail "ステータスの表示" "Status: が見つからない"
fi

# 1-5. Recent Changes が表示される
if echo "$STATUS_OUTPUT" | grep -q "Recent Changes:"; then
    test_pass "最近の変更が表示される"
else
    test_fail "最近の変更の表示" "Recent Changes: が見つからない"
fi

# 1-6. Cache 情報が表示される
if echo "$STATUS_OUTPUT" | grep -q "Cache:"; then
    test_pass "キャッシュ情報が表示される"
else
    test_fail "キャッシュ情報の表示" "Cache: が見つからない"
fi

echo ""

# ========================================
# テスト2: --no-cache オプション
# ========================================
echo -e "${BLUE}テスト2: --no-cache オプション${NC}"
echo "----------------------------------------"

# 2-1. --no-cache オプションが受け入れられる
NO_CACHE_OUTPUT=$("$ISAC_CMD" status --no-cache 2>&1)
if [ $? -eq 0 ]; then
    test_pass "isac status --no-cache が正常終了する"
else
    test_fail "isac status --no-cache の実行" "Exit code: $?"
fi

# 2-2. キャッシュが無効化される
if echo "$NO_CACHE_OUTPUT" | grep -q "Cache: disabled"; then
    test_pass "--no-cache でキャッシュが無効化される"
else
    test_fail "キャッシュ無効化の確認" "Cache: disabled が見つからない"
fi

echo ""

# ========================================
# テスト3: ISAC_NO_CACHE 環境変数
# ========================================
echo -e "${BLUE}テスト3: ISAC_NO_CACHE 環境変数${NC}"
echo "----------------------------------------"

# 3-1. 環境変数でキャッシュが無効化される
ENV_OUTPUT=$(ISAC_NO_CACHE=1 "$ISAC_CMD" status 2>&1)
if echo "$ENV_OUTPUT" | grep -q "Cache: disabled"; then
    test_pass "ISAC_NO_CACHE=1 でキャッシュが無効化される"
else
    test_fail "環境変数によるキャッシュ無効化" "Cache: disabled が見つからない"
fi

echo ""

# ========================================
# テスト4: キャッシュファイルの動作
# ========================================
echo -e "${BLUE}テスト4: キャッシュファイルの動作${NC}"
echo "----------------------------------------"

CACHE_FILE="$HOME/.isac/.version_cache"

# 4-1. キャッシュファイルが作成される（リモートアクセス後）
# まずキャッシュを削除
rm -f "$CACHE_FILE"

# --no-cache で実行してキャッシュを作成
"$ISAC_CMD" status --no-cache > /dev/null 2>&1

if [ -f "$CACHE_FILE" ]; then
    test_pass "キャッシュファイルが作成される"
else
    test_fail "キャッシュファイルの作成" "$CACHE_FILE が存在しない"
fi

# 4-2. キャッシュファイルにコミットハッシュが含まれる
if [ -f "$CACHE_FILE" ]; then
    CACHE_CONTENT=$(cat "$CACHE_FILE")
    if [[ "$CACHE_CONTENT" =~ ^[a-f0-9]{7}$ ]]; then
        test_pass "キャッシュファイルに有効なコミットハッシュが含まれる"
    else
        test_fail "キャッシュファイルの内容" "無効な内容: $CACHE_CONTENT"
    fi
fi

echo ""

# ========================================
# テスト5: isac help の確認
# ========================================
echo -e "${BLUE}テスト5: isac help の確認${NC}"
echo "----------------------------------------"

HELP_OUTPUT=$("$ISAC_CMD" help 2>&1)

# 5-1. Status Options が表示される
if echo "$HELP_OUTPUT" | grep -q "Status Options:"; then
    test_pass "Status Options がヘルプに表示される"
else
    test_fail "Status Options の表示" "Status Options: が見つからない"
fi

# 5-2. --no-cache がヘルプに表示される
if echo "$HELP_OUTPUT" | grep -q "\-\-no-cache"; then
    test_pass "--no-cache がヘルプに表示される"
else
    test_fail "--no-cache の説明" "--no-cache が見つからない"
fi

# 5-3. ISAC_NO_CACHE がヘルプに表示される
if echo "$HELP_OUTPUT" | grep -q "ISAC_NO_CACHE"; then
    test_pass "ISAC_NO_CACHE がヘルプに表示される"
else
    test_fail "ISAC_NO_CACHE の説明" "ISAC_NO_CACHE が見つからない"
fi

echo ""

# ========================================
# 結果サマリー
# ========================================
echo "========================================"
echo "CLI テスト結果"
echo "========================================"
echo -e "${GREEN}PASSED${NC}: $PASSED"
echo -e "${RED}FAILED${NC}: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}テストが失敗しました${NC}"
    exit 1
else
    echo -e "${GREEN}すべてのCLIテストが成功しました${NC}"
    exit 0
fi
