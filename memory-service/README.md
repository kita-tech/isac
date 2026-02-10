# ISAC Memory Service

チーム開発のナレッジを保存・共有するためのサービスです。

## 目次

- [基本概念](#基本概念)
- [記憶の整理（廃止機能）](#記憶の整理廃止機能)
- [セットアップ](#セットアップ)
- [API リファレンス](#api-リファレンス)
- [テスト](#テスト)

---

## 基本概念

### 記憶（Memory）とは？

ISAC における「記憶」とは、開発中に得られた知識や決定事項を保存したものです。

```
例：
- 「APIのレスポンス形式はJSONに統一する」という決定
- 「認証にはJWTを使用する」という技術選定
- 「このバグはキャッシュのクリア忘れが原因だった」という学び
```

### なぜ記憶を保存するのか？

1. **チームでの知識共有**: 誰かが調べたことを全員が活用できる
2. **過去の決定の追跡**: なぜその設計にしたのかを後から確認できる
3. **AI アシスタントの精度向上**: Claude がプロジェクト固有の知識を参照できる

---

## 記憶の整理（廃止機能）

### 問題：古い情報と新しい情報の混在

開発を続けていると、以下のような状況が発生します：

```
古い記憶: 「APIのエンドポイントは /api/v1/users」
新しい記憶: 「APIのエンドポイントは /api/v2/users に変更」
```

両方が検索結果に出てくると、どちらが正しいのかわかりません。

### 解決策：記憶の廃止（Deprecation）

ISAC では、古い記憶を「廃止」することで、この問題を解決します。

```
┌─────────────────┐
│  古い記憶       │
│  deprecated=true│──── superseded_by ────▶ ┌─────────────────┐
│  (非表示)       │                         │  新しい記憶     │
└─────────────────┘                         │  (検索に出る)   │
                                            └─────────────────┘
```

### 廃止の仕組み

| 項目 | 説明 |
|------|------|
| `deprecated` | `true` になると、通常の検索結果から除外される |
| `superseded_by` | 後継の記憶ID。「この記憶の代わりに、こちらを見てね」というリンク |

### 廃止の方法

#### 方法1: 新しい記憶を保存するときに古い記憶を廃止（推奨）

```bash
# POST /store
{
  "content": "APIエンドポイントは /api/v2/users に変更",
  "type": "decision",
  "scope": "project",
  "scope_id": "my-project",
  "supersedes": ["古い記憶のID"]  # ← これを指定すると自動で廃止
}
```

**レスポンス例:**
```json
{
  "id": "新しい記憶のID",
  "superseded_ids": ["古い記憶のID"],
  "skipped_supersedes": []
}
```

#### 方法2: 手動で廃止

```bash
# PATCH /memory/{id}/deprecate
{
  "deprecated": true,
  "superseded_by": "新しい記憶のID"  # 任意
}
```

### 廃止の取り消し（復元）

間違えて廃止した場合は、簡単に復元できます。

```bash
# PATCH /memory/{id}/deprecate
{
  "deprecated": false
}
```

### 廃止済み記憶の確認

履歴を確認したい場合は、検索時に `include_deprecated=true` を指定します。

```bash
# 廃止済みも含めて検索
GET /search?query=API&include_deprecated=true

# 廃止済みも含めてコンテキスト取得
GET /context/my-project?query=API&include_deprecated=true
```

### 権限について

| 操作 | 誰ができる？ |
|------|-------------|
| 自分が作成した記憶を廃止 | 本人 |
| 他人が作成した記憶を廃止 | 管理者（Admin）のみ |
| 廃止済み記憶の復元 | 作成者本人 または 管理者 |

### よくある質問

**Q: 廃止された記憶は削除されるの？**

A: いいえ。廃止は「非表示」にするだけで、データは残っています。いつでも復元できます。

**Q: 同じ記憶を複数回廃止しようとしたらどうなる？**

A: すでに廃止済みの記憶は、`skipped_supersedes` に含まれて報告されます。エラーにはなりません。

**Q: 自分の記憶を他の人が勝手に廃止できる？**

A: いいえ。記憶を廃止できるのは、その記憶を作成した本人か、管理者だけです。

**Q: supersedes に自分自身のIDを指定したらどうなる？**

A: 自己参照は自動的にスキップされます。エラーにはなりません。

---

## セットアップ

### 開発環境

```bash
cd memory-service
docker compose up -d --build
```

### 本番環境（認証有効）

```bash
cd memory-service
docker compose -f docker-compose.yml up -d --build
```

環境変数:
- `REQUIRE_AUTH=true`: 認証を必須にする
- `ADMIN_API_KEY`: 管理者用APIキー

---

## API リファレンス

### 記憶の保存

```
POST /store
```

| パラメータ | 必須 | 説明 |
|-----------|------|------|
| `content` | Yes | 記憶の内容 |
| `type` | No | `work`, `decision`, `knowledge`, `todo` のいずれか（デフォルト: `work`） |
| `scope` | No | `global`, `team`, `project` のいずれか（デフォルト: `project`） |
| `scope_id` | No | チームID または プロジェクトID（`team`/`project` スコープの場合に使用） |
| `supersedes` | No | 廃止する記憶IDのリスト |
| `category` | No | カテゴリ（省略時は自動推定） |
| `tags` | No | タグのリスト（自動抽出タグとマージ） |
| `importance` | No | 重要度（0.0-1.0、デフォルト0.5） |
| `summary` | No | 要約（省略時は自動生成） |
| `metadata` | No | メタデータ（JSON形式） |
| `expires_at` | No | 有効期限（ISO 8601形式、省略時は自動TTL計算） |

### 記憶の検索

```
GET /search?query={検索文字列}&scope_id={プロジェクトID}
```

| パラメータ | 必須 | 説明 |
|-----------|------|------|
| `query` | Yes | 検索キーワード |
| `scope` | No | スコープでフィルタ |
| `scope_id` | No | プロジェクトIDで絞り込み |
| `type` | No | タイプでフィルタ |
| `category` | No | カテゴリでフィルタ |
| `tags` | No | タグでフィルタ（カンマ区切り） |
| `include_deprecated` | No | `true` で廃止済みも含める |
| `limit` | No | 最大件数（デフォルト: 10、最大: 100） |
| `offset` | No | 結果のオフセット（デフォルト: 0） |

### 記憶の廃止

```
PATCH /memory/{id}/deprecate
```

| パラメータ | 必須 | 説明 |
|-----------|------|------|
| `deprecated` | Yes | `true` で廃止、`false` で復元 |
| `superseded_by` | No | 後継の記憶ID |

### 記憶の更新

```
PATCH /memory/{id}
```

| パラメータ | 必須 | 説明 |
|-----------|------|------|
| `content` | No | 新しいコンテンツ |
| `category` | No | 新しいカテゴリ |
| `tags` | No | 新しいタグ（上書き） |
| `add_tags` | No | 追加するタグ |
| `remove_tags` | No | 削除するタグ |
| `importance` | No | 新しい重要度 |
| `summary` | No | 新しい要約 |
| `metadata` | No | メタデータの更新（既存とマージ） |

**注意**:
- `scope`, `scope_id`, `type` は変更不可（イミュータブルフィールド）
- これらのフィールドを送信した場合、無視されて `warnings` フィールドで通知されます
- スコープ変更が必要な場合は `POST /store` の `supersedes` を使って新規作成してください

### 個人TODO一覧の取得

```
GET /my/todos?project_id={プロジェクトID}&owner={オーナー}&status={ステータス}
```

| パラメータ | 必須 | 説明 |
|-----------|------|------|
| `project_id` | Yes | プロジェクトID |
| `owner` | Yes | オーナー（git config user.email の値） |
| `status` | No | `pending`（未完了）, `done`（完了）, `all`（全て）。デフォルト: `pending` |

**レスポンス例:**
```json
{
  "project_id": "my-project",
  "owner": "user@example.com",
  "todos": [...],
  "count": 2
}
```

### 記憶の削除

```
DELETE /memory/{id}
```

---

## テスト

### テスト環境の起動

> **注意**: テスト用 `docker-compose.test.yml` のサービス名は `memory-test`（本番は `memory`）です。
> 手動起動時は `-p` フラグでプロジェクト名を分離し、本番コンテナとの干渉を防いでください。

```bash
cd memory-service
docker compose -p isac-memory-test -f docker-compose.test.yml up -d --build
```

### テストの実行

```bash
# 廃止機能のテスト
pytest tests/test_memory_service.py::TestDeprecation -v

# 権限テスト（認証環境必須）
pytest tests/test_permission.py -v
```

### テスト環境の停止

```bash
cd memory-service
docker compose -p isac-memory-test -f docker-compose.test.yml down -v
```
