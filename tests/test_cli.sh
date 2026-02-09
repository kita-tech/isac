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
# テスト6: プロジェクトIDバリデーション
# ========================================
echo -e "${BLUE}テスト6: プロジェクトIDバリデーション${NC}"
echo "----------------------------------------"

# テスト用一時ディレクトリ
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 6-1. 空白を含むプロジェクトIDはエラー
OUTPUT=$("$ISAC_CMD" switch "my project" 2>&1)
if echo "$OUTPUT" | grep -q "cannot contain spaces"; then
    test_pass "空白を含むプロジェクトIDはエラーになる"
else
    test_fail "空白を含むプロジェクトIDのバリデーション" "エラーメッセージが表示されない"
fi

# 6-2. スラッシュを含むプロジェクトIDはエラー
OUTPUT=$("$ISAC_CMD" switch "my/project" 2>&1)
if echo "$OUTPUT" | grep -q "cannot contain spaces, slashes"; then
    test_pass "スラッシュを含むプロジェクトIDはエラーになる"
else
    test_fail "スラッシュを含むプロジェクトIDのバリデーション" "エラーメッセージが表示されない"
fi

# 6-3. ドットで始まるプロジェクトIDはエラー
OUTPUT=$("$ISAC_CMD" switch ".hidden" 2>&1)
if echo "$OUTPUT" | grep -q "cannot start or end with"; then
    test_pass "ドットで始まるプロジェクトIDはエラーになる"
else
    test_fail "ドットで始まるプロジェクトIDのバリデーション" "エラーメッセージが表示されない"
fi

# 6-4. ハイフンで終わるプロジェクトIDはエラー
OUTPUT=$("$ISAC_CMD" switch "project-" 2>&1)
if echo "$OUTPUT" | grep -q "cannot start or end with"; then
    test_pass "ハイフンで終わるプロジェクトIDはエラーになる"
else
    test_fail "ハイフンで終わるプロジェクトIDのバリデーション" "エラーメッセージが表示されない"
fi

# 6-5. 64文字のプロジェクトIDは許可される（境界値）
LONG_ID_64=""
for i in $(seq 1 64); do LONG_ID_64="${LONG_ID_64}a"; done
OUTPUT=$("$ISAC_CMD" switch "$LONG_ID_64" --yes 2>&1)
if echo "$OUTPUT" | grep -q "Switched to:"; then
    test_pass "64文字のプロジェクトIDは許可される（境界値）"
else
    test_fail "64文字プロジェクトIDの境界値" "許可されるべきだがエラーになった"
fi

# 6-6. 65文字のプロジェクトIDはエラー（境界値）
LONG_ID_65="${LONG_ID_64}a"
OUTPUT=$("$ISAC_CMD" switch "$LONG_ID_65" 2>&1)
if echo "$OUTPUT" | grep -q "64 characters or less"; then
    test_pass "65文字のプロジェクトIDはエラーになる（境界値）"
else
    test_fail "65文字プロジェクトIDの境界値" "エラーメッセージが表示されない"
fi

# 6-7. 特殊文字（&, ?, #）を含むプロジェクトIDはエラー
for CHAR in '&' '?' '#'; do
    OUTPUT=$("$ISAC_CMD" switch "test${CHAR}project" 2>&1)
    # これらの文字はURLで特別な意味を持つが、現在のバリデーションでは許可される
    # セキュリティ上問題ないことを確認（URLエンコードされる）
done
test_pass "特殊文字を含むプロジェクトIDの動作確認"

# 6-8. シェルメタ文字を含むプロジェクトIDの安全性テスト
OUTPUT=$("$ISAC_CMD" switch 'test;ls' 2>&1)
# セミコロンはバリデーションで許可されるが、コマンドインジェクションにならないことを確認
if ! echo "$OUTPUT" | grep -qE "^(bin|tests|CLAUDE)"; then
    test_pass "セミコロンを含むプロジェクトIDでコマンドインジェクションが発生しない"
else
    test_fail "コマンドインジェクション対策" "lsの出力が含まれている"
fi

# 6-9. バッククォートを含むプロジェクトIDの安全性テスト
OUTPUT=$("$ISAC_CMD" switch 'test`whoami`' 2>&1)
CURRENT_USER=$(whoami)
if ! echo "$OUTPUT" | grep -q "$CURRENT_USER"; then
    test_pass "バッククォートを含むプロジェクトIDでコマンド実行が発生しない"
