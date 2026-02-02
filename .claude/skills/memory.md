# Memory Skill

プロジェクトの長期記憶を管理します。

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
curl --get "${MEMORY_SERVICE_URL:-http://localhost:8100}/search" \
  --data-urlencode "query=認証" \
  --data-urlencode "scope=project" \
  --data-urlencode "scope_id=${CLAUDE_PROJECT:-default}"
```

## 記憶の保存

作業内容を記録:

```bash
curl -X POST "${MEMORY_SERVICE_URL:-http://localhost:8100}/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "記録したい内容",
    "type": "work",
    "importance": 0.5,
    "scope": "project",
    "scope_id": "'"${CLAUDE_PROJECT:-default}"'"
  }'
```

### 記憶タイプ

| タイプ | 説明 | 重要度目安 |
|--------|------|-----------|
| decision | 技術的決定 | 0.7-0.9 |
| work | 作業履歴 | 0.3-0.5 |
| knowledge | ナレッジ・学び | 0.5-0.7 |

## コンテキスト取得

現在のクエリに関連するコンテキストを取得:

```bash
curl --get "${MEMORY_SERVICE_URL:-http://localhost:8100}/context/${CLAUDE_PROJECT:-default}" \
  --data-urlencode "query=認証の実装"
```

## 統計情報

プロジェクトの記憶統計:

```bash
curl "${MEMORY_SERVICE_URL:-http://localhost:8100}/stats/${CLAUDE_PROJECT:-default}"
```

## エクスポート

記憶をバックアップ:

```bash
curl "${MEMORY_SERVICE_URL:-http://localhost:8100}/export/${CLAUDE_PROJECT:-default}" > memory_backup.json
```

## 関連スキル

- `/decide` - 決定の記録
- `/review` - 設計レビュー（方針・アーキテクチャの検討）
- `/code-review` - コードレビュー（実装の品質チェック）
- `/suggest` - 状況に応じたSkill提案
