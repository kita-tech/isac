# ISAC - Intelligent System with Augmented Context

Claude Code CLI + Memory Service による軽量開発支援システム

## 概要

ISACは**複数プロジェクトを切り替えながら開発**でき、**チームでナレッジを共有**できるAIエージェント支援システムです。

## 特徴

- **複数プロジェクト対応**: プロジェクトごとの記憶を管理、`isac switch`で切り替え
- **チーム共有**: Memory Serviceでチーム全員のナレッジを共有
- **軽量**: Dockerコンテナ1つ（Memory Service）
- **高速起動**: 即座に利用可能
- **セキュリティ**: 機密情報の自動フィルタリング

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
# → .isac.yaml ファイルを作成し、このディレクトリをISACプロジェクトとして登録
# → プロジェクト名を聞かれるので入力（デフォルトはディレクトリ名）
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
| `isac init` | 現在のディレクトリを新規プロジェクトとして登録 | 新しいプロジェクトを始めるとき |
| `isac init --yes` | 確認なしで初期化（CI/CD向け） | 自動化スクリプトで使う |
| `isac init --force` | 既存設定を上書きして再初期化 | 設定をリセットしたいとき |
| `isac status` | 現在のプロジェクト情報・Memory Service接続状況を表示 | 状態確認したいとき |
| `isac projects` | 登録済みの全プロジェクト一覧を表示 | どんなプロジェクトがあるか確認 |
| `isac switch <id>` | 別のプロジェクトに切り替え | 複数プロジェクトを行き来するとき |

### isac init の動作

`isac init` を実行すると、以下が自動的に作成されます：

```
プロジェクト/
├── .isac.yaml              # プロジェクトID設定
└── .claude/                # Claude Code CLI設定（自動作成）
    ├── settings.yaml       # 設定ファイル（詳細コメント付き）
    ├── hooks/              # ~/.isac/hooks/ へのシンボリックリンク
    └── skills/             # ~/.isac/skills/ へのシンボリックリンク
```

これにより、新規プロジェクトでもすぐにISACの全機能が使えます。

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

# 別プロジェクトに切り替え
$ isac switch another-project
Switched to: another-project
Recent decisions:
  - フレームワークはNext.jsを採用
  - DBはPostgreSQLを使用
```

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│                Claude Code CLI                       │
│  ┌───────────────────────────────────────────────┐  │
│  │ Hooks（~/.isac/hooks/ または .claude/hooks/）   │  │
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
│   ├── settings.yaml           # Hooks設定
│   ├── hooks/
│   │   ├── on-prompt.sh        # 記憶検索
│   │   ├── on-stop.sh          # タスク完了時のAI分類プロンプト
│   │   ├── post-edit.sh        # 記憶保存
│   │   ├── resolve-project.sh  # プロジェクトID解決
│   │   ├── save-memory.sh      # AI分類結果の記憶保存
│   │   └── sensitive-filter.sh # 機密情報フィルター
│   └── skills/                 # ディレクトリ構造
│       ├── isac-autopilot/
│       │   └── SKILL.md
│       ├── isac-code-review/
│       │   └── SKILL.md
│       ├── isac-decide/
│       │   └── SKILL.md
│       ├── isac-later/
│       │   └── SKILL.md
│       ├── isac-memory/
│       │   └── SKILL.md
│       ├── isac-notion-design/
│       │   └── SKILL.md
│       ├── isac-pr-review/
│       │   └── SKILL.md
│       ├── isac-review/
│       │   └── SKILL.md
│       ├── isac-save-memory/
│       │   └── SKILL.md
│       ├── isac-suggest/
│       │   └── SKILL.md
│       └── isac-todo/
│           └── SKILL.md
├── memory-service/
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
└── README.md

~/.isac/                        # グローバル設定
├── config.yaml
├── hooks/                      # グローバルHooks
└── skills/                     # グローバルSkills
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