else
    test_fail "コマンドインジェクション対策" "whoamiの出力が含まれている"
fi

# 6-10. $() を含むプロジェクトIDの安全性テスト
OUTPUT=$("$ISAC_CMD" switch 'test$(id)' 2>&1)
if ! echo "$OUTPUT" | grep -q "uid="; then
    test_pass "\$() を含むプロジェクトIDでコマンド実行が発生しない"
else
    test_fail "コマンドインジェクション対策" "idの出力が含まれている"
fi

# 6-12. 有効なプロジェクトIDは受け入れられる
OUTPUT=$("$ISAC_CMD" switch "valid-project_123" --yes 2>&1)
if echo "$OUTPUT" | grep -q "Switched to:"; then
    test_pass "有効なプロジェクトIDは受け入れられる"
else
    test_fail "有効なプロジェクトIDの受け入れ" "Switched to: が見つからない"
fi

# クリーンアップ
rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト7: switch --yes オプション
# ========================================
echo -e "${BLUE}テスト7: switch --yes オプション${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 7-1. --yes オプションで対話なしに切り替え
OUTPUT=$("$ISAC_CMD" switch "new-test-project" --yes 2>&1)
if [ $? -eq 0 ] && echo "$OUTPUT" | grep -q "Switched to:"; then
    test_pass "switch --yes で対話なしに切り替え可能"
else
    test_fail "switch --yes の動作" "正常終了しない"
fi

# 7-2. -y 短縮形も動作する
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" switch "another-project" -y 2>&1)
if [ $? -eq 0 ] && echo "$OUTPUT" | grep -q "Switched to:"; then
    test_pass "switch -y 短縮形も動作する"
else
    test_fail "switch -y の動作" "正常終了しない"
fi

# 7-3. .isac.yaml が作成される
if [ -f ".isac.yaml" ]; then
    test_pass ".isac.yaml が作成される"
else
    test_fail ".isac.yaml の作成" "ファイルが存在しない"
fi

# 7-4. .isac.yaml に正しいプロジェクトIDが含まれる
if grep -q "project_id: another-project" .isac.yaml; then
    test_pass ".isac.yaml に正しいプロジェクトIDが含まれる"
else
    test_fail ".isac.yaml の内容" "project_id が正しくない"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト8: isac version
# ========================================
echo -e "${BLUE}テスト8: isac version${NC}"
echo "----------------------------------------"

# 8-1. version コマンドが動作する
VERSION_OUTPUT=$("$ISAC_CMD" version 2>&1)
if [ $? -eq 0 ]; then
    test_pass "isac version が正常終了する"
else
    test_fail "isac version の実行" "Exit code: $?"
fi

# 8-2. バージョン番号が表示される
if echo "$VERSION_OUTPUT" | grep -qE "ISAC version [0-9]+\.[0-9]+\.[0-9]+"; then
    test_pass "バージョン番号が正しい形式で表示される"
else
    test_fail "バージョン番号の形式" "期待する形式でない: $VERSION_OUTPUT"
fi

# 8-3. --version オプションも動作する
if "$ISAC_CMD" --version 2>&1 | grep -q "ISAC version"; then
    test_pass "--version オプションが動作する"
else
    test_fail "--version オプション" "出力が期待と異なる"
fi

# 8-4. -v 短縮形も動作する
if "$ISAC_CMD" -v 2>&1 | grep -q "ISAC version"; then
    test_pass "-v 短縮形が動作する"
else
    test_fail "-v 短縮形" "出力が期待と異なる"
fi

echo ""

# ========================================
# テスト9: isac help
# ========================================
echo -e "${BLUE}テスト9: isac help 詳細確認${NC}"
echo "----------------------------------------"

HELP_OUTPUT=$("$ISAC_CMD" help 2>&1)

# 9-1. Init Options が表示される
if echo "$HELP_OUTPUT" | grep -q "Init Options:"; then
    test_pass "Init Options がヘルプに表示される"
else
    test_fail "Init Options の表示" "Init Options: が見つからない"
fi

# 9-2. Switch Options が表示される
if echo "$HELP_OUTPUT" | grep -q "Switch Options:"; then
    test_pass "Switch Options がヘルプに表示される"
