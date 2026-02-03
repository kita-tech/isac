# ISAC - Intelligent System with Augmented Context

## 概要

Claude Code CLI + Memory Service による軽量開発支援システム

**目標**:
1. 複数プロジェクトを切り替えながら開発できること
2. 複数人で開発してもナレッジを共有できること

## 技術スタック

- **言語**: Python 3.11+, Bash
- **フレームワーク**: FastAPI
- **データベース**: SQLite
- **コンテナ**: Docker

## ディレクトリ構成

```
isac/
├── bin/
│   └── isac               # メインCLI
├── .claude/               # Claude Code CLI 設定
│   ├── hooks/
│   │   ├── on-prompt.sh        # 記憶検索
│   │   ├── post-edit.sh        # 記憶保存
│   │   ├── resolve-project.sh  # プロジェクトID解決
│   │   └── sensitive-filter.sh # 機密情報フィルター
│   └── skills/            # Skill 定義
├── memory-service/        # Memory Service (Docker)
├── templates/             # プロジェクトテンプレート
├── tests/                 # テストスイート
└── scripts/               # セットアップスクリプト

~/.isac/                   # グローバル設定（isac install で作成）
├── config.yaml
├── hooks/
└── skills/
```

## コマンド

```bash
isac install            # グローバルインストール
isac update             # グローバル設定を更新
isac init               # プロジェクト初期化
isac status             # 状態表示（バージョン情報含む）
isac status --no-cache  # キャッシュを使わず最新情報を取得
isac projects           # プロジェクト一覧
isac switch <id>        # プロジェクト切り替え
```

### バージョン確認

`isac status` はローカルのバージョンとリモートの最新バージョンを比較し、更新の有無を表示する。

```
Version:
  Local: b92e259 (2024-02-03)
  Status: ✓ Up to date        # または ⚠ Update available (3 commits behind)
  Cache: 15m ago

Recent Changes:
  b92e259 Extend isac-save-memory...
  d63b568 Merge pull request #5...
  0d4c93d Add beginner-friendly...
```

**キャッシュ**: リモートチェックは24時間キャッシュされる。開発中は以下で無効化：

```bash
# 一時的に無効化
isac status --no-cache

# 常に無効化（開発時に便利）
export ISAC_NO_CACHE=1
```

## コーディング規約

### Python

- PEP 8 準拠
- Type hints 使用
- Docstring 必須（公開関数）

### Bash

- `set -e` でエラー時に停止
- 変数は `"${VAR}"` 形式でクォート
- 終了コードを適切に返す
- POSIX互換の正規表現を使用（`[[:space:]]` 等）

## 禁止事項

- Memory Service に LLM を組み込まない（シンプルさ維持）
- Hooks で長時間の処理をしない（5秒以内）
- 外部サービスへの依存を増やさない
- 軽量モード（Docker不要）は採用しない（チームナレッジ共有が困難なため）
- リモートブランチへの直接マージ禁止（必ず PR を作成すること）

## Skills 命名規則

ISACのスキルは必ず `isac-` プレフィックスを付けること（他のコマンドとの競合回避）。

| スキル名 | 用途 |
|---------|------|
| `/isac-autopilot` | 設計→実装→レビュー→テスト→Draft PR作成を自動実行 |
| `/isac-review` | 設計レビュー（ペルソナ議論） |
| `/isac-code-review` | コードレビュー（品質チェック・スコアリング） |
| `/isac-pr-review` | GitHub PRレビュー（PRコメントに投稿） |
| `/isac-memory` | 記憶の検索・管理 |
| `/isac-decide` | 決定の記録 |
| `/isac-suggest` | 状況に応じたSkill提案 |
| `/isac-save-memory` | AI分析による保存形式提案（記憶/Skill/Hooks） |
| `/isac-notion-design` | Notionからの設計書生成 |

### Skills ファイル構造

Claude Code CLI がスキルを認識するには、ディレクトリ構造と YAML フロントマターが必要：

```
.claude/skills/
├── isac-review/
│   └── SKILL.md      # エントリーポイント（必須）
├── isac-code-review/
│   └── SKILL.md
└── ...
```

各 `SKILL.md` の先頭にはフロントマターを記載：

```markdown
---
name: isac-review
description: 設計や技術選定を複数のペルソナで検討し、決定を記録します。
---

# ISAC Review Skill
...
```

## ナレッジ共有と承認フロー

ISACでは、ナレッジを3つの形式で保存・共有できる：

| 形式 | 用途 | 承認 |
|------|------|------|
| 記憶 | 事実・決定・コンテキスト（What/Why） | 不要（即時共有） |
| Skill | 再利用可能な手順・プロセス（How） | **Git PR必須** |
| Hooks | 毎回自動実行すべき処理 | **Git PR必須** |

### 記憶の共有

Memory Serviceに保存すると即時にチーム共有される。問題があれば廃止機能で対処。

```bash
# 保存
curl -X POST http://localhost:8100/store -d '{"content": "...", ...}'

# 問題があれば廃止
curl -X PATCH http://localhost:8100/memory/{id}/deprecate -d '{"deprecated": true}'
```

