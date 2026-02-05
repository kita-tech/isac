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
RUN_COVERAGE=false

for arg in "$@"; do
    case $arg in
        --api-only)
            RUN_HOOKS=false
            RUN_INTEGRATION=false
            RUN_TODO=false
            ;;
        --hooks-only)
            RUN_API=false
            RUN_INTEGRATION=false
            RUN_TODO=false
            ;;
        --integration)
            RUN_API=false
            RUN_HOOKS=false
            RUN_TODO=false
            ;;
        --todo-only)
            RUN_API=false
            RUN_HOOKS=false
            RUN_INTEGRATION=false
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
            echo "  --quick         Hookテストと統合テストとTodoテストのみ (pytest不要)"
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

# Memory Serviceの起動確認
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"
if ! curl -s --connect-timeout 2 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Memory Service が起動していません${NC}"
    echo ""
    echo "以下のコマンドで起動してください:"
    echo "  cd $PROJECT_DIR/memory-service"
    echo "  docker compose up -d"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ Memory Service: OK${NC}"

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
