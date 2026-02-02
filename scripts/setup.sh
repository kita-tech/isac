#!/bin/bash
# ISAC Setup Script
# 新しいプロジェクトにISACをセットアップ

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISAC_ROOT="$(dirname "$SCRIPT_DIR")"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ISAC Setup ===${NC}"
echo ""

# 引数チェック
TARGET_DIR="${1:-.}"

if [ "$TARGET_DIR" = "." ]; then
    TARGET_DIR="$(pwd)"
fi

# ディレクトリ存在チェック
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Directory not found: $TARGET_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Target directory: $TARGET_DIR${NC}"
echo ""

# 1. .claude ディレクトリをコピー
echo -e "${GREEN}[1/4] Setting up .claude directory...${NC}"
if [ -d "$TARGET_DIR/.claude" ]; then
    echo -e "${YELLOW}  .claude already exists, merging...${NC}"
    cp -rn "$ISAC_ROOT/.claude/"* "$TARGET_DIR/.claude/" 2>/dev/null || true
else
    cp -r "$ISAC_ROOT/.claude" "$TARGET_DIR/"
fi

# Hooks に実行権限を付与
chmod +x "$TARGET_DIR/.claude/hooks/"*.sh 2>/dev/null || true

# 2. CLAUDE.md をコピー（存在しない場合のみ）
echo -e "${GREEN}[2/4] Setting up CLAUDE.md...${NC}"
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
    echo -e "${YELLOW}  CLAUDE.md already exists, skipping...${NC}"
else
    cp "$ISAC_ROOT/templates/CLAUDE.md.template" "$TARGET_DIR/CLAUDE.md"
    echo -e "${GREEN}  Created CLAUDE.md (please edit with your project details)${NC}"
fi

# 3. Memory Service のセットアップ（オプション）
echo -e "${GREEN}[3/4] Memory Service setup...${NC}"
echo -n "  Setup Memory Service? (y/N): "
read -r SETUP_MEMORY

if [ "$SETUP_MEMORY" = "y" ] || [ "$SETUP_MEMORY" = "Y" ]; then
    # Memory Service ディレクトリをコピー
    if [ ! -d "$TARGET_DIR/memory-service" ]; then
        cp -r "$ISAC_ROOT/memory-service" "$TARGET_DIR/"
        echo -e "${GREEN}  Copied memory-service directory${NC}"
    fi

    # Docker Compose で起動
    echo -e "${YELLOW}  Starting Memory Service...${NC}"
    (cd "$TARGET_DIR/memory-service" && docker compose up -d --build)

    # ヘルスチェック
    echo -n "  Waiting for Memory Service..."
    for i in {1..10}; do
        if curl -s http://localhost:8100/health > /dev/null 2>&1; then
            echo -e " ${GREEN}OK${NC}"
            break
        fi
        sleep 1
        echo -n "."
    done
else
    echo -e "${YELLOW}  Skipped (Memory Service is optional)${NC}"
fi

# 4. 環境変数の案内
echo -e "${GREEN}[4/4] Environment variables...${NC}"
echo ""
echo -e "${BLUE}Add these to your shell profile (~/.bashrc or ~/.zshrc):${NC}"
echo ""
echo "  export CLAUDE_PROJECT=\"$(basename "$TARGET_DIR")\""
echo "  export MEMORY_SERVICE_URL=\"http://localhost:8100\""
echo ""

# 完了メッセージ
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${BLUE}Usage:${NC}"
echo "  cd $TARGET_DIR"
echo "  claude                    # Start Claude Code CLI"
echo ""
echo -e "${BLUE}Skills:${NC}"
echo "  /memory                   # Manage memories"
echo "  /decide                   # Record important decisions"
echo ""
echo -e "${BLUE}Files created:${NC}"
echo "  .claude/settings.yaml    # Hook configuration"
echo "  .claude/hooks/           # Hook scripts"
echo "  .claude/skills/          # Skill definitions"
echo "  CLAUDE.md                # Project rules (please edit)"
echo ""
