---
name: isac-memory
description: プロジェクトの長期記憶を管理します。
---

# ISAC Memory Skill

プロジェクトの長期記憶を管理します。

## project_id の取得ルール

**重要**: project_id は必ず `.isac.yaml` ファイルから取得すること。`$CLAUDE_PROJECT` 環境変数は `.isac.yaml` が存在しない場合のフォールバックとしてのみ使用する。

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
```

以下のすべての curl コマンドで、この方法で取得した `$PROJECT_ID` を使用すること。

## Memory Service 接続確認

全操作の実行前に、Memory Service の接続を確認する。

```bash
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# 接続確認（3秒タイムアウト）
if ! curl -s --max-time 3 "$MEMORY_URL/health" > /dev/null 2>&1; then
    echo "❌ Memory Service に接続できません（$MEMORY_URL）"
    echo ""
    echo "確認事項:"
    echo "  - Docker が起動しているか: docker ps"
    echo "  - Memory Service が起動しているか: docker compose -f memory-service/docker-compose.yml up -d"
    echo ""
    echo "Memory Service を起動してから再実行してください。"
    exit 1
fi
```

## スコープ

記憶には3つのスコープがあります：

| スコープ | 説明 | 対象 |
|---------|------|------|
| global | 全体共有 | 全ユーザー・全プロジェクト |
| team | チーム共有 | チームメンバー |
| project | プロジェクト限定 | プロジェクトメンバー |

## 記憶の検索

関連する記憶を検索:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESULT=$(curl -s --get "$MEMORY_URL/search" \
  --data-urlencode "query=認証" \
  --data-urlencode "scope=project" \
  --data-urlencode "scope_id=$PROJECT_ID")
COUNT=$(echo "$RESULT" | jq -r '.memories | length')

if [ "$COUNT" = "0" ] || [ -z "$COUNT" ] || [ "$COUNT" = "null" ]; then
    echo "該当する記憶は見つかりませんでした。"
else
    echo "## 🔍 検索結果（${COUNT}件）"
    echo ""
    echo "$RESULT" | jq -r '.memories | to_entries | .[] | "\(.key + 1). [\(.value.type)] \(.value.content | split("\n")[0] | .[0:70]) (ID: \(.value.id))"'
fi
```

## 記憶の保存

作業内容を記録:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESPONSE=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "記録したい内容" \
    --arg scope_id "$PROJECT_ID" \
    '{
      content: $content,
      type: "work",
      importance: 0.5,
      scope: "project",
      scope_id: $scope_id
    }')")

# 保存結果の確認
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    MEMORY_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "✅ 記憶を保存しました (ID: $MEMORY_ID)"
else
    echo "❌ 記憶の保存に失敗しました"
    echo "$RESPONSE"
fi
```

### 記憶タイプ

| タイプ | 説明 | 重要度目安 |
|--------|------|-----------|
| decision | 技術的決定 | 0.7-0.9 |
| work | 作業履歴 | 0.3-0.5 |
| knowledge | ナレッジ・学び | 0.5-0.7 |
| todo | 個人タスク（`/isac-todo` で管理） | 0.5 |

## コンテキスト取得

現在のクエリに関連するコンテキストを取得:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESULT=$(curl -s --get "$MEMORY_URL/context/$PROJECT_ID" \
  --data-urlencode "query=認証の実装")

if echo "$RESULT" | jq -e '.global_knowledge' > /dev/null 2>&1; then
    echo "## 📚 コンテキスト"
    echo ""
    echo "### グローバルナレッジ"
    echo "$RESULT" | jq -r '.global_knowledge // [] | .[] | "- [\(.type)] \(.content | split("\n")[0] | .[0:70])"'
    echo ""
    echo "### プロジェクト決定事項"
    echo "$RESULT" | jq -r '.project_decisions // [] | .[] | "- [\(.type)] \(.content | split("\n")[0] | .[0:70])"'
    echo ""
    echo "### 最近の作業"
    echo "$RESULT" | jq -r '.project_recent // [] | .[] | "- [\(.type)] \(.content | split("\n")[0] | .[0:70])"'
else
    echo "❌ コンテキストの取得に失敗しました"
fi
```

## 統計情報

プロジェクトの記憶統計:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESULT=$(curl -s "$MEMORY_URL/stats/$PROJECT_ID")

if echo "$RESULT" | jq -e '.total_memories' > /dev/null 2>&1; then
    TOTAL=$(echo "$RESULT" | jq -r '.total_memories')
    echo "## 📊 記憶統計（${PROJECT_ID}）"
    echo ""
    echo "合計: ${TOTAL}件"
    echo ""
    echo "### タイプ別"
    echo "$RESULT" | jq -r '.by_type | to_entries | .[] | "  \(.key): \(.value)件"'
else
    echo "❌ 統計情報の取得に失敗しました"
fi
```

## エクスポート

記憶をバックアップ:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

curl -s "$MEMORY_URL/export/$PROJECT_ID" > memory_backup.json

if [ -s memory_backup.json ]; then
    COUNT=$(jq -r '.memories | length' memory_backup.json 2>/dev/null || echo "不明")
    echo "✅ エクスポート完了: memory_backup.json（${COUNT}件）"
else
    echo "❌ エクスポートに失敗しました"
fi
```

## 出力フォーマット

### 検索結果

```
## 🔍 検索結果（3件）

1. [decision] 認証にはJWTを採用する (ID: abc123)
2. [work] 認証機能の実装を完了 (ID: def456)
3. [knowledge] JWT更新時のベストプラクティス (ID: ghi789)
```

### 検索結果なし

```
該当する記憶は見つかりませんでした。
```

### 保存成功時

```
✅ 記憶を保存しました (ID: abc123)
```

### 統計情報

```
## 📊 記憶統計（isac）

合計: 83件

### タイプ別
  decision: 15件
  work: 30件
  knowledge: 10件
  todo: 28件
```

### Memory Service 未接続時

```
❌ Memory Service に接続できません（http://localhost:8100）

確認事項:
  - Docker が起動しているか: docker ps
  - Memory Service が起動しているか: docker compose -f memory-service/docker-compose.yml up -d

Memory Service を起動してから再実行してください。
```

## 関連スキル

- `/isac-decide` - 決定の記録
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-code-review` - コードレビュー（実装の品質チェック）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-todo` - 個人タスク管理（add/list/done/clear）
- `/isac-suggest` - 状況に応じたSkill提案
