---
name: isac-decide
description: 重要な技術的決定を記録します。
---

# ISAC Decide Skill

重要な技術的決定を記録します。

## project_id の取得ルール

**重要**: project_id は必ず `.isac.yaml` ファイルから取得すること。`$CLAUDE_PROJECT` 環境変数は `.isac.yaml` が存在しない場合のフォールバックとしてのみ使用する。

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
```

以下のすべての curl コマンドで、この方法で取得した `$PROJECT_ID` を使用すること。

## 使用場面

- アーキテクチャの決定
- 技術選定
- 設計パターンの採用
- 重要なルールの策定

## Memory Service 接続確認

決定の記録・検索の前に、Memory Service の接続を確認する。

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

## 決定の記録

重要な決定を記録する際は、以下の形式で Memory Service に保存してください:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESPONSE=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "【決定内容】認証にはJWTを採用する\n【理由】ステートレスでスケーラブル、マイクロサービスに適している\n【代替案】セッションベース認証 - サーバー側の状態管理が必要なため不採用" \
    --arg scope_id "$PROJECT_ID" \
    --arg category "authentication" \
    --arg decision "JWT採用" \
    '{
      content: $content,
      type: "decision",
      importance: 0.8,
      scope: "project",
      scope_id: $scope_id,
      metadata: {
        category: $category,
        decision: $decision
      }
    }')")

# 保存結果の確認
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    MEMORY_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "✅ 決定を記録しました (ID: $MEMORY_ID)"
else
    echo "❌ 決定の記録に失敗しました"
    echo "$RESPONSE"
fi
```

### グローバル決定（全プロジェクト共有）

組織全体に影響する決定は`scope: global`で保存:

```bash
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESPONSE=$(curl -s -X POST "$MEMORY_URL/store" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg content "【決定内容】全プロジェクトでPython 3.11以上を使用する" \
    --arg category "technology-stack" \
    '{
      content: $content,
      type: "decision",
      importance: 0.9,
      scope: "global",
      metadata: {
        category: $category
      }
    }')")

# 保存結果の確認
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    MEMORY_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "✅ グローバル決定を記録しました (ID: $MEMORY_ID)"
else
    echo "❌ 決定の記録に失敗しました"
    echo "$RESPONSE"
fi
```

## 重要度の目安

| 重要度 | 説明 | 例 |
|--------|------|-----|
| 0.9-1.0 | プロジェクト全体に影響 | アーキテクチャ決定 |
| 0.7-0.8 | 複数コンポーネントに影響 | 認証方式、DB選定 |
| 0.5-0.6 | 特定機能に影響 | ライブラリ選定 |
| 0.3-0.4 | 軽微な決定 | コーディングスタイル |

## 決定の検索

過去の決定を確認:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
MEMORY_URL="${MEMORY_SERVICE_URL:-http://localhost:8100}"

# Memory Service 接続確認（上記「Memory Service 接続確認」セクション参照）

RESULT=$(curl -s --get "$MEMORY_URL/search" \
  --data-urlencode "query=認証" \
  --data-urlencode "type=decision" \
  --data-urlencode "scope=project" \
  --data-urlencode "scope_id=$PROJECT_ID")
COUNT=$(echo "$RESULT" | jq -r '.memories | length')

if [ "$COUNT" = "0" ] || [ -z "$COUNT" ] || [ "$COUNT" = "null" ]; then
    echo "該当する決定は見つかりませんでした。"
else
    echo "## 📋 決定一覧（${COUNT}件）"
    echo ""
    echo "$RESULT" | jq -r '.memories | to_entries | .[] | "\(.key + 1). \(.value.content | split("\n")[0] | .[0:80]) (ID: \(.value.id))"'
fi
```

## 出力フォーマット

### 決定記録 成功時

```
✅ 決定を記録しました (ID: abc123)
```

### グローバル決定記録 成功時

```
✅ グローバル決定を記録しました (ID: abc123)
```

### 記録失敗時

```
❌ 決定の記録に失敗しました
```

### 検索結果

```
## 📋 決定一覧（2件）

1. 【決定内容】認証にはJWTを採用する (ID: abc123)
2. 【決定内容】セッション有効期限は15分 (ID: def456)
```

### 検索結果なし

```
該当する決定は見つかりませんでした。
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

- `/isac-memory` - 記憶の検索・管理
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-code-review` - コードレビュー（実装の品質チェック）
- `/isac-autopilot` - 設計→実装→テスト→レビュー→Draft PR作成を自動実行
- `/isac-save-memory` - AI分析による保存形式提案
- `/isac-suggest` - 状況に応じたSkill提案
