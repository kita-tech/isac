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

curl --get "${MEMORY_SERVICE_URL:-http://localhost:8100}/search" \
  --data-urlencode "query=認証" \
  --data-urlencode "scope=project" \
  --data-urlencode "scope_id=$PROJECT_ID"
```

## 記憶の保存

作業内容を記録:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")

curl -X POST "${MEMORY_SERVICE_URL:-http://localhost:8100}/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "記録したい内容",
    "type": "work",
    "importance": 0.5,
    "scope": "project",
    "scope_id": "'"$PROJECT_ID"'"
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
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")

curl --get "${MEMORY_SERVICE_URL:-http://localhost:8100}/context/$PROJECT_ID" \
  --data-urlencode "query=認証の実装"
```

## 統計情報

プロジェクトの記憶統計:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")

curl "${MEMORY_SERVICE_URL:-http://localhost:8100}/stats/$PROJECT_ID"
```

## エクスポート

記憶をバックアップ:

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")

curl "${MEMORY_SERVICE_URL:-http://localhost:8100}/export/$PROJECT_ID" > memory_backup.json
```

## 関連スキル

- `/isac-decide` - 決定の記録
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-code-review` - コードレビュー（実装の品質チェック）
- `/isac-suggest` - 状況に応じたSkill提案
