---
name: isac-decide
description: 重要な技術的決定を記録します。
---

# ISAC Decide Skill

重要な技術的決定を記録します。

## 使用場面

- アーキテクチャの決定
- 技術選定
- 設計パターンの採用
- 重要なルールの策定

## 決定の記録

重要な決定を記録する際は、以下の形式で Memory Service に保存してください:

```bash
curl -X POST "${MEMORY_SERVICE_URL:-http://localhost:8100}/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "【決定内容】認証にはJWTを採用する\n【理由】ステートレスでスケーラブル、マイクロサービスに適している\n【代替案】セッションベース認証 - サーバー側の状態管理が必要なため不採用",
    "type": "decision",
    "importance": 0.8,
    "scope": "project",
    "scope_id": "'"${CLAUDE_PROJECT:-default}"'",
    "metadata": {
      "category": "authentication",
      "decision": "JWT採用"
    }
  }'
```

### グローバル決定（全プロジェクト共有）

組織全体に影響する決定は`scope: global`で保存:

```bash
curl -X POST "${MEMORY_SERVICE_URL:-http://localhost:8100}/store" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "【決定内容】全プロジェクトでPython 3.11以上を使用する",
    "type": "decision",
    "importance": 0.9,
    "scope": "global",
    "metadata": {
      "category": "technology-stack"
    }
  }'
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
curl --get "${MEMORY_SERVICE_URL:-http://localhost:8100}/search" \
  --data-urlencode "query=認証" \
  --data-urlencode "type=decision" \
  --data-urlencode "scope=project" \
  --data-urlencode "scope_id=${CLAUDE_PROJECT:-default}"
```

## 関連スキル

- `/isac-memory` - 記憶の検索・管理
- `/isac-review` - 設計レビュー（方針・アーキテクチャの検討）
- `/isac-code-review` - コードレビュー（実装の品質チェック）
- `/isac-suggest` - 状況に応じたSkill提案