### Skill/Hooks の共有（Git PRフロー）

Skill/Hooksは自動実行やチーム全体に影響するため、PRレビューを経て共有する。

#### 1. ローカルで作成

```bash
# Skill の場合
mkdir -p .claude/skills/isac-[skill-name]/
# SKILL.md を作成

# Hooks の場合
# .claude/hooks/[hook-name].sh を作成
chmod +x .claude/hooks/[hook-name].sh
```

#### 2. ブランチ作成 & コミット

```bash
# Skill
git checkout -b skill/[skill-name]
git add .claude/skills/isac-[skill-name]/
git commit -m "Add /isac-[skill-name] skill"

# Hooks
git checkout -b hooks/[hook-name]
git add .claude/hooks/[hook-name].sh
git commit -m "Add [hook-name] hook"
```

#### 3. PR作成 & レビュー

```bash
# Skill
gh pr create --title "Add /isac-[skill-name] skill" --body "..."

# Hooks
gh pr create --title "Add [hook-name] hook" --body "..."
```

#### 4. チェックリスト

**Skill の場合:**
- [ ] SKILL.md のフロントマター（name, description）が正しいか
- [ ] 手順が再現可能か
- [ ] 機密情報が含まれていないか

**Hooks の場合:**
- [ ] 5秒以内に完了するか（禁止事項参照）
- [ ] エラーハンドリングが適切か
- [ ] 機密情報が含まれていないか
- [ ] 既存Hooksとの競合がないか

#### 5. マージ → チーム共有

レビュー承認後、マージすることでチーム全体に共有される。

## 設計原則

1. **シンプルさ優先**: 複雑な機能より使いやすさ
2. **チーム共有**: Memory Serviceでナレッジを共有
3. **高速起動**: 即座に利用可能であること
4. **Claude Code CLI ファースト**: CLI の機能を最大限活用
5. **セキュリティ**: 機密情報は自動フィルタリング
6. **CLAUDE.mdを必ずコンテキストに含める**: ルール、規約、決定事項が集約されている

## 開発フロー（必須）

機能を実装する際は、以下のフローを**必ず**遵守すること：

### 1. テストコードの作成

機能実装後、テストコードを作成し **10人のペルソナでレビュー** する。

```
/isac-review テストケースの網羅性 --team
```

**チェック観点:**
- 正常系・異常系の網羅
- 境界値テスト
- エラーハンドリング
- 既存テストとの整合性

### 2. ドキュメントの更新

実装完了後、関連ドキュメントを**必ず更新**する：

| 変更内容 | 更新対象 |
|----------|----------|
| CLI コマンド追加・変更 | CLAUDE.md（コマンドセクション） |
| Skill 追加・変更 | CLAUDE.md（Skills一覧）、SKILL.md |
| Hooks 追加・変更 | CLAUDE.md（ディレクトリ構成） |
| API 追加・変更 | CLAUDE.md（API セクション）、memory-service/README.md |
| 設計決定 | CLAUDE.md（技術的決定事項） |

### 3. PR作成前チェックリスト

- [ ] テストコードを作成した
- [ ] テストが全て通過する（`bash tests/run_all_tests.sh`）
- [ ] ドキュメントを更新した
- [ ] 10人のペルソナでテストケースをレビューした（重要な機能の場合）

## テスト

```bash
# クイックテスト（推奨）
bash tests/run_all_tests.sh --quick

# フルテスト
bash tests/run_all_tests.sh
```

## 技術的決定事項

- RDBMSを使用している限り、複数人が同時に記憶を追加しても技術的な同期問題は発生しない（SQLiteのACID特性で保証）
- チーム開発での課題は「意味的な競合」や「重複データ」であり、アプリケーションレベルの問題

## 記憶の廃止機能

古い記憶と新しい記憶が混在した場合の対策として、記憶の廃止（deprecation）機能を実装。

### 設計方針

1. **タイムスタンプで新しい方を優先**: 検索結果は新しい順にソート
2. **廃止フラグ**: 古くなった記憶に `deprecated=true` を設定
3. **後継リンク**: 廃止された記憶に `superseded_by` で後継の記憶IDを記録

### API

```bash
# 新しい記憶保存時に古い記憶を廃止
POST /store
{
  "content": "新しいAPI仕様...",
  "supersedes": ["old_memory_id_1", "old_memory_id_2"]
}

# 手動で記憶を廃止
PATCH /memory/{id}/deprecate
{"deprecated": true, "superseded_by": "new_memory_id"}

# 廃止済み記憶を復元
PATCH /memory/{id}/deprecate
{"deprecated": false}

# 検索時に廃止済みを含める（履歴確認用）
GET /search?query=xxx&include_deprecated=true
GET /context/{project_id}?query=xxx&include_deprecated=true
```

### 動作

- **デフォルト**: 検索・コンテキスト取得時、廃止済み記憶は除外される
- **履歴追跡**: `include_deprecated=true` で廃止済みも取得可能
- **復元可能**: 廃止は論理削除のため、いつでも復元可能
