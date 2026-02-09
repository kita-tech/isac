#!/bin/bash
# ISAC テストランナー
#
# すべてのテストを実行
#
# 実行方法:
#   cd /path/to/isac
#   bash tests/run_all_tests.sh
#
# オプション:
#   --api-only      APIテストのみ実行
#   --hooks-only    Hookテストのみ実行
#   --integration   統合テストのみ実行
#   --quick         Hookテストと統合テストのみ（pytest不要）
#   --coverage      カバレッジ計測を有効化（HTMLレポート生成）

set -e

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# オプション解析
RUN_API=true
RUN_HOOKS=true
RUN_INTEGRATION=true
RUN_TODO=true
RUN_CLI=true
RUN_COVERAGE=false

for arg in "$@"; do
    case $arg in
        --api-only)
            RUN_HOOKS=false
            RUN_INTEGRATION=false
            RUN_TODO=false
            RUN_CLI=false
            ;;
        --hooks-only)
            RUN_API=false
            RUN_INTEGRATION=false
            RUN_TODO=false
            RUN_CLI=false
            ;;
        --integration)
            RUN_API=false
            RUN_HOOKS=false
            RUN_TODO=false
            RUN_CLI=false
            ;;
        --todo-only)
            RUN_API=false
            RUN_HOOKS=false
            RUN_INTEGRATION=false
            RUN_CLI=false
            ;;
        --cli-only)
            RUN_API=false
            RUN_HOOKS=false
            RUN_INTEGRATION=false
            RUN_TODO=false
            ;;
        --quick)
            RUN_API=false
            ;;
        --coverage)
            RUN_COVERAGE=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --api-only      APIテストのみ実行 (pytest必要)"
            echo "  --hooks-only    Hookテストのみ実行"
            echo "  --integration   統合テストのみ実行"
            echo "  --todo-only     Todoテストのみ実行"
            echo "  --cli-only      CLIテストのみ実行"
            echo "  --quick         Hookテストと統合テストとTodoテストとCLIテストのみ (pytest不要)"
            echo "  --coverage      カバレッジ計測を有効化 (HTMLレポート生成)"
            echo ""
            exit 0
            ;;
    esac
done

echo "========================================"
echo -e "${BLUE}ISAC テストスイート${NC}"
echo "========================================"
echo ""

# 前提条件チェック
echo -e "${YELLOW}前提条件チェック...${NC}"

# テスト用ポート（通常運用の 8100 と分離）
TEST_PORT=8200
TEST_PROJECT_NAME="isac-memory-test"
MEMORY_URL="http://localhost:${TEST_PORT}"
export MEMORY_SERVICE_URL="$MEMORY_URL"
export ISAC_TEST_URL="$MEMORY_URL"

# テスト用コンテナの起動（-p でプロジェクト名を分離し、通常運用コンテナに影響しない）
echo -e "${YELLOW}テスト用 Memory Service コンテナを起動中 (ポート: ${TEST_PORT})...${NC}"
docker compose -p "$TEST_PROJECT_NAME" -f "$PROJECT_DIR/memory-service/docker-compose.test.yml" up -d --build 2>&1 | while read -r line; do
    echo "  $line"
done

# テスト終了時にコンテナを停止・削除（Ctrl+C 含む）
cleanup_containers() {
    echo ""
    echo -e "${YELLOW}テスト用コンテナを停止・削除中...${NC}"
    docker compose -p "$TEST_PROJECT_NAME" -f "$PROJECT_DIR/memory-service/docker-compose.test.yml" down -v 2>/dev/null
    echo -e "${GREEN}✓ クリーンアップ完了${NC}"
}
trap cleanup_containers EXIT

# ヘルスチェック待機（最大30秒）
echo -e "${YELLOW}ヘルスチェック待機中...${NC}"
MAX_WAIT=30
WAITED=0
while ! curl -s --connect-timeout 2 "$MEMORY_URL/health" > /dev/null 2>&1; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo -e "${RED}ERROR: Memory Service が ${MAX_WAIT}秒以内に起動しませんでした${NC}"
        echo ""
        echo "ログを確認してください:"
        echo "  docker compose -p $TEST_PROJECT_NAME -f $PROJECT_DIR/memory-service/docker-compose.test.yml logs"
        echo ""
        exit 1
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done
echo -e "${GREEN}✓ Memory Service: OK (ポート: ${TEST_PORT})${NC}"

