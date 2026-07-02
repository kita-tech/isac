# ISAC - Intelligent System with Augmented Context

Claude Code CLI + Memory Service による軽量開発支援システム

## 概要

ISACは**複数プロジェクトを切り替えながら開発**でき、**チームでナレッジを共有**できるAIエージェント支援システムです。

## 特徴

- **複数プロジェクト対応**: プロジェクトごとの記憶を管理、`isac init`で初期化
- **チーム共有**: Memory Serviceでチーム全員のナレッジを共有
- **軽量**: Dockerコンテナ1つ（Memory Service）
- **高速起動**: 即座に利用可能
- **セキュリティ**: 機密情報の自動フィルタリング
- **マルチエージェントレビュー**: `--agents`（多レンズ並列＋🔴独立検証）／`--dialectic`（弁証法で意思決定）による Workflow ベースのレビュー

## クイックスタート

### 1. グローバルインストール

```bash
# ISACをクローン
# → GitHubからISACのソースコードをダウンロードし、ホームディレクトリに配置
git clone <repository> ~/isac

# PATHに追加（必須）
# → 「isac」コマンドをどこからでも実行できるようにする
# → ~/.zshrc はシェル起動時に読み込まれる設定ファイル（bashの場合は ~/.bashrc）
echo 'export PATH="$HOME/isac/bin:$PATH"' >> ~/.zshrc

# 設定を即座に反映
# → 通常はターミナル再起動が必要だが、sourceで即座に反映できる
source ~/.zshrc

# グローバルインストール
# → ~/.isac/ フォルダを作成し、hooks（自動処理）とskills（コマンド）をコピー
# → これにより、どのプロジェクトでもISACの機能が使えるようになる
isac install
```

### 2. Memory Service起動

```bash
# Memory Serviceのディレクトリに移動
cd ~/isac/memory-service

# Dockerコンテナをバックグラウンドで起動
# → docker compose: 複数のコンテナを管理するツール
# → up: コンテナを起動
# → -d: バックグラウンド実行（ターミナルを占有しない）
# → これにより http://localhost:8100 でMemory Serviceが動作開始
docker compose up -d
```

