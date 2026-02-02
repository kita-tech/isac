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
isac install       # グローバルインストール
isac update        # グローバル設定を更新
isac init          # プロジェクト初期化
isac status        # 状態表示
isac projects      # プロジェクト一覧
isac switch <id>   # プロジェクト切り替え
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

## 設計原則

1. **シンプルさ優先**: 複雑な機能より使いやすさ
2. **チーム共有**: Memory Serviceでナレッジを共有
3. **高速起動**: 即座に利用可能であること
4. **Claude Code CLI ファースト**: CLI の機能を最大限活用
5. **セキュリティ**: 機密情報は自動フィルタリング

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