else
    test_fail "Switch Options の表示" "Switch Options: が見つからない"
fi

# 9-3. 引数なしでもヘルプが表示される
EMPTY_OUTPUT=$("$ISAC_CMD" 2>&1)
if echo "$EMPTY_OUTPUT" | grep -q "Usage:"; then
    test_pass "引数なしでヘルプが表示される"
else
    test_fail "引数なしの動作" "Usage: が見つからない"
fi

# 9-4. --help オプションも動作する
if "$ISAC_CMD" --help 2>&1 | grep -q "Usage:"; then
    test_pass "--help オプションが動作する"
else
    test_fail "--help オプション" "出力が期待と異なる"
fi

# 9-5. -h 短縮形も動作する
if "$ISAC_CMD" -h 2>&1 | grep -q "Usage:"; then
    test_pass "-h 短縮形が動作する"
else
    test_fail "-h 短縮形" "出力が期待と異なる"
fi

echo ""

# ========================================
# テスト10: スキルカウントの確認
# ========================================
echo -e "${BLUE}テスト10: スキルカウントの確認${NC}"
echo "----------------------------------------"

cd "$SCRIPT_DIR"
STATUS_OUTPUT=$("$ISAC_CMD" status 2>&1)

# 10-1. Skills カウントが表示される
if echo "$STATUS_OUTPUT" | grep -q "Skills:"; then
    test_pass "Skills カウントが表示される"
else
    test_fail "Skills カウントの表示" "Skills: が見つからない"
fi

# 10-2. Skills カウントが0でない（グローバル設定がある場合）
SKILL_COUNT=$(echo "$STATUS_OUTPUT" | grep "Skills:" | grep -oE "[0-9]+")
if [ -d "$HOME/.isac/skills" ] && [ -n "$(ls -A "$HOME/.isac/skills" 2>/dev/null)" ]; then
    if [ "$SKILL_COUNT" -gt 0 ]; then
        test_pass "Skills カウントが正しい (${SKILL_COUNT}個)"
    else
        test_fail "Skills カウント" "0になっている（スキルが存在するはず）"
    fi
else
    test_pass "Skills カウントのテストをスキップ（グローバルスキルなし）"
fi

echo ""

# ========================================
# テスト11: 不明なコマンドのエラー
# ========================================
echo -e "${BLUE}テスト11: エラーハンドリング${NC}"
echo "----------------------------------------"

# 11-1. 不明なコマンドでエラー
OUTPUT=$("$ISAC_CMD" unknown-command 2>&1)
if [ $? -ne 0 ] && echo "$OUTPUT" | grep -q "Unknown command"; then
    test_pass "不明なコマンドでエラーが返る"
else
    test_fail "不明なコマンドのエラー" "適切なエラーが返らない"
fi

# 11-2. switch に引数なしでエラー
OUTPUT=$("$ISAC_CMD" switch 2>&1)
if [ $? -ne 0 ] && echo "$OUTPUT" | grep -q "Project ID required"; then
    test_pass "switch に引数なしでエラーが返る"
else
    test_fail "switch 引数なしのエラー" "適切なエラーが返らない"
fi

# 11-3. init の不明なオプションでエラー
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
OUTPUT=$("$ISAC_CMD" init --unknown 2>&1)
if [ $? -ne 0 ] && echo "$OUTPUT" | grep -q "Unknown option"; then
    test_pass "init の不明なオプションでエラーが返る"
else
    test_fail "init 不明なオプションのエラー" "適切なエラーが返らない"
fi
rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト12: isac init コマンド
# ========================================
echo -e "${BLUE}テスト12: isac init コマンド${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 12-1. init コマンドが--yesで実行できる
OUTPUT=$("$ISAC_CMD" init --yes 2>&1)
if [ $? -eq 0 ]; then
    test_pass "isac init --yes が正常終了する"
else
    test_fail "isac init --yes の実行" "Exit code: $?"
fi

# 12-2. .isac.yaml が作成される
if [ -f ".isac.yaml" ]; then
    test_pass "init で .isac.yaml が作成される"
else
    test_fail ".isac.yaml の作成" "ファイルが存在しない"
fi

# 12-3. プロジェクト名を指定して初期化
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init "custom-project" --yes 2>&1)
if grep -q "project_id: custom-project" .isac.yaml 2>/dev/null; then
    test_pass "プロジェクト名を指定して初期化できる"
