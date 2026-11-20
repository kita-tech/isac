#!/bin/bash
# Workflow スクリプトのスタブ実走テスト
#
# .claude/workflows/*.js の JS 部分（集約・重複排除・プロンプト組み立て）を、
# agent()/parallel() をスタブに差し替えて LLM なしで検証する。
#
# 実行方法:
#   bash tests/test_workflows.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node が見つからないため Workflow テストをスキップします"
    exit 77   # スキップ専用の終了コード（run_all_tests.sh が SKIPPED と表示する。PASSED 扱いにしない）
fi

EXIT_CODE=0
for test_file in "${SCRIPT_DIR}"/workflow_*.test.mjs; do
    [ -e "${test_file}" ] || continue
    if ! node "${test_file}"; then
        EXIT_CODE=1
    fi
done

exit "${EXIT_CODE}"
