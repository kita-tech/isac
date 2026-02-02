# /save-memory - AI分類による記憶保存

タスク完了時に、AIが作業内容を分類してMemory Serviceに保存します。

## 使用方法

```
/save-memory
/save-memory 認証機能の実装が完了
```

## 動作

1. 今回のセッションで行った作業を分析
2. 以下の項目を自動分類：
   - **type**: decision / work / knowledge
   - **category**: backend / frontend / infra など11種類
   - **tags**: 技術スタック、作業種別など（最大5個）
   - **importance**: 重要度（0.0-1.0）
3. Memory Serviceに保存

## 実行手順

以下の形式で作業内容を分類し、JSON出力してください：

```json
{
  "type": "work|decision|knowledge",
  "category": "backend|frontend|infra|security|database|api|ui|test|docs|architecture|other",
  "tags": ["タグ1", "タグ2"],
  "summary": "作業内容の1行要約（50文字以内）",
  "importance": 0.5
}
```

### type（記憶タイプ）
- **decision**: 技術選定、設計方針、アーキテクチャ決定など重要な判断
- **work**: 実装作業、バグ修正、リファクタリングなど日常的な作業
- **knowledge**: 学習した知見、ベストプラクティス、チームで共有すべき情報

### category（カテゴリ）
| カテゴリ | 説明 |
|---------|------|
| backend | サーバーサイド、API実装、データ処理 |
| frontend | UI/UX、クライアントサイド、Webアプリ |
| infra | インフラ、CI/CD、Docker、デプロイ |
| security | 認証、認可、セキュリティ対策 |
| database | DB設計、マイグレーション、クエリ最適化 |
| api | API設計、エンドポイント、OpenAPI |
| ui | コンポーネント、スタイリング、レスポンシブ |
| test | テスト、品質保証、カバレッジ |
| docs | ドキュメント、README、コメント |
| architecture | 全体設計、パターン、構造決定 |
| other | 上記に当てはまらないもの |

### tags（タグ例）
- 技術: python, react, fastapi, postgresql, docker
- 作業種別: bugfix, refactor, feature, optimization
- ドメイン: auth, payment, user, api

### importance（重要度）
- **0.9-1.0**: 長期的に参照すべき重要な決定
- **0.6-0.8**: チームで共有すべき知見
- **0.3-0.5**: 通常の作業記録
- **0.1-0.2**: 軽微な変更

## 分類後の保存

JSONを出力した後、以下のcurlコマンドでMemory Serviceに保存してください：

```bash
curl -X POST http://localhost:8100/store \
  -H "Content-Type: application/json" \
  -d '{
    "content": "【summaryの内容】",
    "type": "【typeの値】",
    "importance": 【importanceの値】,
    "scope": "project",
    "scope_id": "【プロジェクトID】",
    "category": "【categoryの値】",
    "tags": ["タグ1", "タグ2"]
  }'
```

プロジェクトIDは `.isac.yaml` の `project_id` を使用してください。
