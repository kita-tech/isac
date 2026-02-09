---
name: isac-save-memory
description: タスク完了時に、AIが作業内容を分析し、記憶/Skill/Hooksのどれで保存すべきか提案します。
---

# ISAC Save Memory Skill

タスク完了時に、AIが作業内容を分析し、最適な保存形式を提案します。

## project_id の取得ルール

**重要**: project_id は必ず `.isac.yaml` ファイルから取得すること。`$CLAUDE_PROJECT` 環境変数は `.isac.yaml` が存在しない場合のフォールバックとしてのみ使用する。

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")
```

以下のすべての curl コマンドで、この方法で取得した `$PROJECT_ID` を使用すること。

## 使用方法

```
/isac-save-memory
/isac-save-memory 認証機能の実装が完了
```

## 動作概要

1. 今回のセッションで行った作業を分析
2. **保存形式を判定**（記憶 / Skill / Hooks / 保存不要）
3. 判定理由と共に提案
4. 記憶の場合: **既存記憶と比較し、廃止候補を検索・提案**
5. ユーザー選択に応じて保存実行

## 保存形式の判定基準

| 形式 | 判定条件 | 例 |
|------|----------|-----|
| 記憶 | 事実・決定・コンテキスト（What/Why） | 技術選定の理由、バグの原因、設計方針 |
| Skill | 再利用可能な手順・プロセス（How） | デプロイ手順、レビュー方法、調査手順 |
| Hooks | 毎回自動実行すべき処理 | lint実行、機密情報チェック、フォーマット |
| 保存不要 | 一時的な作業・単発の調査 | ファイル場所の確認、一度きりの修正 |

## 実行手順

### Step 1: 作業内容の分析と形式判定

以下の形式で分析結果を出力してください：

```
## 保存提案

### 作業内容
[今回の作業の1-2行要約]

### AI推奨: [記憶 / Skill / Hooks / 保存不要]

**判定理由**: [なぜこの形式が適切か]

### 類似の既存データ
[あれば表示、なければ「なし」]

---

どの形式で保存しますか？
- 記憶として保存
- Skillとして保存（PR作成が必要）
- Hooksとして保存（PR作成が必要）
- スキップ
```

### Step 2: 既存記憶との比較・廃止候補検索（記憶保存時のみ）

Step 1 で「記憶として保存」が選択された場合、保存前に既存記憶を検索し廃止候補を提案します。

#### 2-1. 既存記憶の検索

`/search` API で同じプロジェクト・カテゴリの既存記憶を取得します（最大5件）。
`query` には Step 1 で生成した summary のキーワード2-3語を使用してください。

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")

curl -s "http://localhost:8100/search?query=キーワード2-3語&scope_id=$PROJECT_ID&category=カテゴリ&limit=5"
```

#### 2-2. AI による新旧記憶の比較判定

検索結果がある場合、新しく保存する記憶と各既存記憶を比較し、以下の3段階で判定します：

| 判定 | 意味 | アクション |
|------|------|-----------|
| 廃止すべき | 新しい記憶で完全に置き換わる | 廃止候補としてユーザーに提示 |
| 可能性あり | 部分的に重複している | 情報提供のみ（廃止対象にしない） |
| 廃止不要 | 無関係 or 補完関係 | 何もしない |

**判定のポイント:**
- 迷う場合は**廃止しない**（安全側に倒す）
- 同じトピックでも補完関係であれば廃止不要とする
- 内容が完全に上位互換の場合のみ廃止すべきとする

#### 2-3. 廃止候補のユーザー確認

廃止すべき判定が1件以上ある場合のみ、以下の形式でユーザーに確認します。
候補がない場合はこのステップをスキップし、Step 3 に進みます。

```
## 廃止候補

以下の既存記憶が新しい記憶と重複しています：

| # | ID | 内容 | 判定 |
|---|-----|------|------|
| 1 | abc123 | 旧API仕様の記録 | 廃止すべき |
| 2 | def456 | 関連する設計メモ | 可能性あり（参考情報） |

どうしますか？
- すべて廃止して保存
- 番号を選んで廃止（例: 1）
- 廃止せずそのまま保存
```

---

### Step 3: 選択に応じた処理

#### 記憶を選択した場合