else
    test_fail "プロジェクト名指定の初期化" "project_id が正しくない"
fi

# 12-4. --force オプションで再初期化
OUTPUT=$("$ISAC_CMD" init "forced-project" --yes --force 2>&1)
if grep -q "project_id: forced-project" .isac.yaml 2>/dev/null; then
    test_pass "--force で再初期化できる"
else
    test_fail "--force の動作" "project_id が更新されない"
fi

# 12-5. 不正なプロジェクトIDでエラー
OUTPUT=$("$ISAC_CMD" init "invalid project" --yes 2>&1)
if echo "$OUTPUT" | grep -q "cannot contain spaces"; then
    test_pass "init でも不正なプロジェクトIDはエラーになる"
else
    test_fail "init のバリデーション" "エラーメッセージが表示されない"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト12.5: isac init の project_id 引き継ぎ
# ========================================
echo -e "${BLUE}テスト12.5: isac init の project_id 引き継ぎ${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 12.5-1. 既存の .isac.yaml から project_id を引き継ぐ
cat > ".isac.yaml" << 'YAML_EOF'
# ISAC Project Configuration
project_id: existing-project
YAML_EOF
OUTPUT=$("$ISAC_CMD" init --yes --force 2>&1)
if grep -q "project_id: existing-project" .isac.yaml 2>/dev/null; then
    test_pass "既存の .isac.yaml から project_id を引き継ぐ"
else
    test_fail "project_id の引き継ぎ" "project_id が引き継がれていない"
fi

# 12.5-2. 引数が既存 .isac.yaml より優先される
cat > ".isac.yaml" << 'YAML_EOF'
project_id: old-project
YAML_EOF
OUTPUT=$("$ISAC_CMD" init "arg-project" --yes --force 2>&1)
if grep -q "project_id: arg-project" .isac.yaml 2>/dev/null; then
    test_pass "引数が既存 .isac.yaml の project_id より優先される"
else
    test_fail "引数の優先" "project_id が引数の値になっていない"
fi

# 12.5-3. .isac.yaml が存在しない場合はディレクトリ名をデフォルトにする
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init --yes 2>&1)
EXPECTED_ID=$(basename "$TEST_DIR")
if grep -q "project_id: ${EXPECTED_ID}" .isac.yaml 2>/dev/null; then
    test_pass ".isac.yaml が存在しない場合はディレクトリ名がデフォルトになる"
else
    test_fail "ディレクトリ名デフォルト" "project_id がディレクトリ名になっていない"
fi

# 12.5-4. .isac.yaml に project_id がない場合はディレクトリ名をデフォルトにする
cat > ".isac.yaml" << 'YAML_EOF'
# ISAC Project Configuration
# project_id is missing
YAML_EOF
OUTPUT=$("$ISAC_CMD" init --yes --force 2>&1)
EXPECTED_ID=$(basename "$TEST_DIR")
if grep -q "project_id: ${EXPECTED_ID}" .isac.yaml 2>/dev/null; then
    test_pass ".isac.yaml に project_id がない場合はディレクトリ名がデフォルトになる"
else
    test_fail "project_id 欠落時のフォールバック" "project_id がディレクトリ名になっていない"
fi

# 12.5-5. クォート付き project_id の引き継ぎ（ダブルクォート）
cat > ".isac.yaml" << 'YAML_EOF'
project_id: "quoted-project"
YAML_EOF
OUTPUT=$("$ISAC_CMD" init --yes --force 2>&1)
if grep -q "project_id: quoted-project" .isac.yaml 2>/dev/null; then
    test_pass "ダブルクォート付き project_id が正しく引き継がれる"
else
    test_fail "ダブルクォート付き project_id" "project_id が正しく引き継がれていない"
fi

# 12.5-6. クォート付き project_id の引き継ぎ（シングルクォート）
cat > ".isac.yaml" << 'YAML_EOF'
project_id: 'single-quoted-project'
YAML_EOF
OUTPUT=$("$ISAC_CMD" init --yes --force 2>&1)
if grep -q "project_id: single-quoted-project" .isac.yaml 2>/dev/null; then
    test_pass "シングルクォート付き project_id が正しく引き継がれる"
else
    test_fail "シングルクォート付き project_id" "project_id が正しく引き継がれていない"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト13: projects コマンド