> **Note**: Dockerがインストールされていない場合は、先に[Docker Desktop](https://www.docker.com/products/docker-desktop/)をインストールしてください。

### 3. プロジェクトで使用

```bash
# 開発したいプロジェクトのディレクトリに移動
cd /path/to/your/project

# プロジェクト初期化
# → .isac.yaml、.isac.secrets.yaml.example を作成
# → .claude/ ディレクトリをセットアップ（hooks/skills/agents/workflows のシンボリックリンク）
# → MCPサーバー（notion, context7）を自動登録
# → プロジェクト名を聞かれるので入力（デフォルトは既存.isac.yamlの値 or ディレクトリ名）
isac init

# Claude Code CLIを起動して開発開始
# → ISACのhooksが自動的に動作し、過去の決定事項や作業履歴が参照される
claude
```

## コマンド一覧

| コマンド | 説明 | 使うタイミング |
|---------|------|---------------|
| `isac install` | ~/.isac/ にhooksとskillsをインストール | 初回のみ |
| `isac update` | ISACを更新した後、グローバル設定を最新化 | ISACをgit pullした後 |
| `isac init` | プロジェクト初期化（再初期化時は既存設定を引き継ぎ） | 新しいプロジェクトを始めるとき |
| `isac init --yes` | 確認なしで初期化（CI/CD向け） | 自動化スクリプトで使う |
| `isac init --force` | 既存設定を上書きして再初期化 | 設定をリセットしたいとき |
| `isac status` | 現在のプロジェクト情報・Memory Service接続状況・バージョン情報を表示 | 状態確認したいとき |
| `isac status --no-cache` | リモート更新チェックのキャッシュを無視して最新取得 | 更新直後に最新状態を確認したいとき |
| `isac projects` | 登録済みの全プロジェクト一覧を表示 | どんなプロジェクトがあるか確認 |

### isac init の動作

`isac init` を実行すると、以下が自動的に行われます：

1. **プロジェクトID の決定**
   - 優先順位: コマンド引数 > 既存 `.isac.yaml` の値 > ディレクトリ名
   - 再初期化時は既存の `.isac.yaml` から `project_id` を引き継ぐ

2. **ファイルの作成**

```
プロジェクト/
├── .isac.yaml                 # プロジェクトID設定
├── .isac.secrets.yaml.example # シークレット設定テンプレート（自動生成）
└── .claude/                   # Claude Code CLI設定（自動作成）
    ├── settings.json          # Hooks設定ファイル（JSON形式）
    ├── hooks/                 # ~/.isac/hooks/ へのシンボリックリンク
    ├── skills/                # ~/.isac/skills/ へのシンボリックリンク
    ├── agents/                # ~/.isac/agents/ へのシンボリックリンク（サブエージェント定義）
    └── workflows/             # ~/.isac/workflows/ へのシンボリックリンク（マルチエージェントWorkflow）
```

3. **MCPサーバーの自動登録**
   - `notion`（Notionページ取得）と `context7`（ライブラリドキュメント参照）を `~/.claude.json` に登録
   - `.isac.secrets.yaml` があれば、そのAPIキーを使用して登録

4. **シークレット管理**
   - `.isac.secrets.yaml.example` をテンプレートとして生成
   - `.gitignore` に `.isac.secrets.yaml` を自動追記
   - プロジェクトごとに `.isac.secrets.yaml` でMCPのAPIキーを管理可能（詳細は [CLAUDE.md](CLAUDE.md) を参照）

5. **Memory Service 接続確認**

> **Note**: `settings.json` はHooks設定用です。MCPサーバーは `claude mcp add --scope user` で `~/.claude.json` に登録されます（詳細は [CLAUDE.md](CLAUDE.md) を参照）。

> **チーム開発での注意**: `hooks/` と `skills/` はシンボリックリンクなので、Gitにはコミットされません。チームメンバーは各自 `isac init --force` を実行して自分の環境にリンクを作成してください。

### 使用例

```bash
# 状態確認
$ isac status
Project: my-app (.isac.yaml)
Memory Service: Connected
Memories: 15, Decisions: 3

# プロジェクト一覧
$ isac projects
 * my-app (現在)
   another-project
   old-project

# 別プロジェクトで初期化
$ cd /path/to/another-project
$ isac init
```

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│                Claude Code CLI                       │
│  ┌───────────────────────────────────────────────┐  │
│  │ Hooks（~/.isac/hooks/ または .claude/hooks/）   │  │
│  │  - on-session-start.sh: 起動時ステータス表示   │  │
│  │  - on-prompt.sh: 関連記憶を自動表示            │  │
│  │  - on-stop.sh: タスク完了時のAI分類            │  │
│  │  - post-edit.sh: 作業履歴を自動保存            │  │
│  │  - resolve-project.sh: プロジェクトID解決      │  │
│  │  - save-memory.sh: AI分類結果の記憶保存        │  │
│  │  - sensitive-filter.sh: 機密情報マスキング     │  │
│  ├───────────────────────────────────────────────┤  │
│  │ Skills（~/.isac/skills/ または .claude/skills/）│  │
│  │  - /isac-autopilot: 自動実装フロー             │  │
│  │  - /isac-review: 設計レビュー                  │  │
│  │  - /isac-code-review: コードレビュー           │  │
│  │  - /isac-pr-review: PRレビュー                 │  │
│  │  - /isac-memory: 記憶管理                      │  │
│  │  - /isac-decide: 重要決定の記録                │  │
│  │  - /isac-suggest: Skill提案                    │  │
│  │  - /isac-save-memory: 保存形式提案             │  │
│  │  - /isac-notion-design: Notion設計             │  │
│  │  - /isac-todo: 個人タスク管理                  │  │
│  │  - /isac-later: タスク素早く追加               │  │
│  └───────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│  Memory Service (Docker)                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │
│  │   Global    │ │    Team     │ │   Project   │   │
│  │  Knowledge  │ │  Knowledge  │ │   Memory    │   │
│  └─────────────┘ └─────────────┘ └─────────────┘   │
│  - 全体共有       - チーム共有     - プロジェクト固有 │
└─────────────────────────────────────────────────────┘
```

> **Agents / Workflows**: 上記の Skills に加え、`~/.isac/agents/`（サブエージェント定義: memory-classifier ほか）と
> `~/.isac/workflows/`（マルチエージェントWorkflow: `isac-review-agents` / `isac-review-issues` / `isac-review-dialectic` /
> `isac-pr-review-issues`）が配布されます。`/isac-review --agents` や `/isac-pr-review --agents`、`--dialectic` から利用されます。

## 記憶の階層

| Scope | 内容 | 共有範囲 | TTL |
|-------|------|----------|-----|
| Global | 全体で共有すべきナレッジ | 全員 | 1年 |
| Team | チーム固有のナレッジ | チームメンバー | 1年 |
| Project | プロジェクトの決定事項・作業履歴 | プロジェクト参加者 | 決定:1年, 作業:30日 |

## プロジェクト設定

### ローカル設定（推奨）

プロジェクトルートに `.isac.yaml` を作成:

```yaml
# .isac.yaml
project_id: my-project
team_id: my-team  # オプション
```

### グローバル設定

`~/.isac/config.yaml`:

```yaml
# ~/.isac/config.yaml
version: 1

# Memory Service URL
memory_service_url: http://localhost:8100

# デフォルトプロジェクト（オプション）
# default_project: my-project

# Team ID（チームナレッジ共有用）
# team_id: my-team
```

## チーム開発での使用

### 共有サーバーモード

1. Memory Serviceを共有サーバーにデプロイ
2. 各メンバーの `~/.isac/config.yaml` でURLを設定:

```yaml
memory_service_url: http://shared-server:8100
team_id: my-team
```

3. 各プロジェクトで同じ `project_id` を使用:

```yaml
# .isac.yaml
project_id: shared-project
team_id: my-team
```

### 誰が何を記録したか

Memory Serviceは各記憶に `created_by` を記録します。
`/admin/audit-logs` APIで監査ログを確認できます。

## セキュリティ

### 機密情報フィルター

以下のパターンは自動的にマスキングまたはスキップされます:

- `.env`, `.env.*` ファイル
- `*.pem`, `*.key` ファイル
- `credentials.*`, `secrets.*` ファイル
- APIキー、パスワード、トークンのパターン

### 認証（オプション）

Memory Serviceで認証を有効化:

```bash
# docker-compose.yml
environment:
  - REQUIRE_AUTH=true
  - ADMIN_API_KEY=your-admin-key
```

## ディレクトリ構成

```
isac/
├── bin/
│   └── isac                    # メインCLI
├── .claude/
│   ├── settings.json           # Hooks設定（MCPサーバーは~/.claude.jsonで管理）
│   ├── hooks/
│   │   ├── _log.sh             # 共有ログ関数
│   │   ├── on-session-start.sh # セッション開始時の軽量ステータス表示
│   │   ├── on-prompt.sh        # 記憶検索
│   │   ├── on-stop.sh          # タスク完了時のAI分類プロンプト
│   │   ├── post-edit.sh        # 記憶保存
│   │   ├── resolve-project.sh  # プロジェクトID解決
│   │   ├── save-memory.sh      # AI分類結果の記憶保存
│   │   └── sensitive-filter.sh # 機密情報フィルター
│   ├── skills/                 # Skill定義（isac-autopilot / isac-review / isac-code-review /
│   │   │                       #   isac-pr-review / isac-memory / isac-decide / isac-suggest /
│   │   │                       #   isac-save-memory / isac-notion-design / isac-todo / isac-later）
│   │   └── <skill-name>/SKILL.md
│   ├── agents/                 # サブエージェント定義
│   │   ├── memory-classifier.md
│   │   ├── memory-editor.md
│   │   └── memory-searcher.md
│   └── workflows/              # マルチエージェントWorkflowスクリプト
│       ├── isac-review-agents.js     # --agents（多レンズ投票）
│       ├── isac-review-issues.js     # --agents レビュー版（issue-finding＋🔴検証）
│       ├── isac-review-dialectic.js  # --dialectic（弁証法・意思決定）
│       └── isac-pr-review-issues.js  # PRレビュー徹底版
├── docs/                       # 設計・ガイド
│   ├── DESIGN_isac-review-agents.md
│   ├── MEMORY_SERVICE.md
│   └── TEST_DESIGN_GUIDE.md
├── memory-service/
│   ├── docker-compose.yml
│   ├── docker-compose.test.yml
│   ├── Dockerfile
│   ├── main.py
│   ├── requirements.txt
│   └── README.md
├── tests/                      # テストスイート
└── README.md

~/.isac/                        # グローバル設定
├── config.yaml
├── hooks/                      # グローバルHooks
├── skills/                     # グローバルSkills
├── agents/                     # グローバルAgents
└── workflows/                  # グローバルWorkflows
```

## 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `MEMORY_SERVICE_URL` | http://localhost:8100 | Memory Service URL |
| `ISAC_GLOBAL_DIR` | ~/.isac | グローバル設定ディレクトリ |
| `MEMORY_MAX_TOKENS` | 2000 | コンテキスト取得時の最大トークン数 |

## テスト

```bash
# クイックテスト
bash tests/run_all_tests.sh --quick

# フルテスト
bash tests/run_all_tests.sh
```

## ライセンス

MIT