従来通りMemory Serviceに保存：

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

### PRレビュー作業の分類ルール
- /isac-pr-review や /isac-code-review の実施記録 → type: **work**
- レビュー結果のスコアや個別の指摘事項 → **保存不要**（PRコメントに残っているため記憶として保存しない）
- レビュー中に決まったチーム方針・コーディングルール → type: **decision**（/isac-decide で別途記録を推奨）

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

## 記憶保存時の分類

JSONを出力した後、以下のcurlコマンドでMemory Serviceに保存してください：

```bash
PROJECT_ID=$(grep "project_id:" .isac.yaml 2>/dev/null | sed 's/project_id: *//' | tr -d '"'"'" || echo "${CLAUDE_PROJECT:-default}")

curl -X POST http://localhost:8100/store \
  -H "Content-Type: application/json" \
  -d '{
    "content": "summaryの内容",
    "type": "typeの値",
    "importance": 0.5,
    "scope": "project",
    "scope_id": "'"$PROJECT_ID"'",
    "category": "categoryの値",
    "tags": ["タグ1", "タグ2"],
    "supersedes": ["廃止対象ID1", "廃止対象ID2"],
    "metadata": {
      "supersede_reason": "auto-detected"
    }
  }'
```

- Step 2 で廃止対象が選択された場合、`supersedes` に廃止対象の記憶IDを設定
- 廃止対象がない場合は `"supersedes": []` とするか、フィールドを省略

---

#### Skillを選択した場合

Skillファイルを作成し、Git PRで共有します。

**1. Skillファイルの作成**

```bash
# ディレクトリ作成
mkdir -p .claude/skills/isac-[skill-name]/

# SKILL.md を作成
cat > .claude/skills/isac-[skill-name]/SKILL.md << 'EOF'
---
name: isac-[skill-name]
description: [1行説明]
---

# ISAC [Skill Name] Skill

[詳細な説明と手順]
EOF
```

**2. Git PRで共有（承認フロー）**

```bash
# ブランチ作成
git checkout -b skill/[skill-name]

# コミット
git add .claude/skills/isac-[skill-name]/
git commit -m "Add /isac-[skill-name] skill"

# PR作成
gh pr create --title "Add /isac-[skill-name] skill" --body "## 概要
[Skillの説明]

## 使用方法
\`/isac-[skill-name]\`

## チェックリスト
- [ ] SKILL.md のフロントマター確認
- [ ] 手順が再現可能か確認
- [ ] 機密情報が含まれていないか確認"
```

**3. レビュー後マージ → チーム共有**

---

#### Hooksを選択した場合

Hooksファイルを作成し、Git PRで共有します。

**1. Hooksファイルの作成**

```bash
# Hookスクリプトを作成
cat > .claude/hooks/[hook-name].sh << 'EOF'
#!/bin/bash
set -e

# [Hook の説明]
# トリガー: [on-prompt / post-edit / etc.]

[処理内容]
EOF

chmod +x .claude/hooks/[hook-name].sh
```

**2. Git PRで共有（承認フロー）**

```bash
# ブランチ作成
git checkout -b hooks/[hook-name]

# コミット
git add .claude/hooks/[hook-name].sh
git commit -m "Add [hook-name] hook"

# PR作成
gh pr create --title "Add [hook-name] hook" --body "## 概要
[Hookの説明]

## トリガー
[いつ実行されるか]

## チェックリスト
- [ ] 5秒以内に完了するか確認
- [ ] エラーハンドリング確認
- [ ] 機密情報が含まれていないか確認
- [ ] 既存Hooksとの競合確認"
```

**3. レビュー後マージ → チーム共有**

---

## 承認フローの重要性

| 形式 | 承認 | 理由 |
|------|------|------|
| 記憶 | 不要 | 即時共有。問題があれば廃止機能で対処可能 |
| Skill | **必要** | ユーザーが明示的に実行するが、チーム全体に影響 |
| Hooks | **必要** | 自動実行されるため、誤った処理のリスクが高い |

## 関連スキル

- `/isac-memory` - 記憶の検索・管理
- `/isac-decide` - 決定の直接記録（レビューなし）
- `/isac-review` - 設計レビュー（ペルソナ議論）