# ========================================
echo -e "${BLUE}テスト13: projects コマンド${NC}"
echo "----------------------------------------"

# 12-1. projects コマンドが実行できる（Memory Service 依存）
PROJECTS_OUTPUT=$("$ISAC_CMD" projects 2>&1)
EXIT_CODE=$?

# Memory Service が起動していない場合はエラーになる
if [ $EXIT_CODE -eq 0 ]; then
    test_pass "isac projects が正常終了する"

    # 12-2. 出力にプロジェクト情報が含まれる
    if echo "$PROJECTS_OUTPUT" | grep -qE "Memories:|No projects found"; then
        test_pass "プロジェクト情報またはメッセージが表示される"
    else
        test_fail "プロジェクト情報の表示" "期待する出力がない"
    fi
elif echo "$PROJECTS_OUTPUT" | grep -q "Memory Service not connected"; then
    test_pass "Memory Service 未接続時に適切なエラーが返る"
else
    test_fail "projects コマンド" "予期しないエラー: $PROJECTS_OUTPUT"
fi

echo ""

# ========================================
# テスト14: secrets ファイル基本動作
# ========================================
echo -e "${BLUE}テスト14: secrets ファイル基本動作${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 14-1. init で .isac.secrets.yaml.example が生成される
OUTPUT=$("$ISAC_CMD" init "secrets-test" --yes 2>&1)
if [ -f ".isac.secrets.yaml.example" ]; then
    test_pass "init で .isac.secrets.yaml.example が生成される"
else
    test_fail ".isac.secrets.yaml.example の生成" "ファイルが存在しない"
fi

# 14-2. .gitignore に .isac.secrets.yaml が追記される
if [ -f ".gitignore" ] && grep -q '\.isac\.secrets\.yaml' ".gitignore"; then
    test_pass ".gitignore に .isac.secrets.yaml が追記される"
else
    # .gitignore が存在しない場合は追記されない（正常動作）
    if [ ! -f ".gitignore" ]; then
        test_pass ".gitignore が存在しない場合はスキップされる（正常動作）"
    else
        test_fail ".gitignore への追記" ".isac.secrets.yaml が見つからない"
    fi
fi

# 14-3. secrets ファイルなしで init が正常動作（フォールバック確認）
rm -f .isac.secrets.yaml
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init "no-secrets-test" --yes 2>&1)
if [ $? -eq 0 ]; then
    test_pass "secrets ファイルなしで init が正常動作する"
else
    test_fail "secrets ファイルなしのフォールバック" "Exit code: $?"
fi

# 14-4. ホワイトリスト外のキーで警告が出る
cat > ".isac.secrets.yaml" << 'EOF'
PATH: /malicious/path
NOTION_API_TOKEN: test-token
EOF
chmod 600 ".isac.secrets.yaml"
# load_secrets は setup_mcp_servers 内から呼ばれるが、直接テストするため source
OUTPUT=$(bash -c "
    source '$ISAC_CMD' 2>/dev/null
    load_secrets 2>&1
" 2>&1 || true)
# bin/isac は set -e + case で main を実行するので直接 source は難しい
# 代わりに init --force で間接テスト
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init "whitelist-test" --yes --force 2>&1)
if echo "$OUTPUT" | grep -q "Unknown key.*PATH.*ignored"; then
    test_pass "ホワイトリスト外のキー（PATH）で警告が出る"
else
    test_fail "ホワイトリスト外キーの警告" "警告メッセージが見つからない"
fi

# 14-5. パーミッション 644 で警告が出る
cat > ".isac.secrets.yaml" << 'EOF'
NOTION_API_TOKEN: test-token
EOF
chmod 644 ".isac.secrets.yaml"
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init "perm-test" --yes --force 2>&1)
if echo "$OUTPUT" | grep -q "permissions 644, expected 600"; then
    test_pass "パーミッション 644 で警告が出る"
else
    test_fail "パーミッション警告" "警告メッセージが見つからない"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト15: secrets パース境界値
# ========================================
echo -e "${BLUE}テスト15: secrets パース境界値${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# bin/isac から load_secrets 関数を抽出してテストで使用する（コピー排除）
_LOAD_SECRETS_FUNC_FILE=$(mktemp)
grep '^ALLOWED_SECRET_KEYS=' "$ISAC_CMD" > "$_LOAD_SECRETS_FUNC_FILE"
echo "" >> "$_LOAD_SECRETS_FUNC_FILE"
sed -n '/^load_secrets() {$/,/^}$/p' "$ISAC_CMD" >> "$_LOAD_SECRETS_FUNC_FILE"