# jqの確認
if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq がインストールされていません${NC}"
    echo "  brew install jq  または  apt-get install jq"
    exit 1
fi
echo -e "${GREEN}✓ jq: OK${NC}"

# pytestの確認（APIテスト用）
if [ "$RUN_API" = true ]; then
    if ! command -v pytest &> /dev/null; then
        echo -e "${YELLOW}⚠ pytest がインストールされていません${NC}"
        echo "  pip install pytest requests"
        echo "  APIテストをスキップします"
        RUN_API=false
    else
        echo -e "${GREEN}✓ pytest: OK${NC}"
    fi
fi

echo ""

# 結果を格納
RESULTS=()
EXIT_CODE=0

# ========================================
# APIテスト（pytest）
# ========================================
if [ "$RUN_API" = true ]; then
    echo "========================================"
    echo -e "${BLUE}1. Memory Service APIテスト${NC}"
    echo "========================================"
    echo ""

    cd "$PROJECT_DIR"

    # カバレッジオプションの構築
    PYTEST_OPTS="-v --tb=short"
    if [ "$RUN_COVERAGE" = true ]; then
        PYTEST_OPTS="$PYTEST_OPTS --cov=memory-service --cov-report=term-missing --cov-report=html"
        echo -e "${YELLOW}カバレッジ計測を有効化${NC}"
    fi

    if pytest tests/test_memory_service.py $PYTEST_OPTS; then
        RESULTS+=("API Tests: ${GREEN}PASSED${NC}")
        if [ "$RUN_COVERAGE" = true ]; then
            echo ""
            echo -e "${GREEN}カバレッジレポート生成完了: htmlcov/index.html${NC}"
        fi
    else
        RESULTS+=("API Tests: ${RED}FAILED${NC}")
        EXIT_CODE=1
    fi
    echo ""
fi

# ========================================
# Hookテスト
# ========================================
if [ "$RUN_HOOKS" = true ]; then
    echo "========================================"
    echo -e "${BLUE}2. Hookテスト${NC}"
    echo "========================================"
    echo ""

    if bash "$SCRIPT_DIR/test_hooks.sh"; then
        RESULTS+=("Hook Tests: ${GREEN}PASSED${NC}")
    else
        RESULTS+=("Hook Tests: ${RED}FAILED${NC}")
        EXIT_CODE=1
    fi
    echo ""
fi

# ========================================
# 統合テスト
# ========================================
if [ "$RUN_INTEGRATION" = true ]; then
    echo "========================================"
    echo -e "${BLUE}3. 統合テスト${NC}"
    echo "========================================"
    echo ""

    if bash "$SCRIPT_DIR/test_integration.sh"; then
        RESULTS+=("Integration Tests: ${GREEN}PASSED${NC}")
    else
        RESULTS+=("Integration Tests: ${RED}FAILED${NC}")
        EXIT_CODE=1
    fi
    echo ""
fi

# ========================================
# Todoテスト
# ========================================
if [ "$RUN_TODO" = true ]; then
    echo "========================================"
    echo -e "${BLUE}4. Todoテスト${NC}"
    echo "========================================"
    echo ""

    if bash "$SCRIPT_DIR/test_todo.sh"; then
        RESULTS+=("Todo Tests: ${GREEN}PASSED${NC}")
    else
        RESULTS+=("Todo Tests: ${RED}FAILED${NC}")
        EXIT_CODE=1
    fi
    echo ""
fi

# ========================================
# CLIテスト
# ========================================
if [ "$RUN_CLI" = true ]; then
    echo "========================================"
    echo -e "${BLUE}5. CLIテスト${NC}"
    echo "========================================"
    echo ""

    if bash "$SCRIPT_DIR/test_cli.sh"; then
        RESULTS+=("CLI Tests: ${GREEN}PASSED${NC}")
    else
        RESULTS+=("CLI Tests: ${RED}FAILED${NC}")
        EXIT_CODE=1
    fi
    echo ""
fi

# ========================================
# 最終結果
# ========================================
echo "========================================"
echo -e "${BLUE}テスト結果サマリー${NC}"
echo "========================================"
for result in "${RESULTS[@]}"; do
    echo -e "  $result"
done
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}すべてのテストが成功しました！${NC}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}一部のテストが失敗しました${NC}"
    echo -e "${RED}========================================${NC}"
fi

exit $EXIT_CODE
