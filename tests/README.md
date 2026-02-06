# ISAC テスト

ISAC の自動テストスイートです。

## 前提条件

- Docker が起動していること（テスト用コンテナはポート 8200 で自動起動されます）
- `jq` がインストールされていること
- （APIテストのみ）`pytest` と `requests` がインストールされていること

```bash
# jq インストール（未インストールの場合）
brew install jq  # macOS
apt-get install jq  # Ubuntu/Debian

# Python依存関係（APIテスト用）
pip install -r tests/requirements.txt
```

> **注意**: テスト用 Memory Service はポート **8200** で起動します。
> 通常運用（ポート 8100）とは分離されているため、テスト中も通常サービスに影響しません。

## テスト実行

### クイックテスト（推奨）

pytest不要。Hookと統合テストのみ実行。

```bash
bash tests/run_all_tests.sh --quick
```

### フルテスト

全テスト（API + Hook + 統合）を実行。

```bash
bash tests/run_all_tests.sh
```

### 個別テスト

```bash
# Hookテストのみ
bash tests/test_hooks.sh

# 統合テストのみ
bash tests/test_integration.sh

# APIテストのみ（pytest必要）
pytest tests/test_memory_service.py -v
```

## テスト内容

### Hookテスト (`test_hooks.sh`)

| テスト項目 | 内容 |
|-----------|------|
| resolve-project.sh | ローカル設定読み込み、Team ID取得、デフォルト動作、Typo検出 |
| sensitive-filter.sh | APIキー検出、パスワード検出、AWS認証情報、DB URL、安全なテキスト |
| on-prompt.sh | コンテキスト出力、警告表示 |
| post-edit.sh | メモリ記録、機密ファイルスキップ、エラーハンドリング |
| isac CLI | help, version, status, projects, init |

### 統合テスト (`test_integration.sh`)

| シナリオ | 内容 |
|---------|------|
| プロジェクトセットアップ | .isac.yaml によるプロジェクト解決 |
| 決定事項の記録 | 保存とコンテキストへの反映 |
| 作業履歴の記録 | work タイプの保存 |
| コンテキスト取得 | Hook経由でのメモリ取得 |
| 検索機能 | キーワード検索、タイプフィルタ |
| プロジェクト一覧 | 一覧取得、Typo検出 |
| エクスポート/インポート | データのバックアップと復元 |
| 統計情報 | プロジェクト統計の取得 |

### APIテスト (`test_memory_service.py`)

| クラス | 内容 |
|-------|------|
| TestHealthCheck | ヘルスチェックエンドポイント |
| TestMemoryStore | メモリ保存（各スコープ、バリデーション） |
| TestContext | コンテキスト取得 |
| TestProjects | プロジェクト一覧、Typo提案 |
| TestSearch | 検索、フィルタ |
| TestStats | 統計情報 |
| TestExport | エクスポート |
| TestMemoryOperations | 個別メモリの取得・削除 |
| TestImport | インポート |

## オプション

```bash
# テストランナーのヘルプ
bash tests/run_all_tests.sh --help

# 利用可能なオプション
--quick        # Hook + 統合テストのみ（pytest不要）
--api-only     # APIテストのみ
--hooks-only   # Hookテストのみ
--integration  # 統合テストのみ
```

## トラブルシューティング

### Memory Service に接続できない

テストランナーはテスト用コンテナ（ポート 8200）を自動起動します。
手動で確認する場合:

```bash
# テスト用コンテナの起動確認
curl http://localhost:8200/health

# テスト用コンテナの手動起動
cd memory-service && docker compose -f docker-compose.test.yml up -d --build

# テスト用コンテナのログ確認
docker compose -f memory-service/docker-compose.test.yml logs
```

### jq が見つからない

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

### pytest が見つからない

```bash
pip install -r tests/requirements.txt
# または
pip install pytest requests
```

## テストデータ

テスト実行時に以下のプロジェクトが作成されます（自動削除されません）:

- `test-local-project`
- `test-team-project`
- `test-post-edit`
- `test-post-edit-sensitive`
- `test-cli-init`
- `integration-test-*`

必要に応じてMemory ServiceのAPIで削除してください。