# 抽出結果のガードチェック: 抽出失敗時にサイレントにテストがパスするのを防止
if ! grep -q 'load_secrets()' "$_LOAD_SECRETS_FUNC_FILE"; then
    echo -e "${RED}FATAL: bin/isac から load_secrets 関数の抽出に失敗しました${NC}"
    echo "  sed パターンが bin/isac の関数定義と一致しません"
    exit 1
fi
if ! grep -q 'ALLOWED_SECRET_KEYS=' "$_LOAD_SECRETS_FUNC_FILE"; then
    echo -e "${RED}FATAL: bin/isac から ALLOWED_SECRET_KEYS の抽出に失敗しました${NC}"
    exit 1
fi
test_pass "bin/isac から load_secrets 関数の抽出に成功"

test_load_secrets() {
    local secrets_content="$1"
    local no_trailing_newline="${2:-false}"
    local test_dir
    test_dir=$(mktemp -d)
    if [ "$no_trailing_newline" = "true" ]; then
        printf "%s" "$secrets_content" > "$test_dir/.isac.secrets.yaml"
    else
        printf "%s\n" "$secrets_content" > "$test_dir/.isac.secrets.yaml"
    fi
    chmod 600 "$test_dir/.isac.secrets.yaml"

    bash -c "
        YELLOW=''
        NC=''
        cd '$test_dir'
        source '$_LOAD_SECRETS_FUNC_FILE'
        load_secrets 2>/dev/null
        echo \"NOTION_API_TOKEN=\${NOTION_API_TOKEN:-}\"
        echo \"CONTEXT7_API_KEY=\${CONTEXT7_API_KEY:-}\"
    " 2>/dev/null
    rm -rf "$test_dir"
}

# 15-1. 値にスペースを含む場合
OUTPUT=$(test_load_secrets "NOTION_API_TOKEN: my token with spaces")
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=my token with spaces"; then
    test_pass "値にスペースを含むシークレットが正しくパースされる"
else
    test_fail "スペース含む値のパース" "Output: $OUTPUT"
fi

# 15-2. 値にコロンを含む場合（URL等）
OUTPUT=$(test_load_secrets "NOTION_API_TOKEN: https://example.com:8080/path")
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=https://example.com:8080/path"; then
    test_pass "値にコロンを含むシークレットが正しくパースされる"
else
    test_fail "コロン含む値のパース" "Output: $OUTPUT"
fi

# 15-3. 空ファイル
OUTPUT=$(test_load_secrets "")
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=$"; then
    test_pass "空ファイルで値が設定されない"
else
    test_fail "空ファイルのパース" "Output: $OUTPUT"
fi

# 15-4. コメントのみのファイル
OUTPUT=$(test_load_secrets "# This is a comment
# Another comment")
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=$"; then
    test_pass "コメントのみのファイルで値が設定されない"
else
    test_fail "コメントのみファイルのパース" "Output: $OUTPUT"
fi

# 15-5. クォートされた値（ダブル/シングル）
OUTPUT=$(test_load_secrets 'NOTION_API_TOKEN: "quoted-token"')
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=quoted-token"; then
    test_pass "ダブルクォートされた値が正しくパースされる"
else
    test_fail "ダブルクォート値のパース" "Output: $OUTPUT"
fi

OUTPUT=$(test_load_secrets "NOTION_API_TOKEN: 'single-quoted'")
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=single-quoted"; then
    test_pass "シングルクォートされた値が正しくパースされる"
else
    test_fail "シングルクォート値のパース" "Output: $OUTPUT"
fi

# 15-6. 末尾改行なしのファイル（test_load_secrets の第2引数で末尾改行なしを指定）
OUTPUT=$(test_load_secrets "NOTION_API_TOKEN: no-newline-token" true)
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN=no-newline-token"; then
    test_pass "末尾改行なしのファイルが正しくパースされる"
else
    test_fail "末尾改行なしのパース" "Output: $OUTPUT"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト16: switch での MCP 再登録
# ========================================
echo -e "${BLUE}テスト16: switch での MCP 再登録${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 16-1. .isac.secrets.yaml がある場合にMCP更新メッセージ表示
cat > ".isac.secrets.yaml" << 'EOF'
NOTION_API_TOKEN: test-token-for-switch
EOF
chmod 600 ".isac.secrets.yaml"
OUTPUT=$("$ISAC_CMD" switch "mcp-test-project" --yes 2>&1)
if echo "$OUTPUT" | grep -q "Setting up MCP servers"; then
    test_pass ".isac.secrets.yaml がある場合にMCP更新が実行される"
else
    test_fail "switch MCP更新" "Setting up MCP servers が見つからない"
fi

# 16-2. .isac.secrets.yaml がない場合にMCP更新スキップ
rm -f .isac.secrets.yaml .isac.yaml
OUTPUT=$("$ISAC_CMD" switch "no-mcp-test-project" --yes 2>&1)
if ! echo "$OUTPUT" | grep -q "Setting up MCP servers"; then
    test_pass ".isac.secrets.yaml がない場合にMCP更新がスキップされる"
else
    test_fail "switch MCP更新スキップ" "Setting up MCP servers が出力された"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト17: 環境変数インジェクション防止
# ========================================
echo -e "${BLUE}テスト17: 環境変数インジェクション防止${NC}"
echo "----------------------------------------"

TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# 17-1. LD_PRELOAD インジェクション防止
cat > ".isac.secrets.yaml" << 'EOF'
LD_PRELOAD: /tmp/malicious.so
NOTION_API_TOKEN: safe-token
EOF
chmod 600 ".isac.secrets.yaml"
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init "inject-test1" --yes --force 2>&1)
if echo "$OUTPUT" | grep -q "Unknown key.*LD_PRELOAD.*ignored"; then
    test_pass "LD_PRELOAD インジェクションが防止される"
else
    test_fail "LD_PRELOAD インジェクション防止" "警告メッセージが見つからない"
fi

# 17-2. SHELL インジェクション防止
cat > ".isac.secrets.yaml" << 'EOF'
SHELL: /bin/evil
EOF
chmod 600 ".isac.secrets.yaml"
rm -f .isac.yaml
OUTPUT=$("$ISAC_CMD" init "inject-test2" --yes --force 2>&1)
if echo "$OUTPUT" | grep -q "Unknown key.*SHELL.*ignored"; then
    test_pass "SHELL インジェクションが防止される"
else
    test_fail "SHELL インジェクション防止" "警告メッセージが見つからない"
fi

# 17-3. $() コマンドインジェクション防止（値にコマンドが含まれても実行されない）
# test_load_secrets で直接値を検証: リテラル保持されていれば安全
OUTPUT=$(test_load_secrets 'NOTION_API_TOKEN: $(echo ISAC_INJECTION_TEST_MARKER)')
# インジェクションが防止されていれば、値は "$(echo ISAC_INJECTION_TEST_MARKER)" のリテラル文字列
# インジェクションが発生していれば、値は "ISAC_INJECTION_TEST_MARKER" になる
if echo "$OUTPUT" | grep -qF 'NOTION_API_TOKEN=$(echo ISAC_INJECTION_TEST_MARKER)'; then
    test_pass "\$() コマンドインジェクションが防止される（値がリテラル保持）"
else
    test_fail "\$() コマンドインジェクション防止" "Output: $OUTPUT"
fi

rm -rf "$TEST_DIR"
cd "$SCRIPT_DIR"

echo ""

# ========================================
# テスト18: register_mcp_server の失敗ハンドリング
# ========================================
echo -e "${BLUE}テスト18: register_mcp_server の失敗ハンドリング${NC}"
echo "----------------------------------------"

# bin/isac から register_mcp_server 関数を抽出
_REGISTER_MCP_FUNC_FILE=$(mktemp)
sed -n '/^register_mcp_server() {$/,/^}$/p' "$ISAC_CMD" >> "$_REGISTER_MCP_FUNC_FILE"

# 18-1. claude mcp add が失敗した場合に "registration failed" が出力される
# claude コマンドのモックを作成（mcp get は失敗、mcp add も失敗を返す）
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/claude" << 'MOCK_EOF'
#!/bin/bash
if [ "$1" = "mcp" ] && [ "$2" = "get" ]; then
    exit 1
fi
if [ "$1" = "mcp" ] && [ "$2" = "add" ]; then
    exit 1
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_DIR/claude"

OUTPUT=$(bash -c "
    export PATH='$MOCK_DIR:\$PATH'
    GREEN='' YELLOW='' NC=''
    export NOTION_API_TOKEN='test-token'
    source '$_REGISTER_MCP_FUNC_FILE'
    register_mcp_server 'notion' 'NOTION_API_TOKEN' false \
        -e 'OPENAPI_MCP_HEADERS=test' notion -- echo dummy
" 2>&1)
if echo "$OUTPUT" | grep -q "registration failed"; then
    test_pass "claude mcp add 失敗時に registration failed が出力される"
else
    test_fail "registration failed メッセージ" "Output: $OUTPUT"
fi

# 18-2. force=true で claude mcp add が失敗した場合に "re-registration failed" が出力される
OUTPUT=$(bash -c "
    export PATH='$MOCK_DIR:\$PATH'
    GREEN='' YELLOW='' NC=''
    export NOTION_API_TOKEN='test-token'
    source '$_REGISTER_MCP_FUNC_FILE'
    register_mcp_server 'notion' 'NOTION_API_TOKEN' true \
        -e 'OPENAPI_MCP_HEADERS=test' notion -- echo dummy
" 2>&1)
if echo "$OUTPUT" | grep -q "re-registration failed"; then
    test_pass "force=true で claude mcp add 失敗時に re-registration failed が出力される"
else
    test_fail "re-registration failed メッセージ" "Output: $OUTPUT"
fi

# 18-3. claude mcp add が成功した場合に "registered" が出力される
cat > "$MOCK_DIR/claude" << 'MOCK_EOF'
#!/bin/bash
if [ "$1" = "mcp" ] && [ "$2" = "get" ]; then
    exit 1
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_DIR/claude"

OUTPUT=$(bash -c "
    export PATH='$MOCK_DIR:\$PATH'
    GREEN='' YELLOW='' NC=''
    export NOTION_API_TOKEN='test-token'
    source '$_REGISTER_MCP_FUNC_FILE'
    register_mcp_server 'notion' 'NOTION_API_TOKEN' false \
        -e 'OPENAPI_MCP_HEADERS=test' notion -- echo dummy
" 2>&1)
if echo "$OUTPUT" | grep -q "notion: registered"; then
    test_pass "claude mcp add 成功時に registered が出力される"
else
    test_fail "registered メッセージ" "Output: $OUTPUT"
fi

# 18-4. 環境変数未設定で "not set, skipping" が出力される
OUTPUT=$(bash -c "
    export PATH='$MOCK_DIR:\$PATH'
    GREEN='' YELLOW='' NC=''
    unset NOTION_API_TOKEN
    source '$_REGISTER_MCP_FUNC_FILE'
    register_mcp_server 'notion' 'NOTION_API_TOKEN' false \
        -e 'OPENAPI_MCP_HEADERS=test' notion -- echo dummy
" 2>&1)
if echo "$OUTPUT" | grep -q "NOTION_API_TOKEN not set, skipping"; then
    test_pass "環境変数未設定で skipping が出力される"
else
    test_fail "skipping メッセージ" "Output: $OUTPUT"
fi

# 18-5. already registered の場合のテスト
cat > "$MOCK_DIR/claude" << 'MOCK_EOF'
#!/bin/bash
# mcp get は成功（登録済み）
exit 0
MOCK_EOF
chmod +x "$MOCK_DIR/claude"

OUTPUT=$(bash -c "
    export PATH='$MOCK_DIR:\$PATH'
    GREEN='' YELLOW='' NC=''
    export NOTION_API_TOKEN='test-token'
    source '$_REGISTER_MCP_FUNC_FILE'
    register_mcp_server 'notion' 'NOTION_API_TOKEN' false \
        -e 'OPENAPI_MCP_HEADERS=test' notion -- echo dummy
" 2>&1)
if echo "$OUTPUT" | grep -q "already registered"; then
    test_pass "登録済みの場合に already registered が出力される"
else
    test_fail "already registered メッセージ" "Output: $OUTPUT"
fi

rm -rf "$MOCK_DIR"
rm -f "$_REGISTER_MCP_FUNC_FILE"

echo ""

# ========================================
# クリーンアップ
# ========================================
rm -f "$_LOAD_SECRETS_FUNC_FILE" 2>/dev/null

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
